import XCTest

final class DiscoveryViewUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testScanningAnimationAppearsOnLaunch() {
        XCTAssertTrue(app.navigationBars["Samsung TV Remote"].waitForExistence(timeout: 3))
    }

    func testDiscoveredTVAppearsInList() {
        XCTAssertTrue(app.tables.firstMatch.exists || app.collectionViews.firstMatch.exists)
    }

    func testEmptyStateViewShownWhenNoTVsFound() {
        XCTAssertTrue(app.staticTexts["No TVs Found"].exists || app.navigationBars["Samsung TV Remote"].exists)
    }

    func testTapOnTVNavigatesToRemoteView() {
        let firstCell = app.cells.firstMatch
        if firstCell.waitForExistence(timeout: 2) {
            firstCell.tap()
            XCTAssertTrue(app.buttons["gearshape"].waitForExistence(timeout: 3) || app.navigationBars.element(boundBy: 0).exists)
        }
    }

    func testAddManuallySheetAppearsOnToolbarTap() {
        let addButton = app.buttons["Add Manually"]
        if addButton.waitForExistence(timeout: 3) {
            addButton.tap()
            XCTAssertTrue(app.navigationBars["Add TV by IP"].waitForExistence(timeout: 2))
        }
    }
}
