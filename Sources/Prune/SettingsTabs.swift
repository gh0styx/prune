import SwiftUI
import ServiceManagement

// MARK: Tabs

struct GeneralSettings: View {
    @AppStorage(Prefs.Key.language) private var language = "system"
    @State private var languageChanged = false

    @AppStorage(Prefs.Key.notifications) private var notifications = true
    @AppStorage(Prefs.Key.schedule) private var schedule = "weekly"
    @Environment(Store.self) private var store
    @AppStorage(Prefs.Key.appearance) private var appearance = "dark"
    @AppStorage(Prefs.Key.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.Key.scanOnLaunch) private var scanOnLaunch = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var store = store
        SettingsGroup(title: "Language") {
            SettingRow(title: "Interface language", detail: languageChanged ? "Restart Prune to switch the language." : nil) {
                HStack(spacing: 8) {
                    if languageChanged {
                        Button("Restart") { Lang.relaunch() }.buttonStyle(PruneButtonStyle(kind: .primary, height: 26))
                    }
                    MenuPicker(selection: Binding(get: { language }, set: { language = $0; languageChanged = true }),
                               options: [("system", "Match system"), ("ru", "Русский"), ("uk", "Українська"), ("en", "English")])
                }
            }
        }
        SettingsGroup(title: "Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Color mode").font(Theme.sans(13, .medium)).foregroundStyle(Theme.text)
                HStack(spacing: 14) {
                    ThemeCard(mode: "light", title: "Light", selection: $appearance)
                    ThemeCard(mode: "dark", title: "Dark", selection: $appearance)
                    ThemeCard(mode: "system", title: "Match system", selection: $appearance)
                }
            }
            .padding(.vertical, 12)
            SettingRow(title: "Show in menu bar", detail: "Reclaimable space and quick clean, one click away.") {
                Switch(isOn: $showMenuBar)
            }
        }
        SettingsGroup(title: "Mode") {
            SettingRow(title: "Developer mode",
                       detail: "Show node_modules, build output, Xcode, Docker and package caches.") {
                Switch(isOn: $store.developerMode)
            }
        }
        SettingsGroup(title: "Notifications") {
            SettingRow(title: "Notifications", detail: "Scan results, scheduled reminders and a warning when the disk is almost full.") {
                Switch(isOn: $notifications)
            }
            SettingRow(title: "Remind me to clean",
                       detail: "Prune checks quietly in the background and tells you when there's 1 GB+ to clean. Starts after your first scan.") {
                Segmented(selection: $schedule, options: [("off", "Off"), ("daily", "Daily"), ("weekly", "Weekly")])
            }
        }
        SettingsGroup(title: "Startup") {
            SettingRow(title: "Open at login") {
                Switch(isOn: Binding(get: { launchAtLogin }, set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        NSLog("Prune: login item: \(error)")
                    }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }))
            }
            SettingRow(title: "Scan automatically when Prune opens", detail: "Off by default. Prune only scans when you ask.") { Switch(isOn: $scanOnLaunch) }
        }
    }
}

struct ScanningSettings: View {
    @Environment(Store.self) private var store
    @AppStorage(Prefs.Key.staleDays) private var staleDays = 90
    @AppStorage(Prefs.Key.largeFileMB) private var largeFileMB = 100
    @AppStorage(Prefs.Key.useDefaultFolders) private var useDefaultFolders = true
    @State private var extraFolders = Prefs.extraFolders

    var body: some View {
        SettingsGroup(title: "Thresholds") {
            SettingRow(title: "A project is stale after", detail: "Counted from its last git commit.") {
                Segmented(selection: $staleDays, options: [(30, "30d"), (90, "90d"), (180, "6mo"), (365, "1y")])
            }
            SettingRow(title: "Large files start at") {
                Segmented(selection: $largeFileMB, options: [(50, "50 MB"), (100, "100 MB"), (500, "500 MB"), (1000, "1 GB")])
            }
        }

        if !store.ignored.isEmpty {
            SettingsGroup(title: "Hidden from scans") {
                ForEach(store.ignored, id: \.self) { path in
                    SettingRow(title: Fmt.tilde(path)) {
                        Button("Show again") { store.unignore(path) }.buttonStyle(.ghost)
                    }
                }
            }
        }
        SettingsGroup(title: "Project folders") {
            SettingRow(title: "Look in common folders",
                       detail: "~/" + Scanner.defaultRootNames.joined(separator: ", ~/")) {
                Switch(isOn: $useDefaultFolders)
            }
            ForEach(extraFolders, id: \.self) { path in
                SettingRow(title: Fmt.tilde(path)) {
                    Button {
                        extraFolders.removeAll { $0 == path }
                        Prefs.set(extraFolders, Prefs.Key.extraFolders)
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            SettingRow(title: "Add a folder…", detail: "Prune will look for projects inside it.") {
                Button("Choose") { pickFolder() }.buttonStyle(.secondary)
            }
        }

        HStack {
            Text("Changes apply on the next scan.").font(Theme.sans(12)).foregroundStyle(Theme.faint)
            Spacer()
            Button("Rescan now") {
                store.scan()
                store.tree = nil
                store.mapDisk()
            }
            .buttonStyle(.primary)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !extraFolders.contains(url.path) { extraFolders.append(url.path) }
        Prefs.set(extraFolders, Prefs.Key.extraFolders)
    }
}

struct PermissionSettings: View {
    @Environment(Store.self) private var store
    @State private var fda = FullDiskAccess.granted

    var body: some View {
        SettingsGroup(title: "Access") {
            SettingRow(title: "Full Disk Access",
                       detail: "Lets Prune see Mail, Messages, Safari and other protected folders. Without it the disk map is incomplete.") {
                if fda {
                    Badge(text: "Granted", color: Theme.green)
                } else {
                    Button("Open Settings") { FullDiskAccess.openSettings() }.buttonStyle(.secondary)
                }
            }
            SettingRow(title: "Docker", detail: dockerDetail) {
                Badge(text: dockerBadge.0, color: dockerBadge.1)
            }
        }
        SettingsGroup(title: "Safety") {
            SettingRow(title: "Everything goes to the Trash",
                       detail: "Prune never deletes files for good. Docker prune is the only exception and always asks first.") {
                Image(systemName: "checkmark.shield").foregroundStyle(Theme.green)
            }
            SettingRow(title: "Protected locations",
                       detail: "Anything outside your home folder, except whole apps in /Applications, is refused.") {
                Image(systemName: "checkmark.shield").foregroundStyle(Theme.green)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fda = FullDiskAccess.granted
        }
    }

    private var dockerDetail: String {
        switch store.dockerStatus {
        case .running: "Connected. Images, build cache and volumes are measured."
        case .notRunning: "Installed but not running. Start it to include Docker in scans."
        case .notInstalled: "Not found. Docker Desktop and OrbStack are supported."
        case .unknown: "Checked on the next scan."
        }
    }

    private var dockerBadge: (String, Color) {
        switch store.dockerStatus {
        case .running: ("Running", Theme.green)
        case .notRunning: ("Not running", Theme.amber)
        case .notInstalled: ("Not installed", Theme.faint)
        case .unknown: ("Unknown", Theme.faint)
        }
    }
}

struct AboutSettings: View {
    @AppStorage(Prefs.Key.didOnboard) private var didOnboard = false

    var body: some View {
        VStack(spacing: 10) {
            OrbView(size: 72, intro: true)
            Text("Prune").font(Theme.sans(20, .semibold)).foregroundStyle(Theme.text)
            Text(trf("Version %@", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"))
                .font(Theme.mono(12)).foregroundStyle(Theme.faint)
            Text("See what's taking space on your Mac and clean it safely.")
                .font(Theme.sans(13)).foregroundStyle(Theme.muted)
            Text("Open source under the MIT license.")
                .font(Theme.sans(12)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        SettingsGroup(title: "Help") {
            SettingRow(title: "Show the welcome tour again", detail: "Opens in the main window.") {
                Button("Show") { didOnboard = false }.buttonStyle(.secondary)
            }
        }
    }
}

/// Mini window preview for picking light, dark or system appearance.
private struct ThemeCard: View {
    let mode: String
    let title: String
    @Binding var selection: String
    @State private var hovering = false

    var body: some View {
        let selected = selection == mode
        Button { selection = mode } label: {
            VStack(spacing: 8) {
                ZStack {
                    switch mode {
                    case "light": preview(dark: false)
                    case "dark": preview(dark: true)
                    default:
                        HStack(spacing: 0) {
                            preview(dark: false).frame(width: 60, alignment: .leading).clipped()
                            preview(dark: true).frame(width: 60, alignment: .trailing).clipped()
                        }
                    }
                }
                .frame(width: 120, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Theme.blue : hovering ? Theme.borderStrong : Theme.border,
                                  lineWidth: selected ? 2 : 1))
                Text(tr(title))
                    .font(Theme.sans(12, selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.text : Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func preview(dark: Bool) -> some View {
        let bg = Color(nsColor: NSColor(hex: dark ? 0x191919 : 0xFAFAFA))
        let side = Color(nsColor: NSColor(hex: dark ? 0x2A2A2A : 0xECECEC))
        let line = Color(nsColor: NSColor(hex: dark ? 0x3A3A3A : 0xD9D9D9))
        let card = Color(nsColor: NSColor(hex: dark ? 0x222222 : 0xFFFFFF))
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { c in
                        Circle().fill(Color(nsColor: NSColor(hex: UInt32(c)))).frame(width: 4, height: 4)
                    }
                }
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(line).frame(width: i == 0 ? 26 : 20, height: 4)
                }
            }
            .padding(6)
            .frame(width: 40, height: 76, alignment: .topLeading)
            .background(side)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(line).frame(width: 34, height: 5)
                RoundedRectangle(cornerRadius: 3).fill(card)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(line, lineWidth: 0.5))
                    .frame(height: 26)
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(card).frame(height: 14)
                    RoundedRectangle(cornerRadius: 2).fill(card).frame(height: 14)
                }
            }
            .padding(7)
            .frame(width: 80, height: 76, alignment: .topLeading)
            .background(bg)
        }
    }
}
