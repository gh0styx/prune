import AppKit
import Darwin

/// Finds reclaimable files. Everything here is synchronous and meant to run off the main thread.
struct Scanner: Sendable {
    /// Optional live feedback for the scan screen (folders visited, current path).
    var progress: ScanProgress? = nil

    static var staleAfter: TimeInterval { TimeInterval(Prefs.staleDays) * 60 * 60 * 24 }

    let home = FileManager.default.homeDirectoryForCurrentUser

    // MARK: Projects (node_modules + build artifacts)

    static let defaultRootNames = [
        "Developer", "Projects", "Code", "dev", "src", "repos", "GitHub",
        "Sites", "work", "workspace", "Documents", "Desktop",
    ]

    private static let skipDirs: Set<String> = [
        "Library", "Applications", "Pods", "DerivedData", "vendor", "Movies", "Music", "Pictures",
    ]

    private static let jsArtifacts: Set<String> = [
        ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular", ".docusaurus",
    ]

    func projectRoots() -> [URL] {
        var seen = Set<String>()
        var roots: [URL] = []
        let candidates = (Prefs.useDefaultFolders ? Self.defaultRootNames.map { home.appending(path: $0) } : [])
            + Prefs.extraFolders.map { URL(fileURLWithPath: $0) }
        for url in candidates {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let key = url.resolvingSymlinksInPath().path.lowercased()
            if seen.insert(key).inserted { roots.append(url) }
        }
        // Drop folders that sit inside another root so nothing is counted twice.
        func key(_ u: URL) -> String { u.resolvingSymlinksInPath().path.lowercased() }
        return roots.filter { r in
            !roots.contains { other in other != r && key(r).hasPrefix(key(other) + "/") }
        }
    }

    func scanProjects() -> [CleanItem] {
        var found: [(url: URL, category: CategoryID, kind: String)] = []
        for root in projectRoots() { walk(root, depth: 0, into: &found) }

        var sizes = [(unique: Int64, shared: Int64)](repeating: (0, 0), count: found.count)
        sizes.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: found.count) { i in
                buf[i] = Sizer.measure(found[i].url)
            }
        }

        let git = GitActivity(home: home)
        var items: [CleanItem] = []
        for (i, f) in found.enumerated() where sizes[i].unique + sizes[i].shared > 0 {
            let project = f.url.deletingLastPathComponent()
            let last = git.lastActivity(for: project)
            items.append(CleanItem(
                url: f.url, category: f.category, name: project.lastPathComponent, kind: f.kind,
                location: Fmt.tilde(project.path), size: sizes[i].unique, lastActivity: last,
                isStale: last.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? false,
                shared: sizes[i].shared))
        }
        return items
    }

    private func walk(_ dir: URL, depth: Int, into found: inout [(url: URL, category: CategoryID, kind: String)]) {
        guard depth <= 8 else { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        progress?.tick(1, dir.path)
        let siblings = Set(children.map(\.lastPathComponent))

        for child in children {
            guard let v = try? child.resourceValues(forKeys: Set(keys)),
                  v.isDirectory == true, v.isSymbolicLink != true, v.isPackage != true else { continue }
            let name = child.lastPathComponent

            if name == "node_modules" {
                found.append((child, .nodeModules, "node_modules" + Self.packageManager(siblings)))
                continue
            }
            if let kind = artifactKind(name: name, url: child, siblings: siblings) {
                found.append((child, .buildArtifacts, kind))
                continue
            }
            if name.hasPrefix(".") || Self.skipDirs.contains(name) { continue }
            walk(child, depth: depth + 1, into: &found)
        }
    }

    /// Which package manager installed a node_modules, judged by the lockfile next to it.
    static func packageManager(_ siblings: Set<String>) -> String {
        if siblings.contains("pnpm-lock.yaml") { return " · pnpm" }
        if siblings.contains("bun.lockb") || siblings.contains("bun.lock") { return " · bun" }
        if siblings.contains("yarn.lock") { return " · yarn" }
        if siblings.contains("package-lock.json") { return " · npm" }
        return ""
    }

    private func artifactKind(name: String, url: URL, siblings: Set<String>) -> String? {
        let gradle = siblings.contains("build.gradle") || siblings.contains("build.gradle.kts")
            || siblings.contains("settings.gradle") || siblings.contains("settings.gradle.kts")
        switch name {
        case _ where Self.jsArtifacts.contains(name) && siblings.contains("package.json"):
            return name
        case "target" where siblings.contains("Cargo.toml"):
            return "target · Rust"
        case let n where (n == ".venv" || n == "venv")
            && FileManager.default.fileExists(atPath: url.appending(path: "pyvenv.cfg").path):
            return "\(name) · Python"
        case "build" where gradle:
            return "build · Gradle"
        case ".gradle" where gradle:
            return ".gradle"
        default:
            return nil
        }
    }

    // MARK: Fixed locations

    func scanXcode() -> [CleanItem] {
        let dev = home.appending(path: "Library/Developer")
        var items: [CleanItem] = []
        for url in subdirectories(of: dev.appending(path: "Xcode/DerivedData")) {
            var parts = url.lastPathComponent.split(separator: "-")
            if parts.count > 1 { parts.removeLast() }
            items.append(item(url, .xcode, name: parts.joined(separator: "-"), kind: "DerivedData"))
        }
        for platform in ["iOS", "watchOS", "tvOS", "visionOS"] {
            for url in subdirectories(of: dev.appending(path: "Xcode/\(platform) DeviceSupport")) {
                items.append(item(url, .xcode, name: url.lastPathComponent, kind: "\(platform) DeviceSupport"))
            }
        }
        items.append(item(dev.appending(path: "Xcode/Archives"), .xcode, name: tr("Archives"), kind: "Xcode"))
        items.append(item(dev.appending(path: "CoreSimulator/Caches"), .xcode, name: tr("Simulator caches"), kind: "CoreSimulator"))
        items.append(item(home.appending(path: "Library/Caches/com.apple.dt.Xcode"), .xcode, name: tr("Xcode cache"), kind: "Caches"))
        return items.filter { $0.size + $0.shared > 0 }
    }

    static let packageCachePaths: [(name: String, path: String)] = [
        ("npm", ".npm/_cacache"),
        ("pnpm store", "Library/pnpm/store"),
        ("pnpm cache", "Library/Caches/pnpm"),
        ("Yarn", "Library/Caches/Yarn"),
        ("Bun", ".bun/install/cache"),
        ("pip", "Library/Caches/pip"),
        ("uv", ".cache/uv"),
        ("Homebrew", "Library/Caches/Homebrew"),
        ("Cargo registry", ".cargo/registry/cache"),
        ("Gradle", ".gradle/caches"),
        ("CocoaPods", "Library/Caches/CocoaPods"),
        ("Go build", "Library/Caches/go-build"),
        ("Playwright browsers", "Library/Caches/ms-playwright"),
        ("Puppeteer browsers", ".cache/puppeteer"),
        ("Electron", "Library/Caches/electron"),
        ("node-gyp", "Library/Caches/node-gyp"),
        ("Deno", "Library/Caches/deno"),
    ]

    func scanPackageCaches() -> [CleanItem] {
        Self.packageCachePaths
            .map { item(home.appending(path: $0.path), .packageCaches, name: $0.name, kind: "~/" + $0.path) }
            .filter { $0.size + $0.shared > 0 }
    }

    func scanAppCaches() -> [CleanItem] {
        let caches = home.appending(path: "Library/Caches")
        let excluded = Set(Self.packageCachePaths.compactMap { p -> String? in
            p.path.hasPrefix("Library/Caches/") ? String(p.path.dropFirst("Library/Caches/".count)) : nil
        })
        return subdirectories(of: caches)
            .filter { !excluded.contains($0.lastPathComponent) && !$0.lastPathComponent.hasPrefix("com.apple.") }
            .map { item($0, .appCaches, name: appName(for: $0.lastPathComponent), kind: $0.lastPathComponent) }
            .filter { $0.size > 5_000_000 }
    }

    func scanLogs() -> [CleanItem] {
        let logs = home.appending(path: "Library/Logs")
        let children = (try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)) ?? []
        return children
            .map { item($0, .logs, name: $0.lastPathComponent, kind: "~/Library/Logs") }
            .filter { $0.size > 1_000_000 }
    }

    // MARK: Docker

    static let dockerPaths = [
        "/opt/homebrew/bin/docker", "/usr/local/bin/docker", "~/.docker/bin/docker", "~/.orbstack/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ]

    static func dockerBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return dockerPaths.map { $0.replacingOccurrences(of: "~", with: home) }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func scanDocker() -> (status: DockerStatus, items: [CleanItem]) {
        guard let docker = Self.dockerBinary() else { return (.notInstalled, []) }
        guard let out = Shell.run(docker, ["system", "df", "--format", "{{.Type}}\t{{.TotalCount}}\t{{.Reclaimable}}"]) else {
            return (.notRunning, [])
        }
        let actions: [String: (name: String, kind: String, args: [String])] = [
            "Images": ("Unused images", "images", ["image", "prune", "-a", "-f"]),
            "Build Cache": ("Build cache", "build cache", ["builder", "prune", "-a", "-f"]),
            "Containers": ("Stopped containers", "containers", ["container", "prune", "-f"]),
            // No -a: only anonymous volumes. Named volumes (databases!) are never pruned.
            "Local Volumes": ("Unused anonymous volumes", "volumes", ["volume", "prune", "-f"]),
        ]
        var items: [CleanItem] = []
        for line in out.split(separator: "\n") {
            let cols = line.split(separator: "\t").map(String.init)
            guard cols.count == 3, let a = actions[cols[0]] else { continue }
            let size = Self.parseDockerSize(cols[2])
            guard size > 0 else { continue }
            items.append(CleanItem(
                url: URL(string: "docker://\(a.kind.replacingOccurrences(of: " ", with: "-"))")!,
                category: .docker, name: tr(a.name), kind: a.kind, location: trf("%@ total", cols[1]) + " · docker \(a.args.prefix(2).joined(separator: " "))",
                size: size, lastActivity: nil, isStale: false, command: [docker] + a.args))
        }
        return (.running, items)
    }

    /// "4.21GB (85%)" -> 4_210_000_000
    static func parseDockerSize(_ s: String) -> Int64 {
        let token = s.split(separator: " ").first.map(String.init) ?? ""
        let digits = token.prefix { "0123456789.".contains($0) }
        let unit = token.dropFirst(digits.count).uppercased()
        let mult: Double = switch unit {
        case "KB": 1e3
        case "MB": 1e6
        case "GB": 1e9
        case "TB": 1e12
        default: 1
        }
        return Int64((Double(digits) ?? 0) * mult)
    }

    // MARK: Helpers

    private func item(_ url: URL, _ category: CategoryID, name: String, kind: String) -> CleanItem {
        progress?.tick(1, url.path)
        let m = FileManager.default.fileExists(atPath: url.path) ? Sizer.measure(url) : (unique: Int64(0), shared: Int64(0))
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return CleanItem(url: url, category: category, name: name, kind: kind,
                         location: Fmt.tilde(url.deletingLastPathComponent().path), size: m.unique,
                         lastActivity: modified,
                         isStale: modified.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? false,
                         shared: m.shared)
    }

    private func subdirectories(of url: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    private func appName(for bundleID: String) -> String {
        guard bundleID.contains("."),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }
}

enum Shell {
    /// Runs a binary and returns stdout, or nil on a non-zero exit or after `timeout` seconds
    /// (a stuck `docker` must never freeze scanning or cleaning).
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 30) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }
}

enum Sizer {
    private static let linkCountKey = URLResourceKey("NSURLLinkCountKey")
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, linkCountKey, .fileResourceIdentifierKey,
    ]

    /// Total allocated size.
    static func size(of url: URL) -> Int64 { let m = measure(url); return m.unique + m.shared }

    /// Bytes of an APFS file that are not shared with a clone (pnpm on macOS clones from its store,
    /// so most of node_modules is shared). Nil when the volume can't tell.
    static func privateSize(_ path: String) -> Int64? {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var buf = [UInt8](repeating: 0, count: 32)
        guard getattrlist(path, &list, &buf, buf.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW)) == 0 else { return nil }
        return buf.withUnsafeBytes { raw in
            raw.load(as: UInt32.self) >= 12 ? raw.loadUnaligned(fromByteOffset: 4, as: Int64.self) : nil
        }
    }

    /// Splits a folder's size into bytes removing it would actually free (`unique`) and bytes that stay
    /// because they are shared (`shared`): hard links that also live elsewhere, and APFS clone blocks
    /// shared with another file (pnpm's node_modules and its store). A hard-linked file whose every
    /// link sits inside `url` still counts as unique.
    static func measure(_ url: URL) -> (unique: Int64, shared: Int64) {
        func size(_ v: URLResourceValues) -> Int64 { Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }
        func links(_ v: URLResourceValues) -> Int { (v.allValues[linkCountKey] as? Int) ?? 1 }

        if let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true {
            if links(v) > 1 { return (0, size(v)) }
            let own = min(privateSize(url.path) ?? size(v), size(v))
            return (own, size(v) - own)
        }
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, _ in true }) else { return (0, 0) }
        var unique: Int64 = 0
        var shared: Int64 = 0
        var linked: [AnyHashable: (seen: Int, links: Int, size: Int64)] = [:]
        while let f = e.nextObject() as? URL {
            guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            let n = links(v)
            if n > 1, let id = v.fileResourceIdentifier as? AnyHashable {
                let prev = linked[id]
                linked[id] = ((prev?.seen ?? 0) + 1, n, size(v))
            } else {
                let total = size(v)
                let own = min(privateSize(f.path) ?? total, total)
                unique += own
                shared += total - own
            }
        }
        for entry in linked.values {
            if entry.seen >= entry.links { unique += entry.size } else { shared += entry.size }
        }
        return (unique, shared)
    }
}

/// Last commit time of the git repo a project lives in, falling back to the folder's modification date.
final class GitActivity: @unchecked Sendable {
    private let home: URL
    private var cache: [String: Date?] = [:]

    init(home: URL) { self.home = home }

    func lastActivity(for project: URL) -> Date? {
        var dir = project
        while dir.path.count > home.path.count {
            if FileManager.default.fileExists(atPath: dir.appending(path: ".git").path) {
                if let cached = cache[dir.path] { return cached }
                let date = commitDate(dir) ?? modified(project)
                cache[dir.path] = date
                return date
            }
            dir = dir.deletingLastPathComponent()
        }
        return modified(project)
    }

    private func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func commitDate(_ repo: URL) -> Date? {
        guard let out = Shell.run("/usr/bin/git", ["-C", repo.path, "log", "-1", "--format=%ct"], timeout: 5),
              let s = Optional(out.trimmingCharacters(in: .whitespacesAndNewlines)),
              let t = TimeInterval(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }
}

enum Trasher {
    /// Refuses anything outside the home folder or too close to its root.
    /// `leftover` additionally allows a single entry directly inside one of the ~/Library folders where
    /// apps keep data; only the uninstall flow sets it, for files it matched to that app.
    static func isSafe(_ url: URL, leftover: Bool = false) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        // Resolve symlinks first: /Volumes/Macintosh HD points back at the startup disk.
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        // Files on other disks (external SSDs, USB sticks), but never their hidden system folders.
        if path.hasPrefix("/Volumes/") {
            let parts = path.dropFirst("/Volumes/".count).split(separator: "/")
            return parts.count >= 2 && !parts[1].hasPrefix(".")
        }
        // Whole apps in /Applications can go to the Trash too.
        if path.hasPrefix("/Applications/") && path.hasSuffix(".app")
            && path.dropFirst("/Applications/".count).split(separator: "/").count == 1 { return true }
        guard path.hasPrefix(home + "/") else { return false }
        let rel = String(path.dropFirst(home.count + 1))
        let parts = rel.split(separator: "/")
        guard parts.count >= 2 else { return false }
        // Inside ~/Library only rebuildable places are allowed. iCloud Drive (Mobile Documents),
        // Mail, Messages, Containers, Preferences, Keychains… are refused unless uninstalling.
        if parts[0] == "Library" {
            if leftover, parts.count == 3, Scanner.leftoverDirs.contains(String(parts[1])) { return true }
            // A user launch agent (one plist) flagged by the security check.
            if parts.count == 3, parts[1] == "LaunchAgents", rel.hasSuffix(".plist") { return true }
            let allowed = ["Library/Caches/", "Library/Logs/", "Library/Developer/", "Library/pnpm/",
                           "Library/Application Support/MobileSync/Backup/",
                           "Library/Containers/com.apple.mail/Data/Library/Mail Downloads/",
                           "Library/Mail Downloads/"]
            return allowed.contains { rel.hasPrefix($0) } && parts.count >= 3
        }
        return true
    }

    struct Result: Sendable {
        var freed: Int64 = 0
        var trashed = Set<String>()
        var entry: HistoryEntry
    }

    static func trash(_ items: [CleanItem]) -> Result {
        var result = Result(entry: HistoryEntry(date: Date(), items: []))
        for item in items {
            if let command = item.command, let bin = command.first {
                if Shell.run(bin, Array(command.dropFirst()), timeout: 600) != nil {
                    result.freed += item.size
                    result.trashed.insert(item.id)
                    result.entry.items.append(HistoryItem(name: item.name, kind: item.kind, originalPath: "docker",
                                                          trashPath: nil, size: item.size, state: .pruned))
                }
                continue
            }
            guard isSafe(item.url, leftover: item.isLeftover) else { continue }
            do {
                var moved: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &moved)
                result.freed += item.size
                result.trashed.insert(item.id)
                result.entry.items.append(HistoryItem(name: item.name, kind: item.kind, originalPath: item.url.path,
                                                      trashPath: (moved as URL?)?.path, size: item.size, state: .inTrash))
            } catch {
                NSLog("Prune: could not trash \(item.url.path): \(error)")
            }
        }
        return result
    }
}
