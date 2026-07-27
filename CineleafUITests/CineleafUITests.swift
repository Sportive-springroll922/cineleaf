import XCTest

final class CineleafUITests: XCTestCase {
    func testCreateProjectInEnglish() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "-AppleLanguages", "(en)"]
        app.launch()

        app.buttons["welcome.newProject"].click()
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
            "--ui-testing",
            "-AppleLanguages", "(es)",
            "-AppleLocale", "es_ES",
            "-CineleafPreferredLanguage", "spanish"
        ]
        app.launch()

        let newProjectButton = app.buttons["welcome.newProject"]
        XCTAssertTrue(newProjectButton.waitForExistence(timeout: 3))
        XCTAssertEqual(newProjectButton.label, "Nuevo proyecto")
        newProjectButton.click()
        XCTAssertTrue(app.textFields["newProject.name"].waitForExistence(timeout: 3))
    }
}
