import XCTest

final class AttentionLoopUITests: XCTestCase {
    @MainActor
    func testJustStartUsesTheSmallestStepAndCanStopWithoutCompleting() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-continuity-fixture"]
        app.launch()
        app.buttons["What was I doing?"].tap()
        app.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["Just Start"].waitForExistence(timeout: 5))
        app.buttons["Just Start"].tap()
        XCTAssertTrue(app.textFields["just-start-next-step"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["just-start-next-step"].value as? String, "Write the opening paragraph")
        app.buttons["Start 3 minutes"].tap()
        XCTAssertTrue(app.staticTexts["just-start-countdown"].waitForExistence(timeout: 5))
        app.buttons["I'm done for now"].tap()
        XCTAssertTrue(app.buttons["What was I doing?"].waitForExistence(timeout: 5))
        app.buttons["What was I doing?"].tap()
        XCTAssertTrue(app.staticTexts["Write the opening paragraph"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testUserCanSetAnIndividualWeekdayAsOff() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-working-schedule"]
        app.launch()
        app.buttons["Settings"].tap()
        app.buttons["Weekly schedule"].tap()
        XCTAssertTrue(app.buttons["workday-2"].waitForExistence(timeout: 5))
        app.buttons["workday-2"].tap()
        let dayOff = app.segmentedControls["workday-status"].buttons["Day off"]
        XCTAssertTrue(dayOff.waitForExistence(timeout: 5))
        dayOff.tap()
        XCTAssertTrue(dayOff.isSelected)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["Settings"].tap()
        app.buttons["Weekly schedule"].tap()
        app.buttons["workday-2"].tap()
        XCTAssertTrue(app.segmentedControls["workday-status"].buttons["Day off"].isSelected)
    }

    @MainActor
    func testResumeCaptureAndHoldPreserveTheThread() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-continuity-fixture"]
        app.launch()
        app.buttons["What was I doing?"].tap()
        XCTAssertTrue(app.staticTexts["Write the opening paragraph"].waitForExistence(timeout: 5))
        app.buttons["Resume"].tap()
        app.buttons["Add task"].tap()
        let title = app.textFields["What do you need to remember?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Order camp shirts")
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Back to: Finish lesson notes"].waitForExistence(timeout: 5))
        app.buttons["Resume"].tap()
        app.tabBars.buttons["Inbox"].tap()
        app.staticTexts["Finish lesson notes"].tap()
        app.swipeUp()
        app.buttons["Hold my place"].tap()
        let reason = app.textFields["Why are you stopping?"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()
        reason.typeText("Meeting")
        app.buttons["Hold"].tap()
        app.buttons["Save"].tap()
        app.tabBars.buttons["Today"].tap()
        app.buttons["What was I doing?"].tap()
        XCTAssertTrue(app.staticTexts["You paused because: Meeting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Write the opening paragraph"].exists)
    }
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
