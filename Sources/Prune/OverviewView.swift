import SwiftUI

struct OverviewView: View {
    @Environment(Store.self) private var store

    private var subtitle: String {
        if store.isScanning { return "Scanning your Mac…" }
        if let last = store.lastScan { return trf("Last scanned %@", Fmt.relative(last)) + " · " + trf("%@ found", plural(store.allItems.count, .item)) }
        return "Find gigabytes hiding in dependencies, build output and caches."
    }

    var body: some View {
        ZStack {
            if !store.isScanning && !store.hasScanned {
                ReadyView().transition(.opacity)
            } else if store.isScanning {
                FirstScanView().transition(.opacity)
            } else {
                dashboard.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: store.lastScan == nil)
        .animation(.easeInOut(duration: 0.5), value: store.isScanning)
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Overview", subtitle: subtitle) {
                    Button { store.scan() } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.secondary)
                        .help("⌘R")
                        .disabled(store.isScanning)
                    CleanButton(items: store.selectedItems)
                }
                .appear()

                HeroCard()
                    .appear(0.04)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    ForEach(Array(store.junkCategories.enumerated()), id: \.element) { i, c in
                        CategoryCard(category: c).appear(0.1 + Double(i) * 0.045)
                    }
                }

                Group {
                if store.developerMode {
                    TopItemsCard(
                        title: "Stale projects",
                        subtitle: trf("No commits in %lld+ days. Their dependencies are safe to drop.", Prefs.staleDays),
                        items: Array(store.staleProjects.prefix(6)),
                        empty: store.isScanning ? "Looking through your projects…" : "Every project is active. Nice.",
                        route: .category(.nodeModules),
                        detail: { trf("last commit %@", Fmt.relative($0.lastActivity)) })
                } else {
                    TopItemsCard(
                        title: "Largest files",
                        subtitle: "The biggest single files in your home folder.",
                        items: Array(store.items(.largeFiles).prefix(6)),
                        empty: store.isMappingDisk ? tr("Mapping your disk…") : trf("No files over %lld MB.", Prefs.largeFileMB),
                        route: .category(.largeFiles),
                        detail: { trf("modified %@", Fmt.relative($0.lastActivity)) },
                        selectable: false)
                }
                }
                .appear(0.4)
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 40)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}
