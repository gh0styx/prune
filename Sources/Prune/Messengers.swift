import Darwin
import Foundation

/// Cache folders that messengers keep inside ~/Library/Group Containers. Only regenerable media and
/// render caches are listed here. Message databases, account keys and settings are never matched.
struct MessengerSpec: Sendable {
    let name: String
    /// Folder name under ~/Library/Group Containers.
    let container: String
    /// Cache folders relative to the container, as glob patterns. `*` matches one path component only.
    let cacheGlobs: [(glob: String, label: String)]
}

enum Messengers {
    static let specs: [MessengerSpec] = [
        MessengerSpec(
            name: "Telegram",
            container: "6N38VWS5BX.ru.keepcoder.Telegram",
            cacheGlobs: [
                // Downloaded photos, videos and files, one folder per account. Telegram fetches them again on demand.
                ("appstore/account-*/postbox/media", "Media"),
                // Rendered animated stickers and emoji.
                ("appstore/trlottie-animations", "Animations"),
            ]),
    ]

    private static var groupContainers: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Group Containers")
    }

    static let containersPrefix = "Library/Group Containers/"

    /// True when `relativePath` (relative to the home folder, e.g. `Library/Group Containers/…`)
    /// is exactly one of the cache folders above.
    static func isCachePath(_ relativePath: String) -> Bool {
        guard relativePath.hasPrefix(containersPrefix) else { return false }
        let inContainer = String(relativePath.dropFirst(containersPrefix.count))
        return specs.contains { spec in
            spec.cacheGlobs.contains { glob in
                fnmatch("\(spec.container)/\(glob.glob)", inContainer, FNM_PATHNAME) == 0
            }
        }
    }

    /// Expands a glob such as `container/appstore/account-*/postbox/media` into existing directories.
    static func expand(_ pattern: String) -> [URL] {
        var current = [groupContainers]
        for part in pattern.split(separator: "/").map(String.init) {
            var next: [URL] = []
            for base in current {
                if part.contains("*") {
                    let children = (try? FileManager.default.contentsOfDirectory(
                        at: base, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                    next += children.filter { child in
                        fnmatch(part, child.lastPathComponent, 0) == 0
                            && (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    }
                } else {
                    let url = base.appending(path: part)
                    if FileManager.default.fileExists(atPath: url.path) { next.append(url) }
                }
            }
            current = next
        }
        return current
    }
}

// MARK: Scanner

extension Scanner {
    /// Telegram and other messenger media caches under ~/Library/Group Containers.
    /// Items are cleaned by moving them to the Trash; the app downloads what it still needs again.
    func scanMessengerCaches() -> [CleanItem] {
        var items: [CleanItem] = []
        for spec in Messengers.specs {
            for cache in spec.cacheGlobs {
                for url in Messengers.expand("\(spec.container)/\(cache.glob)") {
                    let m = Sizer.measure(url)
                    guard m.unique + m.shared > 0 else { continue }
                    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    let account = url.pathComponents.first { $0.hasPrefix("account-") }
                    let label = tr(cache.label)
                    let kind = account.map { "\(label) · \($0)" } ?? label
                    items.append(CleanItem(
                        url: url, category: .messengerCaches, name: spec.name, kind: kind,
                        location: Fmt.tilde(url.deletingLastPathComponent().path),
                        size: m.unique, lastActivity: modified,
                        isStale: modified.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? false,
                        shared: m.shared))
                }
            }
        }
        return items
    }
}
