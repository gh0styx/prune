import Foundation

// prune — terminal companion to Prune.app. Uses the same scanners and Trash rules as the app.
// Nothing is removed without --yes, and removal always goes to the Trash (recoverable until you empty it).

let cliVersion = "0.1.1"

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

/// Raw keyboard input for the menu. Commands themselves always run in normal (cooked) mode.
enum Keys {
    enum Key { case up, down, enter, quit, interrupt, char(Character), other }

    /// Runs `body` with single keypresses (no echo, no line buffering). Nil when stdin is not a terminal.
    static func rawMode<T>(_ body: () -> T) -> T? {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }
        var raw = original
        raw.c_lflag &= ~(tcflag_t(ICANON) | tcflag_t(ECHO) | tcflag_t(ISIG))
        withUnsafeMutablePointer(to: &raw.c_cc) { tuple in
            tuple.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
                cc[Int(VMIN)] = 1
                cc[Int(VTIME)] = 0
            }
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        defer { tcsetattr(STDIN_FILENO, TCSAFLUSH, &original) }
        return body()
    }

    static func read() -> Key {
        var byte: UInt8 = 0
        guard Darwin.read(STDIN_FILENO, &byte, 1) == 1 else { return .quit }
        switch byte {
        case 3: return .interrupt               // Ctrl-C
        case 10, 13: return .enter
        case 27:                                 // arrow keys arrive as ESC [ A / ESC [ B
            var seq = [UInt8](repeating: 0, count: 2)
            guard Darwin.read(STDIN_FILENO, &seq[0], 1) == 1, seq[0] == 91,
                  Darwin.read(STDIN_FILENO, &seq[1], 1) == 1 else { return .quit }
            switch seq[1] {
            case 65: return .up
            case 66: return .down
            default: return .other
            }
        default:
            return .char(Character(UnicodeScalar(byte)))
        }
    }
}

/// Logo with the URL and slogan beside it, shown at the top of the menu.
enum Banner {
    static let logo = [
        "██████╗ ██████╗ ██╗   ██╗███╗   ██╗███████╗",
        "██╔══██╗██╔══██╗██║   ██║████╗  ██║██╔════╝",
        "██████╔╝██████╔╝██║   ██║██╔██╗ ██║█████╗  ",
        "██╔═══╝ ██╔══██╗██║   ██║██║╚██╗██║██╔══╝  ",
        "██║     ██║  ██║╚██████╔╝██║ ╚████║███████╗",
        "╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝",
    ]
    static let shades = ["96", "96", "36", "36", "34", "34"]
    static let side = [
        "",
        Style.bold("prune") + Style.dim("  ") + Style.cyan("prune.gh0styx.com"),
        Style.dim("v\(cliVersion)"),
        "Find the space you can free,",
        "then free it safely.",
        "",
    ]

    static func show() {
        if Style.enabled { print("\u{1B}[2J\u{1B}[H", terminator: "") }
        say("")
        for i in logo.indices {
            say("  " + Style.paint(logo[i], shades[i]) + "   " + side[i])
        }
        say("")
    }
}

/// The interactive menu. Arrow keys and digits pick an entry, M shows the rest, Q quits.
enum Menu {
    struct Entry {
        let label: String
        let about: String
        let command: String
        let destructive: Bool
        let inMain: Bool
    }

    static let entries: [Entry] = [
        Entry(label: "Scan", about: "see what can be reclaimed", command: "scan", destructive: false, inMain: true),
        Entry(label: "Clean", about: "move caches and logs to the Trash", command: "clean", destructive: true, inMain: true),
        Entry(label: "Purge", about: "node_modules and build folders", command: "purge", destructive: true, inMain: true),
        Entry(label: "Analyze", about: "biggest folders and large files", command: "analyze", destructive: false, inMain: true),
        Entry(label: "Uninstall", about: "an app with its leftovers", command: "uninstall", destructive: true, inMain: true),
        Entry(label: "Status", about: "disk, memory, load, uptime", command: "status", destructive: false, inMain: false),
        Entry(label: "History", about: "what was moved to the Trash", command: "history", destructive: false, inMain: false),
        Entry(label: "Duplicates", about: "identical files", command: "duplicates", destructive: true, inMain: false),
        Entry(label: "Optimize", about: "DNS, Spotlight and other maintenance", command: "optimize", destructive: true, inMain: false),
    ]

    enum Choice { case run(Entry), version, more, quit }

    static func run() {
        var showMore = false
        var selected = 0
        while true {
            let visible = showMore ? entries : entries.filter(\.inMain)
            selected = min(selected, visible.count - 1)
            // Raw keys when the terminal allows it, otherwise typed numbers.
            let choice: Choice? = Keys.rawMode {
                selectLoop(visible: visible, showMore: showMore, selected: &selected)
            } ?? numberedChoice(visible)
            switch choice {
            case .quit:
                return
            case .more:
                showMore.toggle()
            case .version:
                say("prune \(cliVersion)")
                pause()
            case .run(let entry):
                execute(entry)
                pause()
            case .none:
                continue
            }
        }
    }

    /// Draws the list and handles keys until the user picks something. Runs in raw mode.
    static func selectLoop(visible: [Entry], showMore: Bool, selected: inout Int) -> Choice {
        while true {
            draw(visible, showMore: showMore, selected: selected)
            switch Keys.read() {
            case .up: selected = max(0, selected - 1)
            case .down: selected = min(visible.count - 1, selected + 1)
            case .enter: return .run(visible[selected])
            case .quit, .interrupt: return .quit
            case .char(let c):
                let key = String(c).lowercased()
                if let n = Int(key), n >= 1, n <= visible.count { return .run(visible[n - 1]) }
                if key == "q" { return .quit }
                if key == "v" { return .version }
                if key == "m" { return .more }
            case .other: break
            }
        }
    }

    static func draw(_ visible: [Entry], showMore: Bool, selected: Int) {
        Banner.show()
        let width = visible.map { $0.label.count }.max() ?? 10
        for (i, e) in visible.enumerated() {
            let isSel = i == selected
            let marker = isSel ? Style.cyan("➤") : " "
            let label = isSel ? Style.bold(column(e.label, width + 2)) : column(e.label, width + 2)
            let warn = e.destructive ? Style.yellow(" ▲") : ""
            say("   " + marker + " " + label + Style.dim(e.about) + warn)
        }
        say("")
        say("  " + Style.dim("↑↓ move  |  Enter run  |  1–\(visible.count) pick  |  M \(showMore ? "less" : "more")  |  V version  |  Q quit"))
        say("  " + Style.yellow("▲") + Style.dim(" these ask before moving anything to the Trash"))
    }

    /// Plain numbered menu, used when raw mode is unavailable.
    static func numberedChoice(_ visible: [Entry]) -> Choice? {
        Banner.show()
        for (i, e) in visible.enumerated() {
            say("  " + Style.cyan("\(i + 1)") + ". " + column(e.label, 12) + Style.dim(e.about))
        }
        say("  " + Style.dim("M more · V version · Q quit"))
        guard let line = prompt("  › ")?.lowercased(), !line.isEmpty else { return .quit }
        if ["q", "quit", "exit"].contains(line) { return .quit }
        if line == "v" { return .version }
        if line == "m" { return .more }
        guard let n = Int(line), n >= 1, n <= visible.count else { return nil }
        return .run(visible[n - 1])
    }

    /// Runs a menu entry: destructive ones show the plan first and ask before moving anything.
    static func execute(_ entry: Entry) {
        var o = Options()
        o.command = entry.command
        if entry.command == "analyze" {
            if let p = prompt("  Folder (Enter for your home): "), !p.isEmpty { o.path = p }
        }
        say("")
        _ = dispatch(o)
        if entry.destructive, confirm("\n  Move these to the Trash now?") {
            o.yes = true
            _ = dispatch(o)
        }
    }

    /// Waits for Enter so the output stays on screen before the menu redraws.
    static func pause() {
        guard isatty(STDIN_FILENO) != 0 else { return }
        print("\n  " + Style.dim("Press Enter to return to the menu…"), terminator: "")
        fflush(stdout)
        _ = readLine()
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
