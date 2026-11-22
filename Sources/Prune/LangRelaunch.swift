import AppKit

extension Lang {
    /// Starts a fresh copy of Prune and quits this one, so a new language applies everywhere.
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}
