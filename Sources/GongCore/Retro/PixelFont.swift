import Foundation

/// Tiny 5×7 bitmap font for the "GONG!" burst, the game-over text and the game clock.
enum PixelFont {
    static let glyphWidth = 5
    static let glyphHeight = 7

    static let glyphs: [Character: [String]] = [
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
        "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
        "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
        "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
        "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
        ".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
        ":": [".....", "..#..", "..#..", ".....", "..#..", "..#..", "....."],
        "Æ": [".####", "#.#..", "#.#..", "#####", "#.#..", "#.#..", "#.###"],
        "Ø": [".###.", "#..##", "#.#.#", "#.#.#", "#.#.#", "##..#", ".###."],
        "Ł": ["#....", "#....", "#.#..", "##...", "#....", "#....", "#####"],
    ]

    /// Accented capitals: a base glyph plus a mark above (3 rows, drawn over rows −3…−1) and/or below (2 rows, 7…8).
    static let accented: [Character: (base: Character, above: [String]?, below: [String]?)] = {
        let acute = ["...#.", "..#..", "....."], grave = [".#...", "..#..", "....."]
        let circumflex = ["..#..", ".#.#.", "....."], caron = [".#.#.", "..#..", "....."]
        let tilde = [".##.#", "#..#.", "....."], diaeresis = [".....", ".#.#.", "....."]
        let ring = ["..#..", ".#.#.", "..#.."], dot = [".....", "..#..", "....."]
        let doubleAcute = ["..#.#", ".#.#.", "....."], breve = ["#...#", ".###.", "....."]
        let cedilla = ["..#..", ".##.."], ogonek = ["...#.", "....#"], commaBelow = ["..#..", ".#..."]
        var m: [Character: (Character, [String]?, [String]?)] = [:]
        for (ch, base) in zip("ÁÉÍÓÚÝĆĹŃŔŚŹ", "AEIOUYCLNRSZ") { m[ch] = (base, acute, nil) }
        for (ch, base) in zip("ÀÈÌÒÙ", "AEIOU") { m[ch] = (base, grave, nil) }
        for (ch, base) in zip("ÂÊÎÔÛ", "AEIOU") { m[ch] = (base, circumflex, nil) }
        for (ch, base) in zip("ČĎĚĽŇŘŠŤŽ", "CDELNRSTZ") { m[ch] = (base, caron, nil) }
        for (ch, base) in zip("ÃÑÕ", "ANO") { m[ch] = (base, tilde, nil) }
        for (ch, base) in zip("ÄËÏÖÜ", "AEIOU") { m[ch] = (base, diaeresis, nil) }
        for (ch, base) in zip("ÅŮ", "AU") { m[ch] = (base, ring, nil) }
        for (ch, base) in zip("İŻ", "IZ") { m[ch] = (base, dot, nil) }
        for (ch, base) in zip("ŐŰ", "OU") { m[ch] = (base, doubleAcute, nil) }
        for (ch, base) in zip("ĂĞ", "AG") { m[ch] = (base, breve, nil) }
        for (ch, base) in zip("ÇŞ", "CS") { m[ch] = (base, nil, cedilla) }
        for (ch, base) in zip("ĄĘ", "AE") { m[ch] = (base, nil, ogonek) }
        for (ch, base) in zip("ȘȚ", "ST") { m[ch] = (base, nil, commaBelow) }
        return m.mapValues { (base: $0.0, above: $0.1, below: $0.2) }
    }()

    /// True when every character of `text` can be drawn.
    static func canDraw(_ text: String) -> Bool { text.allSatisfy { glyphs[$0] != nil || accented[$0] != nil } }

    /// Glyph rows used above row 0 (accents) and below row 6 (cedillas, ogoneks) by `text`.
    static func extents(of text: String) -> (above: Int, below: Int) {
        let marks = text.compactMap { accented[$0] }
        return (marks.contains { $0.above != nil } ? 3 : 0, marks.contains { $0.below != nil } ? 2 : 0)
    }

    static func width(of text: String, scale: Int) -> Int {
        max(0, text.count * (glyphWidth + 1) * scale - scale)
    }

    /// `lower`: colour for the glyphs' bottom rows (from row 4), for a two-tone embossed look.
    static func draw(_ text: String, into c: inout PixelCanvas, x: Int, y: Int, scale: Int, color: RGBA, lower: RGBA? = nil) {
        for (i, ch) in text.enumerated() {
            let mark = accented[ch]
            guard let rows = glyphs[mark?.base ?? ch] else { continue }
            let ox = x + i * (glyphWidth + 1) * scale
            func stamp(_ rows: [String], from top: Int) {
                for (r, row) in rows.enumerated() {
                    let gy = top + r
                    for (gx, bit) in row.enumerated() where bit == "#" {
                        c.fillRect(x: ox + gx * scale, y: y + gy * scale, w: scale, h: scale, gy >= 4 ? lower ?? color : color)
                    }
                }
            }
            stamp(rows, from: 0)
            if let above = mark?.above { stamp(above, from: -above.count) }
            if let below = mark?.below { stamp(below, from: glyphHeight) }
        }
    }
}
