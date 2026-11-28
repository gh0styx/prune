import Foundation
import Darwin

/// The subcommands. Anything that removes files goes to the Trash, and only with --yes.
enum Commands {
    static func scanner(_ o: Options) -> Scanner {
        var s = Scanner()
        s.projectRootOverride = o.roots.isEmpty ? nil : o.roots
        return s
    }

    // MARK: scan

    static func scan(_ o: Options) {
        let cats = Groups.resolve(o.names, default: CategoryID.junk)
        note("Scanning…")
        let found = Catalog.scan(cats, scanner: scanner(o))
        var total: Int64 = 0
        say(Style.bold("Reclaimable space"))
        for g in Groups.table where g.cats.contains(where: { cats.contains($0) }) {
            let items = g.cats.flatMap { found[$0] ?? [] }.filter { !$0.reportOnly }
            guard !items.isEmpty else { continue }
            let sum = items.reduce(Int64(0)) { $0 + $1.size }
            total += sum
            let stale = items.filter(\.isStale).count
            var line = "  " + column(g.name, 12) + rightColumn(bytes(sum), 10) + "  "
            line += Style.dim("\(items.count) items" + (stale > 0 ? ", \(stale) not used recently" : ""))
            say(line)
            if o.list {
                for it in items.prefix(300) {
                    say("      " + rightColumn(bytes(it.size), 10) + "  " + it.name + "  " + Style.dim(it.location))
                }
            }
        }
        let reported = cats.flatMap { found[$0] ?? [] }.filter(\.reportOnly).sorted { $0.size > $1.size }
        if !reported.isEmpty {
            say("\n" + Style.bold("Report only") + Style.dim(" (Prune never removes these; the owner does)"))
            for it in reported {
                say("      " + rightColumn(bytes(it.size), 10) + "  " + it.name + "  " + Style.dim(it.location))
            }
        }
        if total == 0 {
            say("Nothing to reclaim.")
        } else {
            say("\nTotal " + Style.bold(bytes(total)) + ". Run " + Style.cyan("prune clean") + " to move junk to the Trash.")
        }
    }

    // MARK: clean / purge

    static func clean(_ o: Options) -> Int32 {
        let cats = Groups.resolve(o.names, default: CategoryID.junk)
        note("Scanning…")
        let found = Catalog.scan(cats, scanner: scanner(o))
        var plan: [CleanItem] = []
        for c in CategoryID.allCases where cats.contains(c) {
            let items = found[c] ?? []
            // Without --all only what Prune pre-selects: caches and stale project folders, never Docker volumes.
            plan += (o.all ? items : items.filter { c.selectedByDefault($0) }).filter { !$0.reportOnly }
        }
        return execute(plan, o)
    }

    static func purge(_ o: Options) -> Int32 {
        note("Looking for project folders…")
        let found = Catalog.scan([.nodeModules, .buildArtifacts], scanner: scanner(o))
        var plan = (found[.nodeModules] ?? []) + (found[.buildArtifacts] ?? [])
        if o.stale { plan = plan.filter(\.isStale) }
        plan.sort { $0.size > $1.size }
        if plan.isEmpty {
            say("No node_modules or build folders found. Use --root DIR to point at your projects.")
            return 0
        }
        return execute(plan, o)
    }

    // MARK: removal

    /// Prints the plan, then moves the items to the Trash when --yes was given.
    static func execute(_ plan: [CleanItem], _ o: Options) -> Int32 {
        guard !plan.isEmpty else {
            say("Nothing to remove.")
            return 0
        }
        printPlan(plan)
        let total = plan.reduce(Int64(0)) { $0 + $1.size }
        guard o.yes else {
            say("\nDry run: nothing was removed. Would free " + Style.bold(bytes(total)) + ".")
            say("Re-run with " + Style.cyan("--yes") + " to move these to the Trash.")
            return 0
        }
        let result = Trasher.trash(plan)
        if !result.entry.items.isEmpty {
            var history = HistoryFile.load()
            history.insert(result.entry, at: 0)
            HistoryFile.save(history)
        }
        let failed = plan.count - result.trashed.count
        say("\n" + Style.green("Moved to Trash: ") + bytes(result.freed) + (failed > 0 ? Style.yellow("  skipped \(failed)") : ""))
        say(Style.dim("Empty the Trash to free the space. `prune history` lists what was moved."))
        for f in result.failures {
            say(Style.yellow("Not removed: ") + f.name + " — " + f.reason)
            if let hint = f.hint { say(Style.dim("  " + hint)) }
        }
        return failed > 0 ? 1 : 0
    }

    static func printPlan(_ plan: [CleanItem]) {
        let limit = 300
        for it in plan.prefix(limit) {
            // Show the kind only when it says something the location does not.
            let kind = it.kind == it.location ? "" : it.kind + "  "
            say("  " + rightColumn(bytes(it.size), 10) + "  " + column(it.name, 34) + Style.dim(kind + it.location))
        }
        if plan.count > limit { say(Style.dim("  … and \(plan.count - limit) more")) }
    }

    // MARK: analyze

    static func analyze(_ o: Options) {
        // The folder can be given as `--path DIR` or as a plain argument: `prune analyze ~/Downloads`.
        if o.path != nil, !o.names.isEmpty { fail("give the folder once: either --path DIR or a plain PATH") }
        if o.names.count > 1 { fail("analyze takes one folder, got \(o.names.count): \(o.names.joined(separator: " "))") }
        let raw = (o.path ?? o.names.first ?? "~") as NSString
        let root = URL(fileURLWithPath: raw.expandingTildeInPath).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            fail("not a folder: \(root.path)")
        }
        note("Measuring \(Fmt.tilde(root.path)). This can take a while on big folders…")
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles])) ?? []
        var sizes: [(URL, Int64)] = children.map { ($0, Sizer.size(of: $0)) }
        sizes.sort { $0.1 > $1.1 }
        let total = sizes.reduce(Int64(0)) { $0 + $1.1 }

        say(Style.bold("Folders in \(Fmt.tilde(root.path))") + Style.dim("  (total \(bytes(total)))"))
        for (url, size) in sizes.prefix(o.top) where size > 0 {
            let share = total > 0 ? Double(size) / Double(total) : 0
            say("  " + rightColumn(bytes(size), 10) + "  " + bar(share, width: 16) + "  " + column(url.lastPathComponent, 30)
                + Style.dim(String(format: "%3.0f%%", share * 100)))
        }

        note("Looking for large files…")
        let large = LargeFileScanner.scan(root: root, progress: ScanProgress()).sorted { $0.size > $1.size }
        say("")
        say(Style.bold("Large files (over \(Prefs.largeFileMB) MB)"))
        if large.isEmpty { say("  None.") }
        for it in large.prefix(o.top) {
            say("  " + rightColumn(bytes(it.size), 10) + "  " + Style.dim(it.location + "/") + it.name)
        }
    }

    // MARK: duplicates

    static func duplicates(_ o: Options) -> Int32 {
        note(o.photos ? "Comparing photos. This is slow on big libraries…" : "Hashing files of 1 MB and up…")
        let progress = DupProgress()
        let folders = o.roots.isEmpty ? nil : o.roots
        let groups = o.photos ? DuplicateFinder.similarPhotos(progress: progress, in: folders)
                              : DuplicateFinder.identical(progress: progress, in: folders)
        let sorted = groups.sorted { $0.wasted > $1.wasted }
        guard !sorted.isEmpty else {
            say("No duplicates found.")
            return 0
        }
        let total = sorted.reduce(Int64(0)) { $0 + $1.wasted }
        say(Style.bold("Duplicates: \(sorted.count) groups, \(bytes(total)) could be freed"))
        if !o.photos {
            say(Style.yellow("Identical copies are sometimes needed on purpose. A project may expect its own copy, so check each path before --yes."))
        }
        for g in sorted.prefix(o.top) {
            say(Style.bold(bytes(g.wasted)) + Style.dim("  \(g.files.count) copies, keeping the \(o.keep.rawValue)"))
            let keeper = o.keep.keeper(in: g.files)?.url
            for f in g.files.sorted(by: { $0.size > $1.size }) {
                let tag = f.url == keeper ? Style.green("keep ") : Style.yellow("trash")
                say("    " + tag + "  " + Style.dim(f.location + "/") + f.name)
            }
        }
        // Move every copy that the keep rule does not pick.
        let plan: [CleanItem] = sorted.flatMap { g -> [CleanItem] in
            g.trashed(keeping: o.keep).map { f in
                CleanItem(url: f.url, category: .duplicates, name: f.name, kind: "duplicate",
                          location: f.location, size: f.size, lastActivity: f.modified, isStale: false)
            }
        }
        return execute(plan, o)
    }

    // MARK: uninstall

    static func uninstall(_ o: Options) -> Int32 {
        note("Reading installed apps…")
        let apps = Scanner().scanApps().sorted { $0.totalSize > $1.totalSize }
        if o.names.isEmpty {
            say(Style.bold("Apps, largest first") + Style.dim("  (remove one with prune uninstall <name> [--yes])"))
            for a in apps.prefix(o.limit) {
                say("  " + rightColumn(bytes(a.totalSize), 10) + "  " + column(a.item.name, 30)
                    + Style.dim("app \(bytes(a.item.size)), leftovers \(bytes(a.leftoverSize)) in \(a.leftovers.count) places"))
            }
            return 0
        }
        let query = o.names.joined(separator: " ").lowercased()
        let matches = apps.filter { $0.item.name.lowercased().contains(query) }
        guard !matches.isEmpty else { fail("no installed app matches '\(query)'") }
        let app: AppInfo
        if let exact = matches.first(where: { $0.item.name.lowercased() == query }) {
            app = exact
        } else if matches.count == 1 {
            app = matches[0]
        } else {
            say("Several apps match. Be more specific:")
            for m in matches.prefix(20) { say("  " + m.item.name) }
            return 1
        }
        say(Style.bold(app.item.name) + "  " + Style.dim(app.bundleID))
        var plan = [app.item] + app.leftovers
        for l in app.leftovers.prefix(40) {
            say("  " + rightColumn(bytes(l.size), 10) + "  " + column(l.kind, 24) + Style.dim(l.location))
        }
        plan = plan.sorted { $0.size > $1.size }
        return execute(plan, o)
    }

    // MARK: status

    static func status() {
        let disk = DiskInfo.current()
        let mem = memory()
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        let memFraction = mem.total > 0 ? Double(mem.used) / Double(mem.total) : 0
        say(column(Style.bold("Disk"), 10) + bar(disk.usedFraction) + "  " + bytes(disk.used) + " of " + bytes(disk.total)
            + Style.dim(", " + bytes(disk.free) + " free"))
        say(column(Style.bold("Memory"), 10) + bar(memFraction) + "  " + bytes(mem.used) + " of " + bytes(mem.total))
        say(column(Style.bold("Load"), 10) + loads.map { String(format: "%.2f", $0) }.joined(separator: "  ")
            + Style.dim("  (1, 5, 15 min)"))
        say(column(Style.bold("Uptime"), 10) + uptimeText(ProcessInfo.processInfo.systemUptime))
    }

    static func memory() -> (used: Int64, total: Int64) {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = Int64(vm_kernel_page_size)
        let used = (Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        return (used, total)
    }

    static func uptimeText(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        return d > 0 ? "\(d)d \(h)h \(m)m" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: history

    static func history(_ o: Options) {
        let entries = Array(HistoryFile.load().prefix(o.limit))
        if o.json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = (try? encoder.encode(entries)) ?? Data("[]".utf8)
            FileHandle.standardOutput.write(data)
            say("")
            return
        }
        guard !entries.isEmpty else {
            say("No cleaning history yet.")
            return
        }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        for e in entries {
            let inTrash = e.inTrash.count
            say(column(df.string(from: e.date), 22) + rightColumn(bytes(e.total), 10) + "  "
                + Style.dim("\(e.items.count) items" + (inTrash > 0 ? ", \(inTrash) still in Trash" : "")))
        }
    }

    // MARK: optimize

    static func optimize(_ o: Options) -> Int32 {
        let tasks = MaintenanceTask.all.filter(\.isAvailable)
        for t in tasks {
            say(column(t.title, 32) + Style.dim(t.detail) + (t.needsAdmin ? Style.yellow("  (asks for your password)") : ""))
        }
        guard o.yes else {
            say("\nDry run: nothing ran. Re-run with " + Style.cyan("--yes") + " to run them all.")
            return 0
        }
        var failed = 0
        for t in tasks {
            switch MaintenanceRunner.execute(t) {
            case .done:
                MaintenanceRunner.markRun(t.id)
                say(Style.green("done     ") + t.title)
            case .cancelled:
                say(Style.yellow("skipped  ") + t.title)
            case .failed(let why):
                failed += 1
                say(Style.red("failed   ") + t.title + Style.dim(" — " + why))
            }
        }
        return failed == 0 ? 0 : 1
    }
}
