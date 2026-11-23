import SwiftUI

// MARK: Staggered appear

struct AppearModifier: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .blur(radius: shown ? 0 : 4)
            .onAppear {
                withAnimation(.spring(duration: 0.55, bounce: 0.18).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Fades, lifts and sharpens the view in when it first appears.
    func appear(_ delay: Double = 0) -> some View { modifier(AppearModifier(delay: delay)) }

    /// A light beam that runs around the border while `active`.
    func borderBeam(_ active: Bool, radius: CGFloat = 12) -> some View {
        overlay {
            if active {
                BorderBeam(radius: radius).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: active)
    }
}

struct BorderBeam: View {
    let radius: CGFloat
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((t * 140).truncatingRemainder(dividingBy: 360))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    AngularGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.62),
                        .init(color: Theme.blue, location: 0.8),
                        .init(color: Theme.teal, location: 0.9),
                        .init(color: .white, location: 0.96),
                        .init(color: .clear, location: 1),
                    ], center: .center, angle: angle),
                    lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: Living orb

/// The logo, drawn live: a matte pearl with a bite and a blue spark.
/// `scanning` sends the spark orbiting with radar pings; `intro` plays the assembly once on appear.
struct OrbView: View {
    var size: CGFloat
    var animated = true
    var glow = true
    var scanning = false
    var intro = false

    @Environment(\.colorScheme) private var scheme
    @State private var orbIn: CGFloat = 1
    @State private var biteIn: CGFloat = 1
    @State private var dotIn: CGFloat = 1

    private static let blue = Color(nsColor: NSColor(hex: 0x3B82F6))

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !(animated || scanning))) { tl in
            let t = (animated || scanning) ? tl.date.timeIntervalSinceReferenceDate : 0
            let speed = scanning ? 2.2 : 0.8
            let light = UnitPoint(x: 0.3 + 0.1 * sin(t * speed), y: 0.25 + 0.08 * cos(t * speed * 0.75))
            // The spark sits in the bite (-45° on a circle of radius 0.6 × size).
            let dotOffset = CGSize(width: cos(-Double.pi / 4) * size * 0.603, height: sin(-Double.pi / 4) * size * 0.603)
            // While scanning the sphere breathes and a sheen sweeps across it every ~1.8 s.
            let breath = scanning ? 1 + 0.025 * sin(t * 2.4) : 1
            let sweep = (t / 1.8).truncatingRemainder(dividingBy: 1)

            ZStack {
                if glow {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: size * 0.9, height: size * 0.9)
                        .blur(radius: size * 0.1)
                        .offset(y: size * 0.06)
                }
                if scanning {
                    // Soft blue glow that swells with the breath.
                    Circle()
                        .fill(Self.blue)
                        .frame(width: size * 0.95, height: size * 0.95)
                        .blur(radius: size * 0.22)
                        .opacity(0.22 + 0.12 * sin(t * 2.4))
                }
                // Pearl on dark backgrounds, graphite on light ones (same as the Dock icon).
                let tones: [UInt32] = scheme == .dark ? [0xFFFFFF, 0xDADADA, 0x7A7A7A] : [0x76767C, 0x2C2C30, 0x0D0D0F]
                RadialGradient(stops: [
                    .init(color: Color(nsColor: NSColor(hex: tones[0])), location: 0),
                    .init(color: Color(nsColor: NSColor(hex: tones[1])), location: 0.45),
                    .init(color: Color(nsColor: NSColor(hex: tones[2])), location: 1),
                ], center: light, startRadius: 0, endRadius: size * 0.85)
                .frame(width: size, height: size)
                .overlay {
                    if scanning {
                        // Diagonal band of light passing over the surface.
                        LinearGradient(colors: [.clear, .white.opacity(scheme == .dark ? 0.55 : 0.25), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: size * 0.45, height: size * 1.6)
                            .rotationEffect(.degrees(25))
                            .offset(x: size * (-1.0 + 2.0 * sweep))
                            .blendMode(.plusLighter)
                    }
                }
                .clipShape(BittenCircle(bite: biteIn))
                .overlay(BittenCircle(bite: biteIn).stroke(Color.black.opacity(0.08), lineWidth: max(0.5, size * 0.006)))
                .scaleEffect((0.7 + 0.3 * orbIn) * breath)
                .opacity(Double(orbIn))
                .blur(radius: (1 - orbIn) * size * 0.08)

                if scanning {
                    // Sonar ripples coming out of the spark.
                    ForEach(0..<3, id: \.self) { i in
                        let p = ((t / 1.6) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(Self.blue.opacity(0.6 * (1 - p)), lineWidth: max(1, size * 0.01))
                            .frame(width: size * (0.1 + p * 0.45), height: size * (0.1 + p * 0.45))
                            .offset(dotOffset)
                    }
                }
                Circle()
                    .fill(Self.blue)
                    .frame(width: size * 0.107, height: size * 0.107)
                    .shadow(color: Self.blue.opacity(0.9), radius: size * (scanning ? 0.08 : 0.04))
                    .scaleEffect((1 + (scanning ? 0.22 : 0.15) * sin(t * (scanning ? 3.9 : 2.2))) * dotIn)
                    .offset(dotOffset)
            }
            .frame(width: size, height: size)
        }
        .onAppear {
            guard intro else { return }
            orbIn = 0; biteIn = 0; dotIn = 0
            withAnimation(.spring(duration: 0.9, bounce: 0.2)) { orbIn = 1 }
            withAnimation(.spring(duration: 0.6, bounce: 0.25).delay(0.55)) { biteIn = 1 }
            withAnimation(.spring(duration: 0.6, bounce: 0.6).delay(0.95)) { dotIn = 1 }
        }
    }
}

/// Unit circle minus the bite, in the same proportions as the app icon.
/// `bite` 0 keeps the bite circle outside the orb; 1 puts it in place.
struct BittenCircle: Shape {
    var bite: CGFloat = 1

    var animatableData: CGFloat {
        get { bite }
        set { bite = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = rect.width
        let d = (1 - bite) * s * 0.35
        let circle = Path(ellipseIn: rect)
        let biteRect = CGRect(x: rect.minX + s * 0.698 + d, y: rect.minY - s * 0.194 - d,
                              width: s * 0.496, height: s * 0.496)
        return circle.subtracting(Path(ellipseIn: biteRect))
    }
}

// MARK: Celebration

/// Particles bursting outward once; re-fires when `trigger` changes.
struct Burst: View {
    let trigger: Int
    @State private var fired = false
    private let colors: [Color] = [Theme.blue, Theme.violet, Theme.teal, Theme.pink, Theme.amber, .white]

    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { i in
                let angle = Double(i) / 18 * 2 * .pi + Double(i % 3) * 0.2
                let dist = 60.0 + Double((i * 37) % 50)
                Circle()
                    .fill(colors[i % colors.count])
                    .frame(width: CGFloat(4 + i % 3 * 2), height: CGFloat(4 + i % 3 * 2))
                    .offset(x: fired ? cos(angle) * dist : 0, y: fired ? sin(angle) * dist * 0.6 : 0)
                    .opacity(fired ? 0 : 1)
                    .scaleEffect(fired ? 0.4 : 1)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger, initial: true) {
            fired = false
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.9)) { fired = true }
            }
        }
    }
}

// MARK: Liquid Glass

extension View {
    /// Real window-level Liquid Glass (NSGlassEffectView) behind the view on macOS 26+,
    /// a popover material before that.
    func glassWindowBackground(radius: CGFloat = 16) -> some View {
        background {
            ZStack {
                WindowGlass(radius: radius)
                if #unavailable(macOS 26.0) {
                    VisualEffect(material: .popover)
                }
            }
            .ignoresSafeArea()
        }
    }
}

/// Swaps the window's own background for an NSGlassEffectView.
struct WindowGlass: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { install(from: v) }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { install(from: v) }
    }

    private func install(from v: NSView) {
        guard let window = v.window, let content = window.contentView, let frame = content.superview else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        guard #available(macOS 26.0, *) else { return }
        hideMaterials(in: frame, except: content)
        if frame.subviews.contains(where: { $0 is NSGlassEffectView }) { return }
        let glass = NSGlassEffectView(frame: frame.bounds)
        glass.cornerRadius = radius
        glass.style = .regular
        glass.autoresizingMask = [.width, .height]
        frame.addSubview(glass, positioned: .below, relativeTo: content)
        window.invalidateShadow()
    }

    /// Hides the system's own popover material so only our glass shows.
    private func hideMaterials(in view: NSView, except content: NSView) {
        for sub in view.subviews where sub !== content {
            if sub is NSVisualEffectView { sub.isHidden = true }
            hideMaterials(in: sub, except: content)
        }
    }
}
