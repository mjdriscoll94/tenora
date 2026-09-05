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
}
