import SwiftUI

/// Native sidebar vibrancy (blends with what's behind the window), like Claude and Codex.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        // Always the active look: with .followsWindowActiveState the sidebar turns see-through when Prune is in the background.
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Real Liquid Glass (NSGlassEffectView) on macOS 26+, the native sidebar material before that.
struct SidebarGlass: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            // A blur that always stays active sits under the glass, so the sidebar does not turn
            // see-through when the window loses focus. The tint stays on top.
            ZStack {
                VisualEffect(material: .sidebar)
                GlassSurface()
                // The glass turns light grey when the window is inactive, so a near-solid colour sits on top of it.
                Color(nsColor: Self.backing).opacity(0.95)
            }
        } else {
            VisualEffect(material: .sidebar)
        }
    }

    /// The sidebar's colour, used for the resize gutter next to it.
    static var backing: NSColor {
        NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0x262624) : NSColor(hex: 0xF2F2F5)
        }
    }
}

@available(macOS 26.0, *)
private struct GlassSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let v = NSGlassEffectView()
        v.style = .regular
        v.tintColor = Self.tint
        return v
    }

    func updateNSView(_ v: NSGlassEffectView, context: Context) { v.tintColor = Self.tint }

    /// A near-opaque dark veil in dark mode (like Claude's sidebar) and a light one in light mode,
    /// so the glass keeps its colour whether or not the window is active.
    private static var tint: NSColor {
        NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: 0x262624, alpha: 0.95)
                : NSColor(hex: 0xF2F2F5, alpha: 0.9)
        }
    }
}

struct Sidebar: View {
    @Environment(Store.self) private var store
    @Namespace private var ns
    @State private var collapsed: Set<CategoryGroup> = []

    static let width: CGFloat = 248

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's title bar (traffic lights + the sidebar button in the toolbar).
            Color.clear.frame(height: 38)

            HStack(spacing: 8) {
                OrbView(size: 20, animated: false, glow: false, scanning: store.isScanning || store.isMappingDisk)
                    .frame(width: 22, height: 22)
                Text("Prune")
                    .font(Theme.sans(14, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 10)

            ActionRow(symbol: store.isScanning ? nil : "bolt.fill",
                      title: store.isScanning ? "Scanning…" : "Scan", shortcut: "⌘R") {
                store.scan()
            }
            .disabled(store.isScanning)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    row(.overview, symbol: "square.grid.2x2", title: "Overview",
                        trailing: store.hasScanned ? Fmt.bytes(store.reclaimable) : nil)
                    row(.space, symbol: "square.split.2x2", title: "Space",
                        trailing: store.tree.map { Fmt.bytes($0.size) }, loading: store.isMappingDisk)
                    categoryRow(.largeFiles)
                    row(.category(.apps), symbol: CategoryID.apps.symbol, title: "Apps",
                        trailing: store.apps.map { "\($0.count)" }, loading: store.isLoadingApps)
                    row(.history, symbol: "clock.arrow.circlepath", title: "History",
                        trailing: store.history.isEmpty ? nil : "\(store.history.count)")

                    SectionHeader(title: "Tools", collapsed: collapsed.contains(.storage)) {
                        withAnimation(.snappy(duration: 0.25)) {
                            if collapsed.contains(.storage) { collapsed.remove(.storage) } else { collapsed.insert(.storage) }
                        }
                    }
                    .padding(.top, 14)
                    if !collapsed.contains(.storage) {
                        categoryRow(.security)
                        categoryRow(.duplicates)
                        row(.loginItems, symbol: "power.circle", title: "Login items", trailing: nil)
                        row(.maintenance, symbol: "wrench.and.screwdriver", title: "Maintenance", trailing: nil)
                    }

                    ForEach([CategoryGroup.developer, .system].filter { store.developerMode || $0 != .developer }, id: \.self) { group in
                        SectionHeader(title: group.rawValue, collapsed: collapsed.contains(group)) {
                            withAnimation(.snappy(duration: 0.25)) {
                                if collapsed.contains(group) { collapsed.remove(group) } else { collapsed.insert(group) }
                            }
                        }
                        .padding(.top, 14)
                        if !collapsed.contains(group) {
                            if group == .developer {
                                row(.devServers, symbol: "network", title: "Dev servers", trailing: nil)
                            }
                            ForEach(CategoryID.allCases.filter { $0.group == group }) { categoryRow($0) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            SidebarFooter()
        }
        .padding(.horizontal, 8)
        .frame(width: store.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        // Liquid Glass on macOS 26+, the native sidebar material before that. No opaque tint on top,
        // so the wallpaper and windows behind the app show through.
        .background {
            SidebarGlass()
                .ignoresSafeArea()
        }
    }

    private func row(_ route: Route, symbol: String, title: String, trailing: String?, loading: Bool = false) -> some View {
        SidebarRow(symbol: symbol, title: title, trailing: trailing, loading: loading,
                   selected: store.route == route, ns: ns) { store.route = route }
    }

    private func categoryRow(_ c: CategoryID) -> some View {
        SidebarRow(symbol: c.symbol, title: c.title,
                   trailing: store.items[c] == nil ? nil : Fmt.bytes(store.size(c)),
                   loading: store.pending.contains(c),
                   selected: store.route == .category(c), ns: ns) {
            store.route = .category(c)
        }
    }
}

// MARK: Pieces

private struct ActionRow: View {
    let symbol: String?
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.text.opacity(0.08))
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                    } else {
                        Spinner(size: 10)
                    }
                }
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.text)
                Text(tr(title))
                    .font(Theme.sans(13, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if hovering {
                    Text(shortcut).font(Theme.sans(11)).foregroundStyle(Theme.faint)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(hovering ? Theme.text.opacity(0.05) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SectionHeader: View {
    let title: String
    let collapsed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(tr(title))
                    .font(Theme.sans(12, .medium))
                    .foregroundStyle(Theme.faint)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.faint)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .opacity(hovering || collapsed ? 1 : 0)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SidebarRow: View {
    let symbol: String
    let title: String
    let trailing: String?
    let loading: Bool
    let selected: Bool
    var ns: Namespace.ID? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Theme.text : Theme.muted)
                Text(tr(title))
                    .font(Theme.sans(13))
                    .foregroundStyle(selected || hovering ? Theme.text : Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if loading {
                    Spinner(size: 9)
                } else if let trailing {
                    Text(trailing)
                        .font(Theme.sans(11.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.faint)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                if selected, let ns {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.text.opacity(0.09))
                        .matchedGeometryEffect(id: "selection", in: ns)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.text.opacity(0.045))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Bottom row, in the spot where Claude shows the account: disk status and settings.
private struct SidebarFooter: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var hovering = false
    @State private var showDisks = false

    var body: some View {
        let disk = store.disk
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.text.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: disk.usedFraction)
                    .stroke(disk.usedFraction > 0.9 ? Theme.red : disk.usedFraction > 0.75 ? Theme.amber : Theme.text,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(store.volumes.first?.name ?? "Macintosh HD").font(Theme.sans(12.5, .medium)).foregroundStyle(Theme.text)
                    if store.volumes.count > 1 {
                        Text("+\(store.volumes.count - 1)")
                            .font(Theme.mono(10, .semibold)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 5).frame(height: 16)
                            .background(Theme.text.opacity(0.08), in: Capsule())
                    }
                }
                Text(trf("%@ free of %@", Fmt.bytes(disk.free), Fmt.bytes(disk.total)))
                    .font(Theme.sans(11)).foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
                .contentShape(Rectangle())
            Button { SettingsOpener.open(openWindow) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(hovering ? Theme.text : Theme.muted)
                    .frame(width: 28, height: 28)
                    .background(hovering ? Theme.text.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Settings  ⌘,")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { store.refreshVolumes(); showDisks = true }
        .popover(isPresented: $showDisks, arrowEdge: .top) { VolumesList().environment(store) }
        .help(tr("Disks"))
        .overlay(alignment: .top) { Rectangle().fill(Theme.text.opacity(0.07)).frame(height: 1) }
    }
}

