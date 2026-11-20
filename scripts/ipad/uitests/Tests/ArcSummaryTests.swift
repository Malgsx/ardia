import XCTest

final class ArcSummaryTests: XCTestCase {
  @MainActor
  func shot(_ name: String) {
    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
  }

  @MainActor
  func log(_ text: String) { XCTContext.runActivity(named: text) { _ in } }

  @MainActor
  func testArcSummaryLayout() throws {
    let app = XCUIApplication(bundleIdentifier: ArdiaUnderTest.bundleID)
    app.launchArguments = ["-pageSummaries.enabled", "YES"]
    app.launch()
    app.open(URL(string: "ardia://open?url=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FCopenhagen")!)
    let web = app.webViews.firstMatch
    XCTAssertTrue(web.waitForExistence(timeout: 20))
    sleep(7)
    shot("a1-page")
    web.pinch(withScale: 0.4, velocity: -2)
    sleep(1)
    shot("a2-collapsing")
    sleep(9)
    shot("a3-summary")
    let back = app.buttons["Back to Page"]
    if back.waitForExistence(timeout: 3) { back.tap(); sleep(2); shot("a4-back-to-page") } else { log("no Back to Page button") }
  }

  @MainActor
  func testChatGPTSignInOpensOpenAI() throws {
    let app = XCUIApplication(bundleIdentifier: ArdiaUnderTest.bundleID)
    app.launch()
    sleep(4)
    if app.buttons["Close Search"].exists { app.buttons["Close Search"].tap(); sleep(2) }
    log("buttons: " + app.buttons.allElementsBoundByIndex.prefix(40).map { "[\($0.label)|\($0.identifier)]" }.joined(separator: " "))
    let sidebar = app.buttons["Show Sidebar"]
    XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "no sidebar button")
    sidebar.tap(); sleep(2)
    let more = app.descendants(matching: .any)["duoSidebarMore"]
    XCTAssertTrue(more.waitForExistence(timeout: 5), "no sidebar More")
    more.tap(); sleep(2)
    shot("s1-menu")
    app.buttons["Settings"].firstMatch.tap(); sleep(3)
    let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Pinch to Summarize'")).firstMatch
    for _ in 0..<6 where !row.isHittable { app.swipeUp(); sleep(1) }
    shot("s2-settings")
    row.tap(); sleep(3)
    let toggle = app.switches.firstMatch
    if toggle.exists, (toggle.value as? String) != "1" { toggle.tap(); sleep(2) }
    shot("s3-summary-settings")
    let claude = app.descendants(matching: .any)["pageSummaryChoice:Claude"]
    if claude.waitForExistence(timeout: 5) {
      claude.tap(); sleep(2)
      shot("s3b-claude-key")
    } else { log("no Claude choice") }
    let chatGPT = app.descendants(matching: .any)["pageSummaryChoice:ChatGPT"]
    XCTAssertTrue(chatGPT.waitForExistence(timeout: 5), "no ChatGPT choice")
    chatGPT.tap()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let allow = springboard.buttons["Continue"]
    if allow.waitForExistence(timeout: 8) { shot("s4-consent"); allow.tap() } else { log("no consent alert") }
    sleep(8)
    shot("s5-openai")
  }
}
