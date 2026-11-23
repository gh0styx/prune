import SwiftUI

extension Store {
    // MARK: History

    /// Moves everything still in the Trash from this entry back to where it was.
    func restore(_ entry: HistoryEntry, only item: HistoryItem? = nil) {
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
        var restored = 0
        for (i, it) in history[index].items.enumerated() where it.state == .inTrash && (item == nil || it.id == item!.id) {
            if TrashOps.restore(it) {
                history[index].items[i].state = .restored
                restored += 1
            }
        }
        HistoryFile.save(history)
        showToast(restored > 0 ? trf("Restored %@", plural(restored, .item)) : tr("Nothing could be restored"))
    }

    func requestPurge(_ entry: HistoryEntry) {
        guard !entry.inTrash.isEmpty else { return }
        confirmingPurge = entry
    }

    /// Permanently deletes what this entry put in the Trash. Only called after the user confirms.
    func purge(_ entry: HistoryEntry) {
        confirmingPurge = nil
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
        let items = history[index].items
        Task {
            let done = await Task.detached(priority: .userInitiated) {
                items.map { $0.state == .inTrash && TrashOps.deleteForever($0) }
            }.value
            var freed: Int64 = 0
            for (i, ok) in done.enumerated() where ok {
                history[index].items[i].state = .deleted
                freed += items[i].size
            }
            HistoryFile.save(history)
            disk = .current()
            showToast(freed > 0 ? trf("Freed %@", Fmt.bytes(freed)) : tr("Couldn't delete. Empty the Trash in Finder instead"))
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.snappy) { toastHasActions = false; toast = tr(text) }
        let token = UUID()
        toastToken = token
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if toastToken == token { withAnimation(.easeOut) { toast = nil } }
        }
    }

    // MARK: Ignore list

    func isIgnored(_ item: CleanItem) -> Bool {
        IgnoreList.contains(item.url)
    }

    func ignore(_ item: CleanItem) {
        guard !ignored.contains(item.url.path) else { return }
        IgnoreList.add(item.url)
        ignored = IgnoreList.paths
        withAnimation(.snappy) {
            items[item.category] = items(item.category).filter { $0.id != item.id }
            selection.remove(item.id)
        }
        showToast("Hidden. Undo in Settings › Scanning")
    }

    func unignore(_ path: String) {
        IgnoreList.remove(path)
        ignored = IgnoreList.paths
    }

}
