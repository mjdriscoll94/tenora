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

    func testSelectedCalendarsFilterEvents() async {
        let defaults = UserDefaults.standard
        let oldUseAll = defaults.object(forKey: AttentionPreferences.useAllCalendarsKey)
        let oldSelection = defaults.object(forKey: AttentionPreferences.selectedCalendarIDsKey)
        defer {
            if let oldUseAll { defaults.set(oldUseAll, forKey: AttentionPreferences.useAllCalendarsKey) }
            else { defaults.removeObject(forKey: AttentionPreferences.useAllCalendarsKey) }
            if let oldSelection { defaults.set(oldSelection, forKey: AttentionPreferences.selectedCalendarIDsKey) }
            else { defaults.removeObject(forKey: AttentionPreferences.selectedCalendarIDsKey) }
        }
        defaults.set(false, forKey: AttentionPreferences.useAllCalendarsKey)
        AttentionPreferences.saveSelectedCalendarIDs(["work"])
        let now = Date()
        let work = CalendarEvent(externalIdentifier: "work-event", title: "Work", startDate: now, endDate: now.addingTimeInterval(3600), calendarIdentifier: "work")
        let personal = CalendarEvent(externalIdentifier: "personal-event", title: "Personal", startDate: now, endDate: now.addingTimeInterval(3600), calendarIdentifier: "personal")
        let repository = FakeCalendarRepository(authorization: .fullAccess, events: [work, personal])
        let store = CalendarStore(repository: repository)

        await store.refresh()

        XCTAssertEqual(store.events, [work])
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

    func calendars() async throws -> [UserCalendar] {
        [UserCalendar(id: "work", title: "Work", sourceTitle: "Test"), UserCalendar(id: "personal", title: "Personal", sourceTitle: "Test")]
    }
}
