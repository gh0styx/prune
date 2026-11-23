import SwiftUI
import AppKit
import ImageIO

struct DuplicatesView: View {
    @Environment(Store.self) private var store

    private enum Tab: Hashable { case identical, photos }
    private enum Phase { case idle, scanning, done }

    private struct TabState {
        var phase = Phase.idle
        var groups: [DuplicateGroup] = []
        var selected = Set<URL>()
        var progress = DupProgress()
    }

    @State private var tab = Tab.identical
    @State private var states: [Tab: TabState] = [.identical: TabState(), .photos: TabState()]
    @State private var snap = DupProgress.Snapshot()

    private var current: TabState { states[tab] ?? TabState() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Duplicates", subtitle: CategoryID.duplicates.blurb) {
                if current.phase == .done, !current.groups.isEmpty {
                    Button {
                        store.requestClean(cleanItems())
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.fill").font(.system(size: 12, weight: .semibold))
                            Text(trf("Move %lld to Trash", selectedFiles().count))
                            Text(Fmt.bytes(selectedBytes()))
                                .font(Theme.mono(12, .medium)).opacity(0.65)
                        }
                    }
                    .buttonStyle(.danger)
                    .disabled(selectedFiles().isEmpty || store.isCleaning)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 20)

            HStack(spacing: 12) {
                Segmented(selection: $tab, options: [(Tab.identical, "Identical files"), (Tab.photos, "Similar photos")])
                Spacer()
                if current.phase == .done {
                    if !current.groups.isEmpty {
                        let wasted = current.groups.reduce(0) { $0 + $1.wasted }
                        Text(trf("%lld groups · %@ can be freed", current.groups.count, Fmt.bytes(wasted)))
                            .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    }
                    Button { start(tab) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                            Text("Scan again")
                        }
                    }
                    .buttonStyle(.ghost)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 14)

            Group {
                switch current.phase {
                case .idle: idleView
                case .scanning: scanningView
                case .done: resultsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: current.phase == .scanning ? tab : nil) {
            guard current.phase == .scanning else { return }
            let p = current.progress
            while !Task.isCancelled {
                snap = p.snapshot()
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        .onChange(of: store.isCleaning) { old, new in
            if old && !new { dropRemoved() }
        }
    }

    // MARK: States

    private var idleView: some View {
        VStack(spacing: 14) {
            IconTile(symbol: tab == .identical ? "square.on.square.fill" : "photo.on.rectangle.angled", color: CategoryID.duplicates.color, size: 52)
            Text(tab == .identical ? "Find identical files" : "Find similar photos")
                .font(Theme.sans(16, .semibold)).foregroundStyle(Theme.text)
            Text(tab == .identical
                 ? "Compares file contents in Documents, Desktop, Downloads, Pictures, Movies and Music. Files under 1 MB are skipped."
                 : "Finds photos that are almost the same shot in Pictures, Desktop, Downloads and Documents. Your Photos library is never touched.")
                .font(Theme.sans(13)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button { start(tab) } label: {
                Text(tab == .identical ? "Find duplicates" : "Find similar photos")
            }
            .buttonStyle(.primary)
            .padding(.top, 4)
        }
        .padding(.bottom, 60)
        .appear()
    }

    private var scanningView: some View {
        VStack(spacing: 14) {
            OrbView(size: 72, scanning: true)
            Text(tab == .identical ? "Comparing files…" : "Comparing photos…")
                .font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
            Text(snap.total > 0 ? trf("%lld of %lld", snap.processed, snap.total) : trf("%lld files found", snap.total))
                .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                .contentTransition(.numericText())
            Text(snap.path)
                .font(Theme.mono(11)).foregroundStyle(Theme.faint)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 480)
        }
        .padding(.bottom, 60)
    }

    @ViewBuilder private var resultsView: some View {
        if current.groups.isEmpty {
            VStack(spacing: 10) {
                IconTile(symbol: "checkmark.circle.fill", color: Theme.green, size: 44)
                Text(tab == .identical ? "No duplicates found" : "No similar photos found")
                    .font(Theme.sans(15, .semibold)).foregroundStyle(Theme.text)
                Text("Nothing to clean up here.").font(Theme.sans(13)).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 60)
            .appear()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if tab == .identical { duplicateWarning }
                    ForEach(Array(current.groups.enumerated()), id: \.element.id) { i, g in
                        groupCard(g)
                            .appear(Double(min(i, 10)) * 0.04)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
            }
        }
    }

    private func groupCard(_ g: DuplicateGroup) -> some View {
        let selected = current.selected
        let unselected = g.files.filter { !selected.contains($0.url) }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                if tab == .identical { SizeText(bytes: g.size) }
                Text(plural(g.files.count, .file)).font(Theme.sans(12.5, .medium)).foregroundStyle(Theme.muted)
                Text(trf("%@ can be freed", Fmt.bytes(g.wasted))).font(Theme.sans(12)).foregroundStyle(Theme.faint)
                Spacer()
                Button("Keep newest") { keep(g, newest: true) }.buttonStyle(.ghost)
                Button("Keep oldest") { keep(g, newest: false) }.buttonStyle(.ghost)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            Hairline()
            ForEach(Array(g.files.enumerated()), id: \.element.id) { i, f in
                if i > 0 { Hairline() }
                let on = selected.contains(f.url)
                let isLast = !on && unselected.count == 1
                fileRow(f, in: g, on: on, locked: isLast)
            }
            Hairline()
            HStack(spacing: 6) {
                Text(keepSummary(g, selected: selected))
                    .font(Theme.sans(12)).foregroundStyle(Theme.muted)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func keepSummary(_ g: DuplicateGroup, selected: Set<URL>) -> String {
        let kept = g.files.filter { !selected.contains($0.url) }
        let moved = g.files.count - kept.count
        if kept.count == 1, let k = kept.first {
            return trf("Keeps %@ · moves %lld to Trash", k.location + "/" + k.name, moved)
        }
        return trf("Keeps %lld copies · moves %lld to Trash", kept.count, moved)
    }

    private var duplicateWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.amber)
            Text(tr("Identical copies are sometimes needed on purpose. A project may expect its own copy of a file. Check both paths before you move anything to the Trash."))
                .font(Theme.sans(12.5)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.hover)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func fileRow(_ f: DuplicateFile, in g: DuplicateGroup, on: Bool, locked: Bool) -> some View {
        HoverRow {
            HStack(spacing: 12) {
                Button { toggle(f) } label: {
                    CheckBox(state: on).opacity(locked ? 0.35 : 1).padding(4).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(locked)
                .help(locked ? tr("Keep at least one file in each group.") : "")
                DupThumb(url: f.url)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.name).font(Theme.sans(13, .medium)).foregroundStyle(Theme.text)
                        .lineLimit(1).truncationMode(.middle)
                    Text(f.location).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                        .lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 12)
                Badge(text: on ? tr("Move to Trash") : tr("Keep"), color: on ? Theme.red : Theme.green)
                if tab == .photos {
                    Text(Fmt.bytes(f.size)).font(Theme.mono(11.5)).foregroundStyle(Theme.muted)
                }
                Text(Fmt.relative(f.modified)).font(Theme.sans(12)).foregroundStyle(Theme.muted)
                    .frame(minWidth: 70, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { if !locked { toggle(f) } }
        }
        .contextMenu {
            Button("Keep only this copy") { keepOnly(g, f) }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
            Button("Open") { NSWorkspace.shared.open(f.url) }
        }
    }

    // MARK: Actions

    private func update(_ t: Tab, _ change: (inout TabState) -> Void) {
        var s = states[t] ?? TabState()
        change(&s)
        states[t] = s
    }

    private func start(_ t: Tab) {
        guard states[t]?.phase != .scanning else { return }
        let progress = DupProgress()
        update(t) { $0.phase = .scanning; $0.progress = progress; $0.groups = []; $0.selected = [] }
        snap = DupProgress.Snapshot()
        Task {
            let groups = await Task.detached(priority: .userInitiated) {
                t == .identical ? DuplicateFinder.identical(progress: progress) : DuplicateFinder.similarPhotos(progress: progress)
            }.value
            withAnimation(.snappy) {
                update(t) {
                    $0.groups = groups
                    $0.selected = Set(groups.flatMap { Self.defaultSelection($0, keepNewest: true) })
                    $0.phase = .done
                }
            }
        }
    }

    private static func defaultSelection(_ g: DuplicateGroup, keepNewest: Bool) -> [URL] {
        g.trashed(keeping: keepNewest ? .newest : .oldest).map(\.url)
    }

    private func keep(_ g: DuplicateGroup, newest: Bool) {
        let urls = Set(g.files.map(\.url))
        update(tab) {
            $0.selected.subtract(urls)
            $0.selected.formUnion(Self.defaultSelection(g, keepNewest: newest))
        }
    }

    private func keepOnly(_ g: DuplicateGroup, _ f: DuplicateFile) {
        let urls = Set(g.files.map(\.url))
        update(tab) {
            $0.selected.subtract(urls)
            $0.selected.formUnion(urls.subtracting([f.url]))
        }
    }

    private func toggle(_ f: DuplicateFile) {
        update(tab) {
            if $0.selected.contains(f.url) { $0.selected.remove(f.url) } else { $0.selected.insert(f.url) }
        }
    }

    private func selectedFiles() -> [DuplicateFile] {
        let s = current.selected
        return current.groups.flatMap { $0.files.filter { s.contains($0.url) } }
    }

    private func selectedBytes() -> Int64 { selectedFiles().reduce(0) { $0 + $1.size } }

    private func cleanItems() -> [CleanItem] {
        let kind = tab == .identical ? tr("Duplicate") : tr("Similar photo")
        return selectedFiles().map {
            CleanItem(url: $0.url, category: .duplicates, name: $0.name, kind: kind, location: $0.location,
                      size: $0.size, lastActivity: $0.modified, isStale: false)
        }
    }

    /// After cleaning, forget files that are gone and groups that no longer have a pair.
    private func dropRemoved() {
        for t in [Tab.identical, .photos] {
            guard let s = states[t], s.phase == .done else { continue }
            let fm = FileManager.default
            let identical = t == .identical
            var groups: [DuplicateGroup] = []
            for g in s.groups {
                let left = g.files.filter { fm.fileExists(atPath: $0.url.path) }
                if left.count > 1 { groups.append(DuplicateGroup(id: g.id, files: left, identical: identical)) }
            }
            let alive = Set(groups.flatMap { $0.files.map(\.url) })
            withAnimation(.snappy) {
                update(t) {
                    $0.groups = groups.sorted { $0.wasted > $1.wasted }
                    $0.selected = $0.selected.intersection(alive)
                }
            }
        }
    }
}

/// 40 pt preview: a real thumbnail for images, the file icon for everything else.
private struct DupThumb: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .frame(width: 40, height: 40)
        .background(Theme.hover)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border))
        .task(id: url) {
            let u = url
            let img = await Task.detached(priority: .utility) { () -> NSImage? in
                let ext = u.pathExtension.lowercased()
                if DuplicateFinder.imageExtensions.contains(ext),
                   let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                   let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                       kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 96,
                   ] as CFDictionary) {
                    return NSImage(cgImage: cg, size: NSSize(width: 40, height: 40))
                }
                return nil
            }.value
            image = img ?? NSWorkspace.shared.icon(forFile: u.path)
        }
    }
}
