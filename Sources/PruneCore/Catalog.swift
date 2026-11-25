import Foundation

/// The scan jobs shared by Prune.app and the prune CLI: which scanner fills which categories.
/// Keeping the table here means both front ends find the same things.
enum Catalog {
    /// Categories one scanner call fills, and the call itself.
    typealias Job = ([CategoryID], @Sendable () -> [CleanItem])

    /// Scans that return plain items. Docker is separate (it also reports whether it is running).
    static func jobs(scanner: Scanner) -> [Job] {
        [
            ([.nodeModules, .buildArtifacts], { scanner.scanProjects() }),
            ([.xcode], { scanner.scanXcode() + scanner.scanUnavailableSimulators() }),
            ([.downloads], { scanner.scanDownloads() }),
            ([.iosBackups], { scanner.scanIOSBackups() }),
            ([.mailAttachments], { scanner.scanMailAttachments() }),
            ([.systemData], { SystemData.scan() }),
            ([.packageCaches], { scanner.scanPackageCaches() }),
            ([.appCaches], { scanner.scanAppCaches() }),
            ([.messengerCaches], { scanner.scanMessengerCaches() }),
            ([.logs], { scanner.scanLogs() }),
        ]
    }

    /// Hidden paths from Settings, and the safety rules every removal goes through.
    static func keep(_ items: [CleanItem]) -> [CleanItem] {
        items.filter { ($0.command != nil || $0.reportOnly || $0.checkFirst || Trasher.isSafe($0.url)) && !isIgnored($0) }
            .sorted { $0.size > $1.size }
    }

    static func isIgnored(_ item: CleanItem) -> Bool {
        IgnoreList.contains(item.url)
    }

    /// Runs the jobs for the given categories (in parallel) and returns the kept items per category.
    static func scan(_ categories: Set<CategoryID>, scanner: Scanner = Scanner()) -> [CategoryID: [CleanItem]] {
        var result: [CategoryID: [CleanItem]] = [:]
        let lock = NSLock()
        let selected = jobs(scanner: scanner).filter { cats, _ in cats.contains { categories.contains($0) } }
        DispatchQueue.concurrentPerform(iterations: selected.count) { i in
            let (cats, run) = selected[i]
            let items = keep(run())
            lock.lock()
            for c in cats where categories.contains(c) {
                result[c] = items.filter { $0.category == c }
            }
            lock.unlock()
        }
        if categories.contains(.docker) {
            let docker = scanner.scanDocker()
            result[.docker] = keep(docker.items)
        }
        return result
    }
}
