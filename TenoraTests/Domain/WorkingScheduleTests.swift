import XCTest
@testable import Tenora

final class WorkingScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
    private func nightSchedule() -> WorkingSchedule {
        var schedule = WorkingSchedule()
        for index in schedule.days.indices { schedule.days[index].isEnabled = false }
        schedule.days[1] = WorkDay(weekday: 2, startMinute: 22 * 60, endMinute: 6 * 60)
        return schedule
    }

    func testOvernightBelongsToStartingDayAndHasExclusiveEnd() {
        let schedule = nightSchedule()
        XCTAssertFalse(schedule.isWorking(at: date(7, 21, 59), calendar: calendar))
        XCTAssertTrue(schedule.isWorking(at: date(7, 22), calendar: calendar))
        XCTAssertTrue(schedule.isWorking(at: date(8, 2), calendar: calendar))
        XCTAssertFalse(schedule.isWorking(at: date(8, 6), calendar: calendar))
        XCTAssertFalse(schedule.isWorking(at: date(8, 22), calendar: calendar))
    }

    func testDifferentDaysAndMinutePrecision() {
        var schedule = nightSchedule()
        schedule.days[2] = WorkDay(weekday: 3, startMinute: 9 * 60 + 30, endMinute: 17 * 60 + 15)
        XCTAssertFalse(schedule.isWorking(at: date(8, 9, 29), calendar: calendar))
        XCTAssertTrue(schedule.isWorking(at: date(8, 9, 30), calendar: calendar))
        XCTAssertFalse(schedule.isWorking(at: date(8, 17, 15), calendar: calendar))
        XCTAssertFalse(schedule.isWorking(at: date(9, 12), calendar: calendar))
    }

    func testAvailabilityChecksMeetingAfterMidnight() {
        let event = CalendarEvent(externalIdentifier: "night", title: "Handoff", startDate: date(8, 1), endDate: date(8, 2))
        let before = AvailabilityEngine().snapshot(at: date(7, 23), events: [event], calendar: calendar, schedule: nightSchedule())
        XCTAssertEqual(before.availableMinutes, 120)
        let busy = AvailabilityEngine().snapshot(at: date(8, 1, 30), events: [event], calendar: calendar, schedule: nightSchedule())
        XCTAssertEqual(busy.availableMinutes, 0)
        let after = AvailabilityEngine().snapshot(at: date(8, 2), events: [event], calendar: calendar, schedule: nightSchedule())
        XCTAssertEqual(after.availableMinutes, 240)
    }

    func testDayOffHasNoWindowsAndNoRecommendation() {
        let schedule = nightSchedule()
        let now = date(9, 12)
        let snapshot = AvailabilityEngine().snapshot(at: now, events: [], calendar: calendar, schedule: schedule)
        XCTAssertNil(snapshot.availableMinutes)
        XCTAssertTrue(snapshot.freeTimeWindows.isEmpty)
        XCTAssertNil(TaskPriorityEngine().recommendation(from: [TenoraTask(title: "Wait")], context: .init(now: now, calendar: calendar, schedule: schedule)))
        XCTAssertNotNil(TaskPriorityEngine().recommendation(from: [TenoraTask(title: "Night task")], context: .init(now: date(7, 23), calendar: calendar, schedule: schedule)))
    }

    func testOverlappingShiftsDoNotDoubleCountFreeTime() {
        var schedule = nightSchedule()
        schedule.days[2] = WorkDay(weekday: 3, startMinute: 5 * 60, endMinute: 10 * 60)
        let snapshot = AvailabilityEngine().snapshot(at: date(8, 5), events: [], calendar: calendar, schedule: schedule)
        XCTAssertEqual(snapshot.availableMinutes, 300)
        XCTAssertEqual(snapshot.freeTimeWindows.count, 1)
    }

    func testDSTKeepsLocalStartAndEndAcrossBothTransitions() {
        var local = calendar
        local.timeZone = TimeZone(identifier: "America/Chicago")!
        let shift = WorkDay(weekday: 7, startMinute: 22 * 60, endMinute: 6 * 60)
        for (month, day, hours) in [(3, 7, 7), (10, 31, 9)] {
            let date = local.date(from: DateComponents(year: 2026, month: month, day: day))!
            let interval = shift.interval(on: date, calendar: local)!
            XCTAssertEqual(local.component(.hour, from: interval.start), 22)
            XCTAssertEqual(local.component(.hour, from: interval.end), 6)
            XCTAssertEqual(interval.duration, Double(hours * 3600))
        }
    }

    func testPersistenceAndLegacyFallback() throws {
        let schedule = nightSchedule()
        let json = String(data: try JSONEncoder().encode(schedule), encoding: .utf8)!
        XCTAssertEqual(AttentionPreferences.schedule(from: json), schedule)
        let legacy = WorkingHours(startHour: 7, endHour: 15)
        for value in ["", "broken", "{\"days\":[]}"] {
            let restored = AttentionPreferences.schedule(from: value, fallback: legacy)
            XCTAssertEqual(restored, WorkingSchedule(hours: legacy))
        }
    }

    func testWidgetUsesSameNightScheduleAfterSnapshotRoundTrip() throws {
        let local = Calendar.current
        let now = local.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 23))!
        let task = TenoraTask(title: "Night shift task")
        let snapshot = WidgetSnapshot(updatedAt: now, tasks: [task], events: [], calendarKnown: false, startHour: 8, endHour: 18, schedule: nightSchedule())
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.recommendation(at: now)?.id, task.id)
        var off = snapshot
        off.schedule?.days[1].isEnabled = false
        XCTAssertNil(off.recommendation(at: now))
    }
}
