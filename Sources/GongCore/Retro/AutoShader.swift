import Foundation

public struct ShadedPixel: Equatable {
    public let x: Int
    public let y: Int
    public let color: RGBA

    public init(x: Int, y: Int, color: RGBA) { self.x = x; self.y = y; self.color = color }
}

/// Turns a material silhouette into 16-bit style pixels, lit from the upper-left (the moon).
/// Each ramp is `[outline, shadow, base, highlight]`.
public enum AutoShader {
    public static func shade(_ grid: SpriteGrid, ramps: [Character: [RGBA]], fixed: [Character: RGBA]) -> [ShadedPixel] {
        var out: [ShadedPixel] = []
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let ch = grid[x, y]
                if ch == "." { continue }
                if let c = fixed[ch] { out.append(ShadedPixel(x: x, y: y, color: c)); continue }
                guard let ramp = ramps[ch], ramp.count == 4 else { continue }
                func empty(_ dx: Int, _ dy: Int) -> Bool { grid[x + dx, y + dy] == "." }
                func foreign(_ dx: Int, _ dy: Int) -> Bool {
                    let c = grid[x + dx, y + dy]
                    return c != "." && c != ch && fixed[c] == nil
                }
                let tone: Int
                if empty(1, 0) || empty(0, 1) { tone = 0 }                                   // dark outline, shadow side
                else if empty(-1, 0) || empty(0, -1) { tone = 1 }                            // soft edge, lit side
                else if empty(-1, -1) || empty(-2, -1) || empty(-1, -2) { tone = 3 }         // moon rim light
                else if empty(2, 1) || empty(1, 2) || empty(2, 2) || foreign(0, 1) || foreign(1, 0) { tone = 1 } // core shadow / occlusion
                else if empty(-2, 0) || empty(0, -2) { tone = 3 }
                else { tone = 2 }
                out.append(ShadedPixel(x: x, y: y, color: ramp[tone]))
            }
        }
        return out
    }
}
