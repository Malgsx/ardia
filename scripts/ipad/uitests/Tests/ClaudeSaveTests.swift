import XCTest

final class ClaudeSaveTests: XCTestCase {
  @MainActor
  func shot(_ name: String) {
    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
  }

  @MainActor
  func log(_ text: String) { XCTContext.runActivity(named: text) { _ in } }

  @MainActor
  func openSummarySettings(_ app: XCUIApplication) {
    if app.buttons["Close Search"].exists { app.buttons["Close Search"].tap(); sleep(2) }
    let sidebar = app.buttons["Show Sidebar"]
    if sidebar.waitForExistence(timeout: 5) { sidebar.tap(); sleep(2) }
    let more = app.descendants(matching: .any)["duoSidebarMore"]
    XCTAssertTrue(more.waitForExistence(timeout: 5), "no sidebar More")
    more.tap(); sleep(2)
    app.buttons["Settings"].firstMatch.tap(); sleep(3)
    let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Pinch to Summarize'")).firstMatch
    for _ in 0..<6 where !row.isHittable { app.swipeUp(); sleep(1) }
    row.tap(); sleep(3)
    let toggle = app.switches.firstMatch
    if toggle.exists, (toggle.value as? String) != "1" { toggle.tap(); sleep(2) }
  }

  @MainActor
  func enter(_ key: String, in app: XCUIApplication) {
    let field = app.secureTextFields["Anthropic API Key"].exists ? app.secureTextFields["Anthropic API Key"] : app.descendants(matching: .any)["claudeKeyField"]
    XCTAssertTrue(field.waitForExistence(timeout: 5), "no key field")
    field.tap(); sleep(1)
    field.typeText(key)
    app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save Key and Use Claude'")).firstMatch.tap()
  }

  @MainActor
  func testClaudeKeySavesAndSummarizes() throws {
    let key = ProcessInfo.processInfo.environment["ARDIA_CLAUDE_KEY"] ?? ""
    XCTAssertTrue(key.hasPrefix("sk-ant-"), "no real key passed to the test")
    let app = XCUIApplication(bundleIdentifier: ArdiaUnderTest.bundleID)
    app.launch()
    sleep(4)
    openSummarySettings(app)

    let remove = app.descendants(matching: .any)["claudeRemoveKey"]
    if remove.exists { remove.tap(); sleep(2); log("removed a previously saved key") }

    let claude = app.descendants(matching: .any)["pageSummaryChoice:Claude"]
    XCTAssertTrue(claude.waitForExistence(timeout: 5), "no Claude choice")
    claude.tap(); sleep(2)

    enter("sk-ant-api03-this-is-not-a-real-key-000000000000", in: app)
    let problem = app.descendants(matching: .any)["claudeKeyProblem"]
    XCTAssertTrue(problem.waitForExistence(timeout: 15), "no error shown for a bad key")
    log("bad key message: \(problem.label)")
    shot("k1-bad-key-error")

    let field = app.descendants(matching: .any)["claudeKeyField"]
    field.tap()
    field.doubleTap()
    if let value = field.value as? String, !value.isEmpty {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 80))
    }
    enter(key, in: app)
    let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "API key ending in \(key.suffix(4))")).firstMatch
    XCTAssertTrue(saved.waitForExistence(timeout: 20), "key was not saved")
    log("saved: \(saved.label)")
    shot("k2-key-saved")

    app.terminate()
    app.launch()
    sleep(3)
    app.open(URL(string: "ardia://open?url=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FCopenhagen")!)
    let web = app.webViews.firstMatch
    XCTAssertTrue(web.waitForExistence(timeout: 20))
    sleep(7)
    web.pinch(withScale: 0.4, velocity: -2)
    let byClaude = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Summarized by Claude'")).firstMatch
    XCTAssertTrue(byClaude.waitForExistence(timeout: 60), "no Claude summary")
    sleep(2)
    shot("k3-claude-summary")
  }
}
