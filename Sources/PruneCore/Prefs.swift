import Foundation

/// UserDefaults-backed preferences. Readable from any thread; views bind the same keys with @AppStorage.
enum Prefs {
    enum Key {
        static let appearance = "appearance"
        static let didOnboard = "didOnboard"
        static let developerMode = "developerMode"
        static let showMenuBar = "showMenuBar"
        static let scanOnLaunch = "scanOnLaunch"
        static let staleDays = "staleDays"
        static let largeFileMB = "largeFileMB"
        static let useDefaultFolders = "useDefaultFolders"
        static let extraFolders = "extraFolders"
        static let ignoredPaths = "ignoredPaths"
        static let language = "language"        // "system" | "en" | "ru" | "uk"
        static let notifications = "notifications"
        static let schedule = "schedule"          // "off" | "daily" | "weekly"
        static let lastScheduledScan = "lastScheduledScan"
        static let lastLowDiskAlert = "lastLowDiskAlert"
    }

    private static var d: UserDefaults { .standard }

    static var staleDays: Int { positive(Key.staleDays, 90) }
    static var largeFileMB: Int { positive(Key.largeFileMB, 100) }
    static var useDefaultFolders: Bool { bool(Key.useDefaultFolders, true) }
    static var extraFolders: [String] { d.stringArray(forKey: Key.extraFolders) ?? [] }
    static var scanOnLaunch: Bool { bool(Key.scanOnLaunch, false) }
    static var developerMode: Bool { bool(Key.developerMode, false) }
    static var ignoredPaths: [String] { d.stringArray(forKey: Key.ignoredPaths) ?? [] }
    static var notifications: Bool { bool(Key.notifications, true) }
    static var schedule: String { d.string(forKey: Key.schedule) ?? "weekly" }

    static func set(_ value: Any?, _ key: String) { d.set(value, forKey: key) }

    private static func positive(_ key: String, _ fallback: Int) -> Int {
        let v = d.integer(forKey: key)
        return v > 0 ? v : fallback
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        // bool(forKey:) also understands "YES"/"1" strings from launch arguments.
        d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }
}
