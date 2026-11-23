import SwiftUI

// MARK: Hero

struct HeroCard: View {
    @Environment(Store.self) private var store

    var body: some View {
        let parts = Fmt.parts(store.reclaimable)
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Reclaimable space")
                            .font(Theme.sans(13, .medium))
                            .foregroundStyle(Theme.muted)
                        if store.isScanning { Badge(text: "Scanning", color: Theme.blue) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(parts.value)
                            .font(.system(size: 64, weight: .semibold))
                            .monospacedDigit()
                            .tracking(-2.5)
                            .foregroundStyle(Theme.text)
                            .contentTransition(.numericText())
                        Text(parts.unit)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Theme.faint)
                    }
                    Text(plural(store.allItems.count, .item) + " · " + plural(store.staleProjects.count, .staleProject))
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.faint)
                        .contentTransition(.numericText())
                }
                Spacer()
                HStack(spacing: 0) {
                    Stat(label: "Selected", bytes: store.selectedSize, accent: true)
                    Hairline(vertical: true).frame(height: 56).padding(.horizontal, 24)
                    Stat(label: "Free on disk", bytes: store.disk.free)
                }
                .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 14) {
                SegmentBar(segments: store.junkCategories.map { ($0.color, Double(store.size($0))) }, height: 10)
                FlowLegend()
            }
        }
        .padding(28)
        .card()
        .borderBeam(store.isScanning)
        .animation(.snappy(duration: 0.5), value: store.reclaimable)
    }
}

private struct Stat: View {
    let label: String
    let bytes: Int64
    var accent = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(tr(label)).font(Theme.sans(12)).foregroundStyle(Theme.faint)
            SizeText(bytes: bytes, size: 22, weight: .semibold)
        }
    }
}

private struct FlowLegend: View {
    @Environment(Store.self) private var store
    var body: some View {
        FlowLayout(spacing: 18, lineSpacing: 8) {
            ForEach(store.junkCategories.filter { store.size($0) > 0 }) { c in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(c.color).frame(width: 8, height: 8)
                    Text(tr(c.title)).font(Theme.sans(12)).foregroundStyle(Theme.muted)
                    Text(Fmt.bytes(store.size(c))).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
    }
}
