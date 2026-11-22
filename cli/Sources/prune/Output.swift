import Foundation

/// Terminal styling. Colors are dropped when stdout is not a terminal or NO_COLOR is set.
enum Style {
    static let enabled: Bool = isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func paint(_ s: String, _ code: String) -> String { enabled ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
    static func bold(_ s: String) -> String { paint(s, "1") }
    static func dim(_ s: String) -> String { paint(s, "2") }
    static func red(_ s: String) -> String { paint(s, "31") }
    static func green(_ s: String) -> String { paint(s, "32") }
    static func yellow(_ s: String) -> String { paint(s, "33") }
    static func cyan(_ s: String) -> String { paint(s, "36") }
}

func say(_ s: String = "") { print(s) }

/// Progress and warnings go to stderr so piping stdout (e.g. `prune history --json`) stays clean.
func note(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

func fail(_ s: String, code: Int32 = 1) -> Never {
    note(Style.red("prune: ") + s)
    exit(code)
}

func bytes(_ b: Int64) -> String { Fmt.bytes(b) }

/// Left-aligned text padded to `width` columns (padding is applied before colors are added).
func column(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func rightColumn(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}

/// A small horizontal bar for a fraction 0...1.
func bar(_ fraction: Double, width: Int = 24) -> String {
    let filled = max(0, min(width, Int((fraction * Double(width)).rounded())))
    let body = String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    return fraction > 0.9 ? Style.red(body) : fraction > 0.75 ? Style.yellow(body) : Style.green(body)
}

/// Asks a yes/no question on the terminal. Returns false when stdin is not interactive.
func confirm(_ question: String) -> Bool {
    guard isatty(STDIN_FILENO) != 0 else { return false }
    print(question + " " + Style.dim("[y/N] "), terminator: "")
    fflush(stdout)
    guard let answer = readLine() else { return false }
    return ["y", "yes", "д", "да"].contains(answer.trimmingCharacters(in: .whitespaces).lowercased())
}

func prompt(_ text: String) -> String? {
    print(text, terminator: "")
    fflush(stdout)
    return readLine()?.trimmingCharacters(in: .whitespaces)
}
