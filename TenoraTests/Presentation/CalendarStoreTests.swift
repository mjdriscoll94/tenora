import XCTest
@testable import Tenora

@MainActor
final class CalendarStoreTests: XCTestCase {
    func testRefreshLoadsTodayEventsWhenAccessIsGranted() async {
        let event = CalendarEvent(
            externalIdentifier: "meeting",
            title: "Staff meeting",
            startDate: Date(timeIntervalSince1970: 1_725_190_200),
            endDate: Date(timeIntervalSince1970: 1_725_193_800)
        )
        let repository = FakeCalendarRepository(authorization: .fullAccess, events: [event])
        let store = CalendarStore(repository: repository)

        await store.refresh()

        XCTAssertEqual(store.events, [event])
        XCTAssertEqual(repository.fetchCount, 1)
    }

    func testRequestAccessLoadsEventsAfterPermissionIsGranted() async {
        let event = CalendarEvent(
            externalIdentifier: "dinner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 1_725_208_200),
            endDate: Date(timeIntervalSince1970: 1_725_211_800)
        )
        let repository = FakeCalendarRepository(authorization: .notDetermined, events: [event])
        let store = CalendarStore(repository: repository)

        await store.requestAccess()

        XCTAssertEqual(store.authorization, .fullAccess)
        XCTAssertEqual(store.events, [event])
        XCTAssertEqual(repository.requestCount, 1)
    }
}

@MainActor
private final class FakeCalendarRepository: CalendarRepository {
    private var authorization: CalendarAuthorization
    private let storedEvents: [CalendarEvent]
    private(set) var fetchCount = 0
    private(set) var requestCount = 0

    init(authorization: CalendarAuthorization, events: [CalendarEvent]) {
        self.authorization = authorization
        storedEvents = events
    }

    func authorizationStatus() -> CalendarAuthorization {
        authorization
    }

    func requestAccess() async throws -> CalendarAuthorization {
        requestCount += 1
        authorization = .fullAccess
        return authorization
    }

    func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        fetchCount += 1
        return storedEvents
    }
}
