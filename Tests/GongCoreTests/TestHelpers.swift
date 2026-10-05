import Foundation

/// "2026-09-28T12:00:00Z" -> Date
func utc(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: iso)!
}

/// Wraps VEVENT-blocks in a minimal VCALENDAR.
func ics(_ body: String) -> String {
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:test\n" + body + "\nEND:VCALENDAR\n"
}

let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!
