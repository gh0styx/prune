import SwiftUI

struct RootView: View {
    @Environment(Store.self) private var store
    @AppStorage(Prefs.Key.didOnboard) private var didOnboard = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            // The sidebar keeps its width inside while the outer frame animates to 0, so nothing reflows.
            Sidebar()
                .frame(width: store.sidebarVisible ? store.sidebarWidth : 0, alignment: .trailing)
                .clipped()
                .opacity(store.sidebarVisible ? 1 : 0)
            if store.sidebarVisible {
                SidebarResizeHandle()
            }
            ZStack(alignment: .top) {
                Group {
                    switch store.route {
                    case .overview: OverviewView()
                    case .space: SpaceView()
                    case .history: HistoryView()
                    case .devServers: DevServersView()
                    case .maintenance: MaintenanceView()
                    case .loginItems: LoginItemsView()
                    case .category(.apps): AppsView()
                    case .category(.duplicates): DuplicatesView()
                    case .category(.security): SecurityView()
                    case .category(let c): CategoryView(category: c)
                    }
                }
                .id(store.route)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.isScanning || store.isCleaning || store.isMappingDisk { ScanLine() }
            }
            .animation(.snappy(duration: 0.28), value: store.route)
            // Content starts below the title bar so it never slides under the traffic lights and toolbar.
            .clipped()
            .padding(.top, 38)
            .background(Theme.bg)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.text.opacity(0.06)).frame(height: 1).padding(.top, 38)
                    .opacity(store.sidebarVisible ? 0 : 1)
            }
        }
        .ignoresSafeArea()
        .background(WindowChrome())
        .toolbar {
            if didOnboard {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.snappy(duration: 0.32)) { store.sidebarVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(tr("Toggle sidebar  ⌃⌘S"))
            }
            }
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(minWidth: 980, minHeight: 640)
        .task { if Prefs.scanOnLaunch && didOnboard && !store.hasScanned { store.scan() } }
        .task {
            // `--args -previewGate YES` presses Quick scan on launch (for screenshots of the permissions gate).
            if UserDefaults.standard.bool(forKey: "previewGate") { store.scan() }
        }
        .task {
            // `--args -openSettings YES` opens Settings on launch (for screenshots).
            if UserDefaults.standard.bool(forKey: "openSettings") { SettingsOpener.open(openWindow) }
        }
        .overlay {
            if let items = store.confirming {
                ModalHost(onDismiss: { store.confirming = nil }) { ConfirmSheet(items: items) }
                    .transition(.opacity)
            }
        }
        .overlay {
            if let entry = store.confirmingPurge {
                ModalHost(onDismiss: { store.confirmingPurge = nil }) { PurgeSheet(entry: entry) }
                    .transition(.opacity)
            }
        }
        .overlay {
            if didOnboard, store.gatedAction != nil {
                ModalHost(onDismiss: { store.gatedAction = nil }) { PermissionGate() }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.gatedAction == nil)
        .animation(.easeOut(duration: 0.2), value: store.confirming == nil)
        .animation(.easeOut(duration: 0.2), value: store.confirmingPurge == nil)
        .overlay {
            if !didOnboard {
                WelcomeView()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .overlay {
            if store.isCleaning {
                CleaningOverlay().transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: store.isCleaning)
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Toast(text: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: Page header

struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(title))
                    .font(Theme.sans(24, .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(tr(subtitle))
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) { actions }
                .layoutPriority(1)
        }
    }
}

struct CleanButton: View {
    @Environment(Store.self) private var store
    let items: [CleanItem]

    var body: some View {
        let size = items.reduce(0) { $0 + $1.size }
        Button {
            store.requestClean(items)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill").font(.system(size: 12, weight: .semibold))
                Text("Clean")
                if size > 0 {
                    Text(Fmt.bytes(size))
                        .font(Theme.mono(12, .medium))
                        .opacity(0.65)
                        .contentTransition(.numericText())
                }
            }
        }
        .buttonStyle(.primary)
        .disabled(items.isEmpty || store.isCleaning || store.isScanning)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

// MARK: Toast

struct Toast: View {
    @Environment(Store.self) private var store
    let text: String
    var body: some View {
        let entry = store.history.first { $0.id == store.lastEntryID && !$0.inTrash.isEmpty }
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.green)
                .symbolEffect(.bounce, value: text)
                .background(Burst(trigger: text.hashValue))
            Text(tr(text))
                .font(Theme.sans(13, .medium))
                .foregroundStyle(Theme.text)
            if let entry, store.toastHasActions {
                Button("Free space now") { store.requestPurge(entry) }
                    .buttonStyle(PruneButtonStyle(kind: .primary, height: 26))
                Button("Undo") { store.restore(entry) }
                    .buttonStyle(PruneButtonStyle(kind: .ghost, height: 26))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 40)
        .card(radius: 10, highlighted: true)
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }
}

// MARK: Confirm

struct ConfirmSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let items: [CleanItem]

    var body: some View {
        let total = items.reduce(0) { $0 + $1.size }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(trf("Move %@ to Trash?", plural(items.count, .item)))
                    .font(Theme.sans(17, .semibold))
                    .foregroundStyle(Theme.text)
                Text(items.contains { $0.command != nil }
                     ? "Files go to the Trash and can be put back. Docker items are pruned with the docker CLI and can't be restored."
                     : "Nothing is deleted for good. You can put things back from the Trash until you empty it.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            Hairline()
            VStack(spacing: 0) {
                ForEach(items.sorted { $0.size > $1.size }.prefix(6)) { item in
                    HStack {
                        Circle().fill(item.category.color).frame(width: 6, height: 6)
                        Text(item.name).font(Theme.sans(13)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(item.kind).font(Theme.mono(11)).foregroundStyle(Theme.faint).lineLimit(1)
                        Spacer()
                        Text(Fmt.bytes(item.size)).font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 24)
                    .frame(height: 32)
                }
                if items.count > 6 {
                    Text(trf("and %lld more", items.count - 6))
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .frame(height: 30)
                }
            }
            .padding(.vertical, 6)
            .background(Theme.bg)
            Hairline()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total").font(Theme.sans(11)).foregroundStyle(Theme.faint)
                    SizeText(bytes: total, size: 15, weight: .semibold)
                }
                Spacer()
                Button("Cancel") { store.confirming = nil }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") { store.clean(items) }
                    .buttonStyle(.danger)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 460)
        .background(Theme.card)
    }
}


/// Shown while files move to the Trash.
struct CleaningOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 18) {
                OrbView(size: 72, scanning: true)
                Text("Moving to Trash…")
                    .font(Theme.sans(15, .semibold))
                    .foregroundStyle(Theme.text)
                Text("You can put anything back from the Trash.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        }
    }
}

/// Dimmed backdrop + a card that springs in. Click outside or press Esc to dismiss.
struct ModalHost<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder var content: Content
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            content
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderStrong))
                .shadow(color: .black.opacity(0.4), radius: 40, y: 20)
                .scaleEffect(shown ? 1 : 0.9)
                .opacity(shown ? 1 : 0)
                .blur(radius: shown ? 0 : 8)
        }
        .onAppear { withAnimation(.spring(duration: 0.38, bounce: 0.28)) { shown = true } }
        .onExitCommand { onDismiss() }
    }
}

/// Drag the sidebar edge to resize it (200–340 pt); the width is remembered.
struct SidebarResizeHandle: View {
    @Environment(Store.self) private var store
    @State private var startWidth: CGFloat?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || startWidth != nil ? Theme.muted : Theme.sidebarEdge)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovering = inside
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let base = startWidth ?? store.sidebarWidth
                            if startWidth == nil { startWidth = base }
                            store.sidebarWidth = min(max(base + value.translation.width, 200), 340)
                        }
                        .onEnded { _ in
                            startWidth = nil
                            UserDefaults.standard.set(Double(store.sidebarWidth), forKey: "sidebarWidth")
                        })
            }
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Window chrome: opaque canvas-colored window background and a visible titlebar separator,
/// so the window edge and the traffic lights never dissolve into the desktop.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { Self.apply(v.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { Self.apply(v.window) }

    static func apply(_ w: NSWindow?) {
        guard let w else { return }
        w.backgroundColor = NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0x191919) : NSColor(hex: 0xFAFAFA)
        }
        w.titlebarSeparatorStyle = .none
    }
}
