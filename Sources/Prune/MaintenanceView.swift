import SwiftUI

struct MaintenanceView: View {
    private enum State_: Equatable { case idle, running, done(Date), cancelled, failed(String) }

    @State private var states: [String: State_] = [:]
    @State private var confirming: MaintenanceTask?
    private let tasks = MaintenanceTask.all.filter(\.isAvailable)
    private let columns = [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Maintenance", subtitle: "Small fixes that keep macOS running smoothly. Some ask for your password.") {}
                .padding(.horizontal, 32)
                .padding(.top, 14)
                .padding(.bottom, 20)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { i, t in
                        card(t)
                            .appear(Double(min(i, 14)) * 0.025)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            for t in tasks where states[t.id] == nil {
                if let d = MaintenanceRunner.lastRun(t.id) { states[t.id] = .done(d) }
            }
        }
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), presenting: confirming) { t in
            Button("Run") { start(t) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("macOS will ask for your password. Prune never sees it.")
        }
    }

    private var dialogTitle: String {
        guard let t = confirming else { return "" }
        return trf("Run “%@”?", tr(t.title))
    }

    private func card(_ t: MaintenanceTask) -> some View {
        let state = states[t.id] ?? .idle
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: t.symbol, color: Theme.blue, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tr(t.title)).font(Theme.sans(13.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.85)
                        if t.needsAdmin { Badge(text: "Needs password", color: Theme.amber) }
                    }
                    Text(tr(t.detail)).font(Theme.sans(12.5)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                status(t, state)
                Spacer(minLength: 8)
                if state == .running {
                    Spinner(size: 14)
                } else {
                    Button("Run") {
                        if t.needsAdmin { confirming = t } else { start(t) }
                    }
                    .buttonStyle(PruneButtonStyle(kind: .secondary, height: 28))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .card()
    }

    @ViewBuilder
    private func status(_ t: MaintenanceTask, _ state: State_) -> some View {
        switch state {
        case .idle:
            if let note = t.note {
                Text(tr(note)).font(Theme.sans(11.5)).foregroundStyle(Theme.faint).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
        case .running:
            Text("Running…").font(Theme.sans(12)).foregroundStyle(Theme.muted)
        case .done(let d):
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(Date().timeIntervalSince(d) < 60 ? tr("Done just now") : trf("Done %@", Fmt.relative(d)))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(Theme.sans(12, .medium)).foregroundStyle(Theme.green)
                if let note = t.note {
                    Text(tr(note)).font(Theme.sans(11.5)).foregroundStyle(Theme.faint).lineLimit(2)
                }
            }
        case .cancelled:
            Text("Cancelled").font(Theme.sans(12)).foregroundStyle(Theme.muted)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(Theme.sans(11.5)).foregroundStyle(Theme.red).lineLimit(3)
        }
    }

    private func start(_ t: MaintenanceTask) {
        states[t.id] = .running
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { MaintenanceRunner.execute(t) }.value
            withAnimation(.snappy(duration: 0.25)) {
                switch outcome {
                case .done:
                    MaintenanceRunner.markRun(t.id)
                    states[t.id] = .done(Date())
                case .cancelled:
                    states[t.id] = MaintenanceRunner.lastRun(t.id).map { .done($0) } ?? .cancelled
                case .failed(let m):
                    states[t.id] = .failed(m)
                }
            }
        }
    }
}
