import SwiftUI

/// Everything Prune removed, with undo and "free space now".
struct HistoryView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let inTrash = store.history.reduce(0) { $0 + $1.inTrashSize }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "History",
                           subtitle: inTrash > 0 ? trf("%@ is still in the Trash. Free it or put things back.", Fmt.bytes(inTrash))
                                                 : "Everything Prune has removed.") {
                    EmptyView()
                }
                .appear()

                if store.history.isEmpty {
                    VStack(spacing: 10) {
                        IconTile(symbol: "clock.arrow.circlepath", color: Theme.blue, size: 44)
                        Text("Nothing cleaned yet").font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                        Text("After you clean, it shows up here and you can undo it.")
                            .font(Theme.sans(13)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .card()
                } else {
                    HistorySummary(entries: store.history).appear()
                    ForEach(Array(store.history.enumerated()), id: \.element.id) { i, entry in
                        EntryCard(entry: entry).appear(Double(min(i, 8)) * 0.05)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 32)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

/// Totals across every cleaning: what is gone for good, what is still in the Trash, what was put back.
private struct HistorySummary: View {
    let entries: [HistoryEntry]

    var body: some View {
        HStack(spacing: 12) {
            stat(tr("Cleanings"), "\(entries.count)")
            stat(tr("Freed for good"), Fmt.bytes(sum([.deleted, .pruned])))
            stat(tr("In the Trash now"), Fmt.bytes(sum([.inTrash])))
            stat(tr("Put back"), Fmt.bytes(sum([.restored])))
        }
    }

    private func sum(_ states: [HistoryItem.State]) -> Int64 {
        entries.flatMap(\.items).filter { states.contains($0.state) }.reduce(0) { $0 + $1.size }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.sans(18, .semibold)).foregroundStyle(Theme.text)
            Text(title).font(Theme.sans(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }
}

private struct EntryCard: View {
    @Environment(Store.self) private var store
    let entry: HistoryEntry
    @State private var open = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: entry.inTrash.isEmpty ? "checkmark" : "trash.fill",
                         color: entry.inTrash.isEmpty ? Theme.green : Theme.amber, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plural(entry.items.count, .item) + " · " + Fmt.bytes(entry.total))
                        .font(Theme.sans(13.5, .semibold)).foregroundStyle(Theme.text)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened) + " · " + status)
                        .font(Theme.sans(12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if !entry.inTrash.isEmpty {
                    Button("Restore") { store.restore(entry) }
                        .buttonStyle(PruneButtonStyle(kind: .secondary, height: 30))
                    Button { store.requestPurge(entry) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                            Text(trf("Free %@", Fmt.bytes(entry.inTrashSize)))
                        }
                    }
                    .buttonStyle(PruneButtonStyle(kind: .primary, height: 30))
                }
                Button { withAnimation(.snappy(duration: 0.3)) { open.toggle() } } label: {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            if open {
                Hairline()
                VStack(spacing: 0) {
                    ForEach(entry.items) { item in
                        HStack(spacing: 10) {
                            Circle().fill(color(item.state)).frame(width: 6, height: 6)
                            Text(item.name).font(Theme.sans(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(Fmt.tilde(item.originalPath)).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(label(item.state)).font(Theme.sans(11)).foregroundStyle(Theme.muted)
                            Text(Fmt.bytes(item.size)).font(Theme.mono(11.5)).foregroundStyle(Theme.muted)
                                .frame(width: 70, alignment: .trailing)
                            if item.state == .inTrash {
                                Button("Put back") { store.restore(entry, only: item) }
                                    .buttonStyle(.ghost)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                    }
                }
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var status: String {
        let trash = entry.inTrash.count
        if trash == entry.items.count { return tr("in the Trash") }
        if trash == 0 { return tr("done") }
        return trf("%lld still in the Trash", trash)
    }

    private func label(_ s: HistoryItem.State) -> String {
        switch s {
        case .inTrash: "In Trash"
        case .restored: "Restored"
        case .deleted: "Deleted"
        case .pruned: "Pruned"
        }
    }

    private func color(_ s: HistoryItem.State) -> Color {
        switch s {
        case .inTrash: Theme.amber
        case .restored: Theme.blue
        case .deleted, .pruned: Theme.green
        }
    }
}

/// Confirmation before permanently deleting what Prune put in the Trash.
struct PurgeSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(symbol: "exclamationmark.triangle.fill", color: Theme.red, size: 36)
                Text(trf("Delete %@ for good?", Fmt.bytes(entry.inTrashSize)))
                    .font(Theme.sans(17, .semibold)).foregroundStyle(Theme.text)
            }
            Text(trf("This permanently deletes %@ Prune moved to the Trash. Nothing else in your Trash is touched. This can't be undone.", plural(entry.inTrash.count, .item)))
                .font(Theme.sans(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { store.confirmingPurge = nil }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Delete forever") { store.purge(entry) }
                    .buttonStyle(.danger)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Theme.card)
    }
}
