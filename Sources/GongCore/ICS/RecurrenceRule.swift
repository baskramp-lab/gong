import Foundation

public struct RecurrenceRule: Equatable {
    public enum Frequency: String { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

    /// weekday uses Calendar convention: 1 = Sunday … 7 = Saturday. ordinal e.g. 2 for "2TU", -1 for "-1FR".
    public struct ByDay: Equatable {
        public let ordinal: Int?
        public let weekday: Int

        static let names = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

        static func parse(_ s: Substring) -> ByDay? {
            let str = String(s).uppercased()
            guard str.count >= 2, let wd = names[String(str.suffix(2))] else { return nil }
            let ordText = str.dropLast(2)
            if ordText.isEmpty { return ByDay(ordinal: nil, weekday: wd) }
            guard let ord = Int(ordText), ord != 0 else { return nil }
            return ByDay(ordinal: ord, weekday: wd)
        }
    }

    public let frequency: Frequency
    public let interval: Int
    public let count: Int?
    public let until: Date?
    public let byDay: [ByDay]
    public let byMonthDay: [Int]
    public let byMonth: [Int]
    /// WKST as a Calendar weekday (default Monday).
    public let weekStart: Int

    /// Parts we cannot expand correctly; a rule using them is rejected rather than expanded wrongly.
    static let unsupportedParts = ["BYSETPOS", "BYWEEKNO", "BYYEARDAY", "BYHOUR", "BYMINUTE", "BYSECOND"]

    /// Returns nil for unsupported FREQ (HOURLY, …), unsupported parts (BYSETPOS, …) or a rule without FREQ.
    public static func parse(_ text: String, defaultTZ: TimeZone) -> RecurrenceRule? {
        var parts: [String: String] = [:]
        for kv in text.split(separator: ";") {
            let p = kv.split(separator: "=", maxSplits: 1)
            if p.count == 2 { parts[String(p[0]).uppercased()] = String(p[1]) }
        }
        guard let freq = parts["FREQ"].flatMap({ Frequency(rawValue: $0.uppercased()) }),
              !unsupportedParts.contains(where: { parts[$0] != nil }) else { return nil }
        let interval = max(1, parts["INTERVAL"].flatMap { Int($0) } ?? 1)
        let count = parts["COUNT"].flatMap { Int($0) }
        let until: Date? = parts["UNTIL"].flatMap { raw in
            guard let p = ICSDate.parse(raw, tzid: nil, isDateValue: raw.count == 8, defaultTZ: defaultTZ) else { return nil }
            return p.isDateOnly ? p.date.addingTimeInterval(86_399) : p.date
        }
        let byDay = (parts["BYDAY"] ?? "").split(separator: ",").compactMap(ByDay.parse)
        let byMonthDay = (parts["BYMONTHDAY"] ?? "").split(separator: ",").compactMap { Int($0) }.filter { $0 != 0 && abs($0) <= 31 }
        let byMonth = (parts["BYMONTH"] ?? "").split(separator: ",").compactMap { Int($0) }.filter { (1...12).contains($0) }
        let weekStart = parts["WKST"].flatMap { ByDay.names[$0.uppercased()] } ?? 2
        // YEARLY;BYDAY without BYMONTH means "every Monday of the year" / "20th Monday": not supported.
        if freq == .yearly, !byDay.isEmpty, byMonth.isEmpty { return nil }
        return RecurrenceRule(frequency: freq, interval: interval, count: count, until: until, byDay: byDay,
                              byMonthDay: byMonthDay, byMonth: byMonth, weekStart: weekStart)
    }

    /// Expands occurrences. Only dates in [windowStart, windowEnd] are returned,
    /// but COUNT counts every occurrence since dtstart.
    public func occurrences(from dtstart: Date, timeZone: TimeZone, windowStart: Date, windowEnd: Date, maxPeriods: Int = 2000) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var out: [Date] = []
        var produced = 0

        // COUNT must count every occurrence since dtstart, so it always walks from period 0. Without COUNT,
        // an old series (e.g. a DAILY rule that started years ago) would otherwise need to walk thousands of
        // periods just to reach the window — jump close to the window instead, one period early to stay safe
        // around DST shifts and BYDAY offsets.
        let startIndex: Int
        if count == nil {
            let periods: Int
            switch frequency {
            case .daily:
                periods = Int((windowStart.timeIntervalSince(dtstart) / (Double(interval) * 86400)).rounded(.down))
            case .weekly:
                periods = Int((windowStart.timeIntervalSince(dtstart) / (Double(interval) * 7 * 86400)).rounded(.down))
            case .monthly:
                periods = (cal.dateComponents([.month], from: dtstart, to: windowStart).month ?? 0) / interval
            case .yearly:
                periods = (cal.dateComponents([.year], from: dtstart, to: windowStart).year ?? 0) / interval
            }
            startIndex = max(0, periods - 1)
        } else {
            startIndex = 0
        }

        for periodIndex in startIndex..<(startIndex + maxPeriods) {
            let candidates = candidateDates(periodIndex: periodIndex, dtstart: dtstart, cal: cal)
                .filter { byMonth.isEmpty || byMonth.contains(cal.component(.month, from: $0)) }
                .sorted()
            for d in candidates {
                if d < dtstart { continue }
                if let until, d > until { return out }
                if d > windowEnd { return out }
                produced += 1
                if let count, produced > count { return out }
                if d >= windowStart { out.append(d) }
            }
        }
        return out
    }

    private func candidateDates(periodIndex: Int, dtstart: Date, cal: Calendar) -> [Date] {
        switch frequency {
        case .daily:
            guard let d = cal.date(byAdding: .day, value: periodIndex * interval, to: dtstart) else { return [] }
            let weekday = cal.component(.weekday, from: d)
            if !byDay.isEmpty, !byDay.contains(where: { $0.weekday == weekday }) { return [] }
            if !byMonthDay.isEmpty, !monthDays(of: d, cal: cal).contains(cal.component(.day, from: d)) { return [] }
            return [d]

        case .weekly:
            guard let anchor = cal.date(byAdding: .weekOfYear, value: periodIndex * interval, to: dtstart) else { return [] }
            if byDay.isEmpty { return [anchor] }
            let offset = (cal.component(.weekday, from: anchor) - weekStart + 7) % 7
            guard let weekBegin = cal.date(byAdding: .day, value: -offset, to: anchor) else { return [] }
            return byDay.compactMap { cal.date(byAdding: .day, value: ($0.weekday - weekStart + 7) % 7, to: weekBegin) }

        case .monthly:
            let start = cal.dateComponents([.year, .month], from: dtstart)
            let months = start.month! - 1 + periodIndex * interval
            return datesInMonth(year: start.year! + months / 12, month: months % 12 + 1, dtstart: dtstart, cal: cal)

        case .yearly:
            let start = cal.dateComponents([.year, .month], from: dtstart)
            let year = start.year! + periodIndex * interval
            return (byMonth.isEmpty ? [start.month!] : byMonth)
                .flatMap { datesInMonth(year: year, month: $0, dtstart: dtstart, cal: cal) }
        }
    }

    /// Occurrences in one month at dtstart's wall-clock time: BYMONTHDAY (intersected with BYDAY), else BYDAY,
    /// else dtstart's day of month. Days that do not exist in the month are skipped.
    private func datesInMonth(year: Int, month: Int, dtstart: Date, cal: Calendar) -> [Date] {
        var base = cal.dateComponents([.hour, .minute, .second], from: dtstart)
        base.year = year; base.month = month; base.day = 1
        guard let first = cal.date(from: base), let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        func date(_ day: Int) -> Date? {
            guard range.contains(day) else { return nil }
            var c = base; c.day = day
            return cal.date(from: c)
        }
        let days: [Int]
        if !byMonthDay.isEmpty {
            days = resolve(byMonthDay, lastDay: range.count).filter { day in
                byDay.isEmpty || byDay.contains { $0.weekday == date(day).map { cal.component(.weekday, from: $0) } }
            }
        } else if !byDay.isEmpty {
            days = byDay.flatMap { bd -> [Int] in
                let matches = range.filter { day in date(day).map { cal.component(.weekday, from: $0) } == bd.weekday }
                guard let ord = bd.ordinal else { return matches }
                let index = ord > 0 ? ord - 1 : matches.count + ord
                return matches.indices.contains(index) ? [matches[index]] : []
            }
        } else {
            days = [cal.component(.day, from: dtstart)]
        }
        return Set(days).compactMap(date)
    }

    /// BYMONTHDAY values as actual days of the month containing `date` (negative counts from the end).
    private func monthDays(of date: Date, cal: Calendar) -> [Int] {
        resolve(byMonthDay, lastDay: cal.range(of: .day, in: .month, for: date)?.count ?? 31)
    }

    private func resolve(_ monthDays: [Int], lastDay: Int) -> [Int] {
        monthDays.map { $0 > 0 ? $0 : lastDay + 1 + $0 }.filter { (1...lastDay).contains($0) }
    }
}
