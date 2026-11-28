import SwiftUI

struct SpaceView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let _ = store.treeVersion
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Space", subtitle: subtitle) {
                VolumePicker()
                Button {
                    store.tree = nil
                    store.mapDisk()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                        Text("Map again")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(store.isMappingDisk)
                .opacity(store.tree == nil ? 0 : 1)
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 16)

            if let focus = store.spaceFocus, !store.isMappingDisk {
                Breadcrumbs(node: focus)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)

                TreemapView(node: focus)
                    .id(focus.id)
                    .frame(height: 300)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 14)

                NodeList(node: focus)
                    .id(focus.id)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            } else if store.isMappingDisk {
                MappingProgress()
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            } else {
                MapPrompt()
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            }
        }
    }

    private var subtitle: String {
        guard let f = store.spaceFocus, !store.isMappingDisk else {
            return store.isMappingDisk ? "Mapping every folder in your home and Applications…" : "A map of every folder in your home and Applications."
        }
        return trf("%@ in %@", Fmt.bytes(f.size), tr(f.name)) + (f.fileCount > 0 ? " · " + plural(f.fileCount, .file) : "")
    }
}

// MARK: Breadcrumbs

private struct Breadcrumbs: View {
    @Environment(Store.self) private var store
    let node: DiskNode

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if let p = node.parent { store.focus(p) }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(node.parent == nil ? Theme.faint : Theme.text)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            .disabled(node.parent == nil)
            .keyboardShortcut("[", modifiers: .command)

            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(node.path.enumerated()), id: \.element.id) { i, n in
                        if i > 0 {
                            Text("/").font(Theme.mono(12)).foregroundStyle(Theme.faint)
                        }
                        Button(n.name) { store.focus(n) }
                            .buttonStyle(.plain)
                            .font(Theme.mono(12, n === node ? .semibold : .regular))
                            .foregroundStyle(n === node ? Theme.text : Theme.muted)
                            .padding(.horizontal, 6)
                            .frame(height: 26)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

// MARK: Treemap

struct TreemapView: View {
    @Environment(Store.self) private var store
    let node: DiskNode
    @State private var hovered: ObjectIdentifier?

    var body: some View {
        let shown = Array(node.children.filter { $0.size > 0 }.prefix(48))
        GeometryReader { geo in
            let rects = Squarify.layout(shown.map { Double($0.size) },
                                        in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 6, dy: 6))
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(shown, rects).enumerated()), id: \.element.0.id) { i, pair in
                    let (child, rect) = pair
                    Tile(node: child, rect: rect, hovered: hovered == child.id, index: i)
                        .onHover { hovered = $0 ? child.id : (hovered == child.id ? nil : hovered) }
                        .onTapGesture { if child.isDrillable { store.focus(child) } }
                        .contextMenu { NodeMenu(node: child) }
                }
            }
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if let h = shown.first(where: { $0.id == hovered }) {
                HStack(spacing: 8) {
                    Image(systemName: h.kind.symbol).foregroundStyle(h.kind.color)
                    Text(h.name).foregroundStyle(Theme.text)
                    Text(Fmt.bytes(h.size)).font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    if h.isDrillable { Text("click to open").foregroundStyle(Theme.faint) }
                }
                .font(Theme.sans(12, .medium))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.borderStrong))
                .padding(12)
                .allowsHitTesting(false)
            }
        }
    }

    private struct Tile: View {
        let node: DiskNode
        let rect: CGRect
        let hovered: Bool
        let index: Int
        @State private var shown = false

        var body: some View {
            let r = rect.insetBy(dx: 1.5, dy: 1.5)
            let color = node.kind.tint(index)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(hovered ? 0.34 : 0.18))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(color.opacity(hovered ? 0.9 : 0.4), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if r.width > 64 && r.height > 34 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name)
                                .font(Theme.sans(12, .medium))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Text(Fmt.bytes(node.size))
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(8)
                    }
                }
                .frame(width: max(r.width, 0), height: max(r.height, 0))
                .scaleEffect(shown ? (hovered ? 1.02 : 1) : 0.6, anchor: .center)
                .opacity(shown ? 1 : 0)
                .offset(x: r.minX, y: r.minY)
                .animation(.spring(duration: 0.25, bounce: 0.3), value: hovered)
                .onAppear {
                    withAnimation(.spring(duration: 0.5, bounce: 0.22).delay(Double(min(index, 30)) * 0.018)) { shown = true }
                }
        }
    }
}

// MARK: List

private struct NodeList: View {
    @Environment(Store.self) private var store
    let node: DiskNode

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SectionLabel(text: "Name")
                Spacer()
                SectionLabel(text: "Share").frame(width: 170, alignment: .leading)
                SectionLabel(text: "Size").frame(width: 84, alignment: .trailing)
                Color.clear.frame(width: 14)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            Hairline()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(node.children.enumerated()), id: \.element.id) { i, child in
                        if i > 0 { Hairline() }
                        NodeRow(node: child, parentSize: node.size, index: i)
                            .onTapGesture { if child.isDrillable { store.focus(child) } }
                            .appear(Double(min(i, 14)) * 0.025)
                            .contextMenu { NodeMenu(node: child) }
                    }
                }
            }
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NodeRow: View {
    let node: DiskNode
    let parentSize: Int64
    let index: Int

    var body: some View {
        let share = parentSize > 0 ? Double(node.size) / Double(parentSize) : 0
        HoverRow {
            HStack(spacing: 12) {
                Image(systemName: node.kind.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(node.kind.tint(index))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(Theme.sans(13, .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(node.kind == .folder || node.kind == .code
                         ? plural(node.fileCount, .file) : node.kind.label)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faint)
                }
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.hover)
                            Capsule().fill(node.kind.tint(index).opacity(0.8))
                                .frame(width: max(2, geo.size.width * share))
                        }
                    }
                    .frame(width: 110, height: 4)
                    Text(share < 0.001 ? "<0.1%" : String(format: "%.1f%%", share * 100))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 48, alignment: .trailing)
                }
                .frame(width: 170, alignment: .leading)
                Text(Fmt.bytes(node.size))
                    .font(Theme.mono(13, .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 84, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .opacity(node.isDrillable ? 1 : 0)
                    .frame(width: 14)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
        }
    }
}

struct NodeMenu: View {
    @Environment(Store.self) private var store
    let node: DiskNode

    var body: some View {
        if let url = node.url {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            if let item = node.asCleanItem(), Trasher.isSafe(url) {
                Divider()
                Button("Move to Trash…") { store.requestClean([item]) }
            }
        }
    }
}

// MARK: Progress + permissions

/// The logo at work plus a live file counter and the folder being read.
struct MappingProgress: View {
    @Environment(Store.self) private var store
    var title = "Mapping your disk"
    var boxed = true

    var body: some View {
        VStack(spacing: 14) {
            OrbView(size: 84, scanning: true)
                .padding(.bottom, 10)
            Text(tr(title))
                .font(Theme.sans(15, .semibold))
                .foregroundStyle(Theme.text)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.mapProgress.files.formatted())
                    .font(Theme.mono(28, .semibold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Text("files").font(Theme.sans(13)).foregroundStyle(Theme.faint)
            }
            .animation(.snappy, value: store.mapProgress.files)
            Text(Fmt.tilde(store.mapProgress.path))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, boxed ? 0 : 40)
        .background { if boxed { Theme.card } }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { if boxed { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border) } }
        .appear()
    }
}

enum FullDiskAccess {
    /// ~/Library/Safari is readable only with Full Disk Access.
    static var granted: Bool {
        // `--args -debugFDA YES|NO` forces the answer (for screenshots).
        if let forced = UserDefaults.standard.object(forKey: "debugFDA") as? Bool { return forced }
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// Opens the pane with a card to drag Prune into the list.
    @MainActor static func openSettings() { PermissionHelper.open(.fullDiskAccess) }
}

/// Shown until the user asks for a disk map.
struct MapPrompt: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            IconTile(symbol: "square.split.2x2.fill", color: Theme.blue, size: 52)
                .padding(.bottom, 6)
            Text("Map your disk")
                .font(Theme.sans(18, .semibold))
                .foregroundStyle(Theme.text)
            Text("See which folders take the most space and drill into them.\nTakes about a minute and reads only file sizes.")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button { store.mapDisk() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                    Text("Map my disk")
                }
            }
            .buttonStyle(PruneButtonStyle(kind: .primary, height: 36))
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }
}
