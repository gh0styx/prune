import SwiftUI
import IOKit.pwr_mgt
import ApplicationServices

// MARK: - Keep awake

/// Keeps the Mac and its display awake through an IOKit power assertion, forever or for a set time.
/// The assertion dies with the process, so quitting Prune always lets the Mac sleep again.
@MainActor @Observable
final class KeepAwake {
    static let shared = KeepAwake()

    private(set) var isOn = false
    /// When the timer ends; nil means "until turned off".
    private(set) var until: Date?
    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?

    static let durations: [(label: String, minutes: Int?)] = [
        ("15 minutes", 15), ("1 hour", 60), ("2 hours", 120), ("5 hours", 300), ("Until turned off", nil),
    ]

    func toggle() { isOn ? stop() : start(minutes: nil) }

    func start(minutes: Int?) {
        if !isOn {
            let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Prune: Keep awake" as CFString, &assertion)
            guard ok == kIOReturnSuccess else { return }
        }
        isOn = true
        timer?.invalidate()
        timer = nil
        until = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        if let minutes {
            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { _ in
                Task { @MainActor in KeepAwake.shared.stop() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        until = nil
        if isOn { IOPMAssertionRelease(assertion) }
        assertion = 0
        isOn = false
    }
}

// MARK: - Keyboard cleaning

/// Locks the keyboard (including media and brightness keys) so it can be wiped. The mouse keeps working:
/// a full-screen overlay has the Done button, and the lock lifts on its own after `limit` seconds.
/// Needs Accessibility access for the event tap. Touch ID and the power button can't be blocked.
@MainActor @Observable
final class KeyboardCleaner {
    static let shared = KeyboardCleaner()
    static let limit = 90

    private(set) var isLocked = false
    private(set) var remaining = limit
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var overlays: [NSWindow] = []
    private var ticker: Timer?

    /// Whether Accessibility access is granted. Without it, opens the pane with a card to drag Prune into the list
    /// (instead of the system prompt, which only says "go to Settings").
    static func ensureAccess() -> Bool {
        if AXIsProcessTrusted() { return true }
        openAccessibilitySettings()
        return false
    }

    static func openAccessibilitySettings() { PermissionHelper.open(.accessibility) }

    /// Starts the lock. Returns false when Accessibility access is missing or the tap could not be created.
    @discardableResult
    func lock() -> Bool {
        guard !isLocked else { return true }
        guard Self.ensureAccess() else { return false }

        // 14 = NX_SYSDEFINED: volume, brightness, media and other special keys.
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        var mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        mask |= 1 << 14
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: keyboardTapCallback, userInfo: nil)
        else { return false }
        self.tap = tap
        keyboardTapPort = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isLocked = true
        remaining = Self.limit
        showOverlays()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                let c = KeyboardCleaner.shared
                c.remaining -= 1
                if c.remaining <= 0 { c.unlock() }
            }
        }
        return true
    }

    func unlock() {
        ticker?.invalidate()
        ticker = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        keyboardTapPort = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        isLocked = false
    }

    private func showOverlays() {
        for screen in NSScreen.screens {
            let window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: KeyboardCleaningOverlay())
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            overlays.append(window)
        }
    }
}

/// The tap's mach port, for re-enabling it from the C callback after macOS disables a slow tap.
nonisolated(unsafe) private var keyboardTapPort: CFMachPort?

/// Swallows every keyboard event while the lock is on.
private func keyboardTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = keyboardTapPort { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    return nil
}

private struct KeyboardCleaningOverlay: View {
    private var cleaner: KeyboardCleaner { .shared }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "keyboard")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Keyboard locked")
                    .font(Theme.sans(28, .semibold))
                    .foregroundStyle(.white)
                Text("Wipe it now. Keys do nothing until you click Done.")
                    .font(Theme.sans(14))
                    .foregroundStyle(.white.opacity(0.65))
                Button { cleaner.unlock() } label: {
                    // Background and hit shape inside the label, so the whole white button is clickable.
                    Text("Done").font(Theme.sans(15, .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 160, height: 40)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                Text(trf("Unlocks by itself in %lld s", cleaner.remaining))
                    .font(Theme.sans(12)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
                    .contentTransition(.numericText())
            }
        }
    }
}

// MARK: - Free memory

/// Runs `purge` (asks for the admin password) and reports how much memory it released.
@MainActor @Observable
final class MemoryFreer {
    static let shared = MemoryFreer()
    private(set) var isRunning = false
    private(set) var lastResult: String?

    func run() {
        guard !isRunning, let task = MaintenanceTask.all.first(where: { $0.id == "ram" }) else { return }
        isRunning = true
        lastResult = nil
        let before = SystemStats.memoryFree() ?? 0
        Task {
            let outcome = await Task.detached { MaintenanceRunner.execute(task) }.value
            SystemStats.shared.sample()
            switch outcome {
            case .done:
                MaintenanceRunner.markRun(task.id)
                let freed = (SystemStats.memoryFree() ?? 0) - before
                lastResult = freed > 0 ? trf("Freed %@", Fmt.memory(freed)) : tr("Done")
            case .cancelled: lastResult = nil
            case .failed: lastResult = tr("Failed")
            }
            isRunning = false
        }
    }
}

// MARK: - Trash

/// Size of the user's Trash and a way to empty it through Finder.
@MainActor @Observable
final class TrashTool {
    static let shared = TrashTool()
    /// nil while unknown (not measured yet, or no access to ~/.Trash).
    private(set) var size: Int64?
    private(set) var count = 0
    private(set) var isEmptying = false

    func refresh() {
        Task {
            let r = await Task.detached { TrashTool.measure() }.value
            size = r?.size
            count = r?.count ?? 0
        }
    }

    nonisolated static func measure(
        _ trash: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
    ) -> (size: Int64, count: Int)? {
        guard let top = try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) else { return nil }
        let items = top.filter { $0.lastPathComponent != ".DS_Store" }
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        var total: Int64 = 0
        for item in items {
            if let v = try? item.resourceValues(forKeys: keys), let s = v.totalFileAllocatedSize ?? v.fileAllocatedSize {
                total += Int64(s)
            }
            if let e = FileManager.default.enumerator(at: item, includingPropertiesForKeys: Array(keys), options: [],
                                                     errorHandler: { _, _ in true }) {
                while let u = e.nextObject() as? URL {
                    if let v = try? u.resourceValues(forKeys: keys), let s = v.totalFileAllocatedSize ?? v.fileAllocatedSize {
                        total += Int64(s)
                    }
                }
            }
        }
        return (total, items.count)
    }

    /// Asks first (emptying can't be undone), then has Finder empty the Trash.
    func confirmAndEmpty() {
        guard !isEmptying else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = tr("Empty the Trash?")
        alert.informativeText = size.map { trf("%@ will be deleted for good. This can't be undone.", Fmt.bytes($0)) }
            ?? tr("Everything in the Trash will be deleted for good. This can't be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: tr("Empty Trash"))
        alert.addButton(withTitle: tr("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let problem = AdminTrash.finderAutomationProblem() {
            let a = NSAlert()
            a.messageText = problem
            a.runModal()
            return
        }
        isEmptying = true
        var info: NSDictionary?
        // Finder empties in the background; don't wait for it here.
        _ = NSAppleScript(source: "tell application \"Finder\" to ignoring application responses\nempty trash\nend ignoring")?
            .executeAndReturnError(&info)
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                let r = await Task.detached { TrashTool.measure() }.value
                size = r?.size
                count = r?.count ?? 0
                if count == 0 { break }
            }
            isEmptying = false
        }
    }
}

// MARK: - Eject

/// External disks that can be ejected (USB sticks, SSDs, disk images, network shares).
@MainActor @Observable
final class EjectTool {
    static let shared = EjectTool()
    private(set) var disks: [URL] = []
    private(set) var isEjecting = false
    private(set) var failed: [String] = []

    func refresh() {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        disks = urls.filter { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsRootFileSystem != true,
                  !url.path.hasPrefix("/System/Volumes") else { return false }
            return v.volumeIsEjectable == true || v.volumeIsRemovable == true || v.volumeIsInternal == false
        }
    }

    func ejectAll() {
        guard !isEjecting, !disks.isEmpty else { return }
        isEjecting = true
        failed = []
        let targets = disks
        Task {
            let failures = await Task.detached {
                targets.compactMap { url -> String? in
                    do { try NSWorkspace.shared.unmountAndEjectDevice(at: url); return nil }
                    catch { return url.lastPathComponent }
                }
            }.value
            failed = failures
            isEjecting = false
            refresh()
        }
    }
}

// MARK: - Menu bar section

/// Quick toggles and one-click actions for the menu bar panel. Which ones show is set in Settings.
struct QuickToolsGrid: View {
    @AppStorage(Prefs.Key.menuKeepAwake) private var showAwake = true
    @AppStorage(Prefs.Key.menuKeyboard) private var showKeyboard = true
    @AppStorage(Prefs.Key.menuMemory) private var showMemory = true
    @AppStorage(Prefs.Key.menuTrash) private var showTrash = true
    @AppStorage(Prefs.Key.menuEject) private var showEject = true

    @State private var awake = KeepAwake.shared
    @State private var cleaner = KeyboardCleaner.shared
    @State private var memory = MemoryFreer.shared
    @State private var trash = TrashTool.shared
    @State private var eject = EjectTool.shared
    @State private var needsAccess = false

    var body: some View {
        let ejectShown = showEject && !eject.disks.isEmpty
        if showAwake || showKeyboard || showMemory || showTrash || ejectShown {
            VStack(spacing: 6) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    if showAwake { awakeTile }
                    if showKeyboard {
                        QuickToggle(symbol: "keyboard", color: Theme.teal, title: "Keyboard",
                                    subtitle: tr("Lock to wipe"), isOn: cleaner.isLocked) {
                            if !cleaner.lock() { needsAccess = true }
                        }
                    }
                    if showMemory {
                        QuickToggle(symbol: "memorychip", color: Theme.violet, title: "Memory",
                                    subtitle: memory.isRunning ? tr("Freeing…") : (memory.lastResult ?? tr("Free up")),
                                    isOn: memory.isRunning) { memory.run() }
                            .help(tr("Releases memory macOS is holding in its disk cache."))
                    }
                    if showTrash {
                        QuickToggle(symbol: trash.count > 0 ? "trash.fill" : "trash", color: Theme.red, title: "Trash",
                                    subtitle: trashSubtitle, isOn: trash.isEmptying) { trash.confirmAndEmpty() }
                            .disabled(trash.size != nil && trash.count == 0)
                    }
                    if ejectShown {
                        QuickToggle(symbol: "eject.fill", color: Theme.blue, title: "Disks",
                                    subtitle: ejectSubtitle, isOn: eject.isEjecting) { eject.ejectAll() }
                            .help(eject.disks.map(\.lastPathComponent).joined(separator: ", "))
                    }
                }
                if needsAccess {
                    HStack(spacing: 8) {
                        Text("Allow Prune in Accessibility to lock the keyboard.")
                            .font(Theme.sans(11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button(tr("Open Settings")) { KeyboardCleaner.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .onAppear { trash.refresh(); eject.refresh() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in eject.refresh() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in eject.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if needsAccess, AXIsProcessTrusted() { needsAccess = false }
            }
            .animation(.snappy, value: needsAccess)
            .animation(.snappy, value: ejectShown)
        }
    }

    private var awakeTile: some View {
        QuickToggle(symbol: awake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                    color: Theme.amber, title: "Keep awake",
                    subtitle: awakeSubtitle, isOn: awake.isOn) { awake.toggle() }
            .contextMenu {
                ForEach(KeepAwake.durations, id: \.label) { d in
                    Button(tr(d.label)) { awake.start(minutes: d.minutes) }
                }
                if awake.isOn {
                    Divider()
                    Button(tr("Turn off")) { awake.stop() }
                }
            }
            .help(tr("Click to toggle. Right-click for a timer."))
    }

    private var awakeSubtitle: String {
        guard awake.isOn else { return tr("Off") }
        guard let until = awake.until else { return tr("On") }
        return trf("Until %@", until.formatted(date: .omitted, time: .shortened))
    }

    private var trashSubtitle: String {
        if trash.isEmptying { return tr("Emptying…") }
        guard let size = trash.size else { return tr("Empty it") }
        return trash.count == 0 ? tr("Empty") : trf("Empty · %@", Fmt.bytes(size))
    }

    private var ejectSubtitle: String {
        if eject.isEjecting { return tr("Ejecting…") }
        if !eject.failed.isEmpty { return trf("Busy: %@", eject.failed.joined(separator: ", ")) }
        return eject.disks.count == 1 ? trf("Eject %@", eject.disks[0].lastPathComponent)
                                      : trf("Eject all %lld", eject.disks.count)
    }
}

private struct QuickToggle: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let isOn: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.inverse : color)
                    .frame(width: 28, height: 28)
                    .background(isOn ? color : color.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr(title)).font(Theme.sans(12, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(subtitle).font(Theme.sans(10.5)).foregroundStyle(.secondary).lineLimit(1)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.text.opacity(hovering && enabled ? 0.06 : 0)))
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.snappy, value: isOn)
    }
}
