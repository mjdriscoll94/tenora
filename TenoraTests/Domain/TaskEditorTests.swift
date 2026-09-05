import XCTest
@testable import Tenora

final class TaskEditorTests: XCTestCase {
    func testExplicitBringBackHidesTaskFromNowUntilChosenDate() throws {
        let now = Date()
        let original = TenoraTask(title: "Hold this")
        var draft = original
        draft.nextSurfaceAt = now.addingTimeInterval(3600)
        let result = try TaskEditor.validated(draft, previous: original, now: now)
        XCTAssertEqual(result.nextSurfaceAt, draft.nextSurfaceAt)
        XCTAssertEqual(result.snoozeCount, 1)
        XCTAssertFalse(TaskPriorityEngine().isEligible(result, context: .init(now: now)))
    }
    func testRescheduleReplacesSnoozeAndMarksScheduled() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let original = TenoraTask(title: "Call", nextSurfaceAt: now, snoozeCount: 3)
        var draft = original
        draft.scheduledDate = now.addingTimeInterval(3600)
        let result = try TaskEditor.validated(draft, previous: original, now: now)
        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.nextSurfaceAt, draft.scheduledDate)
        XCTAssertEqual(result.snoozeCount, 0)
    }
    func testEmptyTitleRejected() {
        let task = TenoraTask(title: "  \n")
        XCTAssertThrowsError(try TaskEditor.validated(task, previous: task, now: Date()))
    }
}
