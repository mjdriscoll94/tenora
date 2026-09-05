import XCTest
@testable import Tenora

final class ReviewEngineTests: XCTestCase {
    func testTomorrowPreservesDeadlineButMovesAttention() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 22))!
        let task = TenoraTask(title: "Call", dueDate: now, snoozeCount: 5)
        let result = ReviewEngine().apply(.tomorrow, to: task, now: now, calendar: calendar)
        XCTAssertEqual(result.dueDate, now)
        XCTAssertEqual(calendar.component(.hour, from: result.scheduledDate!), 9)
        XCTAssertEqual(calendar.component(.day, from: result.scheduledDate!), 1)
        XCTAssertEqual(result.nextSurfaceAt, result.scheduledDate)
        XCTAssertEqual(result.snoozeCount, 0)
    }
    func testFutureScheduledAndCompletedTasksStayOutOfReview() {
        let now = Date()
        let future = TenoraTask(title: "Next week", scheduledDate: now.addingTimeInterval(7 * 86400))
        let done = TenoraTask(title: "Done", status: .completed)
        let unresolved = TenoraTask(title: "Still matters")
        XCTAssertEqual(ReviewEngine().queue(tasks: [future, done, unresolved], now: now).map(\.id), [unresolved.id])
    }
    func testCompletionStopsResurfacing() {
        let now = Date()
        let task = TenoraTask(title: "Call", nextSurfaceAt: now)
        let result = ReviewEngine().apply(.complete, to: task, now: now)
        XCTAssertEqual(result.completedAt, now)
        XCTAssertNil(result.nextSurfaceAt)
    }
}
