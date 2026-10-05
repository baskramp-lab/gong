import Foundation

/// A pixel sprite written as text rows: one character per pixel, `.` is transparent,
/// any other character names a material (see `AutoShader`).
public struct SpriteGrid: Equatable {
    public let rows: [[Character]]

    public init(_ lines: [String]) {
        let w = lines.map(\.count).max() ?? 0
        rows = lines.map { Array($0) + Array(repeating: ".", count: w - $0.count) }
    }

    private init(rows: [[Character]]) { self.rows = rows }

    public var width: Int { rows.first?.count ?? 0 }
    public var height: Int { rows.count }
    public var lines: [String] { rows.map { String($0) } }

    public subscript(x: Int, y: Int) -> Character {
        guard y >= 0, y < height, x >= 0, x < rows[y].count else { return "." }
        return rows[y][x]
    }

    /// Rotates clockwise by `quarterTurns` × 90° (the 8-bit way to draw a salto).
    public func rotated(quarterTurns: Int) -> SpriteGrid {
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1: return SpriteGrid(rows: (0..<width).map { x in (0..<height).map { y in rows[height - 1 - y][x] } })
        case 2: return SpriteGrid(rows: rows.reversed().map { Array($0.reversed()) })
        case 3: return SpriteGrid(rows: (0..<width).map { x in (0..<height).map { y in rows[y][width - 1 - x] } })
        default: return self
        }
    }

    /// Moves the first `upperRows` rows one pixel down (breathing), keeping the rows below in place.
    public func sunk(upperRows: Int) -> SpriteGrid {
        let n = min(upperRows, height)
        guard n > 0 else { return self }
        let empty = [Character](repeating: ".", count: width)
        return SpriteGrid(rows: [empty] + rows[0..<(n - 1)] + rows[n...])
    }

    /// Stacks `b` below `a`.
    public static func + (a: SpriteGrid, b: SpriteGrid) -> SpriteGrid {
        SpriteGrid(a.lines + b.lines)
    }
}
