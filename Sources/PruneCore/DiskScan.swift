import Foundation

// MARK: Node

enum NodeKind: Sendable {
    case folder, app, bundle, video, audio, image, archive, diskImage, code, document, other, system, smallFiles

    var symbol: String {
        switch self {
        case .folder: "folder.fill"
        case .app: "app.dashed"
        case .bundle: "shippingbox.fill"
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        case .archive: "doc.zipper"
        case .diskImage: "opticaldiscdrive"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .document: "doc.text"
        case .other: "doc"
        case .system: "gearshape.2"
        case .smallFiles: "square.grid.3x3"
        }
    }


    var label: String { tr(englishLabel) }

    private var englishLabel: String {
        switch self {
        case .folder: "Folder"
        case .app: "App"
        case .bundle: "Package"
        case .video: "Video"
        case .audio: "Audio"
        case .image: "Image"
        case .archive: "Archive"
        case .diskImage: "Disk image"
        case .code: "Dev"
        case .document: "Document"
        case .other: "File"
        case .system: "System"
        case .smallFiles: "Small items"
        }
    }


    static func forFile(_ ext: String) -> NodeKind {
        switch ext.lowercased() {
        case "mov", "mp4", "m4v", "mkv", "avi", "webm", "prores", "mxf", "braw": .video
        case "mp3", "wav", "aif", "aiff", "flac", "m4a", "aac", "logicx": .audio
        case "jpg", "jpeg", "png", "heic", "raw", "cr2", "cr3", "nef", "arw", "dng", "psd", "tif", "tiff", "gif", "webp": .image
        case "zip", "tar", "gz", "tgz", "rar", "7z", "xz", "bz2", "zst": .archive
        case "dmg", "iso", "pkg", "img", "vmdk", "qcow2", "raw-disk", "sparseimage", "sparsebundle", "ipsw": .diskImage
        case "pdf", "doc", "docx", "pages", "key", "keynote", "ppt", "pptx", "xls", "xlsx", "numbers", "txt", "md", "epub": .document
        case "swift", "js", "ts", "tsx", "jsx", "py", "rs", "go", "java", "kt", "c", "cpp", "h", "json", "lock", "wasm", "so", "dylib", "a", "o": .code
        default: .other
        }
    }

    static func forDirectory(_ name: String, isPackage: Bool) -> NodeKind {
        if isPackage { return name.hasSuffix(".app") ? .app : .bundle }
        switch name {
        case "node_modules", ".next", ".turbo", "target", ".venv", "venv", "DerivedData", ".git", ".gradle", "Pods": return .code
        default: return .folder
        }
    }
}

final class DiskNode: Identifiable, @unchecked Sendable {
    let name: String
    let url: URL?
    let kind: NodeKind
    let modified: Date?
    var size: Int64
    var fileCount: Int
    var children: [DiskNode]
    weak var parent: DiskNode?

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    var isDrillable: Bool { !children.isEmpty }
    var path: [DiskNode] {
        var out: [DiskNode] = [self]
        var p = parent
        while let n = p { out.insert(n, at: 0); p = n.parent }
        return out
    }

    init(name: String, url: URL?, kind: NodeKind, size: Int64, fileCount: Int, modified: Date? = nil, children: [DiskNode] = []) {
        self.name = name
        self.url = url
        self.kind = kind
        self.size = size
        self.fileCount = fileCount
        self.modified = modified
        self.children = children
        for c in children { c.parent = self }
    }

    /// Removes deleted paths (path → bytes freed) from the tree and shrinks every ancestor.
    /// A path that isn't its own node (inside an app bundle, folded into "smaller items", or deeper
    /// than the map went) still shrinks the deepest folder that contains it.
    func remove(deleted: [String: Int64]) {
        for (path, bytes) in deleted { _ = remove(path: path, bytes: bytes) }
    }

    private func remove(path: String, bytes: Int64) -> (size: Int64, files: Int) {
        for (i, c) in children.enumerated() {
            guard let cp = c.url?.path else { continue }
            if cp == path {
                children.remove(at: i)
                size = max(0, size - c.size)
                fileCount = max(0, fileCount - c.fileCount)
                return (c.size, c.fileCount)
            }
            if path.hasPrefix(cp + "/") {
                let r = c.remove(path: path, bytes: bytes)
                size = max(0, size - r.size)
                fileCount = max(0, fileCount - r.files)
                if c.size == 0 && c.children.isEmpty { children.remove(at: i) }
                return r
            }
        }
        // Not mapped as its own node: shrink this folder (and "smaller items" when it's in there).
        guard url != nil else { return (0, 0) }
        let r = min(bytes, size)
        if let small = children.first(where: { $0.kind == .smallFiles }), small.size >= r {
            small.size -= r
            if small.size == 0 { children.removeAll { $0 === small } }
        }
        size -= r
        return (r, 0)
    }

    /// True while this node is still attached to `root` (it wasn't removed with a parent).
    func isAttached(to root: DiskNode) -> Bool {
        var node = self
        while let p = node.parent {
            guard p.children.contains(where: { $0 === node }) else { return false }
            node = p
        }
        return node === root
    }

    func asCleanItem() -> CleanItem? {
        guard let url, kind != .smallFiles, kind != .system else { return nil }
        return CleanItem(url: url, category: .largeFiles, name: name, kind: kind.label,
                         location: Fmt.tilde(url.deletingLastPathComponent().path), size: size,
                         lastActivity: modified, isStale: false)
    }
}

// MARK: Scanner

final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _files = 0
    private var _path = ""

    func tick(_ n: Int, _ path: String) {
        lock.lock(); _files += n; _path = path; lock.unlock()
    }

    var snapshot: (files: Int, path: String) {
        lock.lock(); defer { lock.unlock() }
        return (_files, _path)
    }
}

private final class LargeFileCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var items: [CleanItem] = []
    func add(_ item: CleanItem) { lock.lock(); items.append(item); lock.unlock() }
}

struct DiskScanner: Sendable {
    static var largeFileThreshold: Int64 { Int64(Prefs.largeFileMB) * 1_000_000 }
    static let keepThreshold: Int64 = 1_000_000

    let progress: ScanProgress
    let home = FileManager.default.homeDirectoryForCurrentUser
    /// Set when mapping a disk other than the startup disk; large files are then collected anywhere on it.
    var volumeRoot: URL? = nil

    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
    ]

    /// Maps the home folder and /Applications. Returns the tree root and files over 100 MB.
    func scan(diskUsed: Int64) -> (root: DiskNode, largeFiles: [CleanItem]) {
        let collector = LargeFileCollector()

        // Scan top-level home folders in parallel; they are independent.
        let top = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: Array(Self.keys))) ?? []
        var nodes = [DiskNode?](repeating: nil, count: top.count)
        nodes.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: top.count) { i in
                buf[i] = node(for: top[i], insidePackage: false, collector: collector)
            }
        }
        let homeNode = assemble(name: tr("Home"), url: home, kind: .folder, entries: nodes.compactMap { $0 })

        let appsURL = URL(fileURLWithPath: "/Applications")
        let apps = (try? FileManager.default.contentsOfDirectory(at: appsURL, includingPropertiesForKeys: Array(Self.keys))) ?? []
        var appNodes = [DiskNode?](repeating: nil, count: apps.count)
        appNodes.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: apps.count) { i in
                buf[i] = node(for: apps[i], insidePackage: true, collector: collector)
            }
        }
        let appsNode = assemble(name: tr("Applications"), url: appsURL, kind: .folder, entries: appNodes.compactMap { $0 })

        var rootChildren = [homeNode, appsNode]
        let other = diskUsed - homeNode.size - appsNode.size
        if other > 0 {
            rootChildren.append(DiskNode(name: tr("System & other volumes"), url: nil, kind: .system, size: other, fileCount: 0))
        }
        let root = DiskNode(name: "Macintosh HD", url: nil, kind: .folder,
                            size: rootChildren.reduce(0) { $0 + $1.size },
                            fileCount: homeNode.fileCount + appsNode.fileCount,
                            children: rootChildren.sorted { $0.size > $1.size })
        return (root, collector.items.sorted { $0.size > $1.size })
    }

    /// Maps another disk (external SSD, USB stick…): every visible top-level folder on it.
    func scan(volume: Volume) -> (root: DiskNode, largeFiles: [CleanItem]) {
        let collector = LargeFileCollector()
        let top = ((try? FileManager.default.contentsOfDirectory(at: volume.url, includingPropertiesForKeys: Array(Self.keys),
                                                                options: [.skipsHiddenFiles])) ?? [])
        var nodes = [DiskNode?](repeating: nil, count: top.count)
        nodes.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: top.count) { i in
                buf[i] = node(for: top[i], insidePackage: false, collector: collector)
            }
        }
        var children = nodes.compactMap { $0 }
        let mapped = children.reduce(0) { $0 + $1.size }
        if volume.used - mapped > 50_000_000 {
            children.append(DiskNode(name: tr("Hidden & system files"), url: nil, kind: .system,
                                     size: volume.used - mapped, fileCount: 0))
        }
        let root = assemble(name: volume.name, url: volume.url, kind: .folder, entries: children)
        return (root, collector.items.sorted { $0.size > $1.size })
    }

    private func node(for url: URL, insidePackage: Bool, collector: LargeFileCollector) -> DiskNode? {
        guard let v = try? url.resourceValues(forKeys: Self.keys), v.isSymbolicLink != true else { return nil }
        let name = url.lastPathComponent
        if v.isDirectory == true {
            if skip(url) { return nil }
            let package = v.isPackage == true
            return scanDirectory(url, kind: NodeKind.forDirectory(name, isPackage: package),
                                 insidePackage: insidePackage || package, collector: collector)
        }
        let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        let kind = NodeKind.forFile(url.pathExtension)
        if size >= Self.largeFileThreshold && !insidePackage && collectable(url) {
            let modified = v.contentModificationDate
            collector.add(CleanItem(
                url: url, category: .largeFiles, name: name,
                kind: url.pathExtension.isEmpty ? kind.label : "\(kind.label) · \(url.pathExtension.lowercased())",
                location: Fmt.tilde(url.deletingLastPathComponent().path), size: size, lastActivity: modified,
                isStale: modified.map { Date().timeIntervalSince($0) > 60 * 60 * 24 * 365 } ?? false))
        }
        return DiskNode(name: name, url: url, kind: kind, size: size, fileCount: 1, modified: v.contentModificationDate)
    }

    private func scanDirectory(_ url: URL, kind: NodeKind, insidePackage: Bool, collector: LargeFileCollector) -> DiskNode {
        let entries = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(Self.keys))) ?? []
        var children: [DiskNode] = []
        children.reserveCapacity(entries.count)
        var files = 0
        for e in entries {
            if IgnoreList.contains(e) { continue }
            guard let n = node(for: e, insidePackage: insidePackage, collector: collector) else { continue }
            if n.fileCount == 1 && n.children.isEmpty { files += 1 }
            children.append(n)
        }
        if files > 0 { progress.tick(files, url.path) }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let node = assemble(name: url.lastPathComponent, url: url, kind: kind, entries: children, modified: modified)
        // Packages (apps, Photos library…) are shown as a single block.
        if kind == .app || kind == .bundle { node.children = [] }
        return node
    }

    /// Sums children, folds tiny items into one "smaller items" block, sorts by size.
    private func assemble(name: String, url: URL, kind: NodeKind, entries: [DiskNode], modified: Date? = nil) -> DiskNode {
        var kept: [DiskNode] = []
        var small: Int64 = 0
        var smallCount = 0
        var total: Int64 = 0
        var count = 0
        for n in entries {
            total += n.size
            count += n.fileCount
            if n.size >= Self.keepThreshold { kept.append(n) } else { small += n.size; smallCount += 1 }
        }
        if small > 0 && !kept.isEmpty {
            kept.append(DiskNode(name: plural(smallCount, .smallerItem), url: nil, kind: .smallFiles, size: small, fileCount: 0))
        }
        kept.sort { $0.size > $1.size }
        return DiskNode(name: name, url: url, kind: kind, size: total, fileCount: count, modified: modified, children: kept)
    }

    private func skip(_ url: URL) -> Bool {
        // Cloud provider folders can trigger network listings; skip descending into them.
        url.path == home.appending(path: "Library/CloudStorage").path
    }

    /// Large files we offer for removal. Skips places where a single file is part of something bigger
    /// and removing it would break an app: ~/Library, hidden folders (~/.codex, ~/.ollama, .git, .venv…)
    /// and node_modules (covered by its own category).
    private func collectable(_ url: URL) -> Bool {
        let p = url.path
        if let root = volumeRoot {
            guard p.hasPrefix(root.path + "/") else { return false }
            let parts = p.dropFirst(root.path.count + 1).split(separator: "/").dropLast()
            return !parts.contains { $0.hasPrefix(".") || $0 == "node_modules" }
        }
        guard p.hasPrefix(home.path + "/"), !p.hasPrefix(home.appending(path: "Library").path + "/") else { return false }
        let parts = p.dropFirst(home.path.count + 1).split(separator: "/").dropLast()
        return !parts.contains { $0.hasPrefix(".") || $0 == "node_modules" }
    }
}
