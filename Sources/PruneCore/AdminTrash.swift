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
        outcome.moved = trashWithFinder(items)
        for item in items where outcome.moved[item.id] == nil {
            outcome.failed[item.id] = tr("macOS protects this app's data, so even an administrator can't move it.")
        }
        return outcome
    }

    /// One item at a time, so a refusal for one does not hide the others. Waits for Finder's answer.
    private static func trashWithFinder(_ items: [CleanItem]) -> [String: URL] {
        var moved: [String: URL] = [:]
        for item in items {
            let done = DispatchSemaphore(value: 0)
            var newURL: URL?
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle([item.url]) { result, _ in
                    newURL = result[item.url]
                    done.signal()
                }
            }
            _ = done.wait(timeout: .now() + 300)
            if let newURL { moved[item.id] = newURL }
        }
        return moved
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
