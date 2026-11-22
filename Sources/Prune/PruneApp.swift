import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            do {
                try IconArt.exportIconset(to: URL(fileURLWithPath: args[i + 1]))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
                exit(1)
            }
        }
        Lang.applyOverride()
        if let i = args.firstIndex(of: "--render-dmg-background"), i + 1 < args.count {
            do { try DmgArt.render(to: URL(fileURLWithPath: args[i + 1])); exit(0) } catch { exit(1) }
        }
        if args.contains("--selftest") {
            SelfTest.run()
            exit(0)
        }
        PruneApp.main()
    }
}

struct PruneApp: App {
    @State private var store = Store()

    init() {
        // Start Sparkle at launch so scheduled update checks run from the first session.
        _ = AppUpdater.shared
    }
    @AppStorage(Prefs.Key.appearance) private var appearance = "dark"
    @AppStorage(Prefs.Key.showMenuBar) private var showMenuBar = true

    private var scheme: ColorScheme? {
        switch appearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    var body: some Scene {
        Window("Prune", id: "main") {
            Group {
                // `--args -previewMenuBar YES` renders the menu bar panel in a window for screenshots.
                if UserDefaults.standard.bool(forKey: "previewMenuBar") {
                    MenuBarView()
                } else {
                    RootView()
                }
            }
                .environment(store)
                .appAppearance(appearance)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Quick scan") { store.scan() }
                    .keyboardShortcut("r")
                Button("Full scan") { store.fullScan() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }
            CommandGroup(replacing: .appSettings) {
                OpenSettingsButton()
            }
            CommandGroup(replacing: .sidebar) {
                Button(store.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    withAnimation(.snappy(duration: 0.3)) { store.sidebarVisible.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(store)
                .appAppearance(appearance)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environment(store)
                .appAppearance(appearance)
        } label: {
            MenuBarLabel().environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Opens the Settings window (a regular Window scene so it can hide its title bar).
struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Settings…") { SettingsOpener.open(openWindow) }
            .keyboardShortcut(",")
    }
}

enum SettingsOpener {
    @MainActor static func open(_ openWindow: OpenWindowAction) {
        openWindow(id: "settings")
        NSApp.activate()
    }
}

/// The menu bar icon. It lives for the whole app session, so it also starts background checks
/// and hands Store a way to open the main window (used when a notification is clicked).
struct MenuBarLabel: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: IconArt.menuBarGlyph)
            .task {
                store.openMainWindow = { [openWindow] in
                    openWindow(id: "main")
                    NSApp.activate()
                }
                store.startBackgroundChecks()
            }
    }
}

extension View {
    /// Applies Light / Dark / Match system to the whole app. SwiftUI's preferredColorScheme(nil) doesn't
    /// hand windows back to the system theme on macOS, so set NSApp.appearance directly (nil = follow system).
    func appAppearance(_ value: String) -> some View {
        onAppear { AppAppearance.apply(value) }
            .onChange(of: value) { _, new in AppAppearance.apply(new) }
    }
}

enum AppAppearance {
    private static var observer: NSKeyValueObservation?
    private static var following = false

    @MainActor static func apply(_ value: String) {
        following = false
        switch value {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default:
            NSApp.appearance = nil
            following = true
            // With NSApp.appearance == nil AppKit updates effectiveAppearance on an OS theme change, but
            // SwiftUI content keeps the old color scheme. Pinning the resolved appearance for one runloop
            // turn before releasing it makes SwiftUI re-resolve (same path as switching explicit -> system).
            if observer == nil {
                observer = NSApp.observe(\.effectiveAppearance) { _, _ in
                    DispatchQueue.main.async {
                        guard following, NSApp.appearance == nil else { return }
                        NSApp.appearance = NSApp.effectiveAppearance
                        DispatchQueue.main.async { if following { NSApp.appearance = nil } }
                    }
                }
            }
        }
    }
}
