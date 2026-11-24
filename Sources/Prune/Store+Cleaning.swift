import SwiftUI

extension Store {
    // MARK: Clean

    func requestClean(_ list: [CleanItem]) {
        guard !list.isEmpty, !isCleaning, !isScanning else { return }
        confirming = list
    }

    func clean(_ list: [CleanItem]) {
        confirming = nil
        guard !isCleaning else { return }
        isCleaning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { Trasher.trash(list) }.value
            withAnimation(.snappy) {
                if !result.entry.items.isEmpty {
                    history.insert(result.entry, at: 0)
                    lastEntryID = result.entry.id
                    HistoryFile.save(history)
                }
                apps = apps?.filter { !result.trashed.contains($0.item.id) }
                for c in CategoryID.allCases where items[c] != nil {
                    items[c] = items(c).filter { !result.trashed.contains($0.id) }
                }
                selection.subtract(result.trashed)
                // Items that were not removed stay in the list, marked with the reason, and are deselected
                // so the Clean total only counts what can go. Reselect one to try again.
                for id in result.trashed { failedReasons[id] = nil }
                for f in result.failures {
                    guard let id = f.id else { continue }
                    failedReasons[id] = f.reason
                    selection.remove(id)
                }
                var deleted: [String: Int64] = [:]
                for item in list where result.trashed.contains(item.id) && item.command == nil {
                    deleted[item.url.resolvingSymlinksInPath().path] = item.size + item.shared
                }
                if let tree, !deleted.isEmpty {
                    tree.remove(deleted: deleted)
                    // If the folder on screen was removed, step back to the nearest folder that's still there.
                    var focus = spaceFocus
                    while let f = focus, !f.isAttached(to: tree) { focus = f.parent }
                    spaceFocus = focus ?? tree
                    treeVersion += 1
                }
                isCleaning = false
                disk = .current()
                let failed = list.count - result.trashed.count
                toastHasActions = !result.entry.inTrash.isEmpty
                toast = trf("%@ moved to Trash", Fmt.bytes(result.freed)) + (failed > 0 ? " · " + trf("%lld skipped", failed) : "")
                // Snapshots report no size, so tell the user what is free now instead of a freed total.
                let snapshotsRemoved = list.filter { $0.command?.first == "/usr/bin/tmutil" && result.trashed.contains($0.id) }.count
                if snapshotsRemoved > 0 {
                    toast = (toast ?? "") + " · " + trf("%lld snapshots removed", snapshotsRemoved)
                        + " · " + trf("%@ free now", Fmt.bytes(disk.free))
                }
                if let first = result.failures.first {
                    // Say why, and what to do, instead of only counting the skipped items.
                    var lines = [trf("Not removed: %@ — %@", first.name, first.reason)]
                    if let hint = first.hint { lines.append(hint) }
                    toast = ([toast ?? ""] + lines).joined(separator: "\n")
                }
            }
            if !NSApp.isActive && result.freed > 0 {
                Notifier.shared.post("clean", title: "Cleaning done",
                                     body: trf("%@ moved to the Trash. Empty it to free the space.", Fmt.bytes(result.freed)))
            }
            let token = UUID()
            toastToken = token
            try? await Task.sleep(for: .seconds(3.5))
            if toastToken == token { withAnimation(.easeOut) { toast = nil } }
        }
    }

}
