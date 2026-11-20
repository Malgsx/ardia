internal import ArdiaPhoneNative
internal import Expo
import React
import ReactAppDependencyProvider

@main
class AppDelegate: ExpoAppDelegate, ExpoReactNativeFactoryProvider {
  var reactNativeDelegate: ExpoReactNativeFactoryDelegate?
  var reactNativeFactory: RCTReactNativeFactory?
  @objc var window: UIWindow?
  private var sceneAdoption: NSObjectProtocol?

  // ⌘T on an iPad (or iPhone) with a hardware keyboard: a new tab, the same as the Search quick action.
  override func buildMenu(with builder: UIMenuBuilder) {
    super.buildMenu(with: builder)
    guard builder.system == .main else { return }
    let newTab = UIKeyCommand(title: String(localized: "New Tab"), image: UIImage(systemName: "plus.square.on.square"), action: #selector(ardiaNewTab(_:)), input: "t", modifierFlags: .command)
    newTab.wantsPriorityOverSystemBehavior = true
    builder.insertChild(UIMenu(title: "", options: .displayInline, children: [newTab]), atStartOfMenu: .file)
  }

  @objc func ardiaNewTab(_ sender: Any?) {
    PhoneSystemLinks.shared.receive(shortcutType: "com.ardia.browser.ios.search")
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    NSLog("%@", BuildStamp.line)
    let delegate = ReactNativeDelegate()
    let factory = ExpoReactNativeFactory(delegate: delegate)
    delegate.dependencyProvider = RCTAppDependencyProvider()

    reactNativeDelegate = delegate
    reactNativeFactory = factory
    PhoneSyncHost.shared.launch()
    sceneAdoption = NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: nil) { note in
      guard let scene = note.object as? UIScene else { return }
      MainActor.assumeIsolated { SceneDelegate.adopt(scene) }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }
}

enum BuildStamp {
  static var line: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let value = { (key: String) in info[key] as? String ?? "unstamped" }
    return "ARDIA build \(value("ArdiaBuildCommit")) dirty: \(value("ArdiaBuildDirty")) from the \(value("ArdiaBuildSource")); native \(value("ArdiaBuildNative"))"
  }
}

class ReactNativeDelegate: ExpoReactNativeFactoryDelegate {
  override func customize(_ rootView: UIView) {
    super.customize(rootView)
    LaunchBackdrop.install(in: rootView)
  }

  override func sourceURL(for bridge: RCTBridge) -> URL? {
    bridge.bundleURL ?? bundleURL()
  }

  override func bundleURL() -> URL? {
#if DEBUG
    RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: ".expo/.virtual-metro-entry")
#else
    Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }
}
