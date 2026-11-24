import Foundation
import CryptoKit
import ImageIO
import Vision

struct DuplicateFile: Identifiable, Hashable, Sendable {
    let url: URL
    let modified: Date?
    let size: Int64
    let location: String

    var id: URL { url }
    var name: String { url.lastPathComponent }

    init(url: URL, modified: Date?, size: Int64) {
        self.url = url
        self.modified = modified
        self.size = size
        self.location = Fmt.tilde(url.deletingLastPathComponent().path)
    }
}

struct DuplicateGroup: Identifiable, Sendable {
    let id: UUID
    let files: [DuplicateFile]
    /// Size of one file (the largest one for similar photos).
    let size: Int64
    /// What removing everything but one file frees.
    let wasted: Int64

    /// `identical`: all files have the same size, so wasted = size × (count − 1).
    /// Otherwise (similar photos) the largest file is kept in the sum.
    init(id: UUID = UUID(), files: [DuplicateFile], identical: Bool) {
        self.id = id
        self.files = files
        let largest = files.map(\.size).max() ?? 0
        self.size = largest
        if identical {
            self.wasted = largest * Int64(max(files.count - 1, 0))
        } else {
            self.wasted = max(0, files.reduce(0) { $0 + $1.size } - largest)
        }
    }
}

/// Which copy of a duplicate group stays where it is. Every other copy goes to the Trash.
enum KeepRule: String, CaseIterable, Sendable {
    case newest, oldest, largest

    /// The copy this rule keeps. Files without a date count as the oldest.
    func keeper(in files: [DuplicateFile]) -> DuplicateFile? {
        switch self {
        case .newest: files.max { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
        case .oldest: files.min { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
        case .largest: files.max { $0.size < $1.size }
        }
    }
}

extension DuplicateGroup {
    /// The copies the rule would move to the Trash.
    func trashed(keeping rule: KeepRule) -> [DuplicateFile] {
        guard let keeper = rule.keeper(in: files) else { return [] }
        return files.filter { $0.url != keeper.url }
    }
}

/// Progress shared between the worker thread and the view.
final class DupProgress: @unchecked Sendable {
    struct Snapshot: Sendable {
        var processed = 0
        var total = 0
        var path = ""
    }

    private let lock = NSLock()
    private var value = Snapshot()
    private var cancelled = false

    /// Stops the running scan. The scan loops check this and return what they have so far.
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func reset(total: Int) {
        lock.lock(); value = Snapshot(processed: 0, total: total, path: ""); lock.unlock()
    }
    func setTotal(_ total: Int) {
        lock.lock(); value.total = total; lock.unlock()
    }
    func advance(path: String? = nil, by n: Int = 1) {
        lock.lock()
        value.processed += n
        if let path { value.path = path }
        lock.unlock()
    }
    func setPath(_ path: String) {
        lock.lock(); value.path = path; lock.unlock()
    }
    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

enum DuplicateFinder {
    /// Files smaller than this are ignored by the identical-files scan.
    static let minSize: Int64 = 1_000_000
    /// Feature-print distance below which two photos count as the same shot.
    static let photoThreshold: Float = 0.35
    static let maxPhotos = 3000
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "png", "tiff", "tif", "webp"]

    private static func roots(_ names: [String]) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var seen = Set<String>()
        return names.compactMap { n in
            let u = home.appendingPathComponent(n, isDirectory: true)
            guard FileManager.default.fileExists(atPath: u.path), seen.insert(u.path).inserted else { return nil }
            return u
        }
    }

    private struct Entry {
        let url: URL
        let size: Int64
        let modified: Date?
    }

    /// Walks the roots, skipping hidden folders, packages and dependency folders.
    private static func walk(_ roots: [URL], progress: DupProgress, accept: (URL, Int64) -> Bool, limit: Int = .max) -> [Entry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        var out: [Entry] = []
        var ids = Set<NSObject>()
        var count = 0
        for root in roots {
            if progress.isCancelled { break }
            guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in en {
                if progress.isCancelled { break }
                autoreleasepool {
                    let name = url.lastPathComponent
                    guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return }
                    if v.isDirectory == true {
                        if IgnoreList.contains(url) { en.skipDescendants(); return }
                        let ext = url.pathExtension.lowercased()
                        if name == "node_modules" || name == ".git" || ext == "app" || ext == "photoslibrary" || name == "Library" && url.deletingLastPathComponent() == root.deletingLastPathComponent() {
                            en.skipDescendants()
                        }
                        return
                    }
                    guard v.isRegularFile == true, let size = v.fileSize.map(Int64.init) else { return }
                    guard accept(url, size) else { return }
                    // Hard links and APFS clones share one identifier: count them once.
                    if let id = v.fileResourceIdentifier as? NSObject, !ids.insert(id).inserted { return }
                    out.append(Entry(url: url, size: size, modified: v.contentModificationDate))
                    count += 1
                    if count % 64 == 0 { progress.setPath(Fmt.tilde(url.path)); progress.setTotal(count) }
                }
                if count >= limit { break }
            }
            if count >= limit { break }
        }
        progress.setTotal(count)
        return out
    }

    // MARK: Identical files

    static func identical(progress: DupProgress, in folders: [URL]? = nil) -> [DuplicateGroup] {
        progress.reset(total: 0)
        let all = walk(folders ?? roots(["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music"]), progress: progress) { _, size in size >= minSize }

        var bySize: [Int64: [Entry]] = [:]
        for e in all { bySize[e.size, default: []].append(e) }
        let sized = bySize.values.filter { $0.count > 1 }
        let candidates = sized.reduce(0) { $0 + $1.count }
        // Each candidate is touched twice at most: a quick head hash, then a full hash.
        progress.reset(total: candidates)

        var groups: [DuplicateGroup] = []
        for same in sized {
            if progress.isCancelled { break }
            var byHead: [Data: [Entry]] = [:]
            for e in same {
                progress.advance(path: Fmt.tilde(e.url.path))
                if let h = hash(e.url, limit: 65_536) { byHead[h, default: []].append(e) }
            }
            for headGroup in byHead.values where headGroup.count > 1 {
                var byFull: [Data: [Entry]] = [:]
                for e in headGroup {
                    progress.setPath(Fmt.tilde(e.url.path))
                    if let h = hash(e.url, limit: nil) { byFull[h, default: []].append(e) }
                }
                for g in byFull.values where g.count > 1 {
                    let files = g.map { DuplicateFile(url: $0.url, modified: $0.modified, size: $0.size) }
                    groups.append(DuplicateGroup(files: files, identical: true))
                }
            }
        }
        if progress.isCancelled { return [] }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    /// SHA256 of the file (or its first `limit` bytes), streamed in 1 MB chunks.
    private static func hash(_ url: URL, limit: Int?) -> Data? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        var left = limit ?? .max
        while left > 0 {
            let chunk: Data? = autoreleasepool {
                try? fh.read(upToCount: min(1_048_576, left))
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            left -= chunk.count
        }
        return Data(hasher.finalize())
    }

    // MARK: Similar photos

    static func similarPhotos(progress: DupProgress, in folders: [URL]? = nil) -> [DuplicateGroup] {
        progress.reset(total: 0)
        let entries = walk(folders ?? roots(["Pictures", "Desktop", "Downloads", "Documents"]), progress: progress,
                           accept: { url, size in size > 0 && imageExtensions.contains(url.pathExtension.lowercased()) },
                           limit: maxPhotos)
        if progress.isCancelled { return [] }
        let n = entries.count
        progress.reset(total: n)

        // Feature prints, computed on all cores.
        let lock = NSLock()
        var prints = [VNFeaturePrintObservation?](repeating: nil, count: n)
        DispatchQueue.concurrentPerform(iterations: n) { i in
            if progress.isCancelled { return }
            autoreleasepool {
                let e = entries[i]
                let fp = featurePrint(e.url)
                lock.lock(); prints[i] = fp; lock.unlock()
                progress.advance(path: Fmt.tilde(e.url.path))
            }
        }

        // Pairwise distances. Two photos are "similar" when their distance is under the threshold.
        progress.reset(total: n)
        var edges: [[Int]] = Array(repeating: [], count: n)
        DispatchQueue.concurrentPerform(iterations: n) { i in
            if progress.isCancelled { return }
            var found: [Int] = []
            if let a = prints[i] {
                var j = i + 1
                while j < n {
                    if let b = prints[j] {
                        var d: Float = 0
                        if (try? a.computeDistance(&d, to: b)) != nil, d < photoThreshold { found.append(j) }
                    }
                    j += 1
                }
            }
            lock.lock(); edges[i] = found; lock.unlock()
            progress.advance(path: Fmt.tilde(entries[i].url.path))
        }
        if progress.isCancelled { return [] }

        // Complete-linkage: a photo joins a group only when it is similar to every photo already in it.
        // Chaining (A~B and B~C pulling in an unrelated C) is what union-find did before, and it merged
        // different shots into one group.
        var adj = Array(repeating: Set<Int>(), count: n)
        for i in 0..<n { for j in edges[i] { adj[i].insert(j); adj[j].insert(i) } }
        var assigned = Array(repeating: false, count: n)
        var clusters: [[Int]] = []
        for i in 0..<n where prints[i] != nil && !assigned[i] {
            var cluster = [i]
            assigned[i] = true
            for j in adj[i].sorted() where !assigned[j] {
                if cluster.allSatisfy({ adj[j].contains($0) }) {
                    cluster.append(j)
                    assigned[j] = true
                }
            }
            if cluster.count > 1 { clusters.append(cluster) }
        }
        let groups = clusters.map { idx in
            DuplicateGroup(files: idx.map { DuplicateFile(url: entries[$0].url, modified: entries[$0].modified, size: entries[$0].size) },
                           identical: false)
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    private static func featurePrint(_ url: URL) -> VNFeaturePrintObservation? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        return request.results?.first
    }
}
