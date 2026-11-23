import SwiftUI

// MARK: First scan

/// Shown while a scan runs: the logo at work, a live trail of what's being read, progress and a running total.
struct FirstScanView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let parts = Fmt.parts(store.reclaimable)
        let cats = store.junkCategories
        let done = cats.filter { !store.pending.contains($0) }.count
        let fraction = cats.isEmpty ? 0 : Double(done) / Double(cats.count)

        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                OrbView(size: 104, scanning: true)
                    .padding(.top, 30)
                    .padding(.bottom, 28)

                Text("Scanning your Mac")
                    .font(Theme.sans(26, .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.text)
                    .appear(0.05)

                // Running total.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Found").font(Theme.sans(15)).foregroundStyle(Theme.muted)
                    Text(parts.value)
                        .font(Theme.mono(15, .semibold))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Text(parts.unit).font(Theme.sans(15)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 8)
                .animation(.snappy, value: store.reclaimable)
                .appear(0.1)

                // Progress across categories + elapsed time.
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.text.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.blue, Theme.teal], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, geo.size.width * max(fraction, 0.04)))
                                .animation(.spring(duration: 0.6), value: fraction)
                            // Shimmer on the bar so it never looks frozen.
                            ScanLine().clipShape(Capsule())
                        }
                    }
                    .frame(width: 380, height: 6)
                    HStack {
                        Text(trf("%lld of %lld checked", done, cats.count))
                            .contentTransition(.numericText())
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(elapsed).monospacedDigit()
                        }
                    }
                    .font(Theme.sans(11.5))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 380)
                }
                .padding(.top, 18)
                .appear(0.15)

                // Live trail: folders looked at and the one being read right now.
                VStack(spacing: 4) {
                    Text(trf("%@ folders looked at", store.scanLive.files.formatted(.number.locale(Lang.locale))))
                        .font(Theme.sans(12, .medium))
                        .foregroundStyle(Theme.muted)
                        .contentTransition(.numericText())
                    Text(Fmt.tilde(store.scanLive.path))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 460)
                        .id(store.scanLive.path)
                        .transition(.opacity)
                }
                .animation(.easeOut(duration: 0.15), value: store.scanLive.path)
                .padding(.top, 14)
                .appear(0.2)

            // Categories as tiles across the width: they fill in one by one as each one is checked.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 10)], spacing: 10) {
                ForEach(Array(cats.enumerated()), id: \.element) { i, c in
                    ScanCategoryTile(category: c, pending: store.pending.contains(c), size: store.size(c))
                        .appear(0.3 + Double(i) * 0.04)
                }
            }
            .frame(maxWidth: 780)
            .padding(.horizontal, 32)
            .padding(.top, 18)
                Spacer(minLength: 20)
            }
        .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var elapsed: String {
        let s = Int(Date().timeIntervalSince(store.scanStarted ?? Date()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// One category on the scan screen: a card that switches from spinner to checkmark and shows its size.
private struct ScanCategoryTile: View {
    let category: CategoryID
    let pending: Bool
    let size: Int64

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if pending {
                    Spinner(size: 12)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.green)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(tr(category.title))
                    .font(Theme.sans(13, .medium))
                    .foregroundStyle(pending ? Theme.muted : Theme.text)
                    .lineLimit(1)
                Text(pending ? "—" : Fmt.bytes(size))
                    .font(Theme.mono(12))
                    .foregroundStyle(!pending && size > 0 ? Theme.blue : Theme.faint)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Image(systemName: category.symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(highlighted: !pending && size > 0)
        .scaleEffect(pending ? 0.985 : 1)
        .opacity(pending ? 0.8 : 1)
        .animation(.spring(duration: 0.5, bounce: 0.25), value: pending)
    }
}
