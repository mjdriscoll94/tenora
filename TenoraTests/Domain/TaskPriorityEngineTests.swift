import XCTest
@testable import Tenora

final class TaskPriorityEngineTests: XCTestCase {
    private let engine = TaskPriorityEngine()
    private let now = Date(timeIntervalSince1970: 1_725_187_400) // 2024-09-01 13:50 UTC
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDueTodayOutranksNormalUndatedTask() {
        let undated = TenoraTask(title: "Someday", createdAt: now)
        let dueToday = TenoraTask(title: "Due today", createdAt: now, dueDate: now)

        let result = engine.recommendation(
            from: [undated, dueToday],
            context: .init(now: now, calendar: calendar)
        )

        XCTAssertEqual(result?.id, dueToday.id)
    }

    func testCriticalPriorityAddsWeightWithoutChangingUrgencyModel() {
        let normal = TenoraTask(title: "Normal", createdAt: now)
        let critical = TenoraTask(title: "Critical", createdAt: now, priority: .critical)
        let context = TaskPriorityEngine.Context(now: now, calendar: calendar)

        XCTAssertEqual(engine.score(for: critical, context: context) - engine.score(for: normal, context: context), 60)
    }

    func testTaskThatFitsAvailableTimeReceivesAvailabilityBoost() {
        let fitting = TenoraTask(title: "Short", createdAt: now, estimatedDurationMinutes: 15)
        let tooLong = TenoraTask(title: "Long", createdAt: now, estimatedDurationMinutes: 60)
        let context = TaskPriorityEngine.Context(now: now, availableMinutes: 30, calendar: calendar)

        XCTAssertGreaterThan(
            engine.score(for: fitting, context: context),
            engine.score(for: tooLong, context: context)
        )
    }

    func testCompletedWaitingAndFutureScheduledTasksAreNotRecommended() {
        let completed = TenoraTask(title: "Done", createdAt: now, status: .completed)
        let waiting = TenoraTask(title: "Waiting", createdAt: now, status: .waiting)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let future = TenoraTask(title: "Tomorrow", createdAt: now, status: .scheduled, scheduledDate: tomorrow)

        let result = engine.recommendation(
            from: [completed, waiting, future],
            context: .init(now: now, calendar: calendar)
        )

        XCTAssertNil(result)
    }
}

