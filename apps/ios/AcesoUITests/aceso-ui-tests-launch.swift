import XCTest

// Captures a launch screenshot for every app UI configuration (light/dark, etc.)
// Attach screenshots are kept in the test result bundle so you can review them
// in Xcode's Report Navigator after a CI run.
final class AcesoUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
