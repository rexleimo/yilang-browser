import Flutter
import UIKit
import WebKit

/// Native browser controller used by the migration path, not by the current
/// webview_flutter UI. A data store is selected before WKWebView is created.
final class BrowserViewController: UIViewController {
  let webView: WKWebView
  let isPrivate: Bool

  init(isPrivate: Bool, userAgent: String?) {
    self.isPrivate = isPrivate
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = isPrivate ? .nonPersistent() : .default()
    configuration.processPool = isPrivate ? WKProcessPool() : BrowserViewController.sharedProcessPool
    configuration.allowsInlineMediaPlayback = true
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init(nibName: nil, bundle: nil)
    if let userAgent, !userAgent.isEmpty {
      webView.customUserAgent = userAgent
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() { view = webView }

  func load(urlString: String) throws {
    guard let url = URL(string: urlString), let scheme = url.scheme,
          ["http", "https"].contains(scheme.lowercased()) else {
      throw BrowserViewError.invalidURL
    }
    webView.load(URLRequest(url: url))
  }

  func snapshot(pixelRatio: CGFloat) async throws -> Data {
    guard pixelRatio >= 1, pixelRatio <= 3 else { throw BrowserViewError.invalidSnapshotScale }
    return try await MainActor.run {
      let configuration = WKSnapshotConfiguration()
      configuration.rect = self.webView.bounds
      configuration.snapshotWidth = NSNumber(value: Double(self.webView.bounds.width * pixelRatio))
      return try await self.webView.takeSnapshot(configuration: configuration).pngData()
        ?? { throw BrowserViewError.encodingFailed }()
    }
  }

  static let sharedProcessPool = WKProcessPool()
}

enum BrowserViewError: Error {
  case invalidURL, invalidSnapshotScale, encodingFailed, unsupported
}

/// FlutterPlatformView wrapper. Flutter can later replace WebViewWidget with
/// UiKitView(viewType: "yilan.wkwebview", creationParams: ...).
final class BrowserPlatformView: NSObject, FlutterPlatformView {
  private let controller: BrowserViewController
  private let channel: FlutterMethodChannel
  private var destroyed = false

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    let values = args as? [String: Any]
    let isPrivate = values?["private"] as? Bool ?? false
    let userAgent = values?["userAgent"] as? String
    controller = BrowserViewController(isPrivate: isPrivate, userAgent: userAgent)
    channel = FlutterMethodChannel(name: "yilan.wkwebview/\(viewId)", binaryMessenger: messenger)
    super.init()
    controller.view.frame = frame
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    if let url = values?["url"] as? String, !url.isEmpty {
      do { try controller.load(urlString: url) } catch { resultError(result, error) }
    }
  }

  func view() -> UIView { controller.view }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !destroyed else { resultError(result, BrowserViewError.unsupported); return }
    switch call.method {
    case "loadRequest":
      guard let args = call.arguments as? [String: Any], let url = args["url"] as? String else {
        resultError(result, BrowserViewError.invalidURL); return
      }
      do { try controller.load(urlString: url); result(nil) } catch { resultError(result, error) }
    case "canGoBack": result(controller.webView.canGoBack)
    case "goBack": controller.webView.goBack(); result(nil)
    case "reload": controller.webView.reload(); result(nil)
    case "visibleSnapshot":
      let scale = (call.arguments as? [String: Any])?["pixelRatio"] as? CGFloat ?? 2
      Task { do { result(try await ["bytes": self.controller.snapshot(pixelRatio: scale)]) } catch { resultError(result, error) } }
    case "longSnapshot":
      resultError(result, BrowserViewError.unsupported)
    case "destroy":
      destroyed = true
      channel.setMethodCallHandler(nil)
      controller.webView.stopLoading()
      controller.webView.navigationDelegate = nil
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func resultError(_ result: @escaping FlutterResult, _ error: Error) {
    let code: String
    switch error {
    case BrowserViewError.invalidURL: code = "invalid_request"
    case BrowserViewError.invalidSnapshotScale: code = "invalid_request"
    case BrowserViewError.encodingFailed: code = "capture_failed"
    default: code = "unsupported"
    }
    result(FlutterError(code: code, message: String(describing: error), details: nil))
  }
}

final class BrowserPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    BrowserPlatformView(frame: frame, viewId: viewId, args: args, messenger: messenger)
  }
}
