import ArdiaBrowser
import Foundation
import FoundationModels
import Observation
import SwiftUI
import UIKit
import WebKit

@MainActor
@Observable
final class PageSummarySession: Identifiable {
  enum Trigger: String {
    case pinch
    case menu
  }

  enum Phase: Equatable {
    case reading
    case writing
    case done
    case failed(String)
  }

  enum Writer: String {
    case claude
    case chatGPT = "chatgpt"
    case onDevice = "on_device"
    case excerpts
  }

  static let responseTokens = 320
  static let instructionTokens = 120
  static let charactersPerToken = 3
  static let chatGPTCharacters = 24_000

  let id = UUID()
  let trigger: Trigger
  let page: UUID
  let navigation: Int
  let revision: Int
  @ObservationIgnored weak var source: WKWebView?
  private(set) var title: String
  private(set) var phase: Phase = .reading
  private(set) var text = ""
  private(set) var writer: Writer?
  private(set) var note: String?
  @ObservationIgnored var onSettled: ((PageSummarySession) -> Void)?
  @ObservationIgnored private var task: Task<Void, Never>?

  init(trigger: Trigger, tab: WebTab) {
    self.trigger = trigger
    page = tab.id
    navigation = tab.navigationGeneration
    revision = PageSummarySwitch.shared.revision
    source = tab.webView
    title = tab.title
  }

  var outcome: String {
    if case .failed = phase { return "failed" }
    return writer?.rawValue ?? "failed"
  }

  func isCurrent(for tab: WebTab?) -> Bool {
    guard let tab, let source, PageSummarySwitch.shared.isCurrent(revision) else { return false }
    return tab.id == page && tab.navigationGeneration == navigation && tab.webView === source
  }

  func start(_ tab: WebTab) {
    guard task == nil else { return }
    task = Task { [weak self] in await self?.run(tab) }
  }

  func cancel() {
    onSettled = nil
    task?.cancel()
    task = nil
  }

  private func run(_ tab: WebTab) async {
    let content: ReadableContent
    do {
      content = try await tab.readableContent()
    } catch {
      return settle(failure: String(localized: "Couldn’t read this page."), tab: tab)
    }
    guard !Task.isCancelled, isCurrent(for: tab) else { return }
    if !content.title.isEmpty { title = content.title }
    guard PageSummaryDigest.isSummarizable(content) else {
      return settle(failure: String(localized: "There isn’t enough text on this page to summarize."), tab: tab)
    }
    phase = .writing
    await write(content)
    guard !Task.isCancelled, isCurrent(for: tab) else { return }
    if text.isEmpty { return settle(failure: String(localized: "Couldn’t summarize this page."), tab: tab) }
    phase = .done
    onSettled?(self)
  }

  private func settle(failure: String, tab: WebTab) {
    guard !Task.isCancelled, isCurrent(for: tab) else { return }
    text = ""
    phase = .failed(failure)
    onSettled?(self)
  }

  private func write(_ content: ReadableContent) async {
    var fallback: String?
    if PageSummaryProvider.current == .claude {
      if ClaudeAccount.shared.isConnected {
        do {
          try await ClaudeAccount.shared.streamSummary(
            instructions: PageSummaryDigest.instructions,
            prompt: PageSummaryDigest.prompt(content, characterBudget: Self.chatGPTCharacters)
          ) { [weak self] answer in self?.text = answer }
          writer = .claude
          note = String(localized: "Summarized by Claude with your Anthropic API key.")
          return
        } catch {
          if Task.isCancelled { return }
          text = ""
          fallback = (error as? ClaudeFailure)?.message ?? String(localized: "Claude couldn’t summarize this page")
        }
      } else {
        fallback = String(localized: "No Anthropic API key is saved")
      }
    }
    if PageSummaryProvider.current == .chatGPT {
      let account = BrowseForMeHost.shared.chatGPT
      if account.isConnected {
        do {
          _ = try await account.streamAnswer(
            instructions: PageSummaryDigest.instructions,
            prompt: PageSummaryDigest.prompt(content, characterBudget: Self.chatGPTCharacters)
          ) { [weak self] answer in self?.text = answer }
          writer = .chatGPT
          note = String(localized: "Written by ChatGPT on your plan.")
          return
        } catch {
          if Task.isCancelled { return }
          text = ""
          fallback = String(localized: "ChatGPT couldn’t summarize this page")
        }
      } else {
        fallback = String(localized: "ChatGPT isn’t connected")
      }
    }
    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
      let reason = fallback.map { String(localized: "\($0), so here are the page’s key lines.") }
      return quote(content, reason: reason ?? Self.unavailableReason(model.availability))
    }
    let budget = max((model.contextSize - Self.responseTokens - Self.instructionTokens) * Self.charactersPerToken, 2000)
    for share in [budget, budget / 2] {
      do {
        try await stream(model: model, prompt: PageSummaryDigest.prompt(content, characterBudget: share))
        writer = .onDevice
        note = String(localized: "Written on this device by Apple Intelligence. Nothing left it.")
        return
      } catch {
        if Task.isCancelled { return }
        text = ""
      }
    }
    quote(content, reason: String(localized: "Apple Intelligence couldn’t summarize this page, so here are its key lines."))
  }

  private func stream(model: SystemLanguageModel, prompt: String) async throws {
    let session = LanguageModelSession(model: model, instructions: PageSummaryDigest.instructions)
    let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: Self.responseTokens)
    for try await snapshot in session.streamResponse(to: prompt, options: options) {
      try Task.checkCancellation()
      text = snapshot.content
    }
  }

  private func quote(_ content: ReadableContent, reason: String) {
    text = PageSummaryDigest.excerpts(content)
    writer = .excerpts
    note = reason
  }

  static func unavailableReason(_ availability: SystemLanguageModel.Availability) -> String {
    switch availability {
    case .unavailable(.appleIntelligenceNotEnabled):
      String(localized: "Turn on Apple Intelligence in Settings for a written summary. Until then, here are the page’s key lines.")
    case .unavailable(.modelNotReady):
      String(localized: "Apple Intelligence is still downloading. Until it’s ready, here are the page’s key lines.")
    default:
      String(localized: "This device can’t run Apple Intelligence, so here are the page’s key lines.")
    }
  }
}

extension PageSummarySwitch {
  static let shared = PageSummarySwitch(defaults: .standard)
}

enum PageSummaryProvider: String {
  case onDevice = "on_device"
  case chatGPT = "chatgpt"
  case claude

  static let key = "pageSummaries.provider"

  @MainActor
  static var current: PageSummaryProvider {
    get { UserDefaults.standard.string(forKey: key).flatMap(PageSummaryProvider.init(rawValue:)) ?? .onDevice }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
  }
}

@MainActor
@Observable
final class PageSummaryPresenter {
  var session: PageSummarySession?
  var bottomInset: CGFloat = 0
  var topInset: CGFloat = 0
  var pageImage: UIImage?
  var startScale: CGFloat = 1
  var collapsed = false
  @ObservationIgnored var onDismiss: (() -> Void)?

  func dismiss() { onDismiss?() }
}

final class PageSummaryLayer: UIView {
  let presenter: PageSummaryPresenter
  private let hosting: UIHostingController<PageSummaryOverlay>

  init(presenter: PageSummaryPresenter) {
    self.presenter = presenter
    hosting = UIHostingController(rootView: PageSummaryOverlay(presenter: presenter))
    super.init(frame: .zero)
    backgroundColor = .clear
    hosting.view.backgroundColor = .clear
    hosting.safeAreaRegions = []
    hosting.view.frame = bounds
    hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(hosting.view)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    presenter.session != nil && bounds.contains(point)
  }
}

struct PageSummaryLayout {
  let size: CGSize
  let wide: Bool
  let margin: CGFloat
  let thumbnail: CGRect
  let title: CGRect
  let summaryTop: CGFloat
  let textSize: CGFloat

  init(size: CGSize, topInset: CGFloat) {
    self.size = size
    wide = size.width >= 700
    margin = wide ? 36 : 20
    let top = topInset + (wide ? 24 : 16)
    if wide {
      let width = min(max(size.width * 0.3, 260), 380)
      let height = min(width * 0.68, size.height * 0.3)
      thumbnail = CGRect(x: margin, y: top, width: width, height: height)
      let titleX = thumbnail.maxX + 28
      title = CGRect(x: titleX, y: top, width: max(size.width - titleX - margin, 120), height: height)
      summaryTop = thumbnail.maxY + 28
      textSize = 22
    } else {
      title = CGRect(x: margin, y: top, width: size.width - margin * 2, height: 28)
      let width = min(size.width * 0.62, 340)
      let height = min(width * 0.78, size.height * 0.3)
      thumbnail = CGRect(x: (size.width - width) / 2, y: title.maxY + 12, width: width, height: height)
      summaryTop = thumbnail.maxY + 22
      textSize = 19
    }
  }

  func pageFrame(scale: CGFloat) -> CGRect {
    CGRect(x: size.width * (1 - scale) / 2, y: size.height * (1 - scale) / 2, width: size.width * scale, height: size.height * scale)
  }
}

struct PageSummaryOverlay: View {
  let presenter: PageSummaryPresenter

  var body: some View {
    GeometryReader { proxy in
      if let session = presenter.session {
        let layout = PageSummaryLayout(size: proxy.size, topInset: presenter.topInset)
        let collapsed = presenter.collapsed
        ZStack(alignment: .topLeading) {
          PageSummaryBackdrop()
            .opacity(collapsed ? 1 : 0)
          PageSummaryReading(session: session, layout: layout, bottomInset: presenter.bottomInset) { presenter.dismiss() }
            .opacity(collapsed ? 1 : 0)
            .offset(y: collapsed ? 0 : 36)
          if let image = presenter.pageImage {
            let frame = collapsed ? layout.thumbnail : layout.pageFrame(scale: presenter.startScale)
            Button { presenter.dismiss() } label: {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: frame.width, height: frame.height, alignment: .top)
                .clipped()
                .clipShape(.rect(cornerRadius: collapsed ? 18 : 0))
                .overlay { RoundedRectangle(cornerRadius: collapsed ? 18 : 0).strokeBorder(.separator.opacity(collapsed ? 1 : 0), lineWidth: 0.5) }
                .shadow(color: .black.opacity(collapsed ? 0.18 : 0), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .offset(x: frame.minX, y: frame.minY)
            .accessibilityLabel(Text("Back to Page"))
          }
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { presenter.dismiss() }
      }
    }
    .ignoresSafeArea()
  }
}

struct PageSummaryBackdrop: View {
  var body: some View {
    ZStack {
      Color(uiColor: .systemBackground)
      LinearGradient(colors: [Color.purple.opacity(0.10), Color.indigo.opacity(0.05), Color.pink.opacity(0.06)], startPoint: .top, endPoint: .bottom)
    }
    .ignoresSafeArea()
  }
}

struct PageSummaryReading: View {
  let session: PageSummarySession
  let layout: PageSummaryLayout
  let bottomInset: CGFloat
  let onClose: @MainActor () -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      titleView
        .frame(width: layout.title.width, height: layout.title.height, alignment: layout.wide ? .bottomLeading : .center)
        .offset(x: layout.title.minX, y: layout.title.minY)
      VStack(spacing: 0) {
        ScrollView {
          content
            .frame(maxWidth: layout.wide ? 900 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.margin)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        bar
      }
      .padding(.top, layout.summaryTop)
    }
    .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    .onChange(of: session.phase) { _, phase in
      if phase == .done { UIAccessibility.post(notification: .announcement, argument: String(localized: "Summary ready")) }
    }
  }

  private var titleView: some View {
    VStack(alignment: layout.wide ? .leading : .center, spacing: 6) {
      Text("Summary")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
      if !session.title.isEmpty {
        Text(session.title)
          .font(layout.wide ? .largeTitle.weight(.bold) : .headline)
          .lineLimit(layout.wide ? 3 : 1)
          .multilineTextAlignment(layout.wide ? .leading : .center)
          .minimumScaleFactor(0.7)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder
  private var content: some View {
    VStack(alignment: .leading, spacing: 18) {
      switch session.phase {
      case .failed(let message):
        Text(message)
          .font(.system(size: layout.textSize))
          .foregroundStyle(.secondary)
      default:
        if session.text.isEmpty {
          HStack(spacing: 10) {
            ProgressView()
            Text("Summarizing…")
              .font(.system(size: layout.textSize))
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
        } else {
          ForEach(Array(ResearchAnswer.blocks(session.text).enumerated()), id: \.offset) { _, block in
            line(block)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func line(_ block: ResearchAnswer.Block) -> some View {
    switch block {
    case .heading(let text):
      Text(text)
        .font(.system(size: layout.textSize + 4, weight: .bold))
        .padding(.top, 6)
    case .bullet(let text):
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
        Text(ResearchAnswer.withoutCitations(text))
      }
      .font(.system(size: layout.textSize))
    case .paragraph(let text):
      Text(ResearchAnswer.withoutCitations(text))
        .font(.system(size: layout.textSize))
    }
  }

  private var bar: some View {
    HStack(spacing: 12) {
      Text(session.phase == .done ? (session.note ?? "") : String(localized: "Summarizing…"))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Spacer(minLength: 8)
      if session.phase == .done, !session.text.isEmpty {
        let plain = ResearchAnswer.withoutCitations(session.text)
        Button {
          UIPasteboard.general.string = plain
        } label: {
          Image(systemName: "doc.on.doc").barButton()
        }
        .accessibilityLabel(Text("Copy Summary"))
        ShareLink(item: plain) {
          Image(systemName: "square.and.arrow.up").barButton()
        }
        .accessibilityLabel(Text("Share Summary"))
      }
      Button { onClose() } label: {
        Image(systemName: "xmark").barButton()
      }
      .accessibilityLabel(Text("Close Summary"))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, layout.margin)
    .padding(.top, 12)
    .padding(.bottom, bottomInset + 12)
    .background(.bar)
  }
}

private extension Image {
  func barButton() -> some View {
    font(.body.weight(.semibold))
      .foregroundStyle(.primary)
      .frame(width: 44, height: 44)
      .glassEffect(.regular, in: .circle)
      .contentShape(.circle)
  }
}

@MainActor
final class PagePinchWatcher: NSObject, UIGestureRecognizerDelegate {
  var moment: (() -> PagePinch.Moment?)?
  var onPinchedIn: (() -> Void)?
  var ignoresTouch: ((UITouch) -> Bool)?
  var onSqueeze: ((CGFloat) -> Void)?
  var onRelease: ((Bool) -> Void)?

  private lazy var recognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
  private var pinch: PagePinch?
  private lazy var feedback = UIImpactFeedbackGenerator(style: .light, view: recognizer.view ?? UIView())

  init(container: UIView) {
    super.init()
    recognizer.delegate = self
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesBegan = false
    recognizer.delaysTouchesEnded = false
    container.addGestureRecognizer(recognizer)
  }

  func reset() {
    let wasPinching = pinch != nil
    pinch = nil
    if wasPinching { onRelease?(false) }
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    true
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    ignoresTouch?(touch) != true
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer === recognizer, let moment = moment?() else { return false }
    pinch = PagePinch(at: moment, scale: Double(recognizer.scale))
    if pinch != nil { feedback.prepare() }
    return pinch != nil
  }

  @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
    switch recognizer.state {
    case .changed:
      guard pinch != nil else { return }
      pinch?.moved(to: Double(recognizer.scale))
      onSqueeze?(recognizer.scale)
    case .ended, .cancelled, .failed:
      guard var pinch else { return }
      self.pinch = nil
      pinch.moved(to: Double(recognizer.scale))
      let ending: PagePinch.Ending = recognizer.state == .ended ? .ended : recognizer.state == .cancelled ? .cancelled : .failed
      guard let moment = moment?(), pinch.fires(ending, at: moment) else {
        onRelease?(false)
        return
      }
      feedback.impactOccurred(intensity: 0.7)
      onRelease?(true)
      onPinchedIn?()
    default:
      break
    }
  }
}

enum ClaudeFailure: Error {
  case invalidKey
  case rateLimited
  case overloaded
  case refused
  case network
  case api(Int, String?)

  var message: String {
    switch self {
    case .invalidKey: String(localized: "Anthropic didn’t accept this API key")
    case .rateLimited: String(localized: "Your Anthropic API key hit its rate limit or ran out of credits")
    case .overloaded: String(localized: "Claude is busy right now")
    case .refused: String(localized: "Claude declined to summarize this page")
    case .network: String(localized: "Couldn’t reach Anthropic")
    case .api(let status, let detail): detail ?? String(localized: "Anthropic returned an error (\(status))")
    }
  }

  static func from(status: Int, body: Data) -> ClaudeFailure {
    let detail = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
    switch status {
    case 401, 403: return .invalidKey
    case 402, 429: return .rateLimited
    case 500...599: return status == 529 ? .overloaded : .api(status, detail)
    default: return .api(status, detail)
    }
  }
}

@MainActor
@Observable
final class ClaudeAccount {
  static let shared = ClaudeAccount()
  static let keychainAccount = "anthropic-api-key"
  static let api = URL(string: "https://api.anthropic.com/v1/")!
  static let version = "2026-10-21"
  static let model = "claude-opus-5-5"
  static let maximumAnswerCharacters = 64 * 1024

  private(set) var isConnected: Bool
  private(set) var isChecking = false
  private(set) var problem: String?

  private init() {
    isConnected = KeychainSecret.read(Self.keychainAccount) != nil
  }

  var label: String? {
    guard let key = Self.key, key.count > 8 else { return nil }
    return String(localized: "API key ending in \(String(key.suffix(4)))")
  }

  private static var key: String? {
    KeychainSecret.read(keychainAccount).map { String(decoding: $0, as: UTF8.self) }
  }

  private static func request(_ path: String, query: [URLQueryItem] = [], key: String, method: String = "GET") -> URLRequest {
    let url = query.isEmpty ? api.appending(path: path) : api.appending(path: path).appending(queryItems: query)
    var request = URLRequest(url: url, timeoutInterval: 30)
    request.httpMethod = method
    request.setValue(key, forHTTPHeaderField: "x-api-key")
    request.setValue(version, forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    return request
  }

  @discardableResult
  func save(key raw: String) async -> Bool {
    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    problem = nil
    guard key.hasPrefix("sk-ant-"), key.count > 20 else {
      problem = String(localized: "That doesn’t look like an Anthropic API key. Keys start with sk-ant-.")
      return false
    }
    isChecking = true
    defer { isChecking = false }
    do {
      let (data, response) = try await URLSession.shared.data(for: Self.request("models", query: [URLQueryItem(name: "limit", value: "1")], key: key))
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard status == 200 else {
        problem = ClaudeFailure.from(status: status, body: data).message + "."
        return false
      }
    } catch {
      problem = ClaudeFailure.network.message + "."
      return false
    }
    guard KeychainSecret.write(Data(key.utf8), account: Self.keychainAccount) else {
      problem = String(localized: "Couldn’t save the key to this device’s Keychain.")
      return false
    }
    isConnected = true
    return true
  }

  func remove() {
    KeychainSecret.delete(Self.keychainAccount)
    isConnected = false
    problem = nil
  }

  func clearProblem() { problem = nil }

  func streamSummary(instructions: String, prompt: String, onText: (String) -> Void) async throws {
    guard let key = Self.key else { throw ClaudeFailure.invalidKey }
    var request = Self.request("messages", key: key, method: "POST")
    request.timeoutInterval = 120
    request.setValue("text/event-stream", forHTTPHeaderField: "accept")
    request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
    let body: [String: Any] = [
      "model": Self.model,
      "max_tokens": 8000,
      "stream": true,
      "system": instructions,
      "messages": [["role": "user", "content": prompt]],
      "output_config": ["effort": "low"],
      "fallbacks": "default",
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let bytes: URLSession.AsyncBytes
    let status: Int
    do {
      let (stream, response) = try await URLSession.shared.bytes(for: request)
      bytes = stream
      status = (response as? HTTPURLResponse)?.statusCode ?? 0
    } catch {
      try Task.checkCancellation()
      throw ClaudeFailure.network
    }
    guard status == 200 else {
      var data = Data()
      for try await byte in bytes {
        data.append(byte)
        if data.count > 64 * 1024 { break }
      }
      throw ClaudeFailure.from(status: status, body: data)
    }
    var text = ""
    var stop: String?
    for try await line in bytes.lines {
      try Task.checkCancellation()
      guard line.hasPrefix("data:") else { continue }
      let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
      guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
      switch event["type"] as? String {
      case "content_block_delta":
        guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta", let piece = delta["text"] as? String else { continue }
        text += piece
        guard text.count <= Self.maximumAnswerCharacters else { throw ClaudeFailure.api(200, nil) }
        onText(text)
      case "message_delta":
        if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String { stop = reason }
      case "error":
        let error = event["error"] as? [String: Any]
        throw error?["type"] as? String == "overloaded_error" ? ClaudeFailure.overloaded : ClaudeFailure.api(200, error?["message"] as? String)
      case "message_stop":
        if stop == "refusal" { throw ClaudeFailure.refused }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaudeFailure.api(200, nil) }
        return
      default:
        continue
      }
    }
    try Task.checkCancellation()
    if text.isEmpty { throw ClaudeFailure.network }
  }
}
