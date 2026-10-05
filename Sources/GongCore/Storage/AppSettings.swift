import Foundation

public struct AppSettings: Codable, Equatable {
    public var softMinutes: [Int] = [30, 10]
    public var hardMinutes: Int = 5
    public var snoozeMinutes: Int = 2
    public var lateGraceMinutes: Int = 15
    public var soundEnabled: Bool = true
    public var refreshMinutes: Int = 5
    public var staleMinutes: Int = 15
    /// Empty: taken from the secret iCal URL (see `CalendarIdentity`). Set it when the URL does not carry it.
    public var myEmail: String = ""
    public var includeUnaccepted: Bool = true    // also alert for invitations I haven't accepted yet
    public var bestGameScore: Int = 0        // ninja-game record in points (easter egg)

    public static let `default` = AppSettings()

    public init() {}

    public var schedulerConfig: SchedulerConfig {
        SchedulerConfig(softMinutes: softMinutes, hardMinutes: hardMinutes, snoozeMinutes: snoozeMinutes, lateGraceMinutes: lateGraceMinutes)
    }

    enum CodingKeys: String, CodingKey {
        case softMinutes, hardMinutes, snoozeMinutes, lateGraceMinutes, soundEnabled, refreshMinutes, staleMinutes, myEmail, includeUnaccepted, bestGameScore
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        softMinutes = try c.decodeIfPresent([Int].self, forKey: .softMinutes) ?? d.softMinutes
        hardMinutes = try c.decodeIfPresent(Int.self, forKey: .hardMinutes) ?? d.hardMinutes
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? d.snoozeMinutes
        lateGraceMinutes = try c.decodeIfPresent(Int.self, forKey: .lateGraceMinutes) ?? d.lateGraceMinutes
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? d.soundEnabled
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? d.refreshMinutes
        staleMinutes = try c.decodeIfPresent(Int.self, forKey: .staleMinutes) ?? d.staleMinutes
        myEmail = try c.decodeIfPresent(String.self, forKey: .myEmail) ?? d.myEmail
        includeUnaccepted = try c.decodeIfPresent(Bool.self, forKey: .includeUnaccepted) ?? d.includeUnaccepted
        bestGameScore = try c.decodeIfPresent(Int.self, forKey: .bestGameScore) ?? d.bestGameScore
    }
}
