import SwiftUI

/// First-run tour. Shown over the main window until finished; scanning starts at the end.
struct WelcomeView: View {
    @Environment(Store.self) private var store
    @AppStorage(Prefs.Key.didOnboard) private var didOnboard = false
    @AppStorage(Prefs.Key.showMenuBar) private var showMenuBar = true
    // `--args -welcomeStep 2` opens on a given step (for screenshots).
    @State private var step = min(UserDefaults.standard.integer(forKey: "welcomeStep"), 4)
    @State private var forward = true

    private let steps = 5

    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.blue.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 520)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // One logo for the whole tour: big and centred on the first step, small above the text later.
                let orbSize: CGFloat = step == 0 ? 168 : 52
                OrbView(size: 168, intro: true)
                    .scaleEffect(orbSize / 168)
                    .frame(width: orbSize, height: orbSize)
                    .frame(width: 540, alignment: step == 0 ? .center : .leading)
                    .padding(.bottom, step == 0 ? 40 : 22)

                Group {
                    switch step {
                    case 0: Intro()
                    case 1: WhatItFinds()
                    case 2: HowItWorks()
                    case 3: Permissions()
                    default: Setup(showMenuBar: $showMenuBar)
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .offset(x: forward ? 40 : -40).combined(with: .opacity),
                    removal: .offset(x: forward ? -40 : 40).combined(with: .opacity)))
                .frame(width: 540)
                Spacer(minLength: 40)

                ZStack {
                HStack(spacing: 6) {
                    ForEach(0..<steps, id: \.self) { i in
                        Capsule()
                            .fill(i == step ? Theme.text : Theme.borderStrong)
                            .frame(width: i == step ? 18 : 6, height: 6)
                    }
                }
                HStack {
                    Button("Back") { go(-1) }
                        .buttonStyle(.ghost)
                        .opacity(step == 0 ? 0 : 1)
                        .disabled(step == 0)
                    Spacer()
                    Button {
                        step == steps - 1 ? finish() : go(1)
                    } label: {
                        HStack(spacing: 6) {
                            Text(step == 0 ? "Get started" : step == steps - 1 ? "Open Prune" : "Continue")
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                }
                }
                .frame(width: 540)
                .padding(.bottom, 36)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Switch language right away, before reading anything.
            Segmented(selection: Binding(
                get: { Lang.code.hasPrefix("uk") ? "uk" : Lang.code.hasPrefix("ru") ? "ru" : "en" },
                set: { new in
                    guard !Lang.code.hasPrefix(new) else { return }
                    Prefs.set(new, Prefs.Key.language)
                    Lang.relaunch()
                }),
                options: [("en", "English"), ("ru", "Русский"), ("uk", "Українська")])
            .padding(.top, 14)
            .padding(.trailing, 18)
        }
        .animation(.snappy(duration: 0.35), value: step)
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        step = min(max(step + delta, 0), steps - 1)
    }

    private func finish() {
        // No scan here: the user starts it from the Ready screen.
        withAnimation(.easeOut(duration: 0.3)) { didOnboard = true }
    }
}

private struct StepTitle: View {
    let eyebrow: String
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr(eyebrow).uppercased())
                .font(Theme.mono(11, .medium))
                .tracking(0.8)
                .foregroundStyle(Theme.blue)
            Text(tr(title))
                .font(Theme.sans(30, .semibold))
                .tracking(-0.9)
                .foregroundStyle(Theme.text)
            Text(tr(text))
                .font(Theme.sans(14))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Steps

private struct Intro: View {
    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Text("Welcome to Prune")
                    .font(Theme.sans(40, .semibold))
                    .tracking(-1.4)
                    .foregroundStyle(Theme.text)
                    .appear(1.05)
                Text("See what's taking space on your Mac.\nClean it without the guesswork.")
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .appear(1.2)
            }
            HStack(spacing: 8) {
                Badge(text: "Free & open source", color: Theme.green)
                Badge(text: "Nothing leaves your Mac", color: Theme.blue)
                Badge(text: "Undo with the Trash", color: Theme.violet)
            }
            .appear(1.35)
        }
    }
}

/// A grid of what Prune actually looks at, so the product is clear before any scan.
private struct WhatItFinds: View {
    private let items: [(String, Color, String, String)] = [
        ("square.stack.3d.up.fill", Theme.teal, "App caches", "Files apps rebuild on their own. Often several GB."),
        ("arrow.down.circle.fill", Theme.green, "Old downloads", "Installers you already used and files you forgot."),
        ("doc.fill", Theme.violet, "Large files", "The biggest single files, so you can decide what stays."),
        ("app.badge.fill", Theme.blue, "App leftovers", "Remove apps together with the data they leave behind."),
        ("square.split.2x2.fill", Theme.amber, "Disk map", "Every folder by size. Click to see what's inside."),
        ("doc.text.fill", Theme.gray, "Logs", "Old diagnostic logs nobody reads."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepTitle(eyebrow: "What Prune finds", title: "Space hides in a few places",
                      text: "Prune looks in each of them and shows sizes before anything happens.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    FindTile(symbol: item.0, color: item.1, title: item.2, text: item.3)
                        .appear(0.1 + Double(i) * 0.06)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Text("Write code? Developer mode adds node_modules, build output, Xcode, Docker and running dev servers.")
                    .font(Theme.sans(12)).foregroundStyle(Theme.muted)
            }
            .appear(0.5)
        }
    }

    private struct FindTile: View {
        let symbol: String
        let color: Color
        let title: String
        let text: String
        @State private var hovering = false

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: symbol, color: color, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(title)).font(Theme.sans(13.5, .semibold)).foregroundStyle(Theme.text)
                    Text(tr(text)).font(Theme.sans(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .card(highlighted: hovering)
            .scaleEffect(hovering ? 1.02 : 1)
            .onHover { hovering = $0 }
            .animation(.spring(duration: 0.3, bounce: 0.3), value: hovering)
        }
    }
}

private struct HowItWorks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            StepTitle(eyebrow: "How it works", title: "Scan, review, clean",
                      text: "Three steps. You stay in control the whole way.")
            VStack(spacing: 0) {
                Row(n: "1", symbol: "magnifyingglass", color: Theme.blue, title: "Scan",
                    text: "Prune maps every folder and finds caches, logs, leftovers and large files.")
                Hairline()
                Row(n: "2", symbol: "checklist", color: Theme.violet, title: "Review",
                    text: "Safe items are pre-selected. Everything else waits for your call.")
                Hairline()
                Row(n: "3", symbol: "trash", color: Theme.green, title: "Clean",
                    text: "Files go to the Trash, so you can always put them back.")
            }
            .card()
        }
    }

    private struct Row: View {
        let n: String
        let symbol: String
        let color: Color
        let title: String
        let text: String
        var body: some View {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, color: color, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(title)).font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                    Text(tr(text)).font(Theme.sans(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(n).font(Theme.mono(12)).foregroundStyle(Theme.faint)
            }
            .padding(16)
        }
    }
}

private struct Permissions: View {
    @State private var granted = FullDiskAccess.granted

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            StepTitle(eyebrow: "Permissions", title: "Let Prune see the whole disk",
                      text: "macOS hides some folders from apps. Full Disk Access gives Prune a complete map. It is optional, and you can change it later.")
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    IconTile(symbol: "lock.shield", color: granted ? Theme.green : Theme.amber, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Full Disk Access").font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                        Text(granted ? "Granted. Prune can see everything in your home folder."
                                     : "System Settings → Privacy & Security → Full Disk Access → turn on Prune.")
                            .font(Theme.sans(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if granted {
                        Badge(text: "Granted", color: Theme.green)
                    } else {
                        Button("Open Settings") { FullDiskAccess.openSettings() }.buttonStyle(.secondary)
                    }
                }
                .padding(16)
                Hairline()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.faint)
                    Text("macOS may also ask about Documents, Desktop and Downloads during the first scan. Allow them so your projects and files are included.")
                        .font(Theme.sans(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .card()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = FullDiskAccess.granted
        }
    }
}

private struct Setup: View {
    @Environment(Store.self) private var store
    @Binding var showMenuBar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            StepTitle(eyebrow: "Your setup", title: "What do you use your Mac for?",
                      text: "This only changes what Prune shows. Switch any time in Settings.")
            HStack(spacing: 12) {
                Choice(symbol: "sparkles", title: "Clean my Mac",
                       text: "Caches, logs, large files and a map of your disk.",
                       selected: !store.developerMode) { store.developerMode = false }
                Choice(symbol: "chevron.left.forwardslash.chevron.right", title: "I write code",
                       text: "Everything, plus node_modules, build output, Xcode, Docker and package caches.",
                       selected: store.developerMode) { store.developerMode = true }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Image(nsImage: IconArt.menuBarGlyph)
                    .renderingMode(.template)
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.border))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show in the menu bar").font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                    Text("Check reclaimable space and clean in one click.")
                        .font(Theme.sans(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Toggle("", isOn: $showMenuBar).toggleStyle(.switch).labelsHidden().tint(Theme.blue)
            }
            .padding(16)
            .card()
        }
    }

    private struct Choice: View {
        let symbol: String
        let title: String
        let text: String
        let selected: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        IconTile(symbol: symbol, color: selected ? Theme.blue : Theme.muted, size: 34)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(selected ? Theme.blue : Theme.borderStrong)
                    }
                    Text(tr(title)).font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                    Text(tr(text)).font(Theme.sans(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.blue : hovering ? Theme.borderStrong : Theme.border,
                                  lineWidth: selected ? 1.5 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: selected)
        }
    }
}
