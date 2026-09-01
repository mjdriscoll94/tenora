import XCTest
@testable import Tenora

final class ResurfacingEngineTests: XCTestCase {
    private let engine = ResurfacingEngine()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testNewUndatedTaskInitiallyReturnsFourHoursLater() {
        let createdAt = date(year: 2024, month: 9, day: 1, hour: 10)
        let task = TenoraTask(title: "Remember me", createdAt: createdAt)

        let result = engine.initialSurfaceDate(for: task, calendar: calendar)

        XCTAssertEqual(result, date(year: 2024, month: 9, day: 1, hour: 14))
    }

    func testLateTaskInitiallyReturnsNextMorning() {
        let createdAt = date(year: 2024, month: 9, day: 1, hour: 18)
        let task = TenoraTask(title: "Remember me", createdAt: createdAt)

        let result = engine.initialSurfaceDate(for: task, calendar: calendar)

        XCTAssertEqual(result, date(year: 2024, month: 9, day: 2, hour: 9))
    }

    func testFirstPostponeReturnsInThreeHoursAndTracksDismissal() {
        let now = date(year: 2024, month: 9, day: 1, hour: 10)
        let task = TenoraTask(title: "Call insurance", createdAt: now)

        let result = engine.postpone(task, at: now, calendar: calendar)

        XCTAssertEqual(result.nextSurfaceAt, date(year: 2024, month: 9, day: 1, hour: 13))
        XCTAssertEqual(result.lastSurfacedAt, now)
        XCTAssertEqual(result.surfaceCount, 1)
        XCTAssertEqual(result.snoozeCount, 1)
    }

    func testSecondPostponeReturnsAtSevenPM() {
        let now = date(year: 2024, month: 9, day: 1, hour: 14)
        let task = TenoraTask(title: "Call insurance", createdAt: now, snoozeCount: 1)

        let result = engine.postpone(task, at: now, calendar: calendar)

        XCTAssertEqual(result.nextSurfaceAt, date(year: 2024, month: 9, day: 1, hour: 19))
    }

    func testOnlyDueUnresolvedTasksAreReturnedForResurfacing() {
        let now = date(year: 2024, month: 9, day: 1, hour: 14)
        let due = TenoraTask(title: "Due", createdAt: now, nextSurfaceAt: now.addingTimeInterval(-1))
        let later = TenoraTask(title: "Later", createdAt: now, nextSurfaceAt: now.addingTimeInterval(60))
        let complete = TenoraTask(title: "Complete", createdAt: now, status: .completed, nextSurfaceAt: now.addingTimeInterval(-1))

        let result = engine.tasksToSurface(from: [due, later, complete], at: now)

        XCTAssertEqual(result.map(\.id), [due.id])
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
