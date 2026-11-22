import SwiftUI

struct CategoryView: View {
    @Environment(Store.self) private var store
    let category: CategoryID
    @State private var query = ""
    @State private var sortKey: SortKey = .size
    @State private var ascending = false
    @FocusState private var searchFocused: Bool

    enum SortKey { case name, date, size }

    private var filtered: [CleanItem] {
        var all = store.items(category)
        if !query.isEmpty {
            all = all.filter {
                $0.name.localizedCaseInsensitiveContains(query) || $0.location.localizedCaseInsensitiveContains(query)
                    || $0.kind.localizedCaseInsensitiveContains(query)
            }
        }
        let sorted: [CleanItem] = switch sortKey {
        case .name: all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date: all.sorted { ($0.lastActivity ?? .distantPast) < ($1.lastActivity ?? .distantPast) }
        case .size: all.sorted { $0.size < $1.size }
        }
        return ascending ? sorted : sorted.reversed()
    }

    private func sortHeader(_ title: String, _ key: SortKey) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) {
                if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = key == .name }
            }
        } label: {
            HStack(spacing: 4) {
                SectionLabel(text: title)
                if sortKey == key {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let items = store.items(category)
        let selected = store.selected(in: category)
        let allState: Bool? = selected.isEmpty ? false : selected.count == items.count ? true : nil

        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: category.title, subtitle: category.blurb) {
                if category == .largeFiles {
                    VolumePicker()
                    if store.items[.largeFiles] != nil {
                        Button { store.findLargeFiles() } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(.secondary)
                        .help(tr("Search again"))
                        .disabled(store.isFindingLargeFiles || store.isMappingDisk)
                    }
                }
                if items.contains(where: \.isStale) {
                    Button(category == .largeFiles ? "Select old" : "Select stale") { store.selectStale(category) }
                        .buttonStyle(.secondary)
                }
                CleanButton(items: selected)
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 20)

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faint)
                    TextField("Filter by name or path", text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.sans(13))
                        .focused($searchFocused)
                    Kbd(keys: "⌘F")
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .frame(maxWidth: 360)
                .card(radius: 8, highlighted: searchFocused)
                .background {
                    Button("") { searchFocused = true }
                        .keyboardShortcut("f")
                        .opacity(0)
                }

                Spacer()
                HStack(spacing: 6) {
                    Text(plural(items.count, .item)).foregroundStyle(Theme.muted)
                    Text("·").foregroundStyle(Theme.faint)
                    Text(Fmt.bytes(store.size(category))).foregroundStyle(Theme.text)
                }
                .font(Theme.mono(12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 14)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { store.setAll(category, allState != true) } label: { CheckBox(state: allState) }
                        .buttonStyle(.plain)
                        .disabled(items.isEmpty)
                    sortHeader("Name", .name)
                    Spacer()
                    sortHeader("Last activity", .date).frame(width: 130, alignment: .leading)
                    sortHeader("Frees", .size).frame(width: 110, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .frame(height: 38)
                Hairline()

                if category == .mailAttachments {
                    PhotosTrashCard()
                    Hairline()
                }
                if category == .messengerCaches {
                    MessengerCacheCard()
                    Hairline()
                }
                if category == .largeFiles && store.items[.largeFiles] == nil && !store.isMappingDisk && !store.isFindingLargeFiles {
                    VStack(spacing: 12) {
                        IconTile(symbol: "doc.text.magnifyingglass", color: Theme.blue, size: 48)
                            .padding(.bottom, 4)
                        Text("Find your largest files")
                            .font(Theme.sans(16, .semibold)).foregroundStyle(Theme.text)
                        Text(trf("Looks for files over %lld MB. Skips app data, so nothing here breaks an app.", Prefs.largeFileMB))
                            .font(Theme.sans(13)).foregroundStyle(Theme.muted)
                        HStack(spacing: 8) {
                            Button { store.findLargeFiles() } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .bold))
                                    Text("Find large files")
                                }
                            }
                            .buttonStyle(PruneButtonStyle(kind: .primary, height: 36))
                            Button("Map the whole disk") { store.mapDisk() }
                                .buttonStyle(PruneButtonStyle(kind: .secondary, height: 36))
                        }
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 60)
                } else if category == .docker && (store.dockerStatus == .notRunning || store.dockerStatus == .notInstalled) {
                    DockerState(status: store.dockerStatus)
                } else if category == .largeFiles && (store.isMappingDisk || store.isFindingLargeFiles) {
                    MappingProgress(title: "Finding large files", boxed: false)
                } else if store.pending.contains(category) && items.isEmpty {
                    SkeletonRows()
                } else if filtered.isEmpty {
                    EmptyState(searching: !query.isEmpty)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { Hairline() }
                                ItemRow(item: item, selected: store.selection.contains(item.id))
                                    .onTapGesture { store.toggle(item) }
                                    .appear(Double(min(i, 14)) * 0.025)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
            }
            .card()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
    }
}

struct ItemRow: View {
    @Environment(Store.self) private var store
    let item: CleanItem
    let selected: Bool

    var body: some View {
        HoverRow {
            HStack(spacing: 12) {
                CheckBox(state: selected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(Theme.sans(13, .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(item.kind)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.faint)
                            .lineLimit(1)
                        if item.isStale { Badge(text: item.category == .largeFiles ? "Old" : "Stale", color: Theme.amber) }
                    }
                    Text(item.location)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Text(Fmt.relative(item.lastActivity))
                    .font(Theme.sans(12))
                    .foregroundStyle(item.isStale ? Theme.amber : Theme.muted)
                    .frame(width: 130, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.bytes(item.size))
                        .font(Theme.mono(13, .medium))
                        .foregroundStyle(Theme.text)
                    if item.shared > 0 {
                        Text(trf("+ %@ shared", Fmt.bytes(item.shared)))
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.faint)
                            .help("These files are hard links that also live elsewhere (for example pnpm's store). Removing this item won't free them.")
                    }
                }
                .frame(width: 110, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
        }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button("Never Show This") { store.ignore(item) }
        }
    }
}

private struct SkeletonRows: View {
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                if i > 0 { Hairline() }
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.hover).frame(width: 15, height: 15)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.hover).frame(width: 160, height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(Theme.hover).frame(width: 260, height: 8)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 3).fill(Theme.hover).frame(width: 60, height: 10)
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
            }
            Spacer(minLength: 0)
        }
        // A highlight sweeps across the placeholders, left to right.
        .overlay {
            GeometryReader { geo in
                LinearGradient(colors: [.clear, Theme.text.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: pulse ? geo.size.width : -geo.size.width * 0.5)
            }
            .allowsHitTesting(false)
            .clipped()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

private struct DockerState: View {
    @Environment(Store.self) private var store
    let status: DockerStatus

    var body: some View {
        VStack(spacing: 10) {
            IconTile(symbol: "server.rack", color: Theme.cyan, size: 44)
            Text(status == .notInstalled ? "Docker isn't installed" : "Docker isn't running")
                .font(Theme.sans(14, .semibold))
                .foregroundStyle(Theme.text)
            Text(status == .notInstalled
                 ? "Install Docker Desktop or OrbStack and Prune will find its images and caches."
                 : "Start Docker so Prune can measure images, build cache and volumes.")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
            if status == .notRunning {
                HStack(spacing: 8) {
                    Button("Start Docker") { Self.launchDocker() }
                        .buttonStyle(.secondary)
                    Button("Check again") { store.scan() }
                        .buttonStyle(.primary)
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    static func launchDocker() {
        for id in ["com.docker.docker", "dev.kdrag0n.MacVirt"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
                return
            }
        }
    }
}

private struct EmptyState: View {
    let searching: Bool
    var body: some View {
        VStack(spacing: 10) {
            IconTile(symbol: searching ? "magnifyingglass" : "checkmark", color: Theme.green, size: 40)
            Text(searching ? "No matches" : "Nothing to clean here")
                .font(Theme.sans(14, .semibold))
                .foregroundStyle(Theme.text)
            Text(searching ? "Try a different name or path." : "This category is already tidy.")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}

/// Photos' "Recently Deleted" keeps photos for 30 days and only Photos can empty it.
private struct MessengerCacheCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "exclamationmark.triangle", color: Theme.amber, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Media will download again")
                    .font(Theme.sans(13, .semibold)).foregroundStyle(Theme.text)
                Text("Photos, videos and files come back from the server when you open a chat. Quit Telegram before cleaning. Media from secret chats can't be restored. Messages and your account are not touched.")
                    .font(Theme.sans(12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct PhotosTrashCard: View {
    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "photo.on.rectangle", color: Theme.pink, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Photos keeps deleted pictures for 30 days")
                    .font(Theme.sans(13, .semibold)).foregroundStyle(Theme.text)
                Text("Open Photos › Recently Deleted and choose Delete All to free that space now.")
                    .font(Theme.sans(12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Open Photos") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
            }
            .buttonStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
