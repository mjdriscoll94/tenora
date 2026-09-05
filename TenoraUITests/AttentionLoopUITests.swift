import XCTest

final class AttentionLoopUITests: XCTestCase {
    @MainActor
    func testCaptureScheduleCompleteAndOpenReview() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["Add task"].tap()
        let title = app.textFields["What do you need to remember?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("UI test task")
        app.buttons["Add"].tap()
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["UI test task"].waitForExistence(timeout: 5))
        app.staticTexts["UI test task"].tap()
        XCTAssertTrue(app.switches["Schedule"].waitForExistence(timeout: 5))
        app.switches["Schedule"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Complete UI test task"].waitForExistence(timeout: 5))
        app.buttons["Complete UI test task"].tap()
        XCTAssertTrue(app.staticTexts["Nothing waiting"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        app.swipeUp()
        app.buttons["Morning review"].tap()
        app.buttons["Begin"].tap()
        XCTAssertTrue(app.staticTexts["Your place is held."].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Finish"].tap()
    }
}
