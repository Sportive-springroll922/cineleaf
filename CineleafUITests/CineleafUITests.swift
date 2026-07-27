import XCTest

final class CineleafUITests: XCTestCase {
    func testCreateProjectInEnglish() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launchEnvironment["CINELEAF_UI_TESTING"] = "1"
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let newProjectButton = app.buttons["welcome.newProject"]
        guard newProjectButton.waitForExistence(timeout: 5) else {
            XCTFail("New-project button unavailable.\n\(app.debugDescription)")
            return
        }
        newProjectButton.click()
        let name = app.textFields["newProject.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click()
        name.typeText("UI Test")
        app.buttons["newProject.create"].click()

        XCTAssertTrue(app.scrollViews["editor.timeline"].waitForExistence(timeout: 3))
    }

    func testSpanishWelcomeAndProjectSheet() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(es)",
            "-AppleLocale", "es_ES",
            "-CineleafPreferredLanguage", "spanish"
        ]
        app.launchEnvironment["CINELEAF_UI_TESTING"] = "1"
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let newProjectButton = app.buttons["welcome.newProject"]
        guard newProjectButton.waitForExistence(timeout: 5) else {
            XCTFail("Spanish new-project button unavailable.\n\(app.debugDescription)")
            return
        }
        XCTAssertEqual(newProjectButton.label, "Nuevo proyecto")
        newProjectButton.click()
        XCTAssertTrue(app.textFields["newProject.name"].waitForExistence(timeout: 3))
    }
}
