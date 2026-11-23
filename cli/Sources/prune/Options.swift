import Foundation

/// Command-line options shared by every subcommand.
struct Options {
    var command = ""
    var names: [String] = []        // category names and app names
    var roots: [URL] = []           // --root DIR
    var yes = false                 // actually remove (otherwise dry run)
    var all = false                 // include items that are not pre-selected
    var stale = false               // purge: only folders not touched recently
    var list = false                // scan: print every item
    var photos = false              // duplicates: similar photos too
    var keep = KeepRule.largest     // duplicates: which copy stays
    var json = false                // history: JSON output
    var top = 15
    var limit = 20
    var path: String? = nil         // analyze: folder to look in
    var help = false
    var version = false

    static let commands = ["scan", "clean", "purge", "analyze", "duplicates", "uninstall", "status", "history", "optimize",
                           "login-items", "security", "servers", "ignore"]

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        var i = 0
        func value(_ flag: String) -> String {
            i += 1
            guard i < args.count else { fail("\(flag) needs a value") }
            return args[i]
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "-h", "--help", "help": o.help = true
            case "--version", "-V": o.version = true
            case "--yes", "-y": o.yes = true
            case "--dry-run": o.yes = false
            case "--all": o.all = true
            case "--stale": o.stale = true
            case "--list", "-l": o.list = true
            case "--photos": o.photos = true
            case "--keep":
                let v = value(a)
                guard let rule = KeepRule(rawValue: v) else { fail("--keep takes newest, oldest or largest") }
                o.keep = rule
            case "--json": o.json = true
            case "--root": o.roots.append(URL(fileURLWithPath: (value(a) as NSString).expandingTildeInPath))
            case "--top": o.top = Int(value(a)) ?? 15
            case "--limit": o.limit = Int(value(a)) ?? 20
            case "--path": o.path = value(a)
            default:
                if a.hasPrefix("-") { fail("unknown option \(a). Run prune --help.") }
                if o.command.isEmpty { o.command = a } else { o.names.append(a) }
            }
            i += 1
        }
        return o
    }
}

/// Category groups as named on the command line (`prune clean caches logs`).
enum Groups {
    static let table: [(name: String, cats: [CategoryID], about: String)] = [
        ("projects", [.nodeModules, .buildArtifacts], "node_modules and build folders in your projects"),
        ("xcode", [.xcode], "DerivedData, device support, archives, simulator caches"),
        ("docker", [.docker], "unused images, build cache (containers and volumes are kept)"),
        ("packages", [.packageCaches], "npm, pnpm, Yarn, pip, Homebrew, Cargo, Gradle and more"),
        ("caches", [.appCaches], "caches apps rebuild on their own"),
        ("messengers", [.messengerCaches], "photos and files kept by messengers"),
        ("logs", [.logs], "old logs in ~/Library/Logs"),
        ("downloads", [.downloads], "installers and old files in Downloads"),
        ("backups", [.iosBackups], "local iPhone and iPad backups"),
        ("mail", [.mailAttachments], "attachments Mail saved to disk"),
        ("system", [.systemData], "Time Machine snapshots and Group Container caches; VM disks and logs shown with size only"),
    ]

    static func resolve(_ names: [String], default fallback: [CategoryID]) -> Set<CategoryID> {
        guard !names.isEmpty else { return Set(fallback) }
        var cats = Set<CategoryID>()
        for n in names {
            guard let g = table.first(where: { $0.name == n.lowercased() }) else {
                fail("unknown group '\(n)'. Groups: " + table.map(\.name).joined(separator: ", "))
            }
            cats.formUnion(g.cats)
        }
        return cats
    }

    static func name(of c: CategoryID) -> String {
        table.first { $0.cats.contains(c) }?.name ?? c.title
    }
}
