import Foundation

/// Whose calendar this is. Google's secret iCal address carries the calendar owner's email
/// (`…/calendar/ical/<email>/private-…/basic.ics`); an explicit `myEmail` setting wins.
public enum CalendarIdentity {
    public static func email(fromICalURL string: String?) -> String? {
        guard let string, let url = URL(string: string) else { return nil }
        let parts = url.pathComponents   // percent-decoded
        guard let i = parts.firstIndex(of: "ical"), i + 1 < parts.count else { return nil }
        let candidate = parts[i + 1].lowercased()
        return candidate.contains("@") ? candidate : nil
    }

    public static func myEmail(setting: String, icalURL: String?) -> String {
        let s = setting.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s.isEmpty ? email(fromICalURL: icalURL) ?? "" : s
    }
}
