import Foundation

/// A launchd job described by a property list in one of the LaunchAgents/LaunchDaemons folders.
struct LaunchEntry: Identifiable, Hashable, Sendable {
    enum Scope: Sendable { case user, systemAgent, systemDaemon }

    let plist: URL
    let label: String
    let program: String?
    let runAtLoad: Bool
    let keepAlive: Bool
    let scope: Scope
    var loaded = false
    var disabled = false

    var id: String { plist.path }
    var isUser: Bool { scope == .user }
    var isSystem: Bool { scope != .user }

    /// Nil when the plist names no program (e.g. only a Sockets/MachServices entry).
    var programExists: Bool {
        guard let program else { return true }
        guard program.hasPrefix("/") else { return true }   // resolved through PATH by launchd
        return FileManager.default.fileExists(atPath: program)
    }

    /// The enclosing .app bundle path, if the program lives inside one.
    var appPath: String? {
        guard let program, let r = program.range(of: ".app/") ?? (program.hasSuffix(".app") ? program.range(of: ".app") : nil) else { return nil }
        let path = String(program[..<r.upperBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/" + path
    }

    var appName: String? {
        appPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
    }
}

enum LoginItemsScanner {
    static var uid: uid_t { getuid() }
    static let userDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")

    static func scan() -> (user: [LaunchEntry], system: [LaunchEntry]) {
        let list = userLoadedLabels()
        let disabled = disabledLabels()
        var user = read(userDir, .user)
        for i in user.indices {
            user[i].loaded = list.contains(user[i].label)
            user[i].disabled = disabled.contains(user[i].label)
        }
        var system = read(URL(fileURLWithPath: "/Library/LaunchAgents"), .systemAgent)
        for i in system.indices { system[i].loaded = list.contains(system[i].label) }
        var daemons = read(URL(fileURLWithPath: "/Library/LaunchDaemons"), .systemDaemon)
        for i in daemons.indices {
            // Daemons live in the system domain, which `launchctl list` (user domain) doesn't show.
            daemons[i].loaded = run(["print", "system/\(daemons[i].label)"]).status == 0
        }
        system += daemons
        let byName: (LaunchEntry, LaunchEntry) -> Bool = { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        return (user.sorted(by: byName), system.sorted(by: byName))
    }

    static func read(_ dir: URL, _ scope: LaunchEntry.Scope) -> [LaunchEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "plist" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return nil }
            let label = (dict["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
            let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
            let keepAlive: Bool
            if let b = dict["KeepAlive"] as? Bool { keepAlive = b } else { keepAlive = dict["KeepAlive"] is [String: Any] }
            return LaunchEntry(plist: url, label: label, program: program,
                               runAtLoad: (dict["RunAtLoad"] as? Bool) ?? false, keepAlive: keepAlive, scope: scope)
        }
    }

    /// Labels present in the current user's launchd domain (`launchctl list`: PID, Status, Label).
    static func userLoadedLabels() -> Set<String> {
        guard let out = Shell.run("/bin/launchctl", ["list"], timeout: 10) else { return [] }
        return parseList(out)
    }

    static func parseList(_ out: String) -> Set<String> {
        var labels = Set<String>()
        for line in out.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            if cols.count >= 3 { labels.insert(String(cols[2])) }
        }
        return labels
    }

    /// Labels switched off with `launchctl disable` (`print-disabled`: `"label" => disabled`).
    static func disabledLabels() -> Set<String> {
        guard let out = Shell.run("/bin/launchctl", ["print-disabled", "gui/\(uid)"], timeout: 10) else { return [] }
        return parseDisabled(out)
    }

    static func parseDisabled(_ out: String) -> Set<String> {
        var labels = Set<String>()
        for line in out.split(separator: "\n") {
            guard line.contains("=> disabled") || line.contains("=> true"),
                  let a = line.firstIndex(of: "\""), let b = line[line.index(after: a)...].firstIndex(of: "\"") else { continue }
            labels.insert(String(line[line.index(after: a)..<b]))
        }
        return labels
    }

    // MARK: Actions (user agents only)

    /// Stops the agent and keeps it from starting at login. Reversible with `enable`.
    static func disable(_ e: LaunchEntry) -> String? {
        guard e.isUser else { return "Not allowed" }
        _ = run(["bootout", "gui/\(uid)", e.plist.path])   // fails harmlessly when it isn't loaded
        let r = run(["disable", "gui/\(uid)/\(e.label)"])
        return r.status == 0 ? nil : message(r)
    }

    static func enable(_ e: LaunchEntry) -> String? {
        guard e.isUser else { return "Not allowed" }
        let r = run(["enable", "gui/\(uid)/\(e.label)"])
        if r.status != 0 { return message(r) }
        let b = run(["bootstrap", "gui/\(uid)", e.plist.path])
        // 5 / 37: already bootstrapped.
        return (b.status == 0 || b.status == 5 || b.status == 37) ? nil : message(b)
    }

    private static func message(_ r: (status: Int32, err: String)) -> String {
        let t = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "launchctl failed (\(r.status))" : String(t.split(separator: "\n").last ?? "")
    }

    @discardableResult
    private static func run(_ args: [String]) -> (status: Int32, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let e = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = e
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) { if p.isRunning { p.terminate() } }
        let data = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
