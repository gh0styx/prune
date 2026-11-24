import SwiftUI

@MainActor
@Observable
final class Store {
    var route: Route = .overview
    var items: [CategoryID: [CleanItem]] = [:]
    var pending: Set<CategoryID> = []
    var selection: Set<String> = []
    /// Why an item could not be removed in the last clean, by item id. Shown on its row until it goes or the next scan.
    var failedReasons: [String: String] = [:]
    var lastScan: Date?
    var disk = DiskInfo.current()
    var confirming: [CleanItem]?
    var isCleaning = false
    var toast: String?
    /// The current toast is the one after cleaning, which offers "Free space now" and "Undo".
    var toastHasActions = false
    /// Live scan feedback: folders looked at and the one being read right now.
    var scanLive: (files: Int, path: String) = (0, "")
    var scanStarted: Date?

    // Disks
    var volumes: [Volume] = Volume.all()
    /// Disk shown in Space / Large files; nil means the startup disk.
    var mapVolume: Volume?
    var isFindingLargeFiles = false
    var dockerStatus: DockerStatus = .unknown
    var sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") == nil ? true : UserDefaults.standard.bool(forKey: "sidebarVisible") {
        didSet { Prefs.set(sidebarVisible, "sidebarVisible") }
    }
    var sidebarWidth: CGFloat = UserDefaults.standard.object(forKey: "sidebarWidth") as? CGFloat ?? 248
    var developerMode = Prefs.developerMode {
        didSet { Prefs.set(developerMode, Prefs.Key.developerMode) }
    }

    /// Junk categories shown to this user; developer ones hide when developer mode is off.
    var junkCategories: [CategoryID] {
        CategoryID.junk.filter { developerMode || $0.group != .developer }
    }

    // Disk map
    var tree: DiskNode?
    var spaceFocus: DiskNode?
    var isMappingDisk = false
    var mapProgress: (files: Int, path: String) = (0, "")
    var lastMap: Date?
    /// Bumped when the tree is mutated in place so views re-read it.
    var treeVersion = 0

    // Apps
    var apps: [AppInfo]?
    var isLoadingApps = false

    // History
    var history: [HistoryEntry] = HistoryFile.load()
    /// Entry waiting for "Free space now" confirmation (permanent delete).
    var confirmingPurge: HistoryEntry?
    var lastEntryID: UUID?

    // Background
    /// Opens the main window; captured from a view that has `openWindow`.
    var openMainWindow: (() -> Void)?
    /// What the user asked for while permissions were missing; it starts by itself once they are granted.
    var gatedAction: GatedAction?
    var checksStarted = false
    var scheduledRun = false
    var ignored: [String] = IgnoreList.paths

    init() {
        // `open Prune.app --args -route nodeModules` jumps straight to a page (handy for screenshots).
        if let r = UserDefaults.standard.string(forKey: "route") {
            if r == "space" { route = .space } else if r == "history" { route = .history } else if r == "devServers" { route = .devServers } else if r == "maintenance" { route = .maintenance } else if r == "security" { route = .category(.security) } else if r == "duplicates" { route = .category(.duplicates) } else if r == "loginItems" { route = .loginItems } else if let c = CategoryID(rawValue: r) { route = .category(c) }
        }
    }

    /// Junk scan in progress. Disk mapping is tracked separately by `isMappingDisk`.
    var isScanning: Bool { !pending.subtracting([.largeFiles]).isEmpty }
    var hasScanned: Bool { lastScan != nil }
    var toastToken = UUID()

    func items(_ c: CategoryID) -> [CleanItem] { items[c] ?? [] }
    /// Report-only items are shown with their size but are not part of anything Prune would free.
    func size(_ c: CategoryID) -> Int64 { items(c).filter { !$0.reportOnly }.reduce(0) { $0 + $1.size } }
    /// Size of the report-only rows in a category: shown for information, never counted in what Prune frees.
    func reportOnlySize(_ c: CategoryID) -> Int64 { items(c).filter(\.reportOnly).reduce(0) { $0 + $1.size } }
    /// Items Prune can remove and that are selected. Report-only rows never count.
    func selected(in c: CategoryID) -> [CleanItem] { items(c).filter { !$0.reportOnly && selection.contains($0.id) } }

    var allItems: [CleanItem] { junkCategories.flatMap { items($0) }.filter { !$0.reportOnly } }
    var reclaimable: Int64 { allItems.reduce(0) { $0 + $1.size } }
    var selectedItems: [CleanItem] { allItems.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var staleProjects: [CleanItem] {
        (items(.nodeModules) + items(.buildArtifacts))
            .filter(\.isStale)
            .sorted { $0.size > $1.size }
    }
}
