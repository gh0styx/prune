import SwiftUI

/// The menu bar panel: what you can free, the disk, and one main action. Small actions are icons.
struct MenuBarView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var servers: [DevServer] = []

    private func open(_ route: Route? = nil) {
        if let route { store.route = route }
        openWindow(id: "main")
        NSApp.activate()
    }

    var body: some View {
        let shown = store.junkCategories.filter { store.size($0) > 0 || store.pending.contains($0) }

        VStack(spacing: 0) {
            // Disk gauge + mini stats, like a small Overview.
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.text.opacity(0.08), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: store.disk.usedFraction)
                        .stroke(AngularGradient(colors: [Theme.blue, Theme.teal], center: .center),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int((store.disk.usedFraction * 100).rounded()))%")
                            .font(Theme.sans(15, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                        Text("used").font(Theme.sans(9.5)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.volumes.first?.name ?? "Macintosh HD")
                        .font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                    Text(trf("%@ free of %@", Fmt.bytes(store.disk.free), Fmt.bytes(store.disk.total)))
                        .font(Theme.sans(12)).foregroundStyle(.secondary)
                    status.padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                StatTile(symbol: "sparkles", color: Theme.green, label: "Reclaimable",
                         value: store.hasScanned || store.isScanning ? Fmt.bytes(store.reclaimable) : tr("Not scanned"),
                         dim: !(store.hasScanned || store.isScanning))
                StatTile(symbol: "checkmark.circle", color: Theme.blue, label: "Selected",
                         value: store.hasScanned ? Fmt.bytes(store.selectedSize) : "—", dim: !store.hasScanned)
                StatTile(symbol: "clock", color: Theme.violet, label: "Last scan",
                         value: store.lastScan.map { Fmt.relative($0) } ?? tr("Never"), dim: store.lastScan == nil)
                if store.developerMode {
                    StatTile(symbol: "network", color: Theme.amber, label: "Dev servers",
                             value: servers.isEmpty ? "0" : trf("%lld · %@", servers.count,
                                                                Fmt.bytes(servers.reduce(0) { $0 + $1.memoryBytes })),
                             dim: servers.isEmpty) { open(.devServers) }
                } else {
                    StatTile(symbol: "doc.fill", color: Theme.amber, label: "Large files",
                             value: store.items[.largeFiles].map { Fmt.bytes($0.reduce(0) { $0 + $1.size }) } ?? "—",
                             dim: store.items[.largeFiles] == nil) { open(.category(.largeFiles)) }
                }
            }
            .padding(.horizontal, 12)
            .animation(.snappy, value: store.reclaimable)

            // Categories after a scan, or a clear call to action before the first one.
            Group {
                if shown.isEmpty {
                    HStack(spacing: 12) {
                        IconTile(symbol: "magnifyingglass", color: Theme.blue, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No scan yet").font(Theme.sans(12.5, .semibold)).foregroundStyle(Theme.text)
                            Text("Run a scan to see what you can clean.")
                                .font(Theme.sans(11.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .card(radius: 10)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                } else {
                    VStack(spacing: 0) {
                        SegmentBar(segments: store.junkCategories.map { ($0.color, Double(store.size($0))) }, height: 5)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)
                        ForEach(Array(shown.prefix(5).enumerated()), id: \.element) { i, c in
                            Button { open(.category(c)) } label: {
                                HoverRow {
                                    HStack(spacing: 10) {
                                        Image(systemName: c.tileSymbol)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(c.color)
                                            .frame(width: 16)
                                        Text(tr(c.title)).font(Theme.sans(12.5)).foregroundStyle(Theme.text)
                                        Spacer()
                                        if store.pending.contains(c) {
                                            Spinner(size: 9)
                                        } else {
                                            Text(Fmt.bytes(store.size(c)))
                                                .font(Theme.mono(11.5))
                                                .foregroundStyle(.secondary)
                                                .contentTransition(.numericText())
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 28)
                                }
                            }
                            .buttonStyle(.plain)
                            .appear(Double(i) * 0.03)
                        }
                    }
                    .padding(.top, 12)
                }
            }

            // Main action.
            Group {
                if store.hasScanned || store.isScanning {
                    Button {
                        open(.overview)
                        store.requestClean(store.selectedItems)
                    } label: {
                        Label(trf("Clean %@", Fmt.bytes(store.selectedSize)), systemImage: "trash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(store.selectedItems.isEmpty || store.isScanning)
                } else {
                    Button { store.scan(); if store.gatedAction != nil { open() } } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(PanelPrimaryButtonStyle())
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            // Small actions as icons.
            HStack(spacing: 2) {
                IconButton(symbol: "macwindow", help: "Open Prune") { open() }
                Spacer()
                IconButton(symbol: "gearshape", help: "Settings…") { SettingsOpener.open(openWindow) }
                IconButton(symbol: "power", help: "Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: 320)
        .glassWindowBackground()
        .task {
            guard store.developerMode else { return }
            servers = await Task.detached { DevServerScanner.scan().filter(\.isLikelyDevServer) }.value
        }
    }

    @ViewBuilder private var status: some View {
        if store.isScanning {
            HStack(spacing: 6) {
                Spinner(size: 10)
                Text("Scanning…").font(Theme.sans(11)).foregroundStyle(.secondary)
            }
        } else if let last = store.lastScan {
            Text(trf("Updated %@", Fmt.relative(last))).font(Theme.sans(11)).foregroundStyle(.secondary)
        }
    }
}

/// A 30 pt icon button with a hover background and a tooltip.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? Theme.text : Theme.muted)
                .frame(width: 30, height: 30)
                .background(hovering ? Theme.text.opacity(0.08) : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tr(help))
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Small stat card for the menu bar panel.
private struct StatTile: View {
    let symbol: String
    let color: Color
    let label: String
    let value: String
    var dim = false
    var action: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
                Text(tr(label)).font(Theme.sans(11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(value)
                .font(Theme.sans(15, .semibold))
                .monospacedDigit()
                .foregroundStyle(dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Near-opaque card so the text stays readable over any wallpaper, in both appearances.
        .background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.text.opacity(hovering && action != nil ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The panel's main button: same white-on-dark primary as the app, full width, with a soft lift on hover.
private struct PanelPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .labelStyle(.titleAndIcon)
                .font(Theme.sans(13.5, .semibold))
                .foregroundStyle(Theme.inverse)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.text.opacity(hovering ? 0.9 : 1))
                        .shadow(color: .black.opacity(hovering ? 0.35 : 0.2), radius: hovering ? 10 : 6, y: hovering ? 4 : 2)
                }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.spring(duration: 0.22, bounce: 0.35), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}
