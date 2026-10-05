import Foundation

public enum ICSDate {
    public struct Parsed: Equatable {
        public let date: Date
        public let isDateOnly: Bool
        public let timeZone: TimeZone
    }

    /// Parses `20260928T140000`, `20260928T120000Z` or `20260928`.
    /// - tzid: value of the TZID parameter (IANA name), if any.
    /// - isDateValue: true when `VALUE=DATE` was given.
    /// - defaultTZ: used for floating times and unknown TZIDs.
    public static func parse(_ value: String, tzid: String?, isDateValue: Bool, defaultTZ: TimeZone) -> Parsed? {
        let digits = value.filter { $0.isNumber }
        guard digits.count == 8 || digits.count >= 14 else { return nil }
        let isUTC = value.hasSuffix("Z")
        func n(_ offset: Int, _ len: Int) -> Int? { Int(digits.dropFirst(offset).prefix(len)) }
        guard let y = n(0, 4), let m = n(4, 2), let d = n(6, 2) else { return nil }

        let tz: TimeZone
        if isUTC { tz = TimeZone(identifier: "UTC")! }
        else { tz = tzid.flatMap { TimeZone(identifier: $0) } ?? defaultTZ }

        let dateOnly = isDateValue || digits.count == 8
        var comps = DateComponents(year: y, month: m, day: d)
        if !dateOnly {
            comps.hour = n(8, 2); comps.minute = n(10, 2); comps.second = n(12, 2)
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let date = cal.date(from: comps) else { return nil }
        return Parsed(date: date, isDateOnly: dateOnly, timeZone: tz)
    }
}
