import Foundation

/// The parts of macOS "System Data" that Prune can find.
///
/// Two kinds of items come out of here:
/// - removable items (Time Machine local snapshots, caches inside Group Containers) go through the same
///   rules as every other item: official commands or the Trash, and only after confirmation;
/// - report-only items (VM disks, simulator runtimes, system logs, per-user caches) carry their size so
///   the user can see where the space goes. Prune never removes them: `reportOnly` items are refused by
///   the Trash step, and their size is kept out of the reclaimable total.
enum SystemData {
    static func scan() -> [CleanItem] {
        // Simulator runtimes are removable when Xcode's simctl can list them; otherwise they stay report-only.
        let runtimes = simulatorRuntimeItems()
        return snapshotItems() + groupContainerCaches() + appSupportCaches() + codeSignCloneItems()
            + runtimes + trashItems() + reportOnlyItems(hideSimulatorVolumes: !runtimes.isEmpty)
    }

    // MARK: Trash

    /// The user's Trash as one removable row. Its size only comes back once the Trash is emptied, so the
    /// row shows what Emptying would free. Finder empties it, so items that are still needed stay restorable
    /// until the user confirms. Prune never deletes Trash files itself.
    static func trashItems() -> [CleanItem] {
        let trash = home.appending(path: ".Trash")
        guard FileManager.default.fileExists(atPath: trash.path) else { return [] }
        let m = Sizer.measure(trash)
        let bytes = m.unique + m.shared
        guard bytes > minimumBytes else { return [] }
        return [CleanItem(
            url: trash, category: .systemData, name: tr("Trash"), kind: "Trash",
            location: tr("Empty with Finder. Space is freed only after emptying."),
            size: bytes, lastActivity: nil, isStale: false,
            command: ["/usr/bin/osascript", "-e", "tell application \"Finder\" to empty the trash"])]
    }

    // MARK: Simulator runtimes

    /// Installed Xcode simulator runtimes from `xcrun simctl runtime list -j`. Each one is removed with
    /// `xcrun simctl runtime delete <identifier>`, which Xcode can download again. Returns nothing when the
    /// JSON is not in the expected shape, so the report-only row stays as the fallback.
    static func simulatorRuntimeItems() -> [CleanItem] {
        guard let out = Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], timeout: 30),
              let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return json.compactMap { key, value -> CleanItem? in
            guard let info = value as? [String: Any] else { return nil }
            let identifier = (info["identifier"] as? String) ?? key
            guard let bytes = (info["sizeBytes"] as? NSNumber)?.int64Value, bytes > minimumBytes else { return nil }
            let name = (info["name"] as? String) ?? identifier
            return CleanItem(
                url: URL(fileURLWithPath: "/simulator-runtime/" + identifier), category: .systemData,
                name: name, kind: "Simulator runtime",
                location: tr("Removed with xcrun simctl. Xcode can download it again."),
                size: bytes, lastActivity: nil, isStale: false,
                command: ["/usr/bin/xcrun", "simctl", "runtime", "delete", identifier])
        }
        .sorted { $0.size > $1.size }
    }

    // MARK: Browser code-sign clones

    /// Temp copies of browser apps that Chromium makes for update checks, in /private/var/folders/xx/yyy/X.
    /// Chromium cleans them up itself; they are regenerated when needed. Prune removes one only when its
    /// browser is not running, and moves it to the Trash, so it can be restored.
    static func codeSignCloneItems() -> [CleanItem] {
        let suffix = ".code_sign_clone"
        guard let cache = darwinDirectory("DARWIN_USER_CACHE_DIR") else { return [] }
        let x = URL(fileURLWithPath: cache).deletingLastPathComponent().appending(path: "X")
        return children(of: x).compactMap { clone -> CleanItem? in
            let name = clone.lastPathComponent
            guard name.hasSuffix(suffix) else { return nil }
            let bundle = String(name.dropLast(suffix.count))
            let running = isRunning(bundle: bundle)
            // The clone's files are hard-linked to each other, so Sizer would count most of them as shared.
            // du counts each file once, which is what the clone takes up (a few executables also live in the app).
            guard let bytes = duSize(clone.path), bytes > minimumBytes else { return nil }
            let modified = (try? clone.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return CleanItem(
                url: clone, category: .systemData, name: bundle, kind: "Browser code-sign clone",
                location: running ? trf("Quit %@ first", bundle) : "/private/var/folders/…/X · " + tr("moved to Trash"),
                size: bytes, lastActivity: modified,
                isStale: modified.map { Date().timeIntervalSince($0) > Scanner.staleAfter } ?? false,
                reportOnly: running)
        }
    }

    /// True when `lsappinfo` knows a running app with this bundle identifier.
    static func isRunning(bundle: String) -> Bool {
        guard let out = Shell.run("/usr/bin/lsappinfo", ["find", "bundleid=\(bundle)"], timeout: 10) else { return false }
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ignore floor for items that are too small to be worth a row.
    private static let minimumBytes: Int64 = 5_000_000

    // MARK: Time Machine local snapshots

    /// `tmutil listlocalsnapshots /` prints lines such as `com.apple.TimeMachine.2026-11-22-120000.local`.
    /// macOS does not report their size, so the row shows none and the freed space is not added up.
    static func snapshotItems() -> [CleanItem] {
        guard let out = Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) else { return [] }
        let prefix = "com.apple.TimeMachine."
        let suffix = ".local"
        return out.split(separator: "\n").compactMap { line -> CleanItem? in
            let name = line.trimmingCharacters(in: .whitespaces)
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
            let stamp = String(name.dropFirst(prefix.count).dropLast(suffix.count))
            guard !stamp.isEmpty, let url = URL(string: "snapshot://\(stamp)") else { return nil }
            return CleanItem(
                url: url, category: .systemData,
                name: trf("Time Machine snapshot %@", stamp), kind: "snapshot",
                location: tr("Size unknown. macOS also removes snapshots when it needs space."),
                size: 0, lastActivity: nil, isStale: false,
                command: ["/usr/bin/tmutil", "deletelocalsnapshots", stamp])
        }
    }

    // MARK: Group Container caches

    /// Caches apps keep in ~/Library/Group Containers/<id>/Library/Caches. Messenger containers are
    /// skipped here because the messenger category already covers their media caches.
    static func groupContainerCaches() -> [CleanItem] {
        let messengers = Set(Messengers.specs.map(\.container))
        return children(of: home.appending(path: "Library/Group Containers")).compactMap { container -> CleanItem? in
            let id = container.lastPathComponent
            guard !messengers.contains(id) else { return nil }
            let caches = container.appending(path: "Library/Caches")
            guard FileManager.default.fileExists(atPath: caches.path) else { return nil }
            let item = measured(caches, name: id, kind: "Group Container cache",
                                location: "~/Library/Group Containers")
            return item.size > minimumBytes ? item : nil
        }
    }

    // MARK: Electron and Chromium caches

    /// Cache folders Electron, Chromium and VS Code apps keep directly under ~/Library/Application Support/<app>/.
    /// Each one is rebuilt when the app next starts. Only these exact names are ever removed.
    static let appCacheFolders: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        // VS Code and Cursor: compiled extension data and downloaded extension packages, fetched again on demand.
        "CachedData", "CachedExtensionVSIXs",
    ]

    static func appSupportCaches() -> [CleanItem] {
        let root = home.appending(path: "Library/Application Support")
        var items: [CleanItem] = []
        for app in children(of: root) {
            for folder in appCacheFolders.sorted() {
                let url = app.appending(path: folder)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let item = measured(url, name: "\(app.lastPathComponent) · \(folder)", kind: "App cache",
                                    location: "~/Library/Application Support/\(app.lastPathComponent)")
                if item.size > minimumBytes { items.append(item) }
            }
        }
        return items
    }

    // MARK: Report only

    /// Big System Data pieces Prune shows but never removes. The hint says who owns the removal.
    static func reportOnlyItems(hideSimulatorVolumes: Bool = false) -> [CleanItem] {
        let darwinCache = darwinDirectory("DARWIN_USER_CACHE_DIR")
        let darwinTemp = darwinDirectory("DARWIN_USER_TEMP_DIR")
        let places: [(path: String?, name: String, kind: String, hint: String)] = [
            (home.appending(path: "Library/Containers/com.docker.docker").path, "Docker Desktop disk", "VM disk",
             "Clean inside Docker Desktop (Troubleshoot)"),
            (home.appending(path: ".orbstack").path, "OrbStack data", "VM disk", "Remove inside OrbStack"),
            (home.appending(path: "OrbStack").path, "OrbStack files", "VM disk", "Remove inside OrbStack"),
            (home.appending(path: "Parallels").path, "Parallels VMs", "VM disk", "Remove VMs in Parallels Desktop"),
            (home.appending(path: "Library/Containers/com.utmapp.UTM/Data/Documents").path, "UTM VMs", "VM disk",
             "Remove VMs in UTM"),
            (home.appending(path: "VirtualBox VMs").path, "VirtualBox VMs", "VM disk", "Remove VMs in VirtualBox"),
            (home.appending(path: "Virtual Machines.localized").path, "VMware Fusion VMs", "VM disk",
             "Remove VMs in VMware Fusion"),
            ("/Library/Developer/CoreSimulator/Volumes", "Simulator runtimes", "CoreSimulator",
             "Remove in Xcode › Settings › Platforms"),
            ("/Library/Developer/CoreSimulator/Caches", "Simulator system caches", "CoreSimulator",
             "Needs admin. Xcode rebuilds them."),
            ("/Library/Updates", "macOS update leftovers", "Software Update", "Installers left by macOS updates. Needs admin."),
            ("/private/var/log", "System logs", "Logs", "Needs admin"),
            ("/Library/Logs", "System library logs", "Logs", "Needs admin"),
            (darwinCache, "Per-user system caches", "System caches",
             "macOS rebuilds these. Prune does not remove them."),
            (darwinTemp, "Per-user temporary files", "System temp",
             "Temporary files of running apps. Prune does not remove them."),
        ]
        return places.compactMap { place -> CleanItem? in
            if hideSimulatorVolumes, place.name == "Simulator runtimes" { return nil }
            guard let path = place.path, FileManager.default.fileExists(atPath: path) else { return nil }
            let item = measured(URL(fileURLWithPath: path), name: place.name, kind: place.kind,
                                location: Fmt.tilde(path) + " · " + place.hint, reportOnly: true)
            return item.size > minimumBytes ? item : nil
        }
    }

    // MARK: Helpers

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }

    /// `getconf DARWIN_USER_CACHE_DIR` and friends: the per-user folders under /private/var/folders.
    private static func darwinDirectory(_ key: String) -> String? {
        guard let out = Shell.run("/usr/bin/getconf", [key]) else { return nil }
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func measured(_ url: URL, name: String, kind: String, location: String,
                                 reportOnly: Bool = false) -> CleanItem {
        var m = Sizer.measure(url)
        // Sizer walks file by file and can come back empty for disk-image volumes; du counts them.
        if reportOnly, m.unique + m.shared == 0, let bytes = duSize(url.path) { m = (bytes, 0) }
        // Report rows show what the folder takes up, hard-linked files included (Sizer counts those as shared).
        if reportOnly { m = (m.unique + m.shared, 0) }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return CleanItem(url: url, category: .systemData, name: name, kind: kind, location: location,
                         size: m.unique, lastActivity: modified,
                         isStale: modified.map { Date().timeIntervalSince($0) > Scanner.staleAfter } ?? false,
                         shared: m.shared, reportOnly: reportOnly)
    }

    /// Allocated size in bytes from `du -sk`, or nil when du prints nothing. du exits non-zero when it
    /// meets a folder it may not read, but its total is still right, so the exit status is ignored.
    private static func duSize(_ path: String) -> Int64? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let kb = text.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.flatMap({ Int64($0) }) else { return nil }
        return kb * 1024
    }
}
