import XCTest
@testable import Tenora

final class HabitTrackingEngineTests: XCTestCase {
    private let engine = HabitTrackingEngine()
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Chicago")!
        return value
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testScheduledWeekdaysAndCustomInterval() {
        var weekdays = Habit(name: "Weekdays", createdAt: date(1))
        weekdays.schedule = HabitSchedule(type: .specificWeekdays, weekdays: [2, 4, 6])
        XCTAssertTrue(engine.scheduleCalculator.isScheduled(weekdays, on: date(2), calendar: calendar))
        XCTAssertFalse(engine.scheduleCalculator.isScheduled(weekdays, on: date(3), calendar: calendar))

        var custom = Habit(name: "Alternate", createdAt: date(1))
        custom.schedule = HabitSchedule(type: .custom, intervalDays: 2)
        XCTAssertTrue(engine.scheduleCalculator.isScheduled(custom, on: date(1), calendar: calendar))
        XCTAssertFalse(engine.scheduleCalculator.isScheduled(custom, on: date(2), calendar: calendar))
        XCTAssertTrue(engine.scheduleCalculator.isScheduled(custom, on: date(3), calendar: calendar))
    }

    func testTimesPerWeekStaysVisibleOnCompletionDayThenStopsAtTarget() {
        var habit = Habit(name: "Exercise", createdAt: date(1))
        habit.schedule = HabitSchedule(type: .timesPerWeek, weeklyTarget: 1)
        let completion = HabitCompletion(habitID: habit.id, completionDate: date(1), xpAwarded: 0)
        XCTAssertTrue(engine.scheduleCalculator.isScheduled(habit, on: date(1), completions: [completion], calendar: calendar))
        XCTAssertFalse(engine.scheduleCalculator.isScheduled(habit, on: date(2), completions: [completion], calendar: calendar))
    }

    func testDaySummaryCountsOnlyScheduledHabits() {
        let first = Habit(name: "Read", createdAt: date(1))
        var second = Habit(name: "Walk", createdAt: date(1))
        second.schedule = HabitSchedule(type: .specificWeekdays, weekdays: [7])
        let completion = HabitCompletion(habitID: first.id, completionDate: date(1), xpAwarded: 0)
        let summary = engine.daySummary(habits: [first, second], completions: [completion], on: date(1), calendar: calendar)
        XCTAssertEqual(summary.scheduled, 1)
        XCTAssertEqual(summary.completed, 1)
        XCTAssertTrue(summary.isPerfect)
    }

    func testProgressTracksCompletionCountsWithoutPointsOrLevels() {
        let habit = Habit(name: "Read", createdAt: date(1))
        let completions = [1, 2].map { HabitCompletion(habitID: habit.id, completionDate: date($0), xpAwarded: 0) }
        let progress = engine.progress(habits: [habit], completions: completions, now: date(2), calendar: calendar)
        XCTAssertEqual(progress.totalCompletions, 2)
        XCTAssertEqual(progress.totalXP, 0)
        XCTAssertEqual(progress.level, 1)
    }

    func testRemovingCompletionRecalculatesCounts() {
        let habit = Habit(name: "Read", createdAt: date(1))
        let completion = HabitCompletion(habitID: habit.id, completionDate: date(1), xpAwarded: 0)
        let before = engine.progress(habits: [habit], completions: [completion], now: date(1), calendar: calendar)
        let after = engine.progress(habits: [habit], completions: [], now: date(1), calendar: calendar)
        XCTAssertEqual(before.totalCompletions, 1)
        XCTAssertEqual(after.totalCompletions, 0)
    }

    func testDayBoundaryUsesSelectedTimezoneRatherThanRawHours() {
        let habit = Habit(name: "Late habit", createdAt: date(1, 23))
        let completion = HabitCompletion(habitID: habit.id, completionDate: date(1, 23), xpAwarded: 0)
        XCTAssertEqual(engine.daySummary(habits: [habit], completions: [completion], on: date(1, 1), calendar: calendar).completed, 1)
        XCTAssertEqual(engine.daySummary(habits: [habit], completions: [completion], on: date(2, 1), calendar: calendar).completed, 0)
    }
}
