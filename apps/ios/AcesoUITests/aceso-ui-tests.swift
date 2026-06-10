import XCTest

// UI tests use XCUITest. Each test launches the app as a separate process
// and drives it through the accessibility layer — the same way VoiceOver does.
// Keep continueAfterFailure = false so the first failure stops the run immediately
// rather than letting a broken state cascade through later assertions.
final class AcesoUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAppLaunches() {
        XCTAssertTrue(app.state == .runningForeground)
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

}
