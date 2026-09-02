import Foundation

@MainActor
protocol CalendarRepository {
    func authorizationStatus() -> CalendarAuthorization
    func requestAccess() async throws -> CalendarAuthorization
    func events(in interval: DateInterval) async throws -> [CalendarEvent]
}

