import SwiftUI

// MARK: Building blocks

/// A titled group of rows separated by hairlines, no box around it (Claude/Codex style).
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr(title))
                .font(Theme.sans(13, .semibold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 4)
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { i, v in
                    if i > 0 { Rectangle().fill(Theme.text.opacity(0.07)).frame(height: 1) }
                    v
                }
            }
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var control: Control
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr(title)).font(Theme.sans(13, .medium)).foregroundStyle(Theme.text)
                if let detail {
                    Text(tr(detail)).font(Theme.sans(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 12)
    }
}

struct Segmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button { selection = value } label: {
                    Text(tr(label))
                        .font(Theme.sans(12, .medium))
                        .foregroundStyle(selection == value ? Theme.text : Theme.faint)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(selection == value ? Theme.active : .clear,
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.border))
    }
}

/// Dropdown for a short list of choices (used for the interface language).
/// A dark capsule with the current choice and a chevron; the list opens in a card with a checkmark
/// beside the current value. Replaces the system menu picker, whose blue accent clashed with the app.
struct MenuPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    @State private var open = false
    @State private var hovered = false

    private var currentLabel: String {
        options.first { $0.0 == selection }.map { tr($0.1) } ?? ""
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Text(currentLabel)
                    .font(Theme.sans(13, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(hovered || open ? Theme.hover : Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderStrong))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovered = $0 }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let isCurrent = option.0 == selection
                    Button {
                        selection = option.0
                        open = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.text)
                                .opacity(isCurrent ? 1 : 0)
                                .frame(width: 14)
                            Text(tr(option.1))
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(isCurrent ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(6)
            .frame(minWidth: 170)
            .background(Theme.card)
        }
    }
}

struct Switch: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(Theme.blue)
    }
}
