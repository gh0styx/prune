import SwiftUI

// MARK: Category card

struct CategoryCard: View {
    @Environment(Store.self) private var store
    let category: CategoryID
    @State private var hovering = false

    var body: some View {
        let items = store.items(category)
        let selected = store.selected(in: category).count
        Button {
            store.route = .category(category)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    IconTile(symbol: category.tileSymbol, color: category.color, size: 34)
                    Spacer()
                    if store.pending.contains(category) {
                        Spinner(size: 11)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(hovering ? Theme.text : Theme.faint)
                    }
                }
                Spacer(minLength: 16)
                Text(tr(category.title))
                    .font(Theme.sans(14, .semibold))
                    .foregroundStyle(Theme.text)
                Text(tr(category.blurb))
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(3, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
                HStack(alignment: .firstTextBaseline) {
                    SizeText(bytes: store.size(category), size: 20, weight: .semibold)
                    Spacer()
                    if category == .docker && store.dockerStatus == .notRunning {
                        Text("not running").font(Theme.mono(11)).foregroundStyle(Theme.faint)
                    } else if category == .docker && store.dockerStatus == .notInstalled {
                        Text("not installed").font(Theme.mono(11)).foregroundStyle(Theme.faint)
                    } else if selected > 0 {
                        Badge(text: trf("%lld selected", selected), color: category.color)
                    } else {
                        Text(plural(items.count, .item)).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                    }
                }
                .frame(height: 24)
                .padding(.top, 12)
            }
            .padding(18)
            .frame(height: 212)
            .card(highlighted: hovering)
            .scaleEffect(hovering ? 1.015 : 1)
            .shadow(color: .black.opacity(hovering ? 0.28 : 0), radius: 18, y: 10)
            .borderBeam(store.pending.contains(category))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.3), value: hovering)
    }
}

// MARK: Stale projects

struct TopItemsCard: View {
    @Environment(Store.self) private var store
    let title: String
    let subtitle: String
    let items: [CleanItem]
    let empty: String
    let route: Route
    let detail: (CleanItem) -> String
    /// Large files are cleaned from their own page, so their rows link there instead of toggling.
    var selectable = true

    var body: some View {
        let stale = items
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(title))
                        .font(Theme.sans(14, .semibold))
                        .foregroundStyle(Theme.text)
                    Text(tr(subtitle))
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("View all") { store.route = route }
                    .buttonStyle(.ghost)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Hairline()

            if stale.isEmpty {
                Text(tr(empty))
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
            } else {
                ForEach(Array(stale.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Hairline() }
                    HoverRow {
                        HStack(spacing: 12) {
                            if selectable {
                                CheckBox(state: store.selection.contains(item.id))
                            } else {
                                Image(systemName: NodeKind.forFile(item.url.pathExtension).symbol)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 15)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(item.name).font(Theme.sans(13, .medium)).foregroundStyle(Theme.text)
                                    Text(item.kind).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                                }
                                Text(item.location)
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.faint)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(detail(item))
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.muted)
                            Text(Fmt.bytes(item.size))
                                .font(Theme.mono(13, .medium))
                                .foregroundStyle(Theme.text)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                    }
                    .onTapGesture { if selectable { store.toggle(item) } else { store.route = route } }
                }
            }
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
