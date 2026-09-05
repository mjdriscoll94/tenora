import Foundation

struct CalendarEvent: Identifiable, Equatable, Sendable, Codable {
    let externalIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String
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
        isBusy: Bool = true
    ) {
        self.externalIdentifier = externalIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.isBusy = isBusy
    }
}

enum CalendarAuthorization: Equatable, Sendable {
    case notDetermined
    case fullAccess
    case writeOnly
    case denied
    case restricted
}
