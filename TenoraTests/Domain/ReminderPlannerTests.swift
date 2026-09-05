import XCTest
@testable import Tenora

final class ReminderPlannerTests: XCTestCase {
    func testVolumeQuietHoursAndCompletion() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 22))!
        let tasks = (0..<20).map { TenoraTask(title: "Task \($0)", createdAt: now, nextSurfaceAt: now) }
        let done = TenoraTask(title: "Done", status: .completed, nextSurfaceAt: now)
        let plan = ReminderPlanner().plan(tasks: tasks + [done], now: now, calendar: calendar)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertLessThanOrEqual(plan.count, 21)
        XCTAssertFalse(plan.contains { $0.taskID == done.id })
        for (day, reminders) in Dictionary(grouping: plan, by: { calendar.startOfDay(for: $0.date) }) {
            XCTAssertLessThanOrEqual(reminders.count, 3, "\(day)")
            for reminder in reminders {
                XCTAssertTrue((9..<20).contains(calendar.component(.hour, from: reminder.date)))
                XCTAssertGreaterThan(reminder.date, now)
            }
        }
    }
    func testExplicitSnoozeRespected() {
        let now = Date()
        let tomorrow = now.addingTimeInterval(86400)
        let task = TenoraTask(title: "Call", dueDate: now, nextSurfaceAt: tomorrow)
        XCTAssertTrue(ReminderPlanner().plan(tasks: [task], now: now).allSatisfy { $0.date >= tomorrow })
    }
    func testResynchronizingDoesNotResetDailyBudget() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        let slots = [1, 2, 3].map { now.addingTimeInterval(Double(-$0) * 3600) }
        let plan = ReminderPlanner().plan(tasks: [TenoraTask(title: "Call", nextSurfaceAt: now)], now: now, usedSlots: slots)
        XCTAssertFalse(plan.contains { calendar.isDate($0.date, inSameDayAs: now) })
    }
}
