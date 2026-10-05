import Foundation

/// One RFC 5545 content line: NAME;PARAM=VALUE;...:VALUE
public struct ContentLine: Equatable {
    public let name: String             // uppercased
    public let params: [String: String] // keys uppercased, values unquoted
    public let value: String

    public init(name: String, params: [String: String], value: String) {
        self.name = name; self.params = params; self.value = value
    }

    /// Unfolds raw bytes (CRLF/LF + space/tab) before UTF-8 decoding, so a multi-byte character split
    /// across a fold survives. Invalid UTF-8 is decoded lossily instead of failing.
    public static func decode(_ data: Data) -> String {
        var out = Data(capacity: data.count)
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            let next = i + 1 < bytes.count ? bytes[i + 1] : nil
            let afterCRLF = i + 2 < bytes.count ? bytes[i + 2] : nil
            if b == 0x0A, next == 0x20 || next == 0x09 { i += 2; continue }
            if b == 0x0D, next == 0x0A, afterCRLF == 0x20 || afterCRLF == 0x09 { i += 3; continue }
            out.append(b)
            i += 1
        }
        return String(data: out, encoding: .utf8) ?? String(decoding: out, as: UTF8.self)
    }

    /// Normalises line endings and joins folded continuation lines (leading space/tab).
    public static func unfold(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            // Check the first scalar, not Character: " " + combining mark is one grapheme.
            if let first = line.unicodeScalars.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(line.unicodeScalars.dropFirst())
            } else if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    public static func parse(_ line: String) -> ContentLine? {
        var inQuotes = false
        var nameEnd: String.Index? = nil
        var valueStart: String.Index? = nil
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" {
                inQuotes.toggle()
            } else if !inQuotes {
                if c == ";" && nameEnd == nil { nameEnd = i }
                if c == ":" { valueStart = i; break }
            }
            i = line.index(after: i)
        }
        guard let valueStart else { return nil }
        let head = line[..<valueStart]
        let value = String(line[line.index(after: valueStart)...])
        var params: [String: String] = [:]
        let name: String
        if let nameEnd {
            name = String(head[..<nameEnd]).uppercased()
            let paramString = String(head[head.index(after: nameEnd)...])
            for part in splitOutsideQuotes(paramString, on: ";") {
                guard let eq = part.firstIndex(of: "=") else { continue }
                let key = String(part[..<eq]).uppercased()
                var val = String(part[part.index(after: eq)...])
                if val.count >= 2, val.hasPrefix("\""), val.hasSuffix("\"") {
                    val = String(val.dropFirst().dropLast())
                }
                params[key] = val
            }
        } else {
            name = String(head).uppercased()
        }
        return ContentLine(name: name, params: params, value: value)
    }

    static func splitOutsideQuotes(_ s: String, on sep: Character) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        for c in s {
            if c == "\"" { inQuotes.toggle(); current.append(c) }
            else if c == sep && !inQuotes { out.append(current); current = "" }
            else { current.append(c) }
        }
        out.append(current)
        return out
    }

    /// Reverses RFC 5545 TEXT escaping: \n \, \; \\
    public static func unescapeText(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "\\", let n = it.next() {
                switch n {
                case "n", "N": out.append("\n")
                case ",": out.append(",")
                case ";": out.append(";")
                case "\\": out.append("\\")
                default: out.append("\\"); out.append(n)
                }
            } else {
                out.append(c)
            }
        }
        return out
    }
}
