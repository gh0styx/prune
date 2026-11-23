import SwiftUI

// MARK: Surfaces

struct CardModifier: ViewModifier {
    var radius: CGFloat = 12
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(highlighted ? Theme.borderStrong : Theme.border, lineWidth: 1))
    }
}

extension View {
    func card(radius: CGFloat = 12, highlighted: Bool = false) -> some View {
        modifier(CardModifier(radius: radius, highlighted: highlighted))
    }
}

struct Hairline: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(Theme.border)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

// MARK: Buttons

enum ButtonKind { case primary, secondary, ghost, danger }

struct PruneButtonStyle: ButtonStyle {
    var kind: ButtonKind = .secondary
    var height: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, height: height)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let kind: ButtonKind
        let height: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(Theme.sans(13, .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .ghost ? 8 : 12)
                .frame(height: height)
                .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    if kind == .secondary {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(hovering ? Theme.borderStrong : Theme.border)
                    }
                }
                .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.inverse
            case .danger: .white
            case .secondary: Theme.text
            case .ghost: hovering ? Theme.text : Theme.muted
            }
        }

        private var background: Color {
            switch kind {
            case .primary: hovering ? Theme.text.opacity(0.88) : Theme.text
            case .danger: hovering ? Theme.red.opacity(0.88) : Theme.red
            case .secondary: hovering ? Theme.hover : Theme.card
            case .ghost: hovering ? Theme.hover : .clear
            }
        }
    }
}

extension ButtonStyle where Self == PruneButtonStyle {
    static var primary: PruneButtonStyle { .init(kind: .primary) }
    static var secondary: PruneButtonStyle { .init(kind: .secondary) }
    static var ghost: PruneButtonStyle { .init(kind: .ghost, height: 28) }
    static var danger: PruneButtonStyle { .init(kind: .danger) }
}

// MARK: Small pieces

struct Kbd: View {
    let keys: String
    var body: some View {
        Text(keys)
            .font(Theme.mono(10.5, .medium))
            .foregroundStyle(Theme.faint)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
    }
}

struct Badge: View {
    let text: String
    var color: Color = Theme.muted
    var body: some View {
        Text(tr(text))
            .font(Theme.sans(11, .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct CheckBox: View {
    var state: Bool?   // nil = mixed
    var body: some View {
        let on = state != false
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(on ? Theme.text : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(on ? Theme.text : Theme.borderStrong, lineWidth: 1))
            .overlay {
                Image(systemName: state == nil ? "minus" : "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.inverse)
                    .opacity(on ? 1 : 0)
            }
            .frame(width: 15, height: 15)
            .animation(.easeOut(duration: 0.12), value: state)
    }
}

struct IconTile: View {
    let symbol: String
    var color: Color = Theme.text
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(color.opacity(0.18)))
    }
}

struct SizeText: View {
    let bytes: Int64
    var size: CGFloat = 13
    var weight: Font.Weight = .medium
    var body: some View {
        let p = Fmt.parts(bytes)
        HStack(alignment: .firstTextBaseline, spacing: size * 0.25) {
            Text(p.value)
                .font(Theme.mono(size, weight))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(p.unit)
                .font(Theme.mono(size * 0.72, .medium))
                .foregroundStyle(Theme.faint)
        }
    }
}

struct SegmentBar: View {
    let segments: [(color: Color, value: Double)]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.value }, 1)
            let visible = segments.filter { $0.value > 0 }
            let gaps = CGFloat(max(visible.count - 1, 0)) * 2
            HStack(spacing: 2) {
                if visible.isEmpty {
                    Capsule().fill(Theme.hover)
                } else {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, s in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(s.color)
                            .frame(width: max(3, (geo.size.width - gaps) * s.value / total))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        }
        .frame(height: height)
    }
}

/// Thin indeterminate progress line, Vercel-deploy style.
struct ScanLine: View {
    @State private var phase: CGFloat = -0.4
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, Theme.blue, Theme.teal, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.4)
                .offset(x: geo.size.width * phase)
        }
        .frame(height: 1.5)
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.0 }
        }
    }
}

struct Spinner: View {
    var size: CGFloat = 12
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Theme.muted, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

struct HoverRow<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var hovering = false
    var body: some View {
        content
            .background(hovering ? Theme.text.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(tr(text).uppercased())
            .font(Theme.sans(10.5, .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.faint)
    }
}

/// Lays children out left to right and wraps to a new line when the row is full
/// (keeps long translated labels from pushing the window wider).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += lineHeight + lineSpacing; lineHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Picks which disk Space and Large files look at. Hidden when there's only one disk.
struct VolumePicker: View {
    @Environment(Store.self) private var store

    var body: some View {
        if store.volumes.count > 1 {
            let current = store.mapVolume ?? store.volumes.first
            Menu {
                ForEach(store.volumes) { v in
                    Button {
                        store.selectVolume(v)
                    } label: {
                        Label("\(v.name) — \(trf("%@ free", Fmt.bytes(v.free)))", systemImage: v.symbol)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: current?.symbol ?? "internaldrive").font(.system(size: 12))
                    Text(current?.name ?? "Macintosh HD").font(Theme.sans(13, .medium))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border))
            .disabled(store.isMappingDisk || store.isFindingLargeFiles)
        }
    }
}

/// All mounted disks with how full they are (sidebar footer popover).
struct VolumesList: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Disks")
            ForEach(store.volumes) { v in
                HStack(spacing: 10) {
                    Image(systemName: v.symbol).font(.system(size: 16)).foregroundStyle(Theme.muted).frame(width: 22)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(v.name).font(Theme.sans(12.5, .medium)).foregroundStyle(Theme.text)
                            Spacer()
                            Text(trf("%lld%% used", Int((v.usedFraction * 100).rounded())))
                                .font(Theme.mono(11)).foregroundStyle(Theme.faint)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.text.opacity(0.08))
                                Capsule().fill(v.usedFraction > 0.9 ? Theme.red : v.usedFraction > 0.75 ? Theme.amber : Theme.blue)
                                    .frame(width: geo.size.width * v.usedFraction)
                            }
                        }
                        .frame(height: 4)
                        Text(trf("%@ free of %@", Fmt.bytes(v.free), Fmt.bytes(v.total)))
                            .font(Theme.sans(11)).foregroundStyle(Theme.faint)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.selectVolume(v)
                    store.route = .space
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
