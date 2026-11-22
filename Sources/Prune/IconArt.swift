import AppKit
import SwiftUI

/// Single source for the app icon, the in-app logo and the menu bar glyph.
/// Motif: a pearl (your disk) with a bite taken out of it — space given back.
enum IconArt {
    private static func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor { NSColor(hex: hex, alpha: a).cgColor }
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private static func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    }

    // Geometry in the 1024 icon grid (y-up).
    static let orbCenter = CGPoint(x: 500, y: 500)
    static let orbRadius: CGFloat = 252
    static let biteRect = CGRect(x: 600, y: 600, width: 250, height: 250)
    static let dotRect = CGRect(x: 688, y: 688, width: 54, height: 54)

    /// Draws the orb, bite and dot without the tile background.
    /// "Pearl": a matte off-white sphere lit from the upper left, and one blue spark.
    static func drawMark(in ctx: CGContext, dark: Bool = true) {
        let orb = CGRect(x: orbCenter.x - orbRadius, y: orbCenter.y - orbRadius, width: orbRadius * 2, height: orbRadius * 2)

        ctx.saveGState()
        let outsideBite = CGMutablePath()
        outsideBite.addRect(CGRect(x: -2000, y: -2000, width: 5000, height: 5000))
        outsideBite.addEllipse(in: biteRect)
        ctx.addPath(outsideBite)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 40, color: color(0x000000, dark ? 0.55 : 0.28))
        ctx.addEllipse(in: orb)
        ctx.setFillColor(color(0x8A8A8A))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addEllipse(in: orb)
        ctx.clip()
        let bite = CGMutablePath()
        bite.addRect(CGRect(x: -2000, y: -2000, width: 5000, height: 5000))
        bite.addEllipse(in: biteRect)
        ctx.addPath(bite)
        ctx.clip(using: .evenOdd)
        ctx.drawRadialGradient(gradient(dark ? [color(0xFFFFFF), color(0xDADADA), color(0x7A7A7A)]
                                            : [color(0x76767C), color(0x2C2C30), color(0x0D0D0F)], [0, 0.55, 1]),
                               startCenter: CGPoint(x: 400, y: 620), startRadius: 0,
                               endCenter: CGPoint(x: 470, y: 540), endRadius: orbRadius * 1.25,
                               options: [.drawsAfterEndLocation])
        ctx.restoreGState()

        // The freed spark.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 26, color: color(0x3B82F6, 0.85))
        ctx.addEllipse(in: dotRect)
        ctx.setFillColor(color(0x3B82F6))
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Apple's continuous-corner tile (the same curve SwiftUI uses), on the 1024 grid of macOS icons.
    static func squircle(in r: CGRect) -> CGPath {
        RoundedRectangle(cornerRadius: r.width * 0.2237, style: .continuous).path(in: r).cgPath
    }

    /// Draws the full icon into a 1024×1024 y-up coordinate space.
    /// The tile matches macOS's own dark icons: lifted graphite gradient, bright top rim, soft drop shadow.
    static func drawIcon(in ctx: CGContext) { drawIcon(in: ctx, dark: true) }

    /// `dark` picks the tile for the Dock's dark or light icon appearance.
    static func drawIcon(in ctx: CGContext, dark: Bool) {
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = squircle(in: tile)

        // Drop shadow under the tile.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.4))
        ctx.addPath(tilePath)
        ctx.setFillColor(color(dark ? 0x1A1A1C : 0xE6E6EA))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.clip()
        ctx.drawLinearGradient(gradient(dark ? [color(0x3C3C40), color(0x232326), color(0x141416)]
                                             : [color(0xFFFFFF), color(0xF4F4F6), color(0xE4E4E8)], [0, 0.5, 1]),
                               start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
        // Soft top glow, like light hitting glass.
        ctx.drawRadialGradient(gradient([color(0xFFFFFF, dark ? 0.10 : 0.6), color(0xFFFFFF, 0)], [0, 1]),
                               startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 980), endRadius: 560, options: [])
        drawMark(in: ctx, dark: dark)
        ctx.restoreGState()

        // Rim light: bright along the top edge, faint at the bottom.
        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.setLineWidth(5)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient(dark ? [color(0xFFFFFF, 0.42), color(0xFFFFFF, 0.06), color(0xFFFFFF, 0.14)]
                                             : [color(0xFFFFFF, 0.9), color(0x000000, 0.05), color(0x000000, 0.14)], [0, 0.55, 1]),
                               start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
        ctx.restoreGState()
    }

    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Crop the transparent icon margin so the logo reads larger inside the UI.
            let s = rect.width / 824
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -100, y: -100)
            drawIcon(in: ctx)
            return true
        }
    }

    /// 18pt template glyph for the menu bar: the bitten orb and its dot.
    static let menuBarGlyph: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Map the 1024 grid region around the orb onto 18pt.
            let s: CGFloat = 18 / 700
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -180, y: -170)
            let r = orbRadius
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillEllipse(in: CGRect(x: orbCenter.x - r, y: orbCenter.y - r, width: r * 2, height: r * 2))
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: biteRect.insetBy(dx: -18, dy: -18))
            ctx.setBlendMode(.normal)
            ctx.addEllipse(in: dotRect.insetBy(dx: -10, dy: -10))
            ctx.fillPath()
            return true
        }
        img.isTemplate = true
        return img
    }()

    // MARK: Export

    static func renderPNG(pixels: Int, to url: URL, draw: (CGContext) -> Void = drawIcon) throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let gc = NSGraphicsContext(bitmapImageRep: rep)!
        let ctx = gc.cgContext
        ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let s = CGFloat(pixels) / 1024
        ctx.scaleBy(x: s, y: s)
        draw(ctx)
        gc.flushGraphics()
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    /// `Prune --render-icon <dir>` writes AppIcon.iconset, icon-1024.png and menubar.png into <dir>.
    static func exportIconset(to dir: URL) throws {
        let set = dir.appending(path: "AppIcon.iconset")
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            try renderPNG(pixels: base, to: set.appending(path: "icon_\(base)x\(base).png"))
            try renderPNG(pixels: base * 2, to: set.appending(path: "icon_\(base)x\(base)@2x.png"))
        }
        try renderPNG(pixels: 1024, to: dir.appending(path: "icon-1024.png"))
        try renderPNG(pixels: 1024, to: dir.appending(path: "icon-1024-light.png")) { drawIcon(in: $0, dark: false) }

        // Icon Composer bundle (macOS 26+): the system draws the glass tile and switches
        // light / dark / tinted appearances itself; we only provide the mark as a layer.
        let iconBundle = dir.appending(path: "AppIcon.icon")
        try FileManager.default.createDirectory(at: iconBundle.appending(path: "Assets"), withIntermediateDirectories: true)
        // Icon Composer's canvas is the whole tile (no margin), while drawMark is laid out on the classic
        // 824-in-1024 grid, so scale it up by 1024/824 to keep the orb's size relative to the tile.
        for (file, darkTile) in [("mark-dark.png", true), ("mark-light.png", false)] {
            try renderPNG(pixels: 1024, to: iconBundle.appending(path: "Assets/\(file)")) { ctx in
                ctx.translateBy(x: 512, y: 512)
                ctx.scaleBy(x: 1.4, y: 1.4) // 1024/824 to match the tile, plus a little extra presence
                ctx.translateBy(x: -508, y: -520) // centre the orb + spark visually
                drawMark(in: ctx, dark: darkTile)
            }
        }
        let iconJSON = """
        {
          "fill-specializations" : [
            { "value" : "system-light" },
            { "appearance" : "dark", "value" : "system-dark" }
          ],
          "groups" : [
            {
              "layers" : [ {
                "name" : "mark",
                "image-name-specializations" : [
                  { "value" : "mark-light.png" },
                  { "appearance" : "dark", "value" : "mark-dark.png" }
                ]
              } ],
              "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
              "translucency" : { "enabled" : false, "value" : 0.5 }
            }
          ],
          "supported-platforms" : { "squares" : [ "macOS" ] }
        }
        """
        try Data(iconJSON.utf8).write(to: iconBundle.appending(path: "icon.json"))
        if let tiff = menuBarGlyph.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: dir.appending(path: "menubar.png"))
        }
    }
}
