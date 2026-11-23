import SwiftUI

extension Store {
    // MARK: Background checks & notifications

    /// Runs every 30 minutes while Prune is open (it lives in the menu bar): low-disk alert and scheduled scans.
    func startBackgroundChecks() {
        guard !checksStarted else { return }
        checksStarted = true
        Notifier.shared.setup()
        Notifier.shared.onOpen = { [weak self] in self?.openMainWindow?() }
        Task {
            while true {
                try? await Task.sleep(for: .seconds(60))
                backgroundTick()
                try? await Task.sleep(for: .seconds(29 * 60))
            }
        }
    }

    private func backgroundTick() {
        disk = .current()
        let defaults = UserDefaults.standard

        // Low disk: under 10% free, at most once a day.
        if disk.total > 0, Double(disk.free) / Double(disk.total) < 0.10 {
            let last = defaults.object(forKey: Prefs.Key.lastLowDiskAlert) as? Date ?? .distantPast
            if Date().timeIntervalSince(last) > 86_400 {
                Prefs.set(Date(), Prefs.Key.lastLowDiskAlert)
                Notifier.shared.post("lowdisk", title: "Your disk is almost full",
                                     body: trf("Only %@ left. Open Prune to see what's taking space.", Fmt.bytes(disk.free)))
            }
        }

        // Scheduled scan, counted from the user's last manual scan (never before the first one).
        let interval: TimeInterval? = switch Prefs.schedule {
        case "daily": 86_400
        case "weekly": 7 * 86_400
        default: nil
        }
        if let interval, let last = defaults.object(forKey: Prefs.Key.lastScheduledScan) as? Date,
           Date().timeIntervalSince(last) > interval, !isScanning, !isCleaning {
            Prefs.set(Date(), Prefs.Key.lastScheduledScan)
            scan(scheduled: true)
        }
    }

    func notifyScanFinished() {
        let total = reclaimable
        if scheduledRun {
            if total > 1_000_000_000 {
                Notifier.shared.post("scheduled", title: trf("%@ can be cleaned", Fmt.bytes(total)),
                                     body: "Caches, logs and old dependencies piled up since your last check.")
            }
        } else if !NSApp.isActive {
            Notifier.shared.post("scan", title: tr("Scan finished"), body: trf("Found %@ you can clean.", Fmt.bytes(total)))
        }
    }
}
