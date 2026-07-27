import XCTest

final class CineleafUITests: XCTestCase {
    func testCreateProjectInEnglish() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)"]
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
            "-AppleLanguages", "(es)",
            "-AppleLocale", "es_ES",
            "-CineleafPreferredLanguage", "spanish"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Nuevo proyecto"].waitForExistence(timeout: 3))
        app.buttons["Nuevo proyecto"].click()
        XCTAssertTrue(app.textFields["newProject.name"].waitForExistence(timeout: 3))
    }
}
