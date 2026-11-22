import SwiftUI

@MainActor
@Observable
final class Store {
    var route: Route = .overview
    var items: [CategoryID: [CleanItem]] = [:]
    var pending: Set<CategoryID> = []
    var selection: Set<String> = []
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
    private var checksStarted = false
    private var scheduledRun = false
    var ignored: [String] = Prefs.ignoredPaths

    init() {
        // `open Prune.app --args -route nodeModules` jumps straight to a page (handy for screenshots).
        if let r = UserDefaults.standard.string(forKey: "route") {
            if r == "space" { route = .space } else if r == "history" { route = .history } else if r == "devServers" { route = .devServers } else if r == "maintenance" { route = .maintenance } else if r == "security" { route = .category(.security) } else if r == "duplicates" { route = .category(.duplicates) } else if r == "loginItems" { route = .loginItems } else if let c = CategoryID(rawValue: r) { route = .category(c) }
        }
    }

    /// Junk scan in progress. Disk mapping is tracked separately by `isMappingDisk`.
    var isScanning: Bool { !pending.subtracting([.largeFiles]).isEmpty }
    var hasScanned: Bool { lastScan != nil }
    private var toastToken = UUID()

    func items(_ c: CategoryID) -> [CleanItem] { items[c] ?? [] }
    func size(_ c: CategoryID) -> Int64 { items(c).reduce(0) { $0 + $1.size } }
    func selected(in c: CategoryID) -> [CleanItem] { items(c).filter { selection.contains($0.id) } }

    var allItems: [CleanItem] { junkCategories.flatMap { items($0) } }
    var reclaimable: Int64 { allItems.reduce(0) { $0 + $1.size } }
    var selectedItems: [CleanItem] { allItems.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var staleProjects: [CleanItem] {
        (items(.nodeModules) + items(.buildArtifacts))
            .filter(\.isStale)
            .sorted { $0.size > $1.size }
    }

    // MARK: Permissions

    /// What the user asked for while permissions were missing; it starts by itself once they are granted.
    var gatedAction: GatedAction?

    /// True when every permission the scans need is granted. Otherwise opens the permissions gate
    /// and remembers `action` so it can run as soon as the user comes back with access granted.
    func requirePermissions(for action: GatedAction) -> Bool {
        if AppPermissions.allGranted { return true }
        gatedAction = action
        return false
    }

    /// Called when the app becomes active again: runs the waiting action if access is now granted.
    func resumeGatedAction() {
        guard let action = gatedAction, AppPermissions.allGranted else { return }
        gatedAction = nil
        switch action {
        case .scan: scan()
        case .map: mapDisk()
        }
    }

    // MARK: Scan

    /// One scan: junk categories first (seconds), then the disk map when it is enabled or already exists.
    func scan(scheduled: Bool = false) {
        guard !isScanning else { return }
        // Manual scans wait for the permissions they need; scheduled ones just run with what they have.
        if !scheduled, !requirePermissions(for: .scan) { return }
        scheduledRun = scheduled
        if !scheduled {
            // A manual scan restarts the schedule clock and is the moment to ask for notifications.
            Prefs.set(Date(), Prefs.Key.lastScheduledScan)
            Notifier.shared.requestPermissionIfNeeded()
        }
        // Only what this user sees gets scanned: developer categories are skipped entirely
        // unless developer mode is on.
        let visible = Set(junkCategories)
        pending = visible
        scanStarted = Date()
        let progress = ScanProgress()
        let scanner: Scanner = {
            var s = Scanner()
            s.progress = progress
            return s
        }()
        Task {
            while isScanning {
                scanLive = progress.snapshot
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        if visible.contains(.docker) {
            Task {
                let result = await Task.detached(priority: .userInitiated) { scanner.scanDocker() }.value
                dockerStatus = result.status
                apply([.docker], result.items)
            }
        }
        let allJobs = Catalog.jobs(scanner: scanner)
        let jobs = allJobs.filter { cats, _ in cats.contains { visible.contains($0) } }
        Task {
            await withTaskGroup(of: ([CategoryID], [CleanItem]).self) { group in
                for (cats, job) in jobs {
                    group.addTask {
                        let result = await Task.detached(priority: .userInitiated) { job() }.value
                        return (cats, result)
                    }
                }
                for await (cats, result) in group {
                    apply(cats, result)
                }
            }
            lastScan = Date()
            disk = .current()
            notifyScanFinished()
            scheduledRun = false
        }
    }

    // MARK: Disk map

    /// Finds large files only (no full map): quick, its own button on the Large files page.
    func findLargeFiles() {
        guard !isFindingLargeFiles, !isMappingDisk else { return }
        isFindingLargeFiles = true
        pending.insert(.largeFiles)
        mapProgress = (0, "")
        let progress = ScanProgress()
        let root = mapVolume?.url ?? FileManager.default.homeDirectoryForCurrentUser
        Task {
            while isFindingLargeFiles {
                mapProgress = progress.snapshot
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                LargeFileScanner.scan(root: root, progress: progress)
            }.value
            withAnimation(.snappy(duration: 0.5)) {
                items[.largeFiles] = found.filter { Trasher.isSafe($0.url) && !isIgnored($0) }
                pending.remove(.largeFiles)
                isFindingLargeFiles = false
            }
        }
    }

    /// Switches Space / Large files to another disk and maps it.
    func selectVolume(_ volume: Volume) {
        let target: Volume? = volume.isBoot ? nil : volume
        guard target?.id != mapVolume?.id else { return }
        mapVolume = target
        tree = nil
        spaceFocus = nil
        items[.largeFiles] = nil
        mapDisk()
    }

    func refreshVolumes() {
        volumes = Volume.all()
        disk = .current()
    }

    func mapDisk() {
        guard !isMappingDisk else { return }
        guard requirePermissions(for: .map) else { return }
        isMappingDisk = true
        pending.insert(.largeFiles)
        mapProgress = (0, "")
        let progress = ScanProgress()
        let used = DiskInfo.current().used
        let volume = mapVolume
        Task {
            while isMappingDisk {
                mapProgress = progress.snapshot
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        Task {
            let result = await Task.detached(priority: .utility) {
                if let volume {
                    var scanner = DiskScanner(progress: progress)
                    scanner.volumeRoot = volume.url
                    return scanner.scan(volume: volume)
                }
                return DiskScanner(progress: progress).scan(diskUsed: used)
            }.value
            withAnimation(.snappy(duration: 0.5)) {
                tree = result.root
                spaceFocus = volume != nil ? result.root
                    : (result.root.children.first { $0.url?.path == FileManager.default.homeDirectoryForCurrentUser.path } ?? result.root)
                items[.largeFiles] = result.largeFiles
                pending.remove(.largeFiles)
                isMappingDisk = false
                lastMap = Date()
                treeVersion += 1
            }
        }
    }

    func focus(_ node: DiskNode) {
        withAnimation(.snappy(duration: 0.35)) { spaceFocus = node }
    }

    private func apply(_ cats: [CategoryID], _ result: [CleanItem]) {
        withAnimation(.snappy(duration: 0.5)) {
            for c in cats {
                let list = result.filter { $0.category == c && ($0.command != nil || Trasher.isSafe($0.url)) && !isIgnored($0) }
                    .sorted { $0.size > $1.size }
                selection.subtract(items(c).map(\.id))
                items[c] = list
                selection.formUnion(list.filter { c.selectedByDefault($0) }.map(\.id))
                pending.remove(c)
            }
        }
    }

    // MARK: Selection

    func toggle(_ item: CleanItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func setAll(_ c: CategoryID, _ on: Bool) {
        let ids = items(c).map(\.id)
        if on { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    func selectStale(_ c: CategoryID) {
        selection.subtract(items(c).map(\.id))
        selection.formUnion(items(c).filter(\.isStale).map(\.id))
    }

    // MARK: Clean

    func requestClean(_ list: [CleanItem]) {
        guard !list.isEmpty, !isCleaning, !isScanning else { return }
        confirming = list
    }

    func clean(_ list: [CleanItem]) {
        confirming = nil
        guard !isCleaning else { return }
        isCleaning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { Trasher.trash(list) }.value
            withAnimation(.snappy) {
                if !result.entry.items.isEmpty {
                    history.insert(result.entry, at: 0)
                    lastEntryID = result.entry.id
                    HistoryFile.save(history)
                }
                apps = apps?.filter { !result.trashed.contains($0.item.id) }
                for c in CategoryID.allCases where items[c] != nil {
                    items[c] = items(c).filter { !result.trashed.contains($0.id) }
                }
                selection.subtract(result.trashed)
                var deleted: [String: Int64] = [:]
                for item in list where result.trashed.contains(item.id) && item.command == nil {
                    deleted[item.url.resolvingSymlinksInPath().path] = item.size + item.shared
                }
                if let tree, !deleted.isEmpty {
                    tree.remove(deleted: deleted)
                    // If the folder on screen was removed, step back to the nearest folder that's still there.
                    var focus = spaceFocus
                    while let f = focus, !f.isAttached(to: tree) { focus = f.parent }
                    spaceFocus = focus ?? tree
                    treeVersion += 1
                }
                isCleaning = false
                disk = .current()
                let failed = list.count - result.trashed.count
                toastHasActions = !result.entry.inTrash.isEmpty
                toast = trf("%@ moved to Trash", Fmt.bytes(result.freed)) + (failed > 0 ? " · " + trf("%lld skipped", failed) : "")
            }
            if !NSApp.isActive && result.freed > 0 {
                Notifier.shared.post("clean", title: "Cleaning done",
                                     body: trf("%@ moved to the Trash. Empty it to free the space.", Fmt.bytes(result.freed)))
            }
            let token = UUID()
            toastToken = token
            try? await Task.sleep(for: .seconds(3.5))
            if toastToken == token { withAnimation(.easeOut) { toast = nil } }
        }
    }

    // MARK: History

    /// Moves everything still in the Trash from this entry back to where it was.
    func restore(_ entry: HistoryEntry, only item: HistoryItem? = nil) {
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
        var restored = 0
        for (i, it) in history[index].items.enumerated() where it.state == .inTrash && (item == nil || it.id == item!.id) {
            if TrashOps.restore(it) {
                history[index].items[i].state = .restored
                restored += 1
            }
        }
        HistoryFile.save(history)
        showToast(restored > 0 ? trf("Restored %@", plural(restored, .item)) : tr("Nothing could be restored"))
    }

    func requestPurge(_ entry: HistoryEntry) {
        guard !entry.inTrash.isEmpty else { return }
        confirmingPurge = entry
    }

    /// Permanently deletes what this entry put in the Trash. Only called after the user confirms.
    func purge(_ entry: HistoryEntry) {
        confirmingPurge = nil
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
        let items = history[index].items
        Task {
            let done = await Task.detached(priority: .userInitiated) {
                items.map { $0.state == .inTrash && TrashOps.deleteForever($0) }
            }.value
            var freed: Int64 = 0
            for (i, ok) in done.enumerated() where ok {
                history[index].items[i].state = .deleted
                freed += items[i].size
            }
            HistoryFile.save(history)
            disk = .current()
            showToast(freed > 0 ? trf("Freed %@", Fmt.bytes(freed)) : tr("Couldn't delete. Empty the Trash in Finder instead"))
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.snappy) { toastHasActions = false; toast = tr(text) }
        let token = UUID()
        toastToken = token
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if toastToken == token { withAnimation(.easeOut) { toast = nil } }
        }
    }

    // MARK: Ignore list

    func isIgnored(_ item: CleanItem) -> Bool {
        ignored.contains { item.url.path == $0 || item.url.path.hasPrefix($0 + "/") }
    }

    func ignore(_ item: CleanItem) {
        guard !ignored.contains(item.url.path) else { return }
        ignored.append(item.url.path)
        Prefs.set(ignored, Prefs.Key.ignoredPaths)
        withAnimation(.snappy) {
            items[item.category] = items(item.category).filter { $0.id != item.id }
            selection.remove(item.id)
        }
        showToast("Hidden. Undo in Settings › Scanning")
    }

    func unignore(_ path: String) {
        ignored.removeAll { $0 == path }
        Prefs.set(ignored, Prefs.Key.ignoredPaths)
    }

    // MARK: Apps

    func loadApps() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        Task {
            let list = await Task.detached(priority: .userInitiated) { Scanner().scanApps() }.value
            withAnimation(.snappy(duration: 0.5)) {
                apps = list
                isLoadingApps = false
            }
        }
    }

    func uninstall(_ app: AppInfo) {
        requestClean([app.item] + app.leftovers)
    }

    // MARK: Background checks & notifications

    /// Runs every 30 minutes while Prune is open (it lives in the menu bar): low-disk alert and scheduled scans.
    func startBackgroundChecks() {
        guard !checksStarted else { return }
        checksStarted = true
        Notifier.shared.setup()
        Notifier.shared.onOpen = { [weak self] in self?.openMainWindow?() }
        Task {
            while true {
                try? await Task.sleep(for: .seconds(60))
                backgroundTick()
                try? await Task.sleep(for: .seconds(29 * 60))
            }
        }
    }

    private func backgroundTick() {
        disk = .current()
        let defaults = UserDefaults.standard

        // Low disk: under 10% free, at most once a day.
        if disk.total > 0, Double(disk.free) / Double(disk.total) < 0.10 {
            let last = defaults.object(forKey: Prefs.Key.lastLowDiskAlert) as? Date ?? .distantPast
            if Date().timeIntervalSince(last) > 86_400 {
                Prefs.set(Date(), Prefs.Key.lastLowDiskAlert)
                Notifier.shared.post("lowdisk", title: "Your disk is almost full",
                                     body: trf("Only %@ left. Open Prune to see what's taking space.", Fmt.bytes(disk.free)))
            }
        }

        // Scheduled scan, counted from the user's last manual scan (never before the first one).
        let interval: TimeInterval? = switch Prefs.schedule {
        case "daily": 86_400
        case "weekly": 7 * 86_400
        default: nil
        }
        if let interval, let last = defaults.object(forKey: Prefs.Key.lastScheduledScan) as? Date,
           Date().timeIntervalSince(last) > interval, !isScanning, !isCleaning {
            Prefs.set(Date(), Prefs.Key.lastScheduledScan)
            scan(scheduled: true)
        }
    }

    private func notifyScanFinished() {
        let total = reclaimable
        if scheduledRun {
            if total > 1_000_000_000 {
                Notifier.shared.post("scheduled", title: trf("%@ can be cleaned", Fmt.bytes(total)),
                                     body: "Caches, logs and old dependencies piled up since your last check.")
            }
        } else if !NSApp.isActive {
            Notifier.shared.post("scan", title: tr("Scan finished"), body: trf("Found %@ you can clean.", Fmt.bytes(total)))
        }
    }
}
