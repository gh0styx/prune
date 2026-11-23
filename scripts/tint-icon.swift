// Recolors the neutral (grey) sphere of a Prune icon mark to an orange ramp, for the PruneTest build.
// Saturated pixels (the blue spark) are left as they are. Usage: swift tint-icon.swift <in.png> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3,
      let data = try? Data(contentsOf: URL(fileURLWithPath: args[1])),
      let rep = NSBitmapImageRep(data: data), let src = rep.cgImage else {
    fputs("usage: tint-icon.swift <in.png> <out.png>\n", stderr)
    exit(1)
}

let w = src.width, h = src.height, bytesPerRow = w * 4
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
pixels.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: bytesPerRow, space: space, bitmapInfo: bitmapInfo)!
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
}

// Dark rim, the brand orange at the middle, pale highlight at the top.
typealias Stop = (t: Double, r: Double, g: Double, b: Double)
let stops: [Stop] = [
    Stop(t: 0.0, r: 0x7A / 255.0, g: 0x2A / 255.0, b: 0x00 / 255.0),
    Stop(t: 0.55, r: 0xFF / 255.0, g: 0x7A / 255.0, b: 0x1A / 255.0),
    Stop(t: 1.0, r: 0xFF / 255.0, g: 0xD0 / 255.0, b: 0x9A / 255.0),
]

func ramp(_ t: Double) -> (Double, Double, Double) {
    for i in 1..<stops.count where t <= stops[i].t {
        let a = stops[i - 1], b = stops[i]
        let f = (t - a.t) / (b.t - a.t)
        return (a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f)
    }
    let last = stops[stops.count - 1]
    return (last.r, last.g, last.b)
}

var i = 0
while i < pixels.count {
    defer { i += 4 }
    let a = Double(pixels[i + 3]) / 255
    guard a > 0 else { continue }
    // Un-premultiply, then decide whether the pixel is neutral.
    let r = min(1, Double(pixels[i]) / 255 / a)
    let g = min(1, Double(pixels[i + 1]) / 255 / a)
    let b = min(1, Double(pixels[i + 2]) / 255 / a)
    guard max(r, g, b) - min(r, g, b) < 0.15 else { continue }
    let lum = 0.299 * r + 0.587 * g + 0.114 * b
    let (nr, ng, nb) = ramp(lum)
    pixels[i] = UInt8((nr * a * 255).rounded())
    pixels[i + 1] = UInt8((ng * a * 255).rounded())
    pixels[i + 2] = UInt8((nb * a * 255).rounded())
}

let provider = CGDataProvider(data: Data(pixels) as CFData)!
let out = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                  space: space, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
                  decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: args[2]))
