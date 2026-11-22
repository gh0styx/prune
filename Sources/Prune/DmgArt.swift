import AppKit

/// Background for the installer DMG window (660×400 pt): light canvas (Finder draws icon labels in
/// dark text, so a light background keeps them readable in both themes), a hint and a dashed arrow
/// from the app icon (left) to the Applications folder (right). `Prune --render-dmg-background <dir>`
/// writes background.png and background@2x.png.
enum DmgArt {
    static let size = CGSize(width: 660, height: 400)
    /// Icon centres in Finder coordinates (origin top-left); make-dmg.sh uses the same numbers.
    static let appCenter = CGPoint(x: 180, y: 210)
    static let applicationsCenter = CGPoint(x: 480, y: 210)

    static func render(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scale in [1, 2] {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                                       pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            draw(in: NSGraphicsContext.current!.cgContext)
            NSGraphicsContext.restoreGraphicsState()
            let name = scale == 1 ? "background.png" : "background@2x.png"
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appending(path: name))
        }
    }

    private static func draw(in ctx: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor { NSColor(hex: hex, alpha: a).cgColor }
        let w = size.width, h = size.height

        let bg = CGGradient(colorsSpace: space, colors: [c(0xFFFFFF), c(0xF1F1F3)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: h), end: .zero, options: [])
        // Soft blue light from the top, like the app's welcome screen.
        let glow = CGGradient(colorsSpace: space, colors: [c(0x3B82F6, 0.10), c(0x3B82F6, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: w / 2, y: h + 40), startRadius: 0,
                               endCenter: CGPoint(x: w / 2, y: h + 40), endRadius: 420, options: [])

        // Text (y-up coordinates).
        func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
            let attr = NSAttributedString(string: s, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .kern: size > 16 ? -0.4 : 0,
            ])
            let b = attr.size()
            attr.draw(at: NSPoint(x: (w - b.width) / 2, y: y))
        }
        text(tr("Drag Prune into Applications"), size: 20, weight: .semibold, color: NSColor(hex: 0x171717), y: h - 74)
        text(tr("Then open it from Launchpad or Spotlight."), size: 12.5, weight: .regular, color: NSColor(hex: 0x666666), y: h - 98)

        // Dashed arrow between the two icons (Finder y is top-down, flip it).
        let y = h - appCenter.y
        let x0 = appCenter.x + 84, x1 = applicationsCenter.x - 84
        ctx.setStrokeColor(c(0x000000, 0.28))
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [2, 8])
        ctx.move(to: CGPoint(x: x0, y: y))
        ctx.addLine(to: CGPoint(x: x1 - 6, y: y))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setLineWidth(2.5)
        ctx.move(to: CGPoint(x: x1 - 14, y: y + 9))
        ctx.addLine(to: CGPoint(x: x1, y: y))
        ctx.addLine(to: CGPoint(x: x1 - 14, y: y - 9))
        ctx.strokePath()

        // Footer hint for people who see Apple's "can't be opened" warning.
        text(tr("First launch: right-click Prune › Open, or System Settings › Privacy & Security › Open Anyway."),
             size: 10.5, weight: .regular, color: NSColor(hex: 0x8F8F8F), y: 52)
    }
}
