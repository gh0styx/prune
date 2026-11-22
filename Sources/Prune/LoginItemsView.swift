import SwiftUI

struct LoginItemsView: View {
    @Environment(Store.self) private var store
    @State private var user: [LaunchEntry]?
    @State private var system: [LaunchEntry] = []
    @State private var errors: [String: String] = [:]
    @State private var busy: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Login items", subtitle: "Apps and helpers that start on their own when you log in.") {
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

            if let user {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        settingsCard
                        section("Your launch agents", count: user.count) {
                            if user.isEmpty {
                                emptyRow("No launch agents in your Library folder.")
                            } else {
                                rows(user)
                            }
                        }
                        if !system.isEmpty {
                            section("System-wide", count: system.count) { rows(system) }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
                }
            } else {
                VStack(spacing: 14) {
                    OrbView(size: 72, scanning: true)
                    Text("Looking for login items…").font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await refresh() }
    }

    // MARK: Pieces

    private var settingsCard: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "gearshape", color: Theme.blue, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("Apps that open at login are managed in System Settings")
                    .font(Theme.sans(13.5, .semibold)).foregroundStyle(Theme.text)
                Text("Background items registered by apps can't be listed here. Switch them off in System Settings.")
                    .font(Theme.sans(12.5)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            Button("Open Login Items settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.secondary)
        }
        .padding(16)
        .card()
        .appear()
    }

    private func section<C: View>(_ title: String, count: Int, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel(text: title)
                Text(verbatim: "\(count)").font(Theme.mono(11)).foregroundStyle(Theme.faint)
            }
            content()
                .card()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(tr(text)).font(Theme.sans(13)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity).padding(.vertical, 22)
    }

    private func rows(_ list: [LaunchEntry]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                VStack(spacing: 0) {
                    if i > 0 { Hairline() }
                    LaunchRow(entry: e, error: errors[e.id], busy: busy.contains(e.id),
                              onToggle: { toggle(e) }, onRemove: { remove(e) })
                }
                .appear(Double(min(i, 14)) * 0.025)
            }
        }
    }

    // MARK: Actions

    private func refresh() async {
        let r = await Task.detached(priority: .utility) { LoginItemsScanner.scan() }.value
        if Task.isCancelled { return }
        withAnimation(.snappy(duration: 0.3)) {
            user = r.user
            system = r.system
        }
    }

    private func toggle(_ e: LaunchEntry) {
        busy.insert(e.id)
        errors[e.id] = nil
        Task {
            let err = await Task.detached { e.disabled ? LoginItemsScanner.enable(e) : LoginItemsScanner.disable(e) }.value
            if let err { errors[e.id] = err }
            busy.remove(e.id)
            await refresh()
        }
    }

    private func remove(_ e: LaunchEntry) {
        let item = CleanItem(url: e.plist, category: .security, name: e.label, kind: "Launch agent",
                             location: "~/Library/LaunchAgents", size: 0, lastActivity: nil, isStale: false)
        store.requestClean([item])
    }
}

private struct LaunchRow: View {
    let entry: LaunchEntry
    let error: String?
    let busy: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.label).font(Theme.sans(13, .medium)).foregroundStyle(Theme.text)
                            .lineLimit(1).truncationMode(.middle)
                        if let app = entry.appName {
                            Text(app).font(Theme.sans(11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    Text(entry.program ?? tr("No program"))
                        .font(Theme.mono(11)).foregroundStyle(Theme.faint)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 6) {
                        if entry.isSystem { Badge(text: "System-wide", color: Theme.muted) }
                        if !entry.programExists { Badge(text: "Broken", color: Theme.red) }
                        if entry.disabled { Badge(text: "Disabled", color: Theme.amber) }
                        else if entry.loaded { Badge(text: "Loaded", color: Theme.green) }
                        else { Badge(text: "Not loaded", color: Theme.muted) }
                        if entry.runAtLoad { Badge(text: "Runs at login", color: Theme.blue) }
                        if entry.keepAlive { Badge(text: "Keeps running", color: Theme.teal) }
                    }
                }
                Spacer(minLength: 12)
                if busy {
                    Spinner(size: 14)
                } else if entry.isUser {
                    Button(entry.disabled ? "Enable" : "Disable", action: onToggle)
                        .buttonStyle(PruneButtonStyle(kind: .secondary, height: 28))
                    Button("Remove…", action: onRemove)
                        .buttonStyle(PruneButtonStyle(kind: entry.programExists ? .ghost : .danger, height: 28))
                } else {
                    Button("Reveal in Finder") { reveal() }
                        .buttonStyle(PruneButtonStyle(kind: .ghost, height: 28))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .padding(.vertical, 6)

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                    Text(error).font(Theme.sans(11.5)).lineLimit(2)
                    Spacer()
                }
                .foregroundStyle(Theme.red)
                .padding(.horizontal, 60).padding(.bottom, 8)
            }
        }
        .contextMenu {
            Button("Reveal in Finder") { reveal() }
            Button("Copy label") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.label, forType: .string)
            }
        }
        .modifier(RowHover())
    }

    @ViewBuilder
    private var icon: some View {
        if let app = entry.appPath, FileManager.default.fileExists(atPath: app) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app))
                .resizable().frame(width: 32, height: 32)
        } else {
            IconTile(symbol: entry.programExists ? "gearshape.2" : "exclamationmark.triangle",
                     color: entry.programExists ? Theme.muted : Theme.red, size: 32)
        }
    }

    private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([entry.plist]) }
}

private struct RowHover: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(hovering ? Theme.text.opacity(0.04) : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
