import XCTest

final class VerifyTests: XCTestCase {
  @MainActor
  func shot(_ name: String) {
    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
  }

  @MainActor
  func testLayoutCommandTAndSummary() throws {
    let device = XCUIDevice.shared
    let app = XCUIApplication(bundleIdentifier: ArdiaUnderTest.bundleID)
    app.launchArguments = ["-pageSummaries.enabled", "YES"]
    device.orientation = .portrait
    app.launch()
    app.open(URL(string: "ardia://open?url=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FSea_otter")!)
    XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20))
    sleep(6)
    shot("v1-portrait")

    device.orientation = .landscapeLeft
    sleep(3)
    shot("v2-landscape")

    app.webViews.firstMatch.pinch(withScale: 0.4, velocity: -2)
    sleep(10)
    shot("v3-landscape-summary")

    let tabsBefore = app.descendants(matching: .any).count
    app.typeKey("t", modifierFlags: .command)
    sleep(3)
    shot("v4-after-command-t")
    XCTContext.runActivity(named: "elements before \(tabsBefore), after \(app.descendants(matching: .any).count); keyboard shown: \(app.keyboards.count > 0)") { _ in }

    device.orientation = .portrait
    sleep(2)
    shot("v5-portrait-again")
  }
}
