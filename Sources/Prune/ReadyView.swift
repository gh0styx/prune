import SwiftUI

// MARK: Ready

/// Before the first scan: show what we already know (the disk) and let the user start.
struct ReadyView: View {
    @Environment(Store.self) private var store
    @State private var ringIn: CGFloat = 0

    var body: some View {
        let disk = store.disk
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .stroke(Theme.text.opacity(0.07), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: disk.usedFraction * ringIn)
                    .stroke(AngularGradient(colors: [Theme.blue.opacity(0.6), Theme.blue, Theme.teal],
                                            center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * disk.usedFraction)),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                OrbView(size: 118, intro: true)
            }
            .frame(width: 190, height: 190)
            .onAppear {
                withAnimation(.spring(duration: 1.6, bounce: 0.1).delay(0.6)) { ringIn = 1 }
            }

            HStack(spacing: 6) {
                Text(trf("%lld%% used", Int((disk.usedFraction * 100).rounded())))
                    .foregroundStyle(Theme.text)
                Text("·").foregroundStyle(Theme.faint)
                Text(trf("%@ free of %@", Fmt.bytes(disk.free), Fmt.bytes(disk.total)))
                    .foregroundStyle(Theme.muted)
            }
            .font(Theme.sans(12.5, .medium))
            .monospacedDigit()
            .padding(.top, 18)
            .appear(0.8)

            Text("Let's see what's taking space")
                .font(Theme.sans(30, .semibold))
                .tracking(-0.8)
                .foregroundStyle(Theme.text)
                .padding(.top, 26)
                .appear(0.9)
            Text("Prune reads file sizes only. Nothing is removed until you choose.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)
                .appear(1.0)

            HStack(spacing: 10) {
                Button { store.scan() } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                        .font(Theme.sans(15, .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(PruneButtonStyle(kind: .primary, height: 44))
                .help("⌘R")
            }
            .padding(.top, 26)
            .appear(1.1)
            Text("Checks caches and junk in seconds. The disk map is on the Space page.")
                .font(Theme.sans(11.5))
                .foregroundStyle(Theme.faint)
                .padding(.top, 12)
                .appear(1.15)


            Spacer(minLength: 24)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct Feature: View {
        let symbol: String
        let color: Color
        let title: String
        let text: String
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: symbol, color: color, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(title)).font(Theme.sans(13, .semibold)).foregroundStyle(Theme.text)
                    Text(tr(text)).font(Theme.sans(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card()
        }
    }
}
