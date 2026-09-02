import XCTest
@testable import Tenora

final class AvailabilityEngineTests: XCTestCase {
    private let engine = AvailabilityEngine()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCalculatesMinutesUntilNextEvent() {
        let now = date(year: 2024, month: 9, day: 1, hour: 10)
        let meeting = event("Meeting", startHour: 10, startMinute: 42, endHour: 11)

        let result = engine.snapshot(at: now, events: [meeting], calendar: calendar)

        XCTAssertEqual(result.nextEvent, meeting)
        XCTAssertEqual(result.minutesUntilNextEvent, 42)
        XCTAssertEqual(result.availableMinutes, 42)
    }

    func testCurrentEventMeansNoAvailableTime() {
        let now = date(year: 2024, month: 9, day: 1, hour: 10, minute: 30)
        let meeting = event("Meeting", startHour: 10, endHour: 11)

        let result = engine.snapshot(at: now, events: [meeting], calendar: calendar)

        XCTAssertEqual(result.currentEvent, meeting)
        XCTAssertEqual(result.availableMinutes, 0)
    }

    func testOverlappingEventsProduceMergedBusyWindow() {
        let now = date(year: 2024, month: 9, day: 1, hour: 8)
        let first = event("First", startHour: 9, endHour: 10)
        let overlapping = event("Overlap", startHour: 9, startMinute: 30, endHour: 11)

        let result = engine.snapshot(at: now, events: [first, overlapping], calendar: calendar)

        XCTAssertEqual(result.freeTimeWindows, [
            FreeTimeWindow(
                startDate: date(year: 2024, month: 9, day: 1, hour: 8),
                endDate: date(year: 2024, month: 9, day: 1, hour: 9)
            ),
            FreeTimeWindow(
                startDate: date(year: 2024, month: 9, day: 1, hour: 11),
                endDate: date(year: 2024, month: 9, day: 1, hour: 18)
            )
        ])
    }

    func testAllDayAndFreeEventsDoNotBlockAvailability() {
        let now = date(year: 2024, month: 9, day: 1, hour: 10)
        let allDay = CalendarEvent(
            externalIdentifier: "all-day",
            title: "Birthday",
            startDate: date(year: 2024, month: 9, day: 1, hour: 0),
            endDate: date(year: 2024, month: 9, day: 2, hour: 0),
            isAllDay: true
        )
        let free = CalendarEvent(
            externalIdentifier: "free",
            title: "Optional",
            startDate: date(year: 2024, month: 9, day: 1, hour: 11),
            endDate: date(year: 2024, month: 9, day: 1, hour: 12),
            isBusy: false
        )

        let result = engine.snapshot(at: now, events: [allDay, free], calendar: calendar)

        XCTAssertNil(result.nextEvent)
        XCTAssertEqual(result.availableMinutes, 480)
    }

    func testOutsideWorkingHoursDoesNotSuggestAvailableMinutes() {
        let now = date(year: 2024, month: 9, day: 1, hour: 20)

        let result = engine.snapshot(at: now, events: [], calendar: calendar)

        XCTAssertNil(result.availableMinutes)
    }

    func testWorkingHoursRemainWallClockHoursAcrossDaylightSavingTime() {
        var chicagoCalendar = Calendar(identifier: .gregorian)
        chicagoCalendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = chicagoCalendar.date(
            from: DateComponents(year: 2024, month: 3, day: 10, hour: 12)
        )!

        let result = engine.snapshot(at: now, events: [], calendar: chicagoCalendar)
        let firstWindow = try? XCTUnwrap(result.freeTimeWindows.first)

        XCTAssertEqual(firstWindow.map { chicagoCalendar.component(.hour, from: $0.startDate) }, 8)
        XCTAssertEqual(firstWindow.map { chicagoCalendar.component(.hour, from: $0.endDate) }, 18)
    }

    private func event(
        _ title: String,
        startHour: Int,
        startMinute: Int = 0,
        endHour: Int
    ) -> CalendarEvent {
        CalendarEvent(
            externalIdentifier: title,
            title: title,
            startDate: date(year: 2024, month: 9, day: 1, hour: startHour, minute: startMinute),
            endDate: date(year: 2024, month: 9, day: 1, hour: endHour)
        )
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }
}
