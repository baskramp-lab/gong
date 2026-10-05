import Foundation

public struct PersistedState: Codable, Equatable {
    public var states: [String: MeetingState]
    public var pauseUntil: Date?
    public init(states: [String: MeetingState] = [:], pauseUntil: Date? = nil) {
        self.states = states; self.pauseUntil = pauseUntil
    }
}
