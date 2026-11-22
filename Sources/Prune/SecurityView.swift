import SwiftUI

/// Startup items, browser extensions, known adware and the Mac's built-in protections.
/// Not an antivirus: it only looks where adware and unwanted software usually hide.
struct SecurityView: View {
    @Environment(Store.self) private var store
    @State private var findings: [SecurityFinding]?
    @State private var protection = SystemProtection()
    @State private var checkedAt: Date?
    @State private var scanning = false

    private var all: [SecurityFinding] { findings ?? [] }
    private var threats: [SecurityFinding] { all.filter { $0.severity == .threat } }
    private var warnings: [SecurityFinding] { all.filter { $0.severity == .warning } }
    private var startup: [SecurityFinding] { all.filter { $0.severity == .info && $0.kind != .extension } }
    private var extensions: [SecurityFinding] { all.filter { $0.severity == .info && $0.kind == .extension } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Security check", subtitle: CategoryID.security.blurb) {
                Button {
                    Task { await scan() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                        Text("Check again")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(scanning)
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 20)

            if findings == nil {
                VStack(spacing: 14) {
                    OrbView(size: 72, scanning: true)
                    Text("Checking startup items and extensions…").font(Theme.sans(14, .semibold)).foregroundStyle(Theme.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        statusCard.appear(0)
                        section("Threats", threats, delay: 0.04)
                        section("Needs a look", warnings, delay: 0.06)
                        section("Startup items", startup, delay: 0.08)
                        section("Browser extensions", extensions, delay: 0.1)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
                }
                .opacity(scanning ? 0.5 : 1)
                .animation(.easeOut(duration: 0.2), value: scanning)
            }
        }
        .task { if findings == nil { await scan() } }
        .onChange(of: store.isCleaning) { _, cleaning in
            // After the app's trash flow finishes, drop the items that are gone.
            guard !cleaning, findings != nil else { return }
            withAnimation(.snappy(duration: 0.3)) {
                findings?.removeAll { f in
                    guard f.canTrash, let url = f.path else { return false }
                    return !FileManager.default.fileExists(atPath: url.path)
                }
            }
        }
    }

    // MARK: Status

    private var statusCard: some View {
        let (symbol, color, title): (String, Color, String) =
            !threats.isEmpty ? ("xmark.shield.fill", Theme.red, trf("Threats found: %lld", threats.count))
            : !warnings.isEmpty ? ("exclamationmark.shield.fill", Theme.amber, trf("Items to look at: %lld", warnings.count))
            : ("checkmark.shield.fill", Theme.green, tr("No threats found"))

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                IconTile(symbol: symbol, color: color, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.sans(17, .semibold)).foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Text("Prune checks the places adware and unwanted software usually hide. It isn't an antivirus.")
                        .font(Theme.sans(12.5)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    if scanning {
                        HStack(spacing: 6) { Spinner(); Text("Checking…") }
                            .font(Theme.sans(12)).foregroundStyle(Theme.muted)
                    } else if let checkedAt {
                        Text(trf("Checked %@", Fmt.relative(checkedAt)))
                            .font(Theme.sans(12)).foregroundStyle(Theme.faint)
                    }
                }
            }
            Hairline()
            FlowLayout(spacing: 8, lineSpacing: 8) {
                chip("Gatekeeper", protection.gatekeeper)
                chip("SIP", protection.sip)
                chip("XProtect", protection.xprotectVersion != nil, value: protection.xprotectVersion)
                chip("FileVault", protection.fileVault)
                chip("Firewall", protection.firewall)
            }
        }
        .padding(18)
        .card()
    }

    private func chip(_ name: String, _ on: Bool?, value: String? = nil) -> some View {
        let color = on == true ? Theme.green : on == false ? Theme.amber : Theme.gray
        let text = value ?? (on == true ? tr("On") : on == false ? tr("Off") : tr("Unknown"))
        return HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(tr(name)).font(Theme.sans(12, .medium)).foregroundStyle(Theme.text)
            Text(verbatim: text).font(Theme.mono(11.5)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.hover, in: Capsule())
        .help(help(for: name))
    }

    private func help(for name: String) -> String {
        switch name {
        case "Gatekeeper": tr("Only lets apps from identified developers open.")
        case "SIP": tr("System Integrity Protection keeps system files read-only.")
        case "XProtect": tr("Apple's built-in malware signatures, updated in the background.")
        case "FileVault": tr("Encrypts the startup disk.")
        default: tr("Blocks incoming connections to apps you didn't allow.")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func section(_ title: String, _ list: [SecurityFinding], delay: Double) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SectionLabel(text: title)
                    Text(verbatim: "\(list.count)").font(Theme.mono(10.5, .medium)).foregroundStyle(Theme.faint)
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, f in
                        VStack(spacing: 0) {
                            if i > 0 { Hairline() }
                            FindingRow(finding: f) { remove(f) }
                        }
                        .appear(delay + Double(min(i, 14)) * 0.025)
                    }
                }
                .card()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: Actions

    private func scan() async {
        guard !scanning else { return }
        scanning = true
        let result = await Task.detached(priority: .userInitiated) { SecurityScanner.scan() }.value
        withAnimation(.snappy(duration: 0.3)) {
            findings = result.findings
            protection = result.protection
            checkedAt = Date()
            scanning = false
        }
    }

    /// Hands a user launch agent to the app's confirm-and-trash flow (with undo in History).
    private func remove(_ f: SecurityFinding) {
        guard f.canTrash, let url = f.path else { return }
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey])
        let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        let item = CleanItem(url: url, category: .security, name: f.title, kind: tr("Launch agent"),
                             location: Fmt.tilde(url.deletingLastPathComponent().path), size: size,
                             lastActivity: values?.contentModificationDate, isStale: false)
        store.requestClean([item])
    }
}

private struct FindingRow: View {
    let finding: SecurityFinding
    let onRemove: () -> Void

    var body: some View {
        HoverRow {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, color: color, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(verbatim: finding.title).font(Theme.sans(13, .medium)).foregroundStyle(Theme.text)
                            .lineLimit(1).truncationMode(.middle)
                        Badge(text: finding.reason, color: color)
                    }
                    Text(verbatim: finding.detail).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 6) {
                        if let dev = finding.developer {
                            Label { Text(verbatim: dev) } icon: { Image(systemName: "checkmark.seal") }
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                        }
                        if let hint {
                            if finding.developer != nil { Text(verbatim: "·") }
                            Text(hint).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(Theme.sans(11.5)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 12)
                if finding.removal == .loginItems {
                    Button("Login Items") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(PruneButtonStyle(kind: .ghost, height: 28))
                }
                if let url = finding.path {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(PruneButtonStyle(kind: .ghost, height: 28))
                }
                if finding.canTrash {
                    Button("Remove…", action: onRemove)
                        .buttonStyle(PruneButtonStyle(kind: finding.severity == .threat ? .danger : .secondary, height: 28))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
        }
        .contextMenu {
            if let url = finding.path {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Copy path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            }
        }
    }

    private var color: Color {
        switch finding.severity {
        case .threat: Theme.red
        case .warning: Theme.amber
        case .info: finding.kind == .extension ? Theme.violet : Theme.blue
        }
    }

    private var symbol: String {
        switch finding.kind {
        case .launchAgent: "clock.arrow.circlepath"
        case .launchDaemon: "gearshape.2.fill"
        case .adware: "exclamationmark.triangle.fill"
        case .extension: "puzzlepiece.extension.fill"
        }
    }

    /// How to get rid of it when Prune can't (or shouldn't) do it here.
    private var hint: String? {
        guard finding.severity != .info else { return nil }
        switch finding.removal {
        case .trash: return nil
        case .browser: return tr("Remove it on the browser's Extensions page")
        case .finder: return tr("Quit the app, then move it to the Trash in Finder")
        case .loginItems: return tr("Remove from System Settings › General › Login Items")
        case .admin: return tr("Requires admin; remove in Finder")
        }
    }
}
