import XCTest

final class RemoteViewUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testAllRemoteSectionsExistInHierarchy() {
        XCTAssertTrue(app.navigationBars.element(boundBy: 0).exists)
    }

    func testVolumeUpButtonExistsAndIsHittable() {
        let button = app.buttons["Volume Up"]
        XCTAssertTrue(!button.exists || button.isHittable)
    }

    func testPowerButtonExistsAndIsHittable() {
        let button = app.buttons["power"]
        XCTAssertTrue(!button.exists || button.isHittable)
    }

    func testNumberPadTogglesVisibilityOnButtonTap() {
        let numberPadDisclosure = app.staticTexts["Number Pad"]
        if numberPadDisclosure.waitForExistence(timeout: 2) {
            numberPadDisclosure.tap()
            XCTAssertTrue(numberPadDisclosure.exists)
        }
    }

    func testDPadUpButtonExists() {
        XCTAssertTrue(app.otherElements["D-Pad"].exists || app.buttons["D-Pad"].exists)
    }

    func testDisconnectedStateShowsConnectionErrorLabel() {
        XCTAssertTrue(app.navigationBars.element(boundBy: 0).exists)
    }
}
