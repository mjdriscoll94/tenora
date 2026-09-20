import XCTest
@testable import Tenora

final class AgentBridgeSnapshotTests: XCTestCase {
    func testOAuthScopesSupportIdentityRefreshAndSync() {
        let configuration = AgentBridgeConfiguration(
            bridgeURL: URL(string: "https://bridge.example.com")!,
            oauthIssuer: URL(string: "https://identity.example.com/")!,
            oauthClientID: "native-client"
        )

        XCTAssertEqual(Set(configuration.scopes.split(separator: " ").map(String.init)),
                       Set(["openid", "profile", "email", "offline_access", "tasks:sync"]))
    }

    func testPrivateFieldsStayOutUntilSeparatelyEnabled() {
        let task = TenoraTask(title: "Private task", notes: "Sensitive details")
        let event = CalendarEvent(externalIdentifier: "event", title: "Therapy", startDate: Date(), endDate: Date().addingTimeInterval(3600))
        let snapshot = AgentBridgeSnapshot(tasks: [task], events: [event], focusedTaskID: nil,
                                           notesIncluded: false, calendarIncluded: false)
        XCTAssertEqual(snapshot.tasks.first?.notes, "")
        XCTAssertTrue(snapshot.events.isEmpty)
        XCTAssertFalse(snapshot.notesIncluded)
        XCTAssertFalse(snapshot.calendarIncluded)
    }

    func testExplicitSharingIncludesNotesCalendarAndContext() throws {
        let dependency = UUID()
        let task = TenoraTask(title: "Send proposal", notes: "Use final pricing",
                              returnTrigger: .taskCompleted(taskID: dependency, title: "Review pricing"))
        let event = CalendarEvent(externalIdentifier: "event", title: "Review", startDate: Date(), endDate: Date().addingTimeInterval(3600))
        let snapshot = AgentBridgeSnapshot(tasks: [task], events: [event], focusedTaskID: task.id,
                                           notesIncluded: true, calendarIncluded: true, timeZone: TimeZone(identifier: "America/Chicago")!)
        XCTAssertEqual(snapshot.tasks.first?.notes, task.notes)
        XCTAssertEqual(snapshot.tasks.first?.returnSummary, "After Review pricing is done")
        XCTAssertEqual(snapshot.events.first?.title, event.title)
        XCTAssertEqual(snapshot.focusedTaskID, task.id)
        XCTAssertEqual(snapshot.timeZone, "America/Chicago")

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["notesIncluded"] as? Bool, true)
    }
}
