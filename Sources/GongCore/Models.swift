import Foundation

public enum ParticipationStatus: String, Codable, Equatable, Sendable {
    case accepted, declined, tentative, needsAction, unknown

    static func from(partstat: String?) -> ParticipationStatus {
        switch partstat?.uppercased() {
        case "ACCEPTED": return .accepted
        case "DECLINED": return .declined
        case "TENTATIVE": return .tentative
        case "NEEDS-ACTION": return .needsAction
        default: return .unknown
        }
    }
}

public struct Attendee: Equatable, Codable, Sendable {
    public let email: String   // lowercased, without "mailto:"
    public let name: String?
    public let status: ParticipationStatus

    public init(email: String, name: String?, status: ParticipationStatus) {
        self.email = email; self.name = name; self.status = status
    }
}

/// One concrete occurrence of a calendar item (recurrences are expanded).
public struct Event: Equatable, Codable, Identifiable, Sendable {
    public let id: String          // uid + "/" + unix start, stable across fetches
    public let uid: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let attendees: [Attendee]
    public let myStatus: ParticipationStatus
    public let meetURL: URL?
    public let description: String?
    public let location: String?

    public init(id: String, uid: String, title: String, start: Date, end: Date, isAllDay: Bool,
                attendees: [Attendee], myStatus: ParticipationStatus, meetURL: URL?,
                description: String?, location: String?) {
        self.id = id; self.uid = uid; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.attendees = attendees; self.myStatus = myStatus
        self.meetURL = meetURL; self.description = description; self.location = location
    }

    /// Google event id = UID before the '@'.
    public var calendarEventID: String {
        uid.split(separator: "@", maxSplits: 1).first.map(String.init) ?? uid
    }

    public static func makeID(uid: String, start: Date) -> String {
        "\(uid)/\(Int(start.timeIntervalSince1970))"
    }
}

/// An Event that passed MeetingFilter.
public typealias Meeting = Event
