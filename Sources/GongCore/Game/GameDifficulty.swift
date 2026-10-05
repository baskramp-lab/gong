import Foundation

/// How shurikens spawn right now.
public struct SpawnParams: Equatable, Sendable {
    public let interval: Double
    public let speed: Double
    public let highChance: Double
    /// Unsurvivable: low + high from both sides every `interval`.
    public let wall: Bool
}

/// Harder the closer the meeting is; a light ramp within a run so a run far from the meeting still ends;
/// impossible once the meeting has started.
public enum GameDifficulty {
    static let fullAtMinutes = 5.0
    static let rampSeconds = 90.0
    static let rampWeight = 0.6

    public static func params(minutesToStart m: Double, runTime: Double) -> SpawnParams {
        if m <= 0 { return SpawnParams(interval: 0.25, speed: 120, highChance: 0.5, wall: true) }
        let p = min(max(1 - m / fullAtMinutes, 0), 1)
        let r = min(1, max(0, runTime) / rampSeconds)
        let d = max(p, rampWeight * r)
        return SpawnParams(interval: lerp(1.6, 0.35, d), speed: lerp(50, 110, d), highChance: lerp(0.3, 0.5, d), wall: false)
    }

    private static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }
}
