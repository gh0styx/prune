import Foundation

/// `prune ignore` lists the folders Prune leaves alone. `add` and `remove` change the list that Prune.app shares.
enum IgnoreCommand {
    static func run(_ o: Options) -> Int32 {
        switch o.names.first?.lowercased() {
        case nil, "list":
            say(Style.bold("Ignored folders") + Style.dim("  (add: prune ignore add <path>)"))
            if IgnoreList.paths.isEmpty { say("  None.") }
            for path in IgnoreList.paths { say("  " + Fmt.tilde(path)) }
            return 0
        case "add":
            let raw = o.names.dropFirst().joined(separator: " ")
            guard !raw.isEmpty else { fail("name a folder, e.g. prune ignore add ~/Projects/keep") }
            let url = URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
            IgnoreList.add(url)
            say("Ignored " + Fmt.tilde(url.standardizedFileURL.path))
            return 0
        case "remove":
            let raw = o.names.dropFirst().joined(separator: " ")
            guard !raw.isEmpty else { fail("name a folder, e.g. prune ignore remove ~/Projects/keep") }
            let path = URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath).standardizedFileURL.path
            guard IgnoreList.paths.contains(path) else { fail("\(Fmt.tilde(path)) is not in the ignore list") }
            IgnoreList.remove(path)
            say("No longer ignored: " + Fmt.tilde(path))
            return 0
        default:
            fail("use: prune ignore [list|add <path>|remove <path>]")
        }
    }
}
