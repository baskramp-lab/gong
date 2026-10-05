import Foundation

public struct JSONFile<T: Codable> {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load(default fallback: T) -> T {
        guard let data = try? Data(contentsOf: url) else { return fallback }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(T.self, from: data)) ?? fallback
    }

    /// Read-modify-write: re-reads the file (keeping edits made while the app runs), applies `change` and saves.
    /// A file that exists but does not decode is never overwritten; then nil is returned.
    @discardableResult
    public func update(default fallback: T, _ change: (inout T) -> Void) -> T? {
        var value = fallback
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do { value = try decoder.decode(T.self, from: data) } catch {
                NSLog("\(url.lastPathComponent) does not decode, left untouched: \(error)")
                return nil
            }
        }
        change(&value)
        do { try save(value) } catch { NSLog("\(url.lastPathComponent) save failed: \(error)"); return nil }
        return value
    }

    public func save(_ value: T) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
