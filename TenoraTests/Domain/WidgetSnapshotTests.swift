import XCTest
@testable import Tenora

final class WidgetSnapshotTests: XCTestCase {
    func testRoundTripAndStaleSnapshotDoNotOfferOldTask() throws {
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let task = TenoraTask(title: "Call", createdAt: now)
        let snapshot = WidgetSnapshot(updatedAt: now, tasks: [task], events: [], calendarKnown: false, startHour: 8, endHour: 18)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.recommendation(at: now)?.id, task.id)
        XCTAssertNil(decoded.recommendation(at: now.addingTimeInterval(86400)))
    }

    func testKeptTaskRemainsVisibleDuringCalendarEvent() {
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let task = TenoraTask(title: "Bring paperwork", createdAt: now, keepInFrontUntil: tomorrow)
        let event = CalendarEvent(externalIdentifier: "busy", title: "Meeting",
                                  startDate: now.addingTimeInterval(-600), endDate: now.addingTimeInterval(1800),
                                  isAllDay: false, calendarName: "Work")
        let snapshot = WidgetSnapshot(updatedAt: now, tasks: [task], events: [event], calendarKnown: true, startHour: 8, endHour: 18)

        XCTAssertEqual(snapshot.recommendation(at: now)?.id, task.id)
    }

    func testCurrentDayCapacityModeShapesWidgetRecommendation() {
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let quick = TenoraTask(title: "Quick", createdAt: now, estimatedDurationMinutes: 10)
        let important = TenoraTask(title: "Important", createdAt: now, estimatedDurationMinutes: 60, priority: .critical)
        let snapshot = WidgetSnapshot(
            updatedAt: now, tasks: [important, quick], events: [], calendarKnown: false,
            startHour: 8, endHour: 18, capacityModeRaw: TaskCapacityMode.quick.rawValue,
            capacitySelectedAt: now.timeIntervalSince1970
        )

        XCTAssertEqual(snapshot.recommendation(at: now)?.id, quick.id)
    }
}
