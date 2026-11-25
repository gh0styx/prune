import AppKit
import Foundation

/// Moves items that macOS refused to touch (permission denied) to the Trash the way Finder does, which is
/// the only route macOS allows for protected apps and folders. Finder shows its own Touch ID or password sheet
/// when it needs one. Only items that already passed `Trasher.isSafe` get here. Nothing is deleted.
/// System Settings panes Prune points to when macOS protects something.
enum AppPermissionLinks {
    static let appManagement = "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
}

enum AdminTrash {
    struct Outcome: Sendable {
        /// Item id → where it now sits in the Trash.
        var moved: [String: URL] = [:]
        /// Item id → the reason it was not moved.
        var failed: [String: String] = [:]
        /// True when the user cancelled the Touch ID or password prompt.
        var cancelled = false
    }

    /// Moves the refused items the way Finder does (NSWorkspace.recycle). macOS allows Finder to move protected
    /// apps and folders, and Finder shows its own Touch ID or password sheet when it needs one. Items Finder does
    /// not take keep their reason and point to the App Management setting.
    static func trash(_ items: [CleanItem]) -> Outcome {
        var outcome = Outcome()
        guard !items.isEmpty else { return outcome }
        let result = trashWithFinder(items)
        outcome.moved = result.moved
        for item in items where outcome.moved[item.id] == nil {
            if result.cancelled.contains(item.id) {
                outcome.cancelled = true
                outcome.failed[item.id] = tr("Administrator access was not granted.")
            } else if let reason = result.errors[item.id], reason.localizedCaseInsensitiveContains("not permitted") {
                outcome.failed[item.id] = tr("macOS protects this app's data, so even an administrator can't move it.")
            } else {
                outcome.failed[item.id] = result.errors[item.id] ?? tr("Not removed")
            }
        }
        return outcome
    }

    /// One item at a time, so a refusal for one does not hide the others. Asks Finder to delete each item (an Apple
    /// event, the same as "Move to Trash" in Finder), so macOS treats it as Finder's operation, not Prune's.
    private static func trashWithFinder(_ items: [CleanItem]) -> (moved: [String: URL], errors: [String: String], cancelled: Set<String>) {
        var moved: [String: URL] = [:]
        var errors: [String: String] = [:]
        var cancelled = Set<String>()
        let trashDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
        var permission: String?
        DispatchQueue.main.sync { permission = finderAutomationProblem() }
        if let permission {
            for item in items { errors[item.id] = permission }
            return (moved, errors, cancelled)
        }
        for item in items {
            let outcome = deleteViaFinder(item.url)
            if outcome.ok {
                let name = item.url.lastPathComponent
                let inTrash = trashDir.appending(path: name)
                moved[item.id] = FileManager.default.fileExists(atPath: inTrash.path) ? inTrash : trashDir
            } else if outcome.cancelled {
                cancelled.insert(item.id)
            } else {
                errors[item.id] = outcome.message
            }
        }
        return (moved, errors, cancelled)
    }

    /// Asks macOS for permission to control Finder (Automation), showing its prompt the first time.
    /// Returns nil when allowed, otherwise the reason to show.
    static func finderAutomationProblem() -> String? {
        let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let status = AEDeterminePermissionToAutomateTarget(finder.aeDesc, 0x2A2A2A2A, 0x2A2A2A2A, true)
        if status == noErr { return nil }
        return tr("Prune isn't allowed to control Finder. Turn it on in System Settings → Privacy & Security → Automation.")
    }

    /// `tell application "Finder" to delete POSIX file …` on the main thread (AppleScript needs it).
    private static func deleteViaFinder(_ url: URL) -> (ok: Bool, cancelled: Bool, message: String) {
        let escaped = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Finder\" to delete POSIX file \"\(escaped)\""
        var result: (Bool, Bool, String) = (false, false, tr("Not removed"))
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            var info: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                done.signal()
                return
            }
            _ = script.executeAndReturnError(&info)
            if let info {
                let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
                let message = (info[NSAppleScript.errorMessage] as? String) ?? tr("Not removed")
                result = (false, code == -128, message)
            } else {
                result = (true, false, "")
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 300)
        return (result.0, result.1, result.2)
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
                                          hint: tr("Select it again and clean to confirm with Touch ID or your password."), id: item.id)
            } else if raw.contains("Operation not permitted") {
                // Root is refused too: macOS privacy protection (App Management) guards this folder, not the file mode.
                failure = Trasher.Failure(name: item.name,
                                          reason: tr("macOS protects this app's data, so even an administrator can't move it."),
                                          hint: tr("Allow Prune in System Settings → Privacy & Security → App Management, or quit the app and try again."),
                                          id: item.id, settingsURL: AppPermissionLinks.appManagement)
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
