import XCTest

final class IPadLayoutTests: XCTestCase {
  private static let startMaxWidth: CGFloat = 669
  private static let commandMaxWidth: CGFloat = 615

  override func setUp() async throws {
    continueAfterFailure = false
    let isPad = await MainActor.run { UIDevice.current.userInterfaceIdiom == .pad }
    try XCTSkipUnless(isPad, "iPad layout tests run on an iPad simulator")
  }

  @MainActor func testStartScreenLandscape() {
    checkStartScreen(.landscapeLeft, name: "Start screen, landscape")
  }

  @MainActor func testStartScreenPortrait() {
    checkStartScreen(.portrait, name: "Start screen, portrait")
  }

  @MainActor func testSearchLandscape() {
    let app = launch(["-BrowseQuery", "otters"], .landscapeLeft)
    XCTAssertTrue(app.textFields["Search or Enter Address"].waitForExistence(timeout: 20))
    let suggestion = app.buttons["otters"].firstMatch
    XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
    let screen = capture("Search, landscape", app)
    assertCentered(suggestion.frame, maxWidth: Self.commandMaxWidth, in: screen)
  }

  @MainActor func testPageLandscape() {
    checkPage(.landscapeLeft, name: "Page, landscape")
  }

  @MainActor func testPagePortrait() {
    checkPage(.portrait, name: "Page, portrait")
  }

  @MainActor func testSidebarDeckLandscape() {
    let app = launch(["-BrowseSurface", "browsing", "-BrowseDeck", "-BrowseDelay", "3"], .landscapeLeft)
    let space = app.buttons["Space, Personal"]
    XCTAssertTrue(space.waitForExistence(timeout: 30))
    XCTAssertTrue(app.buttons["Close Tab"].waitForExistence(timeout: 10))
    let screen = capture("Sidebar deck, landscape", app)
    XCTAssertLessThan(space.frame.minX, screen.width / 4, "the deck opens as a sidebar on the leading edge")
  }

  @MainActor private func checkStartScreen(_ orientation: UIDeviceOrientation, name: String) {
    let app = launch(["-ArdiaRestingStart"], orientation)
    let tabs = app.buttons["Tabs"]
    let settings = app.buttons["Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 20))
    let screen = capture(name, app)
    assertCentered(tabs.frame.union(settings.frame), maxWidth: Self.startMaxWidth, in: screen)
  }

  @MainActor private func checkPage(_ orientation: UIDeviceOrientation, name: String) {
    let app = launch(["-BrowseSurface", "browsing"], orientation)
    XCTAssertTrue(app.buttons["Show Sidebar"].waitForExistence(timeout: 30), "a page on an iPad uses the wide layout's toolbar")
    XCTAssertTrue(app.buttons["Address"].firstMatch.waitForExistence(timeout: 10))
    sleep(3)
    capture(name, app)
  }

  @MainActor private func launch(_ arguments: [String], _ orientation: UIDeviceOrientation) -> XCUIApplication {
    XCUIDevice.shared.orientation = orientation
    let app = XCUIApplication()
    app.launchArguments = ["-ArdiaDemo", "YES"] + arguments
    app.launch()
    return app
  }

  @MainActor @discardableResult
  private func capture(_ name: String, _ app: XCUIApplication) -> CGSize {
    let shot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: shot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    let screen = shot.image.size
    XCTAssertEqual(app.windows.firstMatch.frame.size, screen, "the app's window fills the screen")
    return screen
  }

  private func assertCentered(_ frame: CGRect, maxWidth: CGFloat, in screen: CGSize, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(frame.width, maxWidth, "capped at \(maxWidth) pt on a wide screen", file: file, line: line)
    XCTAssertEqual(frame.midX, screen.width / 2, accuracy: 1, "centred on the screen", file: file, line: line)
  }
}
