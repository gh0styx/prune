import SwiftUI

extension Store {
    // MARK: Permissions

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
        // Manual scans wait for the permissions they need; scheduled ones are skipped until access is granted.
        if scheduled { guard AppPermissions.allGranted else { return } }
        else if !requirePermissions(for: .scan) { return }
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
                let list = result.filter { $0.category == c && ($0.command != nil || $0.reportOnly || $0.checkFirst || Trasher.isSafe($0.url)) && !isIgnored($0) }
                    .sorted { $0.size > $1.size }
                selection.subtract(items(c).map(\.id))
                items[c] = list
                selection.formUnion(list.filter { !$0.reportOnly && !$0.checkFirst && c.selectedByDefault($0) }.map(\.id))
                pending.remove(c)
            }
        }
    }

    // MARK: Selection

    func toggle(_ item: CleanItem) {
        // Report-only items (VM disks, simulator runtimes, logs) can't be selected: Prune doesn't remove them.
        guard !item.reportOnly else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func setAll(_ c: CategoryID, _ on: Bool) {
        // "Select all" leaves the check-first items alone: they are ticked one by one.
        let ids = items(c).filter { !$0.reportOnly && !$0.checkFirst }.map(\.id)
        if on { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    func selectStale(_ c: CategoryID) {
        selection.subtract(items(c).map(\.id))
        selection.formUnion(items(c).filter { $0.isStale && !$0.reportOnly && !$0.checkFirst }.map(\.id))
    }

}
