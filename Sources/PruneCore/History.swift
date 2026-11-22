import Foundation

/// One thing Prune removed, and where it went.
struct HistoryItem: Codable, Hashable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case inTrash    // can be restored or deleted for good
        case restored   // moved back to where it was
        case deleted    // permanently removed by "Free space now"
        case pruned     // removed by a command (Docker), nothing to restore
    }

    var id = UUID()
    let name: String
    let kind: String
    let originalPath: String
    let trashPath: String?
    let size: Int64
    var state: State
}

struct HistoryEntry: Codable, Identifiable, Sendable {
    var id = UUID()
    let date: Date
    var items: [HistoryItem]

    var total: Int64 { items.reduce(0) { $0 + $1.size } }
    var inTrash: [HistoryItem] { items.filter { $0.state == .inTrash } }
    var inTrashSize: Int64 { inTrash.reduce(0) { $0 + $1.size } }
}

/// Reads and writes the cleaning history (~/Library/Application Support/Prune/history.json).
enum HistoryFile {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Prune/history.json")
    }

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    static func save(_ entries: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(Array(entries.prefix(200))) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// Undo and "free space now" for items Prune moved to the Trash.
enum TrashOps {
    /// Moves an item back from the Trash. Refuses if something already sits at the original path.
    static func restore(_ item: HistoryItem) -> Bool {
        guard item.state == .inTrash, let trash = item.trashPath else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: trash), !fm.fileExists(atPath: item.originalPath) else { return false }
        let original = URL(fileURLWithPath: item.originalPath)
        do {
            try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: URL(fileURLWithPath: trash), to: original)
            return true
        } catch {
            NSLog("Prune: restore failed for \(item.originalPath): \(error)")
            return false
        }
    }

    /// Permanently deletes exactly what Prune put in the Trash (never anything else in there).
    static func deleteForever(_ item: HistoryItem) -> Bool {
        guard item.state == .inTrash, let trash = item.trashPath else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Only ever touch paths inside a Trash folder.
        guard trash.hasPrefix(home + "/.Trash/") || trash.contains("/.Trashes/") else { return false }
        guard FileManager.default.fileExists(atPath: trash) else { return true } // already emptied by the user
        do {
            try FileManager.default.removeItem(atPath: trash)
            return true
        } catch {
            NSLog("Prune: delete failed for \(trash): \(error)")
            return false
        }
    }
}
