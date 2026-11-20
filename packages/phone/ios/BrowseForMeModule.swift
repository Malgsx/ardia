import AuthenticationServices
import ExpoModulesCore
import ExpoUI
import SwiftUI

final class BrowseForMeSettingsProps: UIBaseViewProps {}

struct BrowseForMeSettingsView: ExpoSwiftUI.View {
  @ObservedObject var props: BrowseForMeSettingsProps

  var body: some View {
    BrowseForMePage()
  }
}

public final class BrowseForMeModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ArdiaPhoneBrowseForMe")

    Events("onBrowseForMe")

    OnCreate {
      onMain {
        BrowseForMeHost.shared.sink = { [weak self] event in self?.sendEvent("onBrowseForMe", event) }
      }
    }

    OnDestroy {
      onMain { BrowseForMeHost.shared.sink = nil }
    }

    AsyncFunction("isConnected") { () -> Bool in
      MainActor.assumeIsolated { BrowseForMeHost.shared.isConnected }
    }.runOnQueue(.main)

    AsyncFunction("open") { (query: String) in
      MainActor.assumeIsolated { BrowseForMeHost.shared.open(query) }
    }.runOnQueue(.main)

    AsyncFunction("account") { () -> [String: Any] in
      MainActor.assumeIsolated { Self.accountState() }
    }.runOnQueue(.main)

    AsyncFunction("connect") { (promise: Promise) in
      Task { @MainActor in
        let account = BrowseForMeHost.shared.chatGPT
        if account.isConnected { return promise.resolve(true) }
        guard let anchor = Self.keyWindow() else { return promise.resolve(false) }
        let connected = await account.signIn(presentingFrom: anchor)
        BrowseForMeHost.shared.sink?(["name": "account", "connected": account.isConnected, "account": Self.accountState()])
        promise.resolve(connected)
      }
    }.runOnQueue(.main)

    AsyncFunction("clearProblem") { () in
      MainActor.assumeIsolated { BrowseForMeHost.shared.chatGPT.clearProblem() }
    }.runOnQueue(.main)

    ExpoUIView(BrowseForMeSettingsView.self)
  }

  @MainActor
  static func accountState() -> [String: Any] {
    let account = BrowseForMeHost.shared.chatGPT
    return [
      "connected": account.isConnected,
      "label": account.accountLabel as Any,
      "signingIn": account.isSigningIn,
      "problem": account.problem as Any,
      "model": account.model?.slug as Any,
      "effort": account.effort as Any,
      "models": account.models.map { ["slug": $0.slug, "name": $0.displayName, "efforts": $0.efforts, "defaultEffort": $0.defaultEffort as Any] },
    ]
  }

  @MainActor
  static func keyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let active = scenes.filter { $0.activationState == .foregroundActive }
    return (active.isEmpty ? scenes : active).flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.flatMap(\.windows).first
  }
}
