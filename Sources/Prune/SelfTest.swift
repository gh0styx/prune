import Foundation

/// `Prune --selftest` runs every scanner once and prints what it found. Read-only: nothing is trashed or pruned.
enum SelfTest {
    /// Tree bookkeeping after deletes (Space map): parents must shrink in every case.
    static func treeTest() -> Bool {
        func n(_ path: String, _ size: Int64, _ kind: NodeKind = .folder, _ kids: [DiskNode] = []) -> DiskNode {
            DiskNode(name: (path as NSString).lastPathComponent, url: URL(fileURLWithPath: path), kind: kind,
                     size: size, fileCount: 1, children: kids)
        }
        let small = DiskNode(name: "small", url: nil, kind: .smallFiles, size: 30, fileCount: 0)
        let app = n("/h/Apps/Big.app", 400, .app)
        let deep = n("/h/a/b", 100, .folder, [n("/h/a/b/file", 100, .other)])
        let a = n("/h/a", 230, .folder, [deep, small])
        let apps = n("/h/Apps", 400, .folder, [app])
        let root = DiskNode(name: "root", url: nil, kind: .folder, size: 630, fileCount: 3,
                            children: [n("/h", 630, .folder, [a, apps])])
        root.remove(deleted: [
            "/h/a/b/file": 100,                 // a mapped node
            "/h/a/tiny.txt": 20,                // folded into "smaller items"
            "/h/Apps/Big.app/Contents/x": 50,   // inside a package (no children)
        ])
        let home = root.children[0]
        let ok = root.size == 460 && home.size == 460 && a.size == 110 && small.size == 10
            && apps.size == 350 && app.size == 350 && a.children.allSatisfy { $0 !== deep }
        print("Tree removal: \(ok ? "ok" : "WRONG") (root \(root.size), a \(a.size), small \(small.size), app \(app.size))")
        return ok
    }

    static func run() {
        _ = treeTest()
        messengerSafetyTest()
        let scanner = Scanner()
        print("Prune self-test (read-only)\n")
        print("Project roots: " + scanner.projectRoots().map { Fmt.tilde($0.path) }.joined(separator: ", "))
        print("")

        report("projects (node_modules + build artifacts)") { scanner.scanProjects() }
        report("xcode") { scanner.scanXcode() }
        report("package caches") { scanner.scanPackageCaches() }
        report("app caches") { scanner.scanAppCaches() }
        report("messenger caches") { scanner.scanMessengerCaches() }
        report("logs") { scanner.scanLogs() }
        report("downloads") { scanner.scanDownloads() }
        report("iPhone backups") { scanner.scanIOSBackups() }
        report("unavailable simulators") { scanner.scanUnavailableSimulators() }

        let appsStart = Date()
        let apps = scanner.scanApps()
        let leftovers = apps.flatMap(\.leftovers)
        print(String(format: "%-42@ %3d apps  %10@  (%.1fs)  leftovers=%d (%@)", "apps" as NSString, apps.count,
                     Fmt.bytes(apps.reduce(0) { $0 + $1.item.size }) as NSString, Date().timeIntervalSince(appsStart),
                     leftovers.count, Fmt.bytes(leftovers.reduce(0) { $0 + $1.size }) as NSString))
        for a in apps.prefix(3) {
            print("    \(Fmt.bytes(a.totalSize))  \(a.item.name) [\(a.leftovers.count) leftovers] last used \(Fmt.relative(a.lastUsed))")
        }
        let badLeftovers = leftovers.filter { !Trasher.isSafe($0.url, leftover: true) }
        print("    leftovers refused by Trasher: \(badLeftovers.count)")

        let start = Date()
        let docker = scanner.scanDocker()
        print(String(format: "%-42@ status=%@ items=%d (%.1fs)", "docker" as NSString,
                     "\(docker.status)", docker.items.count, Date().timeIntervalSince(start)))
        for i in docker.items { print("    \(i.name): \(Fmt.bytes(i.size))  cmd: \(i.command?.dropFirst().joined(separator: " ") ?? "-")") }

        let lfStart = Date()
        let quickLarge = LargeFileScanner.scan(root: FileManager.default.homeDirectoryForCurrentUser, progress: ScanProgress())
        print(String(format: "%-42@ %3d files  %10@  (%.1fs)", "large files (quick scan)" as NSString, quickLarge.count,
                     Fmt.bytes(quickLarge.reduce(0) { $0 + $1.size }) as NSString, Date().timeIntervalSince(lfStart)))

        let servers = DevServerScanner.scan()
        print("dev servers: \(servers.filter(\.isLikelyDevServer).count) likely, \(servers.count) listening processes")
        for sv in servers.prefix(6) {
            print("    pid \(sv.pid) \(sv.processName) ports \(sv.ports) \(Fmt.bytes(sv.memoryBytes)) [\(sv.kind.rawValue)] dev=\(sv.isLikelyDevServer)")
        }
        print("volumes: " + Volume.all().map { "\($0.name) (\(Fmt.bytes($0.free)) free of \(Fmt.bytes($0.total)))" }.joined(separator: ", "))
        print("\nDisk map…")
        let mapStart = Date()
        let progress = ScanProgress()
        let result = DiskScanner(progress: progress).scan(diskUsed: DiskInfo.current().used)
        print(String(format: "  mapped %@ in %d files, %.1fs", Fmt.bytes(result.root.size), result.root.fileCount,
                     Date().timeIntervalSince(mapStart)))
        for c in result.root.children { print("    \(c.name): \(Fmt.bytes(c.size))") }
        let largeTotal = result.largeFiles.reduce(0) { $0 + $1.size }
        print("  large files: \(result.largeFiles.count), \(Fmt.bytes(largeTotal))")
        for f in result.largeFiles.prefix(5) { print("    \(Fmt.bytes(f.size))  \(f.location)/\(f.name)") }

        // Sanity: every item a scanner offers must pass the trash safety check (Docker items excepted).
        let all = scanner.scanProjects() + scanner.scanXcode() + scanner.scanPackageCaches()
            + scanner.scanAppCaches() + scanner.scanLogs() + result.largeFiles
        let unsafe = all.filter { $0.command == nil && !$0.checkFirst && !Trasher.isSafe($0.url) }
        print("\nSafety: \(all.count) file items checked, \(unsafe.count) would be refused by Trasher")
        for u in unsafe.prefix(5) { print("    refused: \(u.url.path)") }

        // Path rules: what may and may not go to the Trash.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cases: [(String, Bool)] = [
            ("\(home)/Library/Mobile Documents/com~apple~CloudDocs", false),
            ("\(home)/Library/Mail/V10", false),
            ("\(home)/Library/Containers/com.apple.Notes", false),
            ("\(home)/Library/Preferences/com.apple.finder.plist", false),
            ("\(home)/Library/Caches", false),
            ("\(home)/Library/Caches/com.google.Chrome", true),
            ("\(home)/Library/Developer/Xcode/DerivedData/App-abc", true),
            ("\(home)/Library/pnpm/store", true),
            ("\(home)/Documents", false),
            ("\(home)/Documents/dev/app/node_modules", true),
            ("\(home)/.npm/_cacache", true),
            ("/Applications/Some.app", true),
            ("/Applications/Utilities/Terminal.app", false),
            ("/System/Library", false),
            ("\(home)/Library/Application Support/MobileSync/Backup/00008-ABC", true),
            ("\(home)/Library/Application Support/Slack", false), // only allowed as an uninstall leftover
        ]
        var bad = 0
        for (path, expected) in cases where Trasher.isSafe(URL(fileURLWithPath: path)) != expected {
            bad += 1
            print("    WRONG: \(Fmt.tilde(path)) expected \(expected ? "allowed" : "refused")")
        }
        print("Path rules: \(cases.count - bad)/\(cases.count) correct")
    }

    /// Messenger caches may be trashed; their databases, account keys and settings never may.
    private static func messengerSafetyTest() {
        let tg = FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/appstore/"
        let mustAllow = [tg + "account-1/postbox/media", tg + "account-1/postbox/media/", tg + "trlottie-animations"]
        let mustRefuse = [tg + "account-1/postbox/db", tg + "account-1/postbox", tg + "accounts-metadata",
                          tg + ".tempkeyEncrypted", tg + "account-1/postbox/media/../db", tg + "account-1/postbox/mediaX"]
        let allowed = mustAllow.allSatisfy { Trasher.isSafe(URL(fileURLWithPath: $0)) }
        let refused = mustRefuse.allSatisfy { !Trasher.isSafe(URL(fileURLWithPath: $0)) }
        print("Messenger cache safety: \(allowed && refused ? "ok" : "WRONG") (allowed \(allowed), refused \(refused))\n")
    }

    private static func report(_ name: String, _ scan: () -> [CleanItem]) {
        let start = Date()
        let items = scan()
        let total = items.reduce(0) { $0 + $1.size }
        let byCat = Dictionary(grouping: items, by: \.category).map { "\($0.key.rawValue)=\($0.value.count)" }.sorted()
        print(String(format: "%-42@ %3d items  %10@  (%.1fs)  %@", name as NSString, items.count,
                     Fmt.bytes(total) as NSString, Date().timeIntervalSince(start), byCat.joined(separator: " ") as NSString))
        for i in items.sorted(by: { $0.size > $1.size }).prefix(3) {
            print("    \(Fmt.bytes(i.size))  \(i.name) [\(i.kind)]\(i.isStale ? " stale" : "")")
        }
    }
}
