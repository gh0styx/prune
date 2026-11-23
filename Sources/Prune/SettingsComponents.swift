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
struct MenuPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.0) { value, label in
                Text(tr(label)).tag(value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

struct Switch: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(Theme.blue)
    }
}
