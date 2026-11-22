import SwiftUI

/// What a scan was asked for while permissions were missing.
enum GatedAction { case scan, map }

/// Everything the scans need from macOS. Full Disk Access also covers Documents, Desktop,
/// Downloads, Mail and Messages, so it is the only one to check.
enum AppPermissions {
    static var allGranted: Bool { FullDiskAccess.granted }
}

/// Shown instead of starting a scan while a required permission is missing.
/// Re-checks when the user comes back from System Settings and then starts the scan itself.
struct PermissionGate: View {
    @Environment(Store.self) private var store
    @State private var granted = AppPermissions.allGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Allow Prune to see your disk")
                    .font(Theme.sans(17, .semibold))
                    .foregroundStyle(Theme.text)
                Text("A scan needs Full Disk Access. Without it macOS hides Mail, Messages, Safari data and some caches, and the results would be incomplete.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            Hairline()
            HStack(spacing: 14) {
                IconTile(symbol: "lock.shield", color: granted ? Theme.green : Theme.amber, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Full Disk Access").font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                    Text(granted ? "Granted. Prune can see everything in your home folder."
                                 : "System Settings → Privacy & Security → Full Disk Access → turn on Prune.")
                        .font(Theme.sans(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if granted { Badge(text: "Granted", color: Theme.green) }
            }
            .padding(20)
            .background(Theme.bg)
            Hairline()
            Text("Prune checks again when you return to the app.")
                .font(Theme.sans(12)).foregroundStyle(Theme.faint)
                .padding(.horizontal, 24).padding(.top, 14)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { store.gatedAction = nil }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                if granted {
                    Button("Start scan") { store.resumeGatedAction() }
                        .buttonStyle(.primary)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Check again") { recheck() }
                        .buttonStyle(.secondary)
                    Button("Open Settings") { FullDiskAccess.openSettings() }
                        .buttonStyle(.primary)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(20)
        }
        .frame(width: 540)
        .background(Theme.card)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in recheck() }
    }

    private func recheck() {
        granted = AppPermissions.allGranted
        if granted { store.resumeGatedAction() }
    }
}
