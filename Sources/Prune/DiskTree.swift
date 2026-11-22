import SwiftUI

// MARK: Treemap layout

enum Squarify {
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return values.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }
        var result: [CGRect] = []
        var r = rect
        var row: [Double] = []
        var i = 0
        while i < areas.count {
            let side = Double(min(r.width, r.height))
            let a = areas[i]
            if row.isEmpty || worst(row + [a], side) <= worst(row, side) {
                row.append(a)
                i += 1
            } else {
                r = place(row, in: r, into: &result)
                row = []
            }
        }
        if !row.isEmpty { _ = place(row, in: r, into: &result) }
        return result
    }

    private static func worst(_ row: [Double], _ side: Double) -> Double {
        let s = row.reduce(0, +)
        guard s > 0, let mx = row.max(), let mn = row.min(), mn > 0 else { return .infinity }
        return max(side * side * mx / (s * s), s * s / (side * side * mn))
    }

    private static func place(_ row: [Double], in r: CGRect, into result: inout [CGRect]) -> CGRect {
        let s = row.reduce(0, +)
        if r.width >= r.height {
            let w = CGFloat(s) / r.height
            var y = r.minY
            for a in row {
                let h = CGFloat(a) / w
                result.append(CGRect(x: r.minX, y: y, width: w, height: h))
                y += h
            }
            return CGRect(x: r.minX + w, y: r.minY, width: r.width - w, height: r.height)
        } else {
            let h = CGFloat(s) / r.width
            var x = r.minX
            for a in row {
                let w = CGFloat(a) / h
                result.append(CGRect(x: x, y: r.minY, width: w, height: h))
                x += w
            }
            return CGRect(x: r.minX, y: r.minY + h, width: r.width, height: r.height - h)
        }
    }
}
