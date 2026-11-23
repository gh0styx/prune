import Foundation

/// Folders the user asked Prune to leave alone. Scans skip them and removals refuse them.
///
/// The list lives in a JSON file rather than UserDefaults, because the app and the CLI are separate
/// processes with separate defaults domains. Both read and write the same file.
enum IgnoreList {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Prune/ignored.json")
    }

    private static let lock = NSLock()
    private static var cache: [String]?

    /// Standardized absolute paths, in the order they were added.
    static var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let loaded = load()
        cache = loaded
        return loaded
    }

    /// True when the URL is an ignored folder or sits inside one.
    static func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return paths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func add(_ url: URL) {
        let path = url.standardizedFileURL.path
        update { list in
            if !list.contains(path) { list.append(path) }
        }
    }

    static func remove(_ path: String) {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        update { list in list.removeAll { $0 == path } }
    }

    private static func update(_ change: (inout [String]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var list = cache ?? load()
        change(&list)
        cache = list
        save(list)
    }

    /// Reads the file. The first time, imports the list the app kept in UserDefaults before this file existed.
    private static func load() -> [String] {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            return list
        }
        return UserDefaults.standard.stringArray(forKey: Prefs.Key.ignoredPaths) ?? []
    }

    private static func save(_ list: [String]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(list).write(to: fileURL, options: .atomic)
    }
}
