import Foundation


enum CategoryGroup: String, CaseIterable {
    case storage = "Storage"
    case developer = "Developer"
    case system = "System"
}

enum CategoryID: String, CaseIterable, Identifiable, Hashable, Sendable {
    case nodeModules, buildArtifacts, xcode, docker, packageCaches, appCaches, messengerCaches, logs, downloads, iosBackups, mailAttachments, largeFiles, apps, duplicates, security

    /// Categories that count as junk: summed into "reclaimable" and shown on the overview.
    static var junk: [CategoryID] { allCases.filter { ![.largeFiles, .apps, .duplicates, .security].contains($0) } }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nodeModules: "node_modules"
        case .buildArtifacts: "Build artifacts"
        case .xcode: "Xcode"
        case .docker: "Docker"
        case .packageCaches: "Package caches"
        case .appCaches: "App caches"
        case .messengerCaches: "Messenger caches"
        case .logs: "Logs"
        case .downloads: "Downloads"
        case .iosBackups: "iPhone backups"
        case .largeFiles: "Large files"
        case .apps: "Apps"
        case .mailAttachments: "Mail attachments"
        case .duplicates: "Duplicates"
        case .security: "Security check"
        }
    }

    var blurb: String {
        switch self {
        case .nodeModules: "Dependencies inside your JS projects. Reinstall any time with pnpm i."
        case .buildArtifacts: ".next, .turbo, Rust target, Gradle build, Python venvs."
        case .xcode: "DerivedData, archives, device support files, simulator caches."
        case .docker: "Unused images, build cache, stopped containers and volumes."
        case .packageCaches: "npm, pnpm, Yarn, Bun, pip, uv, Homebrew, Cargo, Gradle."
        case .appCaches: "Caches that apps rebuild on their own when needed."
        case .messengerCaches: "Photos, videos and files kept by messengers. They download again when you open a chat."
        case .logs: "Old diagnostic and application logs."
        case .downloads: "Installers you already used and files untouched for 90+ days."
        case .iosBackups: "Local backups of iPhone and iPad. Check you have a newer one first."
        case .apps: "Remove apps together with the files they leave in your Library."
        case .mailAttachments: "Attachments Mail saved when you opened them. Mail downloads them again if needed."
        case .duplicates: "Identical files and similar photos. Keep one, move the rest to the Trash."
        case .security: "Startup items, browser extensions and known adware."
        case .largeFiles: trf("Files over %lld MB in your home folder. Not junk by default, so look before you remove.", Prefs.largeFileMB)
        }
    }

    var symbol: String {
        switch self {
        case .nodeModules: "shippingbox"
        case .buildArtifacts: "hammer"
        case .xcode: "swift"
        case .docker: "server.rack"
        case .packageCaches: "archivebox"
        case .appCaches: "square.stack.3d.up"
        case .messengerCaches: "bubble.left.and.bubble.right"
        case .logs: "text.alignleft"
        case .downloads: "arrow.down.circle"
        case .iosBackups: "iphone"
        case .largeFiles: "doc.text.magnifyingglass"
        case .apps: "app.badge"
        case .mailAttachments: "paperclip"
        case .duplicates: "square.on.square"
        case .security: "checkmark.shield"
        }
    }

    /// Filled variant for tiles and chips; the outline `symbol` is for the sidebar.
    var tileSymbol: String {
        switch self {
        case .nodeModules: "shippingbox.fill"
        case .buildArtifacts: "hammer.fill"
        case .xcode: "swift"
        case .docker: "server.rack"
        case .packageCaches: "archivebox.fill"
        case .appCaches: "square.stack.3d.up.fill"
        case .messengerCaches: "bubble.left.and.bubble.right.fill"
        case .logs: "doc.text.fill"
        case .downloads: "arrow.down.circle.fill"
        case .iosBackups: "iphone"
        case .largeFiles: "doc.fill"
        case .apps: "app.badge.fill"
        case .mailAttachments: "paperclip"
        case .duplicates: "square.on.square.fill"
        case .security: "checkmark.shield.fill"
        }
    }

    var group: CategoryGroup {
        switch self {
        case .nodeModules, .buildArtifacts, .xcode, .docker, .packageCaches: .developer
        case .appCaches, .messengerCaches, .logs, .downloads, .iosBackups: .system
        case .largeFiles, .apps, .duplicates, .security: .storage
        case .mailAttachments: .system
        }
    }

    /// Items selected after a scan: everything that is safe to remove without thinking.
    func selectedByDefault(_ item: CleanItem) -> Bool {
        switch self {
        case .nodeModules, .buildArtifacts: item.isStale
        case .xcode: item.url.lastPathComponent != "Archives"
        // Containers and volumes can hold state (databases!), so only caches are pre-selected.
        case .docker: item.kind == "images" || item.kind == "build cache"
        case .packageCaches, .logs: true
        case .mailAttachments: true
        // Off by default: media is downloaded again, but only once you open the chat again.
        case .appCaches, .messengerCaches, .largeFiles, .downloads, .iosBackups, .apps, .duplicates, .security: false
        }
    }
}

struct CleanItem: Identifiable, Hashable, Sendable {
    let url: URL
    let category: CategoryID
    let name: String
    let kind: String
    let location: String
    let size: Int64
    let lastActivity: Date?
    let isStale: Bool
    /// Set for items that are cleaned by running a command instead of moving files to the Trash.
    var command: [String]? = nil
    /// Bytes held by hard links that also exist outside this item. Removing it won't free these.
    var shared: Int64 = 0
    /// A file an uninstalled app left in ~/Library. Allowed through the trash rules only as part of an uninstall.
    var isLeftover = false

    var id: String { url.absoluteString }
}

enum DockerStatus: Equatable, Sendable {
    case unknown, notInstalled, notRunning, running
}

struct DiskInfo: Equatable {
    var total: Int64 = 0
    var free: Int64 = 0
    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo {
        let url = URL(fileURLWithPath: "/")
        let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return DiskInfo(total: Int64(v?.volumeTotalCapacity ?? 0),
                        free: v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

enum Route: Hashable {
    case overview
    case space
    case history
    case devServers
    case maintenance
    case loginItems
    case category(CategoryID)
}

enum Fmt {
    static func parts(_ bytes: Int64) -> (value: String, unit: String) {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(bytes)
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        let s: String
        if i == 0 { s = "\(Int(v))" }
        else if v < 100 { s = String(format: "%.1f", v) }
        else { s = String(format: "%.0f", v) }
        return (s, tr(units[i]))
    }

    static func bytes(_ b: Int64) -> String {
        let p = parts(b)
        return "\(p.value) \(p.unit)"
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        if Date().timeIntervalSince(date) < 60 { return tr("just now") }
        let f = RelativeDateTimeFormatter()
        f.locale = Lang.locale
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func tilde(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
