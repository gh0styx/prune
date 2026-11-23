import Foundation
import Security

/// One thing the security check wants the user to know about.
struct SecurityFinding: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case launchAgent, launchDaemon, adware, `extension` }

    enum Severity: Int, Comparable, Sendable {
        case threat = 0, warning = 1, info = 2
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    /// Where the user goes to get rid of it.
    enum Removal: Sendable {
        /// Prune can move it to the Trash (a single plist in ~/Library/LaunchAgents).
        case trash
        /// A browser extension: remove it from the browser's extensions page.
        case browser
        /// Inside the home folder, but outside what Prune's trash rules allow: Finder.
        case finder
        /// A system-wide startup item: System Settings › General › Login Items.
        case loginItems
        /// A system-wide file that needs an admin password to remove.
        case admin
    }

    let id: String
    let kind: Kind
    let severity: Severity
    let title: String
    let detail: String
    let path: URL?
    let developer: String?
    /// Short reason shown in the badge ("Known adware", "Unsigned program", …). English; translate with tr().
    let reason: String
    let removal: Removal

    /// True when Prune itself can move it to the Trash.
    var canTrash: Bool { removal == .trash }
}

struct SystemProtection: Hashable, Sendable {
    var gatekeeper: Bool?
    var sip: Bool?
    var xprotectVersion: String?
    var fileVault: Bool?
    var firewall: Bool?
}

enum SecurityScanner {
    static func scan() -> (findings: [SecurityFinding], protection: SystemProtection) {
        var findings: [SecurityFinding] = []
        var seen = Set<String>()
        func add(_ f: SecurityFinding) { if seen.insert(f.id).inserted { findings.append(f) } }

        launchItems().forEach(add)
        adwareFolders().forEach(add)
        browserExtensions().forEach(add)
        safariExtensions().forEach(add)

        findings.sort {
            if $0.severity != $1.severity { return $0.severity < $1.severity }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        return (findings, protection())
    }

    // MARK: Known adware

    /// Name fragments used by common Mac adware and unwanted "cleaner" apps.
    /// Matched against names with spaces, dashes, dots and underscores removed.
    private static let adwareFragments = [
        "mackeeper", "advancedmaccleaner", "macautofixer", "searchmine", "searchbaron", "pirrit", "genieo",
        "installmac", "crossrider", "bundlore", "shlayer", "adload", "smartshow", "weknow", "chilltab",
        "mapsgalaxy", "operatorsearch", "searchoperator", "macsearch", "searchpulse", "safefinder",
        "mybrowserhelper", "comspigot", "comconduit", "conduitsearch", "comvsearch",
    ].map(normalize)

    /// Short names that only count as a whole word ("vsearch" but not "devsearch").
    /// Generic words like "operator", "spigot" or "conduit" are matched only as "com.<name>" above,
    /// because legitimate tools use them too.
    private static let adwareWords: Set<String> = ["vsearch"]

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The adware name a string matches, if any.
    static func adwareMatch(_ strings: [String]) -> String? {
        for s in strings where !s.isEmpty {
            let n = normalize(s)
            if let hit = adwareFragments.first(where: { n.contains($0) }) { return hit }
            let words = s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            if let hit = words.first(where: { adwareWords.contains($0) }) { return hit }
        }
        return nil
    }

    // MARK: Launch agents and daemons

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func launchItems() -> [SecurityFinding] {
        let dirs: [(URL, SecurityFinding.Kind, Bool)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .launchAgent, true),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .launchAgent, false),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .launchDaemon, false),
        ]
        var out: [SecurityFinding] = []
        for (dir, kind, isUser) in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "plist" {
                out.append(launchItem(file, kind: kind, isUser: isUser))
            }
        }
        return out
    }

    private static func launchItem(_ file: URL, kind: SecurityFinding.Kind, isUser: Bool) -> SecurityFinding {
        let plist = (try? Data(contentsOf: file)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        } ?? [:]
        let label = plist["Label"] as? String ?? file.deletingPathExtension().lastPathComponent
        let args = plist["ProgramArguments"] as? [String] ?? []
        let program = (plist["Program"] as? String) ?? args.first
        // Items registered by an app through SMAppService point inside that app; we can't resolve them here.
        let bundleProgram = plist["BundleProgram"] as? String

        let removal: SecurityFinding.Removal = isUser ? .trash : .loginItems
        let id = file.path
        let detail = program.map { Fmt.tilde($0) } ?? bundleProgram ?? Fmt.tilde(file.path)

        if adwareMatch([label, file.lastPathComponent, program ?? ""]) != nil {
            return SecurityFinding(id: id, kind: kind, severity: .threat, title: label, detail: detail, path: file,
                                   developer: program.flatMap { CodeSignature.read($0) }?.developer,
                                   reason: "Known adware", removal: isUser ? .trash : .admin)
        }

        guard let program, program.hasPrefix("/") else {
            // No absolute program path (an app-managed helper or a plain command name): nothing to check.
            return SecurityFinding(id: id, kind: kind, severity: .info, title: label, detail: detail, path: file,
                                   developer: nil, reason: "Startup item", removal: removal)
        }

        if !FileManager.default.fileExists(atPath: program) {
            return SecurityFinding(id: id, kind: kind, severity: .warning, title: label, detail: detail, path: file,
                                   developer: nil, reason: "Leftover: program is missing", removal: removal)
        }

        let sig = CodeSignature.read(program)
        switch sig.status {
        case .valid:
            return SecurityFinding(id: id, kind: kind, severity: .info, title: label, detail: detail, path: file,
                                   developer: sig.developer, reason: "Startup item", removal: removal)
        case .adhoc where sig.isHomebrew:
            return SecurityFinding(id: id, kind: kind, severity: .info, title: label, detail: detail, path: file,
                                   developer: "Homebrew", reason: "Startup item", removal: removal)
        case .unreadable:
            return SecurityFinding(id: id, kind: kind, severity: .info, title: label, detail: detail, path: file,
                                   developer: nil, reason: "Startup item", removal: removal)
        case .untrusted:
            return SecurityFinding(id: id, kind: kind, severity: .warning, title: label, detail: detail, path: file,
                                   developer: sig.developer, reason: "Not signed by a known developer", removal: removal)
        case .adhoc:
            return SecurityFinding(id: id, kind: kind, severity: .warning, title: label, detail: detail, path: file,
                                   developer: nil, reason: "Not signed by a known developer", removal: removal)
        case .unsigned:
            return SecurityFinding(id: id, kind: kind, severity: .warning, title: label, detail: detail, path: file,
                                   developer: nil, reason: "Unsigned program", removal: removal)
        case .invalid:
            return SecurityFinding(id: id, kind: kind, severity: .warning, title: label, detail: detail, path: file,
                                   developer: sig.developer, reason: "Signature is broken", removal: removal)
        }
    }

    // MARK: Adware folders and apps

    private static func adwareFolders() -> [SecurityFinding] {
        let places: [(URL, SecurityFinding.Removal)] = [
            (home.appendingPathComponent("Library/Application Support"), .finder),
            (URL(fileURLWithPath: "/Library/Application Support"), .admin),
            (URL(fileURLWithPath: "/Applications"), .admin),
            (home.appendingPathComponent("Applications"), .finder),
        ]
        var out: [SecurityFinding] = []
        for (dir, removal) in places {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in entries {
                let url = dir.appendingPathComponent(name)
                var strings = [name]
                if name.hasSuffix(".app"), let id = Bundle(url: url)?.bundleIdentifier { strings.append(id) }
                guard adwareMatch(strings) != nil else { continue }
                let title = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
                out.append(SecurityFinding(id: url.path, kind: .adware, severity: .threat, title: title,
                                           detail: Fmt.tilde(url.path), path: url,
                                           developer: name.hasSuffix(".app") ? CodeSignature.read(url.path).developer : nil,
                                           reason: "Known adware", removal: removal))
            }
        }
        return out
    }

    // MARK: Browser extensions

    private static func browserExtensions() -> [SecurityFinding] {
        let browsers: [(String, String)] = [
            ("Chrome", "Library/Application Support/Google/Chrome"),
            ("Brave", "Library/Application Support/BraveSoftware/Brave-Browser"),
            ("Edge", "Library/Application Support/Microsoft Edge"),
            ("Arc", "Library/Application Support/Arc/User Data"),
            ("Vivaldi", "Library/Application Support/Vivaldi"),
        ]
        let fm = FileManager.default
        var out: [SecurityFinding] = []
        for (browser, rel) in browsers {
            let root = home.appendingPathComponent(rel)
            let profiles = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
            // "Profile 9" -> the name the user gave it, from the browser's Local State.
            let info = (json(root.appendingPathComponent("Local State"))?["profile"] as? [String: Any])?["info_cache"] as? [String: Any]
            for profile in profiles {
                let extDir = root.appendingPathComponent(profile).appendingPathComponent("Extensions")
                guard let ids = try? fm.contentsOfDirectory(atPath: extDir.path) else { continue }
                for extID in ids where !extID.hasPrefix(".") && extID != "Temp" && !builtInExtensions.contains(extID) {
                    let idDir = extDir.appendingPathComponent(extID)
                    // Several versions can sit side by side while an update is pending; take the newest.
                    let versions = ((try? fm.contentsOfDirectory(atPath: idDir.path)) ?? [])
                        .filter { fm.fileExists(atPath: idDir.appendingPathComponent($0).appendingPathComponent("manifest.json").path) }
                        .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
                    guard let latest = versions.last else { continue }
                    let dir = idDir.appendingPathComponent(latest)
                    guard let manifest = json(dir.appendingPathComponent("manifest.json")) else { continue }
                    // Chrome's own built-in component extensions have no "update_url" and live elsewhere; skip themes.
                    if manifest["theme"] != nil { continue }
                    let name = localized(manifest["name"] as? String ?? extID, dir: dir, manifest: manifest)
                    let version = manifest["version"] as? String ?? latest
                    let shownProfile = ((info?[profile] as? [String: Any])?["name"] as? String) ?? profile
                    let profileName = profiles.filter({ fm.fileExists(atPath: root.appendingPathComponent($0).appendingPathComponent("Extensions").path) }).count > 1
                        ? " · \(shownProfile)" : ""
                    let hit = adwareMatch([name, extID])
                    out.append(SecurityFinding(
                        id: idDir.path + "#" + profile, kind: .extension,
                        severity: hit == nil ? .info : .threat,
                        title: name, detail: "\(browser)\(profileName) · \(version) · \(extID)",
                        path: idDir, developer: browser,
                        reason: hit == nil ? "Browser extension" : "Known adware", removal: .browser))
                }
            }
        }
        return out
    }

    /// Parts of Chrome itself that show up as extensions.
    private static let builtInExtensions: Set<String> = [
        "nmmhkkegccagdldgiimedpiccmgmieda", // Chrome Web Store Payments
        "pkedcjkdefgpdelpbcmbmeomcjbeemfm", // Chrome Media Router
        "mhjfbmdgcfjbbpaeojofohoefgiehjai", // Chrome PDF Viewer
    ]

    /// Resolves "__MSG_key__" names through the extension's _locales.
    private static func localized(_ name: String, dir: URL, manifest: [String: Any]) -> String {
        guard name.hasPrefix("__MSG_"), name.hasSuffix("__") else { return name }
        let key = String(name.dropFirst(6).dropLast(2)).lowercased()
        var locales = ["en", "en_US", "en_GB"]
        if let def = manifest["default_locale"] as? String { locales.append(def) }
        for loc in locales {
            guard let messages = json(dir.appendingPathComponent("_locales/\(loc)/messages.json")) else { continue }
            for (k, v) in messages where k.lowercased() == key {
                if let msg = (v as? [String: Any])?["message"] as? String, !msg.isEmpty { return msg }
            }
        }
        return name
    }

    private static func json(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Some manifests start with a UTF-8 BOM, which JSONSerialization rejects.
        let clean = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
        return (try? JSONSerialization.jsonObject(with: Data(clean))) as? [String: Any]
    }

    /// Safari web extensions are app extensions; pluginkit lists them read-only.
    private static func safariExtensions() -> [SecurityFinding] {
        guard let out = Shell.run("/usr/bin/pluginkit", ["-mAvv", "-p", "com.apple.Safari.web-extension"], timeout: 10) else { return [] }
        var findings: [SecurityFinding] = []
        for line in out.split(separator: "\n") {
            // "     +    com.example.ext(1.2)\tUUID\t2024-01-01 00:00:00 +0000\t/Applications/X.app/Contents/PlugIns/Ext.appex"
            let cols = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = cols.first, let path = cols.last, path.hasPrefix("/") else { continue }
            let ident = first.trimmingCharacters(in: CharacterSet(charactersIn: "+-=!? ")).components(separatedBy: "(").first ?? first
            let url = URL(fileURLWithPath: path)
            let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            let hit = adwareMatch([name, ident])
            findings.append(SecurityFinding(
                id: path, kind: .extension, severity: hit == nil ? .info : .threat,
                title: name, detail: "Safari · \(ident)", path: url,
                developer: CodeSignature.read(path).developer ?? "Safari",
                reason: hit == nil ? "Browser extension" : "Known adware",
                removal: path.hasPrefix(home.path + "/") ? .finder : .admin))
        }
        return findings
    }

    // MARK: System protection

    private static func protection() -> SystemProtection {
        var p = SystemProtection()
        if let s = capture("/usr/sbin/spctl", ["--status"])?.lowercased() {
            p.gatekeeper = s.contains("enabled") ? true : (s.contains("disabled") ? false : nil)
        }
        if let s = capture("/usr/bin/csrutil", ["status"])?.lowercased() {
            p.sip = s.contains("status: enabled") ? true : (s.contains("status: disabled") ? false : nil)
        }
        if let s = capture("/usr/bin/fdesetup", ["status"])?.lowercased() {
            p.fileVault = s.contains("filevault is on") ? true : (s.contains("filevault is off") ? false : nil)
        }
        if let s = capture("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])?.lowercased() {
            if s.contains("state = 0") || s.contains("disabled") { p.firewall = false }
            else if s.contains("enabled") || s.contains("state = 1") || s.contains("state = 2") { p.firewall = true }
        }
        for path in ["/Library/Apple/System/Library/CoreServices/XProtect.bundle",
                     "/System/Library/CoreServices/XProtect.bundle"] {
            let info = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
            if let d = NSDictionary(contentsOf: info), let v = d["CFBundleShortVersionString"] as? String {
                p.xprotectVersion = v
                break
            }
        }
        return p
    }

    /// stdout and stderr together, whatever the exit code (spctl exits 1 when Gatekeeper is off).
    private static func capture(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Code signature of a file, read with the Security framework (no codesign subprocess).
struct CodeSignature: Sendable {
    /// `untrusted`: a valid signature, but not from a certificate Apple issued (self-signed, as cracked apps often are).
    /// `unreadable`: the file is root-only, so it can't be checked without admin.
    enum Status: Sendable { case valid, adhoc, untrusted, unsigned, invalid, unreadable }
    var status: Status
    var teamID: String?
    /// "Google LLC", "Apple", … from the leaf certificate.
    var developer: String?
    var isHomebrew: Bool

    static func read(_ path: String) -> CodeSignature {
        let homebrew = path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/Cellar/") || path.hasPrefix("/usr/local/opt/")
        guard FileManager.default.isReadableFile(atPath: path) else {
            return CodeSignature(status: .unreadable, isHomebrew: homebrew)
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else {
            return CodeSignature(status: .unsigned, isHomebrew: homebrew)
        }
        var infoRef: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef)
        let info = infoRef as? [String: Any] ?? [:]

        let validity = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), nil)
        if validity == errSecCSUnsigned || info[kSecCodeInfoIdentifier as String] == nil {
            return CodeSignature(status: .unsigned, isHomebrew: homebrew)
        }

        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        var developer: String?
        if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first,
           let summary = SecCertificateCopySubjectSummary(leaf) as String? {
            developer = cleanName(summary)
        }
        if info[kSecCodeInfoPlatformIdentifier as String] != nil { developer = "Apple" }

        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdhoc = flags & 0x2 != 0 || (developer == nil && team == nil)

        let status: Status
        if validity != errSecSuccess { status = .invalid }
        else if isAdhoc { status = .adhoc }
        else if !issuedByApple(code) { status = .untrusted }
        else { status = .valid }
        let shown = developer.map { name in team.map { "\(name) (\($0))" } ?? name }
        return CodeSignature(status: status, teamID: team, developer: shown, isHomebrew: homebrew)
    }

    /// Developer ID, App Store and Apple's own signatures all chain to Apple's root.
    private static func issuedByApple(_ code: SecStaticCode) -> Bool {
        var req: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &req) == errSecSuccess, let req else { return true }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), req) == errSecSuccess
    }

    /// "Developer ID Application: Google LLC (EQHXZ8M8AV)" -> "Google LLC"; Apple's own chain -> "Apple".
    private static func cleanName(_ summary: String) -> String {
        if summary == "Software Signing" || summary.hasPrefix("Apple Mac OS Application Signing") { return "Apple" }
        var s = summary
        for prefix in ["Developer ID Application: ", "Apple Development: ", "Apple Distribution: ", "Mac Developer: ", "3rd Party Mac Developer Application: "] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        if let r = s.range(of: " (", options: .backwards), s.hasSuffix(")") { s = String(s[..<r.lowerBound]) }
        return s
    }
}
