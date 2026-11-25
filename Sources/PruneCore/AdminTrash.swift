import Foundation

/// Moves items that macOS refused to touch (permission denied) into the user's Trash with administrator
/// rights. The password comes from macOS's own dialog: osascript runs the commands with
/// `with administrator privileges`, so Prune never sees the password and nothing is stored.
/// Only items that already passed `Trasher.isSafe` get here. Nothing is deleted: each item is moved to
/// ~/.Trash and handed back to the user, so "Put back" and emptying the Trash work as usual.
enum AdminTrash {
    struct Outcome: Sendable {
        /// Item id → where it now sits in the Trash.
        var moved: [String: URL] = [:]
        /// Item id → the reason it was not moved (the raw error from mv).
        var failed: [String: String] = [:]
        /// True when the user pressed Cancel in the password dialog.
        var cancelled = false
    }

    static func trash(_ items: [CleanItem]) -> Outcome {
        var outcome = Outcome()
        guard !items.isEmpty else { return outcome }
        let trashDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
        var destinations: [String: URL] = [:]
        var taken = Set<String>()
        var lines: [String] = []
        let owner = "\(getuid()):\(getgid())"
        for (i, item) in items.enumerated() {
            let dst = uniqueTrashURL(for: item.url.lastPathComponent, in: trashDir, taken: &taken)
            destinations[item.id] = dst
            // mv -n never overwrites. On success hand the item back to the user; on failure print the error.
            lines.append("if r=$(/bin/mv -n \(quote(item.url.path)) \(quote(dst.path)) 2>&1) && [ ! -e \(quote(item.url.path)) ]; then "
                + "/usr/sbin/chown -R \(owner) \(quote(dst.path)) 2>/dev/null; echo \(i)ok; "
                + "else echo \"\(i)fail $(printf '%s' \"$r\" | tr '\\n' ' ')\"; fi")
        }
        let script = lines.joined(separator: "; ")
        let run = runAsAdmin(script)
        if run.status != 0 {
            // -128 is AppleScript's "User canceled".
            if run.err.contains("-128") || run.err.localizedCaseInsensitiveContains("User canceled") {
                outcome.cancelled = true
            } else {
                for item in items { outcome.failed[item.id] = lastLine(run.err) }
            }
            return outcome
        }
        var answered = Set<Int>()
        for raw in run.out.split(separator: "\n") {
            let parts = raw.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard let first = parts.first, let i = Int(first.dropLast(first.hasSuffix("ok") ? 2 : 4)),
                  items.indices.contains(i) else { continue }
            let item = items[i]
            answered.insert(i)
            if first.hasSuffix("ok") {
                outcome.moved[item.id] = destinations[item.id]
            } else {
                let reason = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
                outcome.failed[item.id] = reason.trimmingCharacters(in: .whitespaces).isEmpty ? "mv failed" : reason
            }
        }
        for (i, item) in items.enumerated() where !answered.contains(i) && outcome.moved[item.id] == nil {
            outcome.failed[item.id] = tr("No answer from the administrator task.")
        }
        return outcome
    }

    /// `~/.Trash/Name`, or `Name 2`, `Name 3` … when that name is already in the Trash.
    private static func uniqueTrashURL(for name: String, in dir: URL, taken: inout Set<String>) -> URL {
        let fm = FileManager.default
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var n = 1
        while true {
            let candidate = n == 1 ? name : (ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            let url = dir.appending(path: candidate)
            if !taken.contains(candidate), !fm.fileExists(atPath: url.path) {
                taken.insert(candidate)
                return url
            }
            n += 1
        }
    }

    /// Single-quotes a path for /bin/sh.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func lastLine(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = t.split(separator: "\n").last.map(String.init) ?? t
        return line.isEmpty ? "Command failed" : String(line.prefix(200))
    }

    /// Runs a shell script as administrator through osascript, which shows macOS's password dialog.
    private static func runAsAdmin(_ script: String) -> (status: Int32, out: String, err: String) {
        // Escape for an AppleScript string literal.
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch { return (-1, "", error.localizedDescription) }
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

extension Trasher.Result {
    /// Folds the administrator pass into the result: moved items join the trashed set and the history,
    /// and items still refused get a reason the user can act on.
    mutating func applyAdmin(_ outcome: AdminTrash.Outcome, items: [CleanItem]) {
        for item in items {
            if let dst = outcome.moved[item.id] {
                freed += item.size
                trashed.insert(item.id)
                entry.items.append(HistoryItem(name: item.name, kind: item.kind, originalPath: item.url.path,
                                               trashPath: dst.path, size: item.size, state: .inTrash))
                failures.removeAll { $0.id == item.id }
                continue
            }
            let raw = outcome.failed[item.id] ?? ""
            var failure: Trasher.Failure
            if outcome.cancelled {
                failure = Trasher.Failure(name: item.name, reason: tr("Administrator access was not granted."),
                                          hint: tr("Select it again and clean to enter the administrator password."), id: item.id)
            } else if raw.contains("Operation not permitted") {
                // Root is refused too: macOS privacy protection (App Management) guards this folder, not the file mode.
                failure = Trasher.Failure(name: item.name,
                                          reason: tr("macOS protects this app's data, so even an administrator can't move it."),
                                          hint: tr("Allow Prune in System Settings → Privacy & Security → App Management, or quit the app and try again."),
                                          id: item.id)
            } else {
                failure = Trasher.Failure(name: item.name, reason: raw.isEmpty ? tr("Not removed") : raw, id: item.id)
            }
            if let i = failures.firstIndex(where: { $0.id == item.id }) {
                failures[i] = failure
            } else {
                failures.append(failure)
            }
        }
    }
}
