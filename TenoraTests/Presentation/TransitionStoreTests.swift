import XCTest
@testable import Tenora

@MainActor
final class TransitionStoreTests: XCTestCase {
    func testPlanPersistsAndTracksCalendarTimeChanges() async throws {
        let suite = "TransitionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let event = CalendarEvent(externalIdentifier: "id", title: "Dentist", startDate: Date(), endDate: Date().addingTimeInterval(3600))
        let store = TransitionStore(defaults: defaults)
        await store.save(TransitionPlan(eventID: event.externalIdentifier, eventTitle: event.title, eventStart: event.startDate))
        XCTAssertNotNil(TransitionStore(defaults: defaults).plan(for: event))

        let moved = CalendarEvent(externalIdentifier: "id", title: "Dentist moved", startDate: event.startDate.addingTimeInterval(1800), endDate: event.endDate.addingTimeInterval(1800))
        await store.synchronize(events: [moved], now: event.startDate.addingTimeInterval(-3600))
        XCTAssertEqual(store.plans.first?.eventTitle, "Dentist moved")
        XCTAssertEqual(store.plans.first?.eventStart, moved.startDate)
    }
}
