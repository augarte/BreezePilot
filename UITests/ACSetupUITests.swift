import XCTest

final class ACSetupUITests: XCTestCase {
    @MainActor
    func testCreatesSetupAndShowsPartialResult() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BREEZEPILOT_UI_TESTING"] = "setups"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let scenes = app.buttons["Scenes"]
        XCTAssertTrue(scenes.waitForExistence(timeout: 8))
        scenes.tap()
        app.buttons["New Scene"].tap()
        let name = app.textFields["Scene name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("Sleep")

        app.buttons["Add AC"].tap()
        app.buttons.containing(.staticText, identifier: "Living Room AC").firstMatch.tap()
        app.buttons["Off"].tap()
        XCTAssertTrue(app.staticTexts["This AC will turn off when you run the scene."].exists)

        app.buttons["Add AC"].tap()
        app.buttons.containing(.staticText, identifier: "Bedroom AC").firstMatch.tap()
        app.buttons["On"].tap()
        let cool = app.buttons["Scene mode Cool"]
        XCTAssertTrue(cool.waitForExistence(timeout: 8))
        cool.tap()
        let setTemperature = app.buttons["Set"]
        if !setTemperature.isHittable { app.scrollViews.firstMatch.swipeUp() }
        setTemperature.tap()
        app.buttons["Raise scene temperature"].tap()
        XCTAssertEqual(app.staticTexts["setupTemperature"].label, "26°C")
        app.buttons["Save"].tap()

        let run = app.buttons["Run Sleep"]
        XCTAssertTrue(run.waitForExistence(timeout: 8))
        run.tap()
        // On iOS 26 the identifier lands on the label's icon too, so match the summary text itself.
        let result = app.staticTexts["1 of 2 ACs updated"]
        XCTAssertTrue(result.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Retry Failed ACs"].waitForExistence(timeout: 5))
    }
}
