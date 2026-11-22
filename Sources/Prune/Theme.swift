import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

/// Geist-like tokens: dark-gray canvas (like Claude/Codex), hairline borders, one accent per meaning.
enum Theme {
    static let bg = Color.dynamic(0xFAFAFA, 0x191919)
    static let sidebarEdge = Color.dynamic(0xBFBFC4, 0x4A4A4F)
    static let card = Color.dynamic(0xFFFFFF, 0x212121)
    static let border = Color.dynamic(0xEAEAEA, 0x2E2E2E)
    static let borderStrong = Color.dynamic(0xD4D4D4, 0x404040)
    static let hover = Color.dynamic(0xF2F2F2, 0x2A2A2A)
    static let active = Color.dynamic(0xEBEBEB, 0x303030)
    static let text = Color.dynamic(0x171717, 0xEDEDED)
    static let muted = Color.dynamic(0x666666, 0xA1A1A1)
    static let faint = Color.dynamic(0x8F8F8F, 0x7A7A7A)
    static let inverse = Color.dynamic(0xFFFFFF, 0x191919)

    static let blue = Color.dynamic(0x0068D6, 0x47A8FF)
    static let violet = Color.dynamic(0x7D4CDB, 0xA78BFA)
    static let pink = Color.dynamic(0xD6336C, 0xF472B6)
    static let amber = Color.dynamic(0xAD5700, 0xFFB224)
    static let cyan = Color.dynamic(0x0369A1, 0x38BDF8)
    static let teal = Color.dynamic(0x0E8A7E, 0x2DD4BF)
    static let gray = Color.dynamic(0x8F8F8F, 0x7A7A7A)
    static let green = Color.dynamic(0x297A3A, 0x4ADE80)
    static let red = Color.dynamic(0xDA2F35, 0xFF5A5F)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
