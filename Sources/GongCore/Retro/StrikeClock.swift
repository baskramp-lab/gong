import Foundation

/// One clock for picture and sound: the ninja hits the gong at `start + leadIn + hit + n × cycle`.
public struct StrikeClock: Equatable, Sendable {
    public static let cycle: TimeInterval = 4
    public static let hit: TimeInterval = 0.82
    /// Idle (guard stance) after the modal opens, before the first leap starts.
    public static let leadIn: TimeInterval = 1

    public let start: Date

    public init(start: Date) { self.start = start }

    /// Seconds into the current cycle; during the lead-in (and before `start`) this is the idle end of a cycle.
    public func cycleTime(at date: Date) -> Double {
        (max(0, date.timeIntervalSince(start)) - Self.leadIn + Self.cycle).truncatingRemainder(dividingBy: Self.cycle)
    }

    /// The first strike strictly after `date`.
    public func nextStrike(after date: Date) -> Date {
        let first = Self.leadIn + Self.hit
        let sinceFirst = date.timeIntervalSince(start) - first
        if sinceFirst < 0 { return start.addingTimeInterval(first) }
        let n = (sinceFirst / Self.cycle).rounded(.down) + 1
        return start.addingTimeInterval(first + n * Self.cycle)
    }
}
