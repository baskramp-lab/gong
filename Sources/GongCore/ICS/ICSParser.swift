import Foundation
import os

public struct ParseWindow: Equatable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
    func contains(_ d: Date) -> Bool { d >= start && d <= end }
}

struct RawEvent {
    var uid = ""
    var summary = ""
    var start: ICSDate.Parsed?
    var end: ICSDate.Parsed?
    var duration: DateComponents?
    var rrule: String?
    var exdates: [Date] = []
    var recurrenceID: Date?
    var status: String?
    var attendees: [Attendee] = []
    var description: String?
    var location: String?
    var conferenceURL: String?
}

public enum ICSParser {
    static let log = Logger(subsystem: "nl.baskramp.gong", category: "ICSParser")

    public static func parse(_ text: String, myEmail: String, window: ParseWindow,
                             defaultTZ: TimeZone = .current) -> [Event] {
        let raws = rawEvents(from: text, defaultTZ: defaultTZ)
        let masters = raws.filter { $0.recurrenceID == nil }
        let overrides = Dictionary(grouping: raws.filter { $0.recurrenceID != nil }, by: \.uid)
        let cancelledMasters = Set(masters.filter { $0.status?.uppercased() == "CANCELLED" }.map(\.uid))
        var events: [Event] = []

        for raw in masters {
            guard let start = raw.start else { continue }
            let isCancelled = raw.status?.uppercased() == "CANCELLED"
            if let ruleText = raw.rrule {
                guard !isCancelled else { continue }
                guard let rule = RecurrenceRule.parse(ruleText, defaultTZ: defaultTZ) else {
                    log.warning("Unsupported RRULE '\(ruleText, privacy: .public)' for UID \(raw.uid, privacy: .public); skipped")
                    continue
                }
                let overridden = Set((overrides[raw.uid] ?? []).compactMap { $0.recurrenceID }.map(seconds))
                let excluded = Set(raw.exdates.map(seconds))
                let occurrences = rule.occurrences(from: start.date, timeZone: start.timeZone,
                                                   windowStart: window.start, windowEnd: window.end)
                for occ in occurrences where !excluded.contains(seconds(occ)) && !overridden.contains(seconds(occ)) {
                    events.append(makeEvent(raw, start: occ, myEmail: myEmail))
                }
            } else {
                guard !isCancelled, window.contains(start.date) else { continue }
                events.append(makeEvent(raw, start: start.date, myEmail: myEmail))
            }
        }

        for raw in overrides.values.flatMap({ $0 }) {
            guard !cancelledMasters.contains(raw.uid), let start = raw.start,
                  raw.status?.uppercased() != "CANCELLED", window.contains(start.date) else { continue }
            events.append(makeEvent(raw, start: start.date, myEmail: myEmail))
        }

        return events.sorted { $0.start < $1.start }
    }

    private static func seconds(_ d: Date) -> Int { Int(d.timeIntervalSince1970.rounded()) }

    static func rawEvents(from text: String, defaultTZ: TimeZone) -> [RawEvent] {
        var result: [RawEvent] = []
        var current: RawEvent? = nil
        var depth = 0   // nesting inside the current VEVENT (VALARM, …); their properties are not the event's
        for line in ContentLine.unfold(text) {
            guard let cl = ContentLine.parse(line) else { continue }
            let value = cl.value.uppercased()
            switch cl.name {
            case "BEGIN" where current != nil:
                depth += 1
            case "BEGIN" where value == "VEVENT":
                current = RawEvent()
                depth = 0
            case "END" where current != nil && depth > 0:
                depth -= 1
            case "END" where value == "VEVENT":
                if let c = current { result.append(c) }
                current = nil
            default:
                if depth == 0, var c = current {
                    apply(cl, to: &c, defaultTZ: defaultTZ)
                    current = c
                }
            }
        }
        return result
    }

    static func apply(_ cl: ContentLine, to raw: inout RawEvent, defaultTZ: TimeZone) {
        let tzid = cl.params["TZID"]
        let isDate = cl.params["VALUE"]?.uppercased() == "DATE"
        func date(_ v: String) -> ICSDate.Parsed? {
            ICSDate.parse(v, tzid: tzid, isDateValue: isDate, defaultTZ: defaultTZ)
        }
        switch cl.name {
        case "UID": raw.uid = cl.value
        case "SUMMARY": raw.summary = ContentLine.unescapeText(cl.value)
        case "DTSTART": raw.start = date(cl.value)
        case "DTEND": raw.end = date(cl.value)
        case "DURATION": raw.duration = parseDuration(cl.value)
        case "RRULE": raw.rrule = cl.value
        case "EXDATE": raw.exdates += cl.value.split(separator: ",").compactMap { date(String($0))?.date }
        case "RECURRENCE-ID": raw.recurrenceID = date(cl.value)?.date
        case "STATUS": raw.status = cl.value
        case "DESCRIPTION": raw.description = ContentLine.unescapeText(cl.value)
        case "LOCATION": raw.location = ContentLine.unescapeText(cl.value)
        case "X-GOOGLE-CONFERENCE": raw.conferenceURL = cl.value
        case "ATTENDEE":
            let email = cl.value.lowercased().replacingOccurrences(of: "mailto:", with: "")
            raw.attendees.append(Attendee(email: email, name: cl.params["CN"],
                                          status: .from(partstat: cl.params["PARTSTAT"])))
        default: break
        }
    }

    /// RFC 5545 DURATION: `[+-]P[n]W` or `[+-]P[n]DT[n]H[n]M[n]S`. Weeks are returned as days.
    static func parseDuration(_ text: String) -> DateComponents? {
        var s = Substring(text.uppercased())
        var sign = 1
        if s.first == "+" || s.first == "-" { sign = s.removeFirst() == "-" ? -1 : 1 }
        guard s.first == "P" else { return nil }
        s.removeFirst()
        var c = DateComponents()
        var number = ""
        var inTime = false
        var any = false
        for ch in s {
            if ch.isASCII, ch.isNumber { number.append(ch); continue }
            if ch == "T" { guard number.isEmpty, !inTime else { return nil }; inTime = true; continue }
            guard let n = Int(number) else { return nil }
            number = ""
            any = true
            switch (ch, inTime) {
            case ("W", false): c.day = (c.day ?? 0) + 7 * n * sign
            case ("D", false): c.day = (c.day ?? 0) + n * sign
            case ("H", true): c.hour = n * sign
            case ("M", true): c.minute = n * sign
            case ("S", true): c.second = n * sign
            default: return nil
            }
        }
        return any && number.isEmpty ? c : nil
    }

    static func makeEvent(_ raw: RawEvent, start: Date, myEmail: String) -> Event {
        let originalStart = raw.start?.date ?? start
        var originalEnd = raw.end?.date
        if originalEnd == nil, let duration = raw.duration, let tz = raw.start?.timeZone {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            originalEnd = cal.date(byAdding: duration, to: originalStart)
        }
        let duration = max(0, (originalEnd ?? originalStart).timeIntervalSince(originalStart))
        let me = myEmail.lowercased()
        let mine = raw.attendees.first { $0.email == me }?.status ?? .unknown
        return Event(
            id: Event.makeID(uid: raw.uid, start: start),
            uid: raw.uid,
            title: raw.summary,
            start: start,
            end: start.addingTimeInterval(duration),
            isAllDay: raw.start?.isDateOnly ?? false,
            attendees: raw.attendees,
            myStatus: mine,
            meetURL: VideoLink.find(conference: raw.conferenceURL, description: raw.description, location: raw.location),
            description: raw.description,
            location: raw.location
        )
    }
}
