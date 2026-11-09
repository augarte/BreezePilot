import XCTest

final class ACControlUITests: XCTestCase {
    @MainActor
    func testPowerTemperatureAndFanControls() {
        let app = openDemoAC(using: "connected")
        let powerOff = app.buttons["Turn Off"]
        let powerOn = app.buttons["Turn On"]
        let raiseTemperature = app.buttons["Raise set temperature"]
        let target = app.staticTexts["coolingTarget"]
        let refresh = app.buttons["Refresh"]

        XCTAssertTrue(powerOff.waitForExistence(timeout: 8))
        XCTAssertEqual(target.label, "24 degrees Celsius")
        powerOff.tap()
        XCTAssertTrue(powerOn.waitForExistence(timeout: 8))
        XCTAssertFalse(raiseTemperature.isEnabled)
        powerOn.tap()
        XCTAssertTrue(powerOff.waitForExistence(timeout: 8))

        raiseTemperature.tap()
        XCTAssertTrue(refresh.wait(for: \.isEnabled, toEqual: true, timeout: 8))
        refresh.tap()
        XCTAssertTrue(refresh.wait(for: \.isEnabled, toEqual: true, timeout: 8))
        XCTAssertEqual(target.label, "24.5 degrees Celsius")

        let fanTwo = app.buttons["Fan speed 2"]
        let fanThree = app.buttons["Fan speed 3"]
        if !fanThree.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(fanTwo.isSelected)
        fanThree.tap()
        XCTAssertTrue(fanThree.wait(for: \.isSelected, toEqual: true, timeout: 8))
        XCTAssertFalse(fanTwo.isSelected)
    }

    @MainActor
    func testUnavailableACOffersRecoveryActions() {
        let app = openDemoAC(using: "unavailable")
        let status = app.staticTexts["connectionStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        XCTAssertEqual(status.label, "AC unavailable")
        XCTAssertTrue(app.buttons["Try Again"].isEnabled)
        XCTAssertTrue(app.buttons["Edit Connection"].isEnabled)
        XCTAssertFalse(app.buttons["Turn On"].exists)
    }

    @MainActor
    private func openDemoAC(using fixture: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BREEZEPILOT_UI_TESTING"] = fixture
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Air Conditioners"].waitForExistence(timeout: 8))
        let card = app.buttons["acListItem"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        XCTAssertTrue(app.navigationBars["Demo AC"].waitForExistence(timeout: 8))
        return app
    }
}
