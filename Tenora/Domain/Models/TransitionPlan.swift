import Foundation

struct TransitionPlan: Identifiable, Equatable, Sendable, Codable {
    var eventID: String
    var eventTitle: String
    var eventStart: Date
    var leaveLeadMinutes: Int = 15
    var wrapUpLeadMinutes: Int = 10

    var id: String { eventID }
    var leaveAt: Date { eventStart.addingTimeInterval(TimeInterval(-leaveLeadMinutes * 60)) }
    var wrapUpAt: Date { leaveAt.addingTimeInterval(TimeInterval(-wrapUpLeadMinutes * 60)) }
}
