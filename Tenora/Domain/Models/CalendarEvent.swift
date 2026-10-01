import Foundation

struct CalendarEvent: Identifiable, Equatable, Sendable, Codable {
    let externalIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String
    let calendarIdentifier: String?
    let isBusy: Bool

    var id: String {
        "\(externalIdentifier)-\(startDate.timeIntervalSinceReferenceDate)"
    }

    init(
        externalIdentifier: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        calendarName: String = "",
        calendarIdentifier: String? = nil,
        isBusy: Bool = true
    ) {
        self.externalIdentifier = externalIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.calendarIdentifier = calendarIdentifier
        self.isBusy = isBusy
    }
}

struct UserCalendar: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let sourceTitle: String
}

enum CalendarAuthorization: Equatable, Sendable {
    case notDetermined
    case fullAccess
    case writeOnly
    case denied
    case restricted
}
