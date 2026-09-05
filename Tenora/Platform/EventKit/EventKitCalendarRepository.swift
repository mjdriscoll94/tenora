import EventKit
import Foundation

@MainActor
final class EventKitCalendarRepository: CalendarRepository {
    private let eventStore: EKEventStore
    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func authorizationStatus() -> CalendarAuthorization {
        Self.mapAuthorization(EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccess() async throws -> CalendarAuthorization {
        _ = try await eventStore.requestFullAccessToEvents()
        return authorizationStatus()
    }

    func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        guard authorizationStatus() == .fullAccess else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )
        return eventStore.events(matching: predicate)
            .map { event in
                CalendarEvent(
                    externalIdentifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                    title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled event",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarName: event.calendar.title,
                    isBusy: event.availability != .free
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func mapAuthorization(_ status: EKAuthorizationStatus) -> CalendarAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .fullAccess: return .fullAccess
        case .writeOnly: return .writeOnly
        @unknown default: return .denied
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
