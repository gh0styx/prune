import Foundation

/// A small macOS upkeep task. Admin tasks go through osascript so macOS shows its own password dialog.
struct MaintenanceTask: Identifiable, Sendable {
    enum Run: Sendable {
        /// Shell snippet run with administrator privileges.
        case admin(String)
        /// Plain commands run as the current user, in order.
        case user([[String]])
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let run: Run
    var note: String? = nil
    /// Binary that must exist for the task to be offered.
    var requires: String? = nil

    var needsAdmin: Bool { if case .admin = run { return true }; return false }
    var isAvailable: Bool { requires.map { FileManager.default.isExecutableFile(atPath: $0) } ?? true }

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static let all: [MaintenanceTask] = [
        .init(id: "dns", title: "Flush DNS cache",
              detail: "Fixes sites that won't load after a network or hosts change.",
              symbol: "network",
              run: .admin("dscacheutil -flushcache; killall -HUP mDNSResponder")),
        .init(id: "spotlight", title: "Reindex Spotlight",
              detail: "Rebuilds the search index. Search may be slow for a while.",
              symbol: "magnifyingglass",
              run: .admin("mdutil -E /")),
        .init(id: "periodic", title: "Run maintenance scripts",
              detail: "Runs the daily, weekly and monthly system housekeeping scripts.",
              symbol: "calendar.badge.clock",
              run: .admin("periodic daily weekly monthly"),
              requires: "/usr/sbin/periodic"),
        .init(id: "launchservices", title: "Rebuild Launch Services",
              detail: "Fixes duplicate entries in the “Open With” menu.",
              symbol: "square.stack.3d.up",
              run: .user([[lsregister, "-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"]]),
              note: "Finder may relaunch and the menu rebuilds over a few minutes.",
              requires: lsregister),
        .init(id: "quicklook", title: "Reset Quick Look cache",
              detail: "Fixes missing or stale previews when you press Space.",
              symbol: "eye",
              run: .user([["/usr/bin/qlmanage", "-r", "cache"], ["/usr/bin/qlmanage", "-r"]])),
        .init(id: "fonts", title: "Clear font caches",
              detail: "Fixes garbled text and fonts that don't show up.",
              symbol: "textformat",
              run: .user([["/usr/bin/atsutil", "databases", "-removeUser"]]),
              note: "Log out and back in to finish."),
        .init(id: "ram", title: "Free inactive memory",
              detail: "Releases memory macOS is holding in its disk cache.",
              symbol: "memorychip",
              run: .admin("purge")),
    ]
}

enum MaintenanceOutcome: Sendable, Equatable {
    case done
    case cancelled
    case failed(String)
}

enum MaintenanceRunner {
    static func lastRun(_ id: String) -> Date? {
        UserDefaults.standard.object(forKey: "maintenance.lastRun." + id) as? Date
    }

    static func markRun(_ id: String) {
        UserDefaults.standard.set(Date(), forKey: "maintenance.lastRun." + id)
    }

    static func execute(_ task: MaintenanceTask) -> MaintenanceOutcome {
        switch task.run {
        case .admin(let command):
            // Escape for an AppleScript string literal.
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let r = exec("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
            if r.status == 0 { return .done }
            if r.err.contains("-128") || r.err.localizedCaseInsensitiveContains("User canceled") { return .cancelled }
            return .failed(clean(r.err))
        case .user(let commands):
            for c in commands {
                guard let path = c.first else { continue }
                let r = exec(path, Array(c.dropFirst()))
                if r.status != 0 { return .failed(clean(r.err.isEmpty ? r.out : r.err)) }
            }
            return .done
        }
    }

    private static func clean(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = t.split(separator: "\n").last.map(String.init) ?? t
        return line.isEmpty ? "Command failed" : String(line.prefix(160))
    }

    private static func exec(_ path: String, _ args: [String], timeout: TimeInterval = 300) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch { return (-1, "", error.localizedDescription) }
        // Drain stderr concurrently so a chatty tool can't fill the pipe and stall.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { errData = e.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let outData = o.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        group.wait()
        return (p.terminationStatus, String(data: outData, encoding: .utf8) ?? "", String(data: errData, encoding: .utf8) ?? "")
    }
}
