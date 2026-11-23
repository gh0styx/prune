import Foundation

/// A mounted disk (the startup disk, an external SSD, a USB stick…).
struct Volume: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let total: Int64
    let free: Int64
    let isBoot: Bool
    let isInternal: Bool
    let isRemovable: Bool

    var id: String { url.path }
    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var symbol: String { isBoot || isInternal ? "internaldrive" : (isRemovable ? "externaldrive.badge.minus" : "externaldrive") }

    /// Browsable, visible volumes; the startup disk first.
    static func all() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsRemovableKey,
                                      .volumeIsBrowsableKey, .volumeIsReadOnlyKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var list: [Volume] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsBrowsable != false,
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            // Skip the read-only system snapshot and tiny system volumes (Preboot, VM, …).
            let path = url.path
            if path.hasPrefix("/System/Volumes") { continue }
            let free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            list.append(Volume(url: url, name: v.volumeName ?? url.lastPathComponent, total: Int64(total), free: free,
                               isBoot: path == "/", isInternal: v.volumeIsInternal ?? false,
                               isRemovable: v.volumeIsRemovable ?? false))
        }
        return list.sorted { ($0.isBoot ? 0 : 1, $0.name) < ($1.isBoot ? 0 : 1, $1.name) }
    }
}

/// Finds large files without building the whole disk map: walks the home folder (or another volume)
/// and skips places where single files belong to something bigger (Library, hidden folders,
/// app bundles, node_modules). Much faster than mapping everything.
enum LargeFileScanner {
    static func scan(root: URL, progress: ScanProgress) -> [CleanItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL
        let threshold = DiskScanner.largeFileThreshold
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey, .contentModificationDateKey]
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                    errorHandler: { _, _ in true }) else { return [] }
        let library = home.appending(path: "Library").path
        var items: [CleanItem] = []
        var seen = 0
        while let url = e.nextObject() as? URL {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true {
                let name = url.lastPathComponent
                if IgnoreList.contains(url) { e.skipDescendants(); continue }
                if url.path == library || name == "node_modules" || name == "CloudStorage" { e.skipDescendants() }
                continue
            }
            seen += 1
            if seen % 500 == 0 { progress.tick(500, url.deletingLastPathComponent().path) }
            guard v.isRegularFile == true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            guard size >= threshold else { continue }
            let kind = NodeKind.forFile(url.pathExtension)
            let modified = v.contentModificationDate
            items.append(CleanItem(
                url: url, category: .largeFiles, name: url.lastPathComponent,
                kind: url.pathExtension.isEmpty ? kind.label : "\(kind.label) · \(url.pathExtension.lowercased())",
                location: Fmt.tilde(url.deletingLastPathComponent().path), size: size, lastActivity: modified,
                isStale: modified.map { Date().timeIntervalSince($0) > 60 * 60 * 24 * 365 } ?? false))
        }
        return items.sorted { $0.size > $1.size }
    }
}
