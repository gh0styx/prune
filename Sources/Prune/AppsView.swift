import SwiftUI

/// Third-party apps with their size, last use and the files they keep in ~/Library.
struct AppsView: View {
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var expanded: String?

    private var filtered: [AppInfo] {
        let all = store.apps ?? []
        guard !query.isEmpty else { return all }
        return all.filter { $0.item.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Apps", subtitle: CategoryID.apps.blurb) {
                Button {
                    store.loadApps()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                        Text("Refresh")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(store.isLoadingApps)
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 20)

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.faint)
                    TextField("Filter apps", text: $query).textFieldStyle(.plain).font(Theme.sans(13))
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .frame(maxWidth: 360)
                .card(radius: 8)
                Spacer()
                if let apps = store.apps {
                    let total = apps.reduce(0) { $0 + $1.totalSize }
                    Text(plural(apps.count, .app) + " · " + Fmt.bytes(total)).font(Theme.mono(12)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 14)

            Group {
                if store.apps == nil {
                    VStack(spacing: 14) {
                        OrbView(size: 72, scanning: true)
                        Text("Looking at your apps…").font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { i, app in
                                if i > 0 { Hairline() }
                                AppRow(app: app, expanded: expanded == app.id) {
                                    withAnimation(.snappy(duration: 0.3)) { expanded = expanded == app.id ? nil : app.id }
                                }
                                .appear(Double(min(i, 14)) * 0.025)
                            }
                        }
                    }
                }
            }
            .card()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .onAppear { if store.apps == nil { store.loadApps() } }
    }
}

private struct AppRow: View {
    @Environment(Store.self) private var store
    let app: AppInfo
    let expanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.item.url.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(app.item.name).font(Theme.sans(13, .medium)).foregroundStyle(Theme.text)
                        Text(app.item.kind).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                        if app.item.isStale { Badge(text: "Unused", color: Theme.amber) }
                    }
                    Text(app.lastUsed.map { trf("Opened %@", Fmt.relative($0)) } ?? tr("Never opened"))
                        .font(Theme.sans(11.5))
                        .foregroundStyle(app.item.isStale ? Theme.amber : Theme.faint)
                }
                Spacer()
                if !app.leftovers.isEmpty {
                    Button(action: toggle) {
                        HStack(spacing: 4) {
                            Text(trf("+ %@ data", Fmt.bytes(app.leftoverSize)))
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
                Text(Fmt.bytes(app.totalSize))
                    .font(Theme.mono(13, .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 84, alignment: .trailing)
                Button("Uninstall…") { store.uninstall(app) }
                    .buttonStyle(PruneButtonStyle(kind: .secondary, height: 28))
                    .opacity(hovering ? 1 : 0.0001)
                    .disabled(store.isCleaning || store.isScanning)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .background(hovering ? Theme.text.opacity(0.04) : .clear)
            .contextMenu {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.item.url]) }
                Button("Uninstall…") { store.uninstall(app) }
            }

            if expanded {
                VStack(spacing: 0) {
                    ForEach(app.leftovers) { l in
                        HStack(spacing: 10) {
                            Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(Theme.faint)
                            Text(l.location + "/" + l.name).font(Theme.mono(11)).foregroundStyle(Theme.muted)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Fmt.bytes(l.size)).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                        }
                        .padding(.leading, 60)
                        .padding(.trailing, 16)
                        .frame(height: 26)
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
