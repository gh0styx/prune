import Foundation

/// Login items, the security check and dev servers. They share the scanners that Prune.app uses.
/// Anything that changes the system is dry-run unless --yes is given.
enum Extras {
    // MARK: login-items

    /// `prune login-items` lists them. `prune login-items off|on <name> [--yes]` turns one off or on.
    static func loginItems(_ o: Options) -> Int32 {
        let scan = LoginItemsScanner.scan()
        let all = (scan.user + scan.system).sorted { $0.label < $1.label }
        guard let verb = o.names.first?.lowercased() else {
            say(Style.bold("Login items") + Style.dim("  (turn one off: prune login-items off <name> --yes)"))
            for e in all {
                let state = e.disabled ? Style.dim("off  ") : e.loaded ? Style.green("on   ") : Style.dim("idle ")
                let scope = e.isUser ? "" : Style.dim("system ")
                let program = e.program.map { Fmt.tilde($0) } ?? Style.dim("no program")
                say("  " + state + scope + column(e.label, 46) + Style.dim(program))
            }
            if all.isEmpty { say("  None.") }
            return 0
        }
        guard verb == "off" || verb == "on" else { fail("use: prune login-items [off|on <name>]") }
        let query = o.names.dropFirst().joined(separator: " ").lowercased()
        guard !query.isEmpty else { fail("name the login item, e.g. prune login-items off <name>") }
        let matches = all.filter {
            $0.label.lowercased().contains(query) || ($0.appName ?? "").lowercased().contains(query)
        }
        guard let entry = matches.first, matches.count == 1 else {
            if matches.isEmpty { fail("no login item matches '\(query)'") }
            say("Several login items match. Be more specific:")
            for m in matches.prefix(20) { say("  " + m.label) }
            return 1
        }
        guard entry.isUser else {
            say("System-wide items need an administrator. Use System Settings › General › Login Items.")
            return 1
        }
        guard o.yes else {
            say("Dry run: would turn \(verb) \(entry.label). Re-run with " + Style.cyan("--yes") + " to change it.")
            return 0
        }
        let error = verb == "off" ? LoginItemsScanner.disable(entry) : LoginItemsScanner.enable(entry)
        if let error {
            note(Style.red("prune: ") + error)
            return 1
        }
        say(Style.green("Turned \(verb) ") + entry.label)
        return 0
    }

    // MARK: security

    /// `prune security` lists startup items, browser extensions and known adware.
    /// `prune security --yes` moves the findings Prune may remove (single launch agents) to the Trash.
    static func security(_ o: Options) -> Int32 {
        note("Checking startup items, browser extensions and known adware…")
        let result = SecurityScanner.scan()
        let p = result.protection
        func flag(_ v: Bool?) -> String {
            v == true ? Style.green("on") : v == false ? Style.red("off") : Style.dim("unknown")
        }
        say(Style.bold("System protection"))
        say("  Gatekeeper " + flag(p.gatekeeper) + "   SIP " + flag(p.sip) + "   FileVault " + flag(p.fileVault)
            + "   Firewall " + flag(p.firewall))
        say("")
        if result.findings.isEmpty {
            say(Style.green("No problems found in startup items, extensions or known adware."))
            return 0
        }
        say(Style.bold("Findings (\(result.findings.count))"))
        for f in result.findings.sorted(by: { $0.severity < $1.severity }) {
            let badge: String
            switch f.severity {
            case .threat: badge = Style.red("threat ")
            case .warning: badge = Style.yellow("warning")
            case .info: badge = Style.dim("info   ")
            }
            say("  " + badge + "  " + column(f.title, 40) + Style.dim(f.reason))
            if let path = f.path { say("           " + Style.dim(Fmt.tilde(path.path))) }
            say("           " + Style.dim(removalHint(f.removal)))
        }
        let trashable = result.findings.filter(\.canTrash)
        guard !trashable.isEmpty else { return 0 }
        let items: [CleanItem] = trashable.compactMap { f in
            guard let url = f.path else { return nil }
            return CleanItem(url: url, category: .security, name: f.title, kind: "launch agent",
                             location: Fmt.tilde(url.deletingLastPathComponent().path),
                             size: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0),
                             lastActivity: nil, isStale: false)
        }
        say("")
        say("Can be moved to the Trash by prune: \(items.count). Unload them first with prune login-items off <name>.")
        return Commands.execute(items, o)
    }

    static func removalHint(_ r: SecurityFinding.Removal) -> String {
        switch r {
        case .trash: return "prune can move this to the Trash with --yes"
        case .browser: return "remove it on the browser's extensions page"
        case .finder: return "remove it in Finder"
        case .loginItems: return "remove it in System Settings › General › Login Items"
        case .admin: return "removing it needs an administrator password"
        }
    }

    // MARK: servers

    /// `prune servers` lists dev servers. `prune servers stop <pid|name> [--yes]` stops one with SIGTERM.
    static func servers(_ o: Options) -> Int32 {
        if o.names.first?.lowercased() == "stop" {
            return stopServer(o, query: o.names.dropFirst().joined(separator: " ").lowercased())
        }
        note("Looking for dev servers…")
        let servers = DevServerScanner.scan().filter { o.all || $0.isLikelyDevServer }
        if servers.isEmpty {
            say("No dev servers running. Use --all to show every listening process.")
            return 0
        }
        say(Style.bold("Dev servers") + Style.dim("  (stop one: prune servers stop <pid|name> --yes)"))
        for s in servers {
            let ports = s.ports.isEmpty ? "" : ":" + s.ports.map(String.init).joined(separator: ",")
            let dir = s.cwd.map { Fmt.tilde($0) } ?? ""
            say("  " + rightColumn(String(s.pid), 7) + "  " + column(s.kind.label, 9) + column(s.processName + ports, 28)
                + rightColumn(bytes(s.memoryBytes), 9) + "  " + Style.dim(dir))
        }
        return 0
    }

    static func stopServer(_ o: Options, query: String) -> Int32 {
        guard !query.isEmpty else { fail("name a server or its pid: prune servers stop <pid|name>") }
        let servers = DevServerScanner.scan()
        let matches: [DevServer]
        if let pid = Int32(query) {
            matches = servers.filter { $0.pid == pid }
        } else {
            matches = servers.filter {
                $0.processName.lowercased().contains(query) || ($0.cwd ?? "").lowercased().contains(query)
                    || $0.ports.contains { String($0) == query }
            }
        }
        guard let server = matches.first, matches.count == 1 else {
            if matches.isEmpty { fail("no running server matches '\(query)'") }
            say("Several servers match. Use the pid:")
            for m in matches { say("  \(m.pid)  \(m.processName)") }
            return 1
        }
        let ports = server.ports.isEmpty ? "" : " on :" + server.ports.map(String.init).joined(separator: ",")
        guard o.yes else {
            say("Dry run: would stop \(server.processName) (pid \(server.pid))\(ports). Re-run with " + Style.cyan("--yes") + ".")
            return 0
        }
        guard DevServerKiller.stop(server.pid, force: false) else {
            note(Style.red("prune: ") + "could not stop pid \(server.pid). It may belong to another user or already be gone.")
            return 1
        }
        say(Style.green("Stopped ") + server.processName + " (pid \(server.pid))")
        return 0
    }
}
