import Foundation
import SwiftUI

enum DevServerKind: String, Sendable {
    case node, bun, deno, python, ruby, go, java, php, rust, docker, database, other

    var symbol: String {
        switch self {
        case .node: "hexagon.fill"
        case .bun: "bolt.fill"
        case .deno: "leaf.fill"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .ruby: "diamond.fill"
        case .go: "g.circle.fill"
        case .java: "cup.and.saucer.fill"
        case .php: "p.circle.fill"
        case .rust: "gearshape.fill"
        case .docker: "shippingbox.fill"
        case .database: "cylinder.fill"
        case .other: "network"
        }
    }

    var color: Color {
        switch self {
        case .node: Theme.green
        case .bun: Theme.amber
        case .deno: Theme.teal
        case .python: Theme.blue
        case .ruby: Theme.red
        case .go: Theme.cyan
        case .java: Theme.amber
        case .php: Theme.violet
        case .rust: Theme.pink
        case .docker: Theme.blue
        case .database: Theme.violet
        case .other: Theme.gray
        }
    }

    var label: String {
        switch self {
        case .node: "Node.js"
        case .bun: "Bun"
        case .deno: "Deno"
        case .python: "Python"
        case .ruby: "Ruby"
        case .go: "Go"
        case .java: "Java"
        case .php: "PHP"
        case .rust: "Rust"
        case .docker: "Docker"
        case .database: "Database"
        case .other: "Other"
        }
    }
}

struct DevServer: Identifiable, Hashable, Sendable {
    let pid: Int32
    var ports: [Int]
    var processName: String
    var command: String
    var cwd: String?
    var memoryBytes: Int64
    var cpuPercent: Double
    var started: Date?
    var kind: DevServerKind
    var isLikelyDevServer: Bool
    var id: Int32 { pid }
}

enum DevServerScanner {
    private static let denylist: Set<String> = [
        "rapportd", "controlcenter", "sharingd", "identityservicesd", "spotify", "dropbox",
        "airplayxpchelper", "airplayuiagent", "remoted", "wifiagent", "mdnsresponder", "apsd",
        "figma_agent", "google drive", "googledrivefs", "onedrive", "1password", "raycast",
        "loginwindow", "trustd", "cloudd", "bird", "usernoted", "assistantd", "zoom.us",
        "slack", "discord", "teams", "creative cloud", "adobe desktop service", "logioptionsplus_agent",
    ]

    static func scan() -> [DevServer] {
        let uid = getuid()
        let me = ProcessInfo.processInfo.processIdentifier
        guard let out = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-u", String(uid), "-F", "pcn"], timeout: 10) else { return [] }

        var ports: [Int32: Set<Int>] = [:]
        var names: [Int32: String] = [:]
        var current: Int32?
        for line in out.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": current = Int32(value); if let c = current { ports[c, default: []] = ports[c] ?? [] }
            case "c": if let c = current { names[c] = value.replacingOccurrences(of: "\\x20", with: " ") }
            case "n":
                if let c = current, let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) {
                    ports[c, default: []].insert(port)
                }
            default: break
            }
        }
        ports = ports.filter { !$0.value.isEmpty && $0.key != me }
        guard !ports.isEmpty else { return [] }

        let pids = ports.keys.sorted()
        let pidList = pids.map(String.init).joined(separator: ",")
        let info = psInfo(pidList)
        let cwds = workingDirs(pidList)

        var result: [DevServer] = []
        for pid in pids {
            guard let p = info[pid] else { continue }
            let name = names[pid] ?? (p.command.split(separator: " ").first.map { String(($0 as Substring).split(separator: "/").last ?? $0) } ?? "?")
            if denylist.contains(name.lowercased()) { continue }
            let portList = (ports[pid] ?? []).sorted()
            let kind = classify(name: name, command: p.command)
            result.append(DevServer(
                pid: pid, ports: portList, processName: name, command: p.command, cwd: cwds[pid],
                memoryBytes: p.rss * 1024, cpuPercent: p.cpu, started: p.started, kind: kind,
                isLikelyDevServer: likely(kind: kind, command: p.command, ports: portList)))
        }
        return result.sorted {
            if $0.isLikelyDevServer != $1.isLikelyDevServer { return $0.isLikelyDevServer }
            return $0.memoryBytes > $1.memoryBytes
        }
    }

    private struct PS { var rss: Int64; var cpu: Double; var started: Date?; var command: String }

    private static func psInfo(_ pidList: String) -> [Int32: PS] {
        guard let out = Shell.run("/bin/ps", ["-o", "pid=,rss=,%cpu=,lstart=,command=", "-p", pidList], timeout: 10) else { return [:] }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        var res: [Int32: PS] = [:]
        for line in out.split(separator: "\n") {
            let t = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard t.count >= 8, let pid = Int32(t[0]), let rss = Int64(t[1]) else { continue }
            let date = f.date(from: t[3...7].joined(separator: " "))
            res[pid] = PS(rss: rss, cpu: Double(t[2]) ?? 0, started: date, command: t.count > 8 ? String(t[8]) : "")
        }
        return res
    }

    private static func workingDirs(_ pidList: String) -> [Int32: String] {
        guard let out = Shell.run("/usr/sbin/lsof", ["-a", "-p", pidList, "-d", "cwd", "-Fn"], timeout: 10) else { return [:] }
        var res: [Int32: String] = [:]
        var current: Int32?
        for line in out.split(separator: "\n") {
            let value = String(line.dropFirst())
            if line.first == "p" { current = Int32(value) }
            else if line.first == "n", let c = current { res[c] = value }
        }
        return res
    }

    private static func classify(name: String, command: String) -> DevServerKind {
        let n = name.lowercased()
        let c = command.lowercased()
        func has(_ words: [String], in s: String) -> Bool { words.contains { s.contains($0) } }
        if has(["postgres", "mysqld", "redis-server", "mongod"], in: n) || has(["postgres", "mysqld", "redis-server", "mongod"], in: c) { return .database }
        if n == "ollama" || c.contains("/ollama") { return .other }
        if has(["com.docker", "docker", "vpnkit"], in: n) || c.contains("com.docker") { return .docker }
        if n.hasPrefix("bun") || c.contains("/bun ") || c.hasPrefix("bun ") { return .bun }
        if n.hasPrefix("deno") || c.contains("/deno ") { return .deno }
        if has(["node", "npm", "pnpm", "yarn", "next", "vite"], in: n) || has(["node_modules", "/node ", "next dev", "vite"], in: c) { return .node }
        if has(["python", "uvicorn", "gunicorn", "flask", "django"], in: n) || has(["uvicorn", "gunicorn", "flask", "django", "python"], in: c) { return .python }
        if has(["ruby", "rails", "puma"], in: n) || has(["rails", "puma", "/ruby "], in: c) { return .ruby }
        if c.contains("go run") || c.contains("/go-build") || n == "go" { return .go }
        if has(["java", "gradle", "kotlin"], in: n) || c.contains("/java ") { return .java }
        if n.hasPrefix("php") || c.contains("/php ") { return .php }
        if has(["cargo"], in: n) || c.contains("target/debug") || c.contains("target/release") { return .rust }
        return .other
    }

    private static func likely(kind: DevServerKind, command: String, ports: [Int]) -> Bool {
        if kind != .other { return true }
        let c = command.lowercased()
        let words = ["node_modules/.bin", "vite", "webpack", "next", "nuxt", "astro", "remix", "uvicorn", "flask", "rails"]
        if words.contains(where: { c.contains($0) }) { return true }
        return ports.contains { (3000...9999).contains($0) }
    }
}

enum DevServerKiller {
    static func stop(_ pid: Int32, force: Bool) -> Bool {
        guard pid > 1, pid != ProcessInfo.processInfo.processIdentifier else { return false }
        guard let uidOut = Shell.run("/bin/ps", ["-o", "uid=", "-p", String(pid)], timeout: 5),
              uid_t(uidOut.trimmingCharacters(in: .whitespacesAndNewlines)) == getuid() else { return false }
        kill(pid, SIGTERM)
        if force { kill(pid, SIGKILL) }
        for _ in 0..<15 {
            usleep(100_000)
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
        }
        return kill(pid, 0) != 0 && errno == ESRCH
    }
}
