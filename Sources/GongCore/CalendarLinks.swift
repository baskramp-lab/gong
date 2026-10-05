import Foundation

public enum CalendarLinks {
    /// Google Calendar event page: eid = base64("<eventId> <email>") without padding.
    public static func eventURL(calendarEventID: String, email: String) -> URL {
        let raw = Data("\(calendarEventID) \(email)".utf8).base64EncodedString()
        let eid = raw.replacingOccurrences(of: "=", with: "")
        return URL(string: "https://calendar.google.com/calendar/event?eid=\(eid)")!
    }

    /// Fallback: the day view for the meeting's date.
    public static func dayURL(for date: Date, timeZone: TimeZone = .current) -> URL {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return URL(string: "https://calendar.google.com/calendar/r/day/\(c.year!)/\(c.month!)/\(c.day!)")!
    }
}
