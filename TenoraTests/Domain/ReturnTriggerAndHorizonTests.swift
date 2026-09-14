import XCTest
@testable import Tenora

final class ReturnTriggerAndHorizonTests: XCTestCase {
    private let engine = ReturnTriggerEngine()

    func testTaskCompletionAndEventEndReleaseTheirTriggers() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var dependency = TenoraTask(title: "First")
        dependency.complete(at: now)
        XCTAssertTrue(engine.isReady(.taskCompleted(taskID: dependency.id, title: dependency.title),
                                     tasks: [dependency], events: [], availability: nil, now: now))
        XCTAssertTrue(engine.isReady(.calendarEventEnded(eventID: "event", title: "Meeting", endDate: now),
                                     tasks: [], events: [], availability: nil, now: now))
    }

    func testFreeWindowRequiresKnownCurrentCapacityAndFindsNextCandidate() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let future = FreeTimeWindow(startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(7200))
        let availability = AvailabilitySnapshot(currentEvent: nil, nextEvent: nil, minutesUntilNextEvent: nil,
                                                availableMinutes: 20, freeTimeWindows: [future])
        let trigger = ReturnTrigger.freeWindow(minimumMinutes: 30, candidateDate: nil)
        XCTAssertFalse(engine.isReady(trigger, tasks: [], events: [], availability: availability, now: now))
        XCTAssertEqual(engine.nextCandidate(for: trigger, availability: availability, now: now), future.startDate)
        XCTAssertFalse(engine.isReady(trigger, tasks: [], events: [], availability: nil, now: now))
    }

    func testHorizonCombinesAndClassifiesTasksEventsAndTransitions() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let event = CalendarEvent(externalIdentifier: "event", title: "Appointment",
                                  startDate: now.addingTimeInterval(2 * 3600), endDate: now.addingTimeInterval(3 * 3600))
        let transition = TransitionPlan(eventID: event.externalIdentifier, eventTitle: event.title, eventStart: event.startDate,
                                        leaveLeadMinutes: 15, wrapUpLeadMinutes: 10)
        let laterTask = TenoraTask(title: "Prepare notes", scheduledDate: now.addingTimeInterval(6 * 3600))
        let items = DayHorizonEngine().items(tasks: [laterTask], events: [event], transitions: [transition], now: now)
        XCTAssertEqual(items.filter { $0.phase == .soon }.count, 3)
        XCTAssertEqual(items.filter { $0.phase == .later }.map(\.title), ["Prepare notes"])
        XCTAssertEqual(items, items.sorted { $0.date < $1.date })
    }
}
