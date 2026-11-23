import Foundation

// MARK: Downloads, iPhone backups, simulators

extension Scanner {
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "zip", "xip", "iso", "app"]
    static let downloadsStaleAfter: TimeInterval = 60 * 60 * 24 * 90

    /// Top-level items in ~/Downloads: installers of any age, and anything untouched for 90+ days.
    func scanDownloads() -> [CleanItem] {
        let downloads = home.appending(path: "Downloads")
        let keys: [URLResourceKey] = [.contentModificationDateKey, .addedToDirectoryDateKey, .contentAccessDateKey]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        var items: [CleanItem] = []
        for url in children {
            let v = try? url.resourceValues(forKeys: Set(keys))
            // The most recent of added / modified / opened: a file you opened last week isn't stale.
            let last = [v?.addedToDirectoryDate, v?.contentModificationDate, v?.contentAccessDate].compactMap { $0 }.max()
            let age = last.map { Date().timeIntervalSince($0) } ?? 0
            let ext = url.pathExtension.lowercased()
            let installer = Self.installerExtensions.contains(ext)
            guard installer || age > Self.downloadsStaleAfter else { continue }
            let m = Sizer.measure(url)
            guard m.unique + m.shared > 0 else { continue }
            items.append(CleanItem(
                url: url, category: .downloads, name: url.lastPathComponent,
                kind: installer ? tr("Installer") + " · \(ext)" : (ext.isEmpty ? tr("Folder") : ext.uppercased()),
                location: "~/Downloads", size: m.unique, lastActivity: last,
                isStale: age > Self.downloadsStaleAfter, shared: m.shared))
        }
        return items
    }

    /// Local iPhone / iPad backups. Needs Full Disk Access; empty without it.
    func scanIOSBackups() -> [CleanItem] {
        let root = home.appending(path: "Library/Application Support/MobileSync/Backup")
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return children.compactMap { url in
            let info = NSDictionary(contentsOf: url.appending(path: "Info.plist"))
            let device = info?["Device Name"] as? String ?? "Unknown device"
            let product = info?["Product Type"] as? String ?? ""
            let date = info?["Last Backup Date"] as? Date
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let m = Sizer.measure(url)
            guard m.unique > 0 else { return nil }
            return CleanItem(url: url, category: .iosBackups, name: device,
                             kind: product.isEmpty ? tr("Backup") : tr("Backup") + " · \(product)",
                             location: "~/Library/Application Support/MobileSync/Backup", size: m.unique,
                             lastActivity: date,
                             isStale: date.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? false)
        }
    }

    /// Simulators whose iOS runtime is gone (`simctl list devices unavailable`).
    func scanUnavailableSimulators() -> [CleanItem] {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun"),
              let json = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"], timeout: 20),
              let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let byRuntime = obj["devices"] as? [String: [[String: Any]]] else { return [] }
        let devices = home.appending(path: "Library/Developer/CoreSimulator/Devices")
        var items: [CleanItem] = []
        for (runtime, list) in byRuntime {
            let os = runtime.split(separator: ".").last.map { $0.replacingOccurrences(of: "-", with: " ") } ?? runtime
            for d in list {
                guard let udid = d["udid"] as? String else { continue }
                let url = devices.appending(path: udid)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let m = Sizer.measure(url)
                items.append(CleanItem(url: url, category: .xcode, name: d["name"] as? String ?? udid,
                                       kind: tr("Unavailable simulator") + " · \(os)", location: Fmt.tilde(devices.path),
                                       size: m.unique, lastActivity: nil, isStale: true, shared: m.shared))
            }
        }
        return items
    }
}

// MARK: Apps

struct AppInfo: Identifiable, Sendable {
    let item: CleanItem          // the .app bundle
    let leftovers: [CleanItem]   // files it keeps in ~/Library
    let bundleID: String
    let version: String
    let lastUsed: Date?

    var id: String { item.id }
    var leftoverSize: Int64 { leftovers.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { item.size + leftoverSize }
}

extension Scanner {
    /// Folders inside ~/Library where apps keep data, and how the entry is named there.
    private static let leftoverPlaces: [(dir: String, byID: [String], byName: [String])] = [
        ("Application Support", ["%@"], ["%@"]),
        ("Caches", ["%@"], []),
        ("Containers", ["%@"], []),
        ("Preferences", ["%@.plist"], []),
        ("Saved Application State", ["%@.savedState"], []),
        ("HTTPStorages", ["%@", "%@.binarycookies"], []),
        ("WebKit", ["%@"], []),
        ("Logs", ["%@"], ["%@"]),
        ("Application Scripts", ["%@"], []),
    ]

    static var leftoverDirs: [String] { leftoverPlaces.map(\.dir) }

    /// Third-party apps in /Applications and ~/Applications, with their leftovers.
    func scanApps() -> [AppInfo] {
        let roots = [URL(fileURLWithPath: "/Applications"), home.appending(path: "Applications")]
        let ownID = Bundle.main.bundleIdentifier ?? "dev.prune.app"
        var apps: [AppInfo] = []
        for root in roots {
            let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for url in children where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                      !id.hasPrefix("com.apple."), id != ownID else { continue }
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                let lastUsed = NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date
                let size = Sizer.allocated(url)
                let app = CleanItem(url: url, category: .apps, name: name, kind: version.isEmpty ? tr("App") : "v\(version)",
                                    location: Fmt.tilde(root.path), size: size, lastActivity: lastUsed,
                                    isStale: lastUsed.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? false)
                apps.append(AppInfo(item: app, leftovers: leftovers(bundleID: id, name: name),
                                    bundleID: id, version: version, lastUsed: lastUsed))
            }
        }
        return apps.sorted { $0.totalSize > $1.totalSize }
    }

    func leftovers(bundleID: String, name: String) -> [CleanItem] {
        let library = home.appending(path: "Library")
        var seen = Set<String>()
        var items: [CleanItem] = []
        for place in Self.leftoverPlaces {
            let names = place.byID.map { String(format: $0, bundleID) } + place.byName.map { String(format: $0, name) }
            for entry in names {
                let url = library.appending(path: place.dir).appending(path: entry)
                guard seen.insert(url.path).inserted, FileManager.default.fileExists(atPath: url.path) else { continue }
                var item = CleanItem(url: url, category: .apps, name: entry, kind: place.dir,
                                     location: "~/Library/\(place.dir)", size: Sizer.allocated(url),
                                     lastActivity: nil, isStale: false)
                item.isLeftover = true
                items.append(item)
            }
        }
        return items
    }
}

extension Sizer {
    /// Plain allocated size, without the per-file clone check (fast enough for whole app bundles).
    static func allocated(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        func size(_ v: URLResourceValues) -> Int64 { Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }
        if let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true { return size(v) }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [],
                                                     errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        while let f = e.nextObject() as? URL {
            if let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true { total += size(v) }
        }
        return total
    }
}

// MARK: Mail & Photos

extension Scanner {
    /// Attachments Mail saved to disk when you opened them (Mail fetches them again from the server).
    /// Needs Full Disk Access; empty without it.
    func scanMailAttachments() -> [CleanItem] {
        let roots = [home.appending(path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"),
                     home.appending(path: "Library/Mail Downloads")]
        var items: [CleanItem] = []
        for root in roots {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            for url in children {
                let m = Sizer.measure(url)
                guard m.unique > 0 else { continue }
                // Each entry is a folder named by a UUID; show the attachment file inside when there is one.
                let inner = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.first { !$0.hasPrefix(".") }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                items.append(CleanItem(url: url, category: .mailAttachments, name: inner ?? url.lastPathComponent,
                                       kind: tr("Attachment"), location: Fmt.tilde(root.path), size: m.unique,
                                       lastActivity: modified,
                                       isStale: modified.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? false))
            }
        }
        return items
    }
}
