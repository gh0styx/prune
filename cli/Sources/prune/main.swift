import Foundation

// prune — terminal companion to Prune.app. Uses the same scanners and Trash rules as the app.
// Nothing is removed without --yes, and removal always goes to the Trash (recoverable until you empty it).

let cliVersion = "0.1.0"

enum Help {
    static func print() {
        say(Style.bold("prune \(cliVersion)") + " — find and clean reclaimable space on macOS")
        say("""

        \(Style.bold("Usage"))
          prune                           interactive menu
          prune <command> [groups] [options]

        \(Style.bold("Commands"))
          scan       show what can be reclaimed (changes nothing)
          clean      move junk caches and logs to the Trash
          purge      move node_modules and build folders from your projects to the Trash
          analyze    biggest folders and large files, with [PATH] (default: your home)
          duplicates find identical files (and similar photos with --photos)
          uninstall  list apps by size, or remove one with its leftovers: uninstall <name>
          status     disk, memory, load and uptime
          history    what was moved to the Trash, most recent first (--json for scripts)
          optimize   flush DNS, rebuild Spotlight and other maintenance (--yes to run)

        \(Style.bold("Groups"))  (for scan and clean; default: all junk)
        """)
        for g in Groups.table {
            say("  " + column(g.name, 12) + Style.dim(g.about))
        }
        say("""

        \(Style.bold("Options"))
          --yes, -y      actually remove (otherwise a dry run that only shows the plan)
          --all          also include items that are not pre-selected (clean)
          --stale        only project folders not touched recently (purge)
          --root DIR     project folder to search (repeatable; default: Developer, Projects, dev, …)
          --list, -l     list every item (scan)
          --photos       similar photos instead of identical files (duplicates; slow)
          --path DIR     folder to analyze (analyze)
          --top N        rows to show (default 15)
          --limit N      entries to show (default 20)
          --json         JSON output (history)
          --version, -V  print the version
          --help, -h     this help

        \(Style.bold("Examples"))
          prune scan                      what you could free right now
          prune clean caches logs --yes   clear caches and logs
          prune purge --stale --yes       remove project folders you have not touched in 90 days
          prune uninstall Figma --yes     remove an app and its leftovers
          prune analyze ~/Downloads       where your space went

        Set NO_COLOR=1 to turn off colors. Removed items stay in the Trash until you empty it.
        """)
    }
}

/// Interactive menu, used when prune runs with no arguments in a terminal.
enum Menu {
    static func run() {
        let entries: [(label: String, command: String, destructive: Bool)] = [
            ("Scan: what can be reclaimed", "scan", false),
            ("Clean junk (caches, logs)", "clean", true),
            ("Purge project folders (node_modules, builds)", "purge", true),
            ("Analyze a folder", "analyze", false),
            ("Find duplicates", "duplicates", true),
            ("Uninstall an app", "uninstall", true),
            ("System status", "status", false),
            ("History of moves", "history", false),
            ("Optimize (maintenance)", "optimize", true),
        ]
        while true {
            say("")
            say(Style.bold("prune") + Style.dim(" — pick an action"))
            for (i, e) in entries.enumerated() {
                say("  " + Style.cyan("\(i + 1)") + ". " + e.label)
            }
            say("  " + Style.cyan("q") + ". quit")
            guard let choice = prompt("> "), !choice.isEmpty else { return }
            if ["q", "quit", "exit"].contains(choice.lowercased()) { return }
            guard let n = Int(choice), n >= 1, n <= entries.count else {
                say("Pick a number from the list, or q.")
                continue
            }
            let entry = entries[n - 1]
            var o = Options()
            o.command = entry.command
            if entry.command == "analyze" {
                if let p = prompt("Folder (Enter for your home): "), !p.isEmpty { o.path = p }
            }
            if entry.destructive {
                // Show the plan first (dry run), then ask before anything is moved.
                _ = dispatch(o)
                if confirm("\nMove these to the Trash now?") { o.yes = true; _ = dispatch(o) }
            } else {
                _ = dispatch(o)
            }
        }
    }

    /// Runs one command and returns its exit code. Never exits, so the menu keeps going after it.
    static func dispatch(_ o: Options) -> Int32 {
        switch o.command {
        case "scan": Commands.scan(o); return 0
        case "clean": return Commands.clean(o)
        case "purge": return Commands.purge(o)
        case "analyze": Commands.analyze(o); return 0
        case "duplicates": return Commands.duplicates(o)
        case "uninstall": return Commands.uninstall(o)
        case "status": Commands.status(); return 0
        case "history": Commands.history(o); return 0
        case "optimize": return Commands.optimize(o)
        default: return 2
        }
    }
}

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))

if options.version {
    say("prune \(cliVersion)")
    exit(0)
}
if options.help {
    Help.print()
    exit(0)
}
if options.command.isEmpty {
    if isatty(STDIN_FILENO) != 0 {
        Menu.run()
    } else {
        Help.print()
    }
    exit(0)
}
guard Options.commands.contains(options.command) else {
    fail("unknown command '\(options.command)'. Run prune --help.", code: 2)
}
exit(Menu.dispatch(options))
