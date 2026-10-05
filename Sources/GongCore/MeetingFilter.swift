import Foundation

/// Keeps only "real" meetings: not all-day, not declined by me, and with at least one other attendee or a video link.
/// With `includeUnaccepted == false`, invitations I have not accepted yet (tentative / needs-action) are dropped too;
/// events where I'm not an attendee (my own solo events with a link) are unaffected.
public enum MeetingFilter {
    public static func meetings(from events: [Event], myEmail: String, includeUnaccepted: Bool = true) -> [Meeting] {
        let me = myEmail.lowercased()
        return events
            .filter { e in
                guard !e.isAllDay, e.myStatus != .declined else { return false }
                if !includeUnaccepted, e.myStatus == .tentative || e.myStatus == .needsAction { return false }
                let hasOther = e.attendees.contains { $0.email.lowercased() != me }
                return hasOther || e.meetURL != nil
            }
            .sorted { $0.start < $1.start }
    }
}
