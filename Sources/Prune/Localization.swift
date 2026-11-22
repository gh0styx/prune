import AppKit

/// Translates an English UI string through the app's Localizable.strings (ru.lproj, …).
/// Missing keys fall back to the English text, so untranslated strings still read fine.
func tr(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Translates a format string (e.g. "%lld items") and fills it in.
func trf(_ format: String, _ args: CVarArg...) -> String {
    String(format: tr(format), locale: Lang.locale, arguments: args)
}

enum Lang {
    /// The language the UI actually uses (first match between the user's choice and our localizations).
    static var code: String { Bundle.main.preferredLocalizations.first ?? "en" }
    static var locale: Locale { Locale(identifier: code) }

    /// Starts a fresh copy of Prune and quits this one, so a new language applies everywhere.
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// Applies the language picked in Settings ("system", "en", "ru") before the UI starts.
    static func applyOverride() {
        let choice = UserDefaults.standard.string(forKey: Prefs.Key.language) ?? "system"
        if choice == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([choice], forKey: "AppleLanguages")
        }
    }
}

/// "5 items" with the right plural form for the UI language (Russian has three).
enum Noun: String {
    case item, file, app, staleProject, smallerItem

    var forms: (en: (String, String), ru: (String, String, String)) {
        switch self {
        case .item: (("item", "items"), ("элемент", "элемента", "элементов"))
        case .file: (("file", "files"), ("файл", "файла", "файлов"))
        case .app: (("app", "apps"), ("приложение", "приложения", "приложений"))
        case .staleProject: (("stale project", "stale projects"), ("заброшенный проект", "заброшенных проекта", "заброшенных проектов"))
        case .smallerItem: (("smaller item", "smaller items"), ("мелкий элемент", "мелких элемента", "мелких элементов"))
        }
    }
}

func plural(_ n: Int, _ noun: Noun) -> String {
    let number = n.formatted(.number.locale(Lang.locale))
    if Lang.code.hasPrefix("ru") {
        let f = noun.forms.ru
        let mod10 = n % 10, mod100 = n % 100
        let word = (mod10 == 1 && mod100 != 11) ? f.0 : ((2...4).contains(mod10) && !(12...14).contains(mod100)) ? f.1 : f.2
        return "\(number) \(word)"
    }
    return "\(number) \(n == 1 ? noun.forms.en.0 : noun.forms.en.1)"
}
