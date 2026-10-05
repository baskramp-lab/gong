import Foundation

public struct SchedulerConfig: Codable, Equatable {
    public var softMinutes: [Int]
    public var hardMinutes: Int
    public var snoozeMinutes: Int
    public var lateGraceMinutes: Int

    public init(softMinutes: [Int] = [30, 10], hardMinutes: Int = 5, snoozeMinutes: Int = 2, lateGraceMinutes: Int = 15) {
        self.softMinutes = softMinutes; self.hardMinutes = hardMinutes
        self.snoozeMinutes = snoozeMinutes; self.lateGraceMinutes = lateGraceMinutes
    }
}

public enum MeetingState: Codable, Equatable {
    case quiet
    case softSent(minutes: Int)   // lowest (most urgent) soft threshold already notified
    case blocking
    case snoozed(until: Date)
    case handled
}

public struct TickResult: Equatable {
    public struct Notification: Equatable {
        public let meeting: Meeting
        public let minutesBefore: Int
        public init(meeting: Meeting, minutesBefore: Int) { self.meeting = meeting; self.minutesBefore = minutesBefore }
    }
    public var notifications: [Notification] = []
    public var blocking: [Meeting] = []
    public init(notifications: [Notification] = [], blocking: [Meeting] = []) {
        self.notifications = notifications; self.blocking = blocking
    }
}

/// Decides, per meeting, whether to notify softly, block, or stay quiet. Pure apart from the injected clock.
public final class Scheduler {
    public private(set) var states: [String: MeetingState]
    public private(set) var pauseUntil: Date?
    public var config: SchedulerConfig
    private let now: () -> Date

    public init(config: SchedulerConfig = SchedulerConfig(), states: [String: MeetingState] = [:],
                pauseUntil: Date? = nil, now: @escaping () -> Date) {
        self.config = config; self.states = states; self.pauseUntil = pauseUntil; self.now = now
    }

    public var isPaused: Bool {
        guard let p = pauseUntil else { return false }
        return now() < p
    }

    public func pause(until: Date) { pauseUntil = until }
    public func resume() { pauseUntil = nil }

    public func snooze(_ id: String) {
        states[id] = .snoozed(until: now().addingTimeInterval(Double(config.snoozeMinutes) * 60))
    }

    public func handle(_ id: String) { states[id] = .handled }

    public func nextMeeting(in meetings: [Meeting]) -> Meeting? {
        let t = now()
        return meetings
            .filter { $0.start >= t && states[$0.id] != .handled }
            .min { $0.start < $1.start }
    }

    public func tick(meetings: [Meeting]) -> TickResult {
        let t = now()
        let ids = Set(meetings.map(\.id))
        // Keep the state of a meeting that is briefly missing (filter toggled, short feed) until a day after its start.
        states = states.filter { ids.contains($0.key) || (Self.start(ofID: $0.key).map { t.timeIntervalSince($0) < 86_400 } ?? false) }
        if let p = pauseUntil, t >= p { pauseUntil = nil }
        let paused = isPaused

        var result = TickResult()
        for m in meetings.sorted(by: { $0.start < $1.start }) {
            let state = states[m.id] ?? .quiet
            if state == .handled { continue }
            let minutesUntil = m.start.timeIntervalSince(t) / 60

            if paused {
                if m.start <= t { states[m.id] = .handled }
                continue
            }

            switch state {
            case .quiet, .softSent:
                if minutesUntil < -Double(config.lateGraceMinutes) || t > m.end {
                    states[m.id] = .handled
                } else if minutesUntil <= Double(config.hardMinutes) {
                    states[m.id] = .blocking
                    result.blocking.append(m)
                } else if let threshold = config.softMinutes.filter({ minutesUntil <= Double($0) }).min() {
                    var alreadySent: Int? = nil
                    if case .softSent(let sent) = state { alreadySent = sent }
                    if alreadySent == nil || threshold < alreadySent! {
                        states[m.id] = .softSent(minutes: threshold)
                        result.notifications.append(.init(meeting: m, minutesBefore: threshold))
                    }
                }
            case .snoozed(let until):
                if t > m.end {
                    states[m.id] = .handled
                } else if t >= until {
                    states[m.id] = .blocking
                    result.blocking.append(m)
                }
            case .blocking:
                if t > m.end {
                    states[m.id] = .handled
                } else {
                    result.blocking.append(m)
                }
            case .handled:
                break
            }
        }
        return result
    }

    /// Meeting ids are `uid/unixStart` (see `Event.id`).
    static func start(ofID id: String) -> Date? {
        guard let slash = id.lastIndex(of: "/"), let secs = Double(id[id.index(after: slash)...]) else { return nil }
        return Date(timeIntervalSince1970: secs)
    }
}
