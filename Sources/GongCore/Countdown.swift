import Foundation

public enum Countdown {
    public static func timeString(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_GB")   // 24-hour HH:mm in every language
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// "starts at 14:00 — in 4 min" / "starts at 14:00 — in less than 1 min" / "starting now — 14:00" / "started 2 min ago — 14:00"
    public static func text(start: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let time = timeString(start, timeZone: timeZone)
        let seconds = start.timeIntervalSince(now)
        if seconds > 0 {
            let minutes = Int(seconds / 60)
            return minutes >= 1 ? L("starts at %1$@ — in %2$d min", time, minutes) : L("starts at %@ — in less than 1 min", time)
        }
        let minutesAgo = Int(-seconds / 60)
        return minutesAgo >= 1 ? L("started %1$d min ago — %2$@", minutesAgo, time) : L("starting now — %@", time)
    }
}
