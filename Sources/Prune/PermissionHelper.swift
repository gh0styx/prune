import SwiftUI

/// Opens a Privacy & Security pane and shows a small floating card under the System Settings window
/// with Prune's icon to drag into the list there. Closes itself once the permission is granted,
/// when System Settings goes away, or when the user closes it.
@MainActor
enum PermissionHelper {
    enum Kind {
        case fullDiskAccess, accessibility, appManagement

        var url: String {
            switch self {
            case .fullDiskAccess: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            case .accessibility: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case .appManagement: AppPermissionLinks.appManagement
            }
        }

        /// nil when there is no reliable check (the card then stays until closed).
        var isGranted: Bool? {
            switch self {
            case .fullDiskAccess: FullDiskAccess.granted
            case .accessibility: AXIsProcessTrusted()
            case .appManagement: nil
            }
        }
    }

    private static var panel: NSPanel?
    private static var timer: Timer?
    private static var sawSettings = false

    static let size = NSSize(width: 460, height: 132)

    static func open(_ kind: Kind) {
        if let url = URL(string: kind.url) { NSWorkspace.shared.open(url) }
        close()
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DragToSettingsCard(onClose: { close() }))
        panel.setFrameOrigin(fallbackOrigin())
        panel.orderFrontRegardless()
        self.panel = panel
        sawSettings = false

        // Follow the System Settings window; close when access is granted or Settings is gone.
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated { tick(kind) }
        }
    }

    static func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func tick(_ kind: Kind) {
        guard let panel else { return }
        if kind.isGranted == true { close(); return }
        if let frame = settingsWindowFrame() {
            sawSettings = true
            if panel.frame != cardFrame(in: frame) { panel.setFrame(cardFrame(in: frame), display: true) }
        } else if sawSettings {
            close()   // System Settings was closed.
        }
    }

    /// Inside the bottom of the Settings window, lined up with the right-hand pane that holds the app list
    /// (System Settings' sidebar is about 230 pt wide; the list has a 20 pt inset).
    private static func cardFrame(in window: NSRect) -> NSRect {
        let sidebar: CGFloat = 230, inset: CGFloat = 20
        let width = max(320, window.width - sidebar - inset * 2)
        return NSRect(x: window.maxX - inset - width, y: window.minY + inset, width: width, height: size.height)
    }

    private static func fallbackOrigin() -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(x: screen.midX - size.width / 2, y: screen.minY + 40)
    }

    /// The main System Settings window in Cocoa coordinates (window bounds don't need Screen Recording access).
    private static func settingsWindowFrame() -> NSRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let windows = list.filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0
        }
        let frames = windows.compactMap { w -> CGRect? in
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        }
        guard let cg = frames.max(by: { $0.width * $0.height < $1.width * $1.height }), cg.width > 200 else { return nil }
        // CG has its origin at the top-left of the primary screen; Cocoa at the bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    }
}

/// "↑ Drag Prune into the list above" with a draggable app tile.
private struct DragToSettingsCard: View {
    let onClose: () -> Void
    private let appURL = Bundle.main.bundleURL
    private var appName: String {
        FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(trf("Drag %@ into the list above", appName), systemImage: "arrow.up")
                    .font(Theme.sans(14, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("Close"))
            }
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable().frame(width: 36, height: 36)
                Text(appName).font(Theme.sans(15, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "hand.draw").font(.system(size: 13)).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(Theme.text.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onDrag { NSItemProvider(object: appURL as NSURL) }
            .help(tr("Drag into the list in System Settings"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))
    }
}
