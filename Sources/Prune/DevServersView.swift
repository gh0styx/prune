import SwiftUI

/// Processes of the current user that listen on TCP ports, with memory use and a way to stop them.
struct DevServersView: View {
    @State private var servers: [DevServer]?
    @State private var onlyDev = true
    @State private var confirming: DevServer?
    @State private var errors: [Int32: String] = [:]

    private var shown: [DevServer] {
        let all = servers ?? []
        return onlyDev ? all.filter(\.isLikelyDevServer) : all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Dev servers", subtitle: "Local servers and processes listening on ports. Stop the ones you forgot.") {
                Button {
                    Task { await refresh() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                        Text("Refresh")
                    }
                }
                .buttonStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 20)

            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    chip("Dev servers", on: onlyDev) { onlyDev = true }
                    chip("All listening apps", on: !onlyDev) { onlyDev = false }
                }
                .padding(2)
                .card(radius: 8)
                Spacer()
                if servers != nil {
                    let mem = shown.reduce(Int64(0)) { $0 + $1.memoryBytes }
                    Text(trf("%lld servers · %@ memory", shown.count, Fmt.bytes(mem)))
                        .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 14)

            Group {
                if servers == nil {
                    VStack(spacing: 14) {
                        OrbView(size: 72, scanning: true)
                        Text("Looking for running servers…").font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if shown.isEmpty {
                    VStack(spacing: 12) {
                        IconTile(symbol: "checkmark", color: Theme.green, size: 44)
                        Text("No dev servers running").font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                        Text("Nothing is listening on a port right now.").font(Theme.sans(13)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                                VStack(spacing: 0) {
                                    if i > 0 { Hairline() }
                                    DevServerRow(server: s, error: errors[s.pid]) { confirming = s }
                                }
                                .appear(Double(min(i, 14)) * 0.025)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                            }
                        }
                    }
                }
            }
            .card()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), presenting: confirming) { s in
            Button("Stop") { stop(s, force: false) }
            Button("Force quit", role: .destructive) { stop(s, force: true) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var dialogTitle: String {
        guard let s = confirming else { return "" }
        if let p = s.ports.first { return trf("Stop %@ on :%lld?", s.processName, p) }
        return trf("Stop %@?", s.processName)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { action() }
        } label: {
            Text(tr(title))
                .font(Theme.sans(12.5, .medium))
                .foregroundStyle(on ? Theme.text : Theme.muted)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(on ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refresh() async {
        let list = await Task.detached(priority: .utility) { DevServerScanner.scan() }.value
        if Task.isCancelled { return }
        withAnimation(.snappy(duration: 0.3)) {
            servers = list
            errors = errors.filter { e in list.contains { $0.pid == e.key } }
        }
    }

    private func stop(_ s: DevServer, force: Bool) {
        let pid = s.pid
        Task {
            let ok = await Task.detached { DevServerKiller.stop(pid, force: force) }.value
            if ok {
                withAnimation(.snappy(duration: 0.3)) {
                    servers?.removeAll { $0.pid == pid }
                    errors[pid] = nil
                }
            } else {
                errors[pid] = tr("Couldn't stop the process")
            }
            await refresh()
        }
    }
}

private struct DevServerRow: View {
    let server: DevServer
    let error: String?
    let onStop: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: server.kind.symbol, color: server.kind.color, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(server.processName).font(Theme.sans(13, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        ForEach(server.ports.prefix(4), id: \.self) { p in
                            Text(verbatim: ":\(p)")
                                .font(Theme.mono(11, .medium))
                                .foregroundStyle(Theme.blue)
                                .padding(.horizontal, 7).frame(height: 20)
                                .background(Theme.blue.opacity(0.12), in: Capsule())
                        }
                        if server.ports.count > 4 { Text(verbatim: "+\(server.ports.count - 4)").font(Theme.mono(11)).foregroundStyle(Theme.faint) }
                    }
                    Text(server.command).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 8) {
                        if let cwd = server.cwd {
                            Label(Fmt.tilde(cwd), systemImage: "folder")
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1).truncationMode(.head)
                        }
                        if let d = server.started { Text(trf("started %@", Fmt.relative(d))) }
                    }
                    .font(Theme.sans(11.5)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 12)
                Text(Fmt.bytes(server.memoryBytes))
                    .font(Theme.mono(13, .medium)).foregroundStyle(Theme.text)
                    .frame(width: 80, alignment: .trailing)
                if let port = server.ports.first {
                    Button("Open") {
                        if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(PruneButtonStyle(kind: .ghost, height: 28))
                }
                Button("Stop", action: onStop)
                    .buttonStyle(PruneButtonStyle(kind: .secondary, height: 28))
            }
            .padding(.horizontal, 16)
            .frame(height: 64)

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                    Text(error).font(Theme.sans(11.5))
                    Spacer()
                }
                .foregroundStyle(Theme.red)
                .padding(.horizontal, 60).padding(.bottom, 8)
            }
        }
        .background(hovering ? Theme.text.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if let cwd = server.cwd {
                Button("Reveal folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)]) }
            }
            Button("Copy command") { copy(server.command) }
            Button("Copy PID") { copy(String(server.pid)) }
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
