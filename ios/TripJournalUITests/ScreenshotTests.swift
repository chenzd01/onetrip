import XCTest

/// Screenshots for the README and for sharing your own destination. Run through `scripts/make_screenshots.py`,
/// which sets the simulator status bar and appearance, passes the frozen trip time and exports the attachments.
/// Only the `Screenshots` scheme runs these; the regular `TripJournal` scheme runs the unit tests.
final class ScreenshotTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor func testCaptureScreens() throws {
        let app = launch()
        snap(app, "01-today")
        app.tabBars.buttons["行程"].tap(); snap(app, "02-itinerary")
        app.tabBars.buttons["探索"].tap(); snap(app, "03-places")
        app.buttons.matching(identifier: "explore.place").firstMatch.tap(); snap(app, "04-place-detail")
        app.navigationBars.buttons.firstMatch.tap()
        app.segmentedControls.buttons["餐饮"].tap(); snap(app, "05-dining")
        app.segmentedControls.buttons["攻略"].tap(); snap(app, "06-guides")
        app.tabBars.buttons["行囊"].tap(); snap(app, "07-travel-kit")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '旅行短句'")).firstMatch.tap(); snap(app, "08-phrases")
    }

    /// A slow walk through the app for the README animation; the script records the simulator screen meanwhile.
    @MainActor func testDemoTour() throws {
        let app = launch()
        pause(2.5); app.swipeUp(); pause(1.5); app.swipeDown(); pause(1)
        app.tabBars.buttons["行程"].tap(); pause(2)
        app.tabBars.buttons["探索"].tap(); pause(1.5)
        app.buttons.matching(identifier: "explore.place").firstMatch.tap(); pause(2); app.swipeUp(); pause(1.5)
        app.navigationBars.buttons.firstMatch.tap(); pause(1)
        app.tabBars.buttons["行囊"].tap(); pause(1)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '旅行短句'")).firstMatch.tap(); pause(3)  // make_screenshots.py cuts the video where the app closes
    }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // xcodebuild forwards TEST_RUNNER_TRIP_NOW to the runner as TRIP_NOW (destination local time).
        if let now = ProcessInfo.processInfo.environment["TRIP_NOW"], !now.isEmpty { app.launchArguments += ["-TripNow", now] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["今日"].waitForExistence(timeout: 10))
        pause(1.5)  // let photos decode before the first capture
        return app
    }

    @MainActor private func snap(_ app: XCUIApplication, _ name: String) {
        pause(1.8)  // navigation transitions and photo fades finish
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways
        add(shot)
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }
}
