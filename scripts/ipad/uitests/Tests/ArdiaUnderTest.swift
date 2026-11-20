import Foundation

enum ArdiaUnderTest {
  static var bundleID: String { ProcessInfo.processInfo.environment["ARDIA_BUNDLE_ID"] ?? "com.ardia.browser.ios" }
}
