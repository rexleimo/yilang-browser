import Flutter
import Foundation

/// Registers the native migration surface without claiming that Flutter has
/// already switched from webview_flutter to this platform view.
final class IOSBrowserNativeService: NSObject {
  static let channelName = "com.yilan.yilan_browser/ios_browser"
  static let viewType = "yilan.wkwebview"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "capabilities":
        // The Flutter page still uses webview_flutter; this is migration-only.
        result([
          "nativeWebViewAccess": false,
          "platformView": false,
          "visibleSnapshot": false,
          "longSnapshot": false,
          "privateDataStore": false,
          "status": "unsupported_until_platform_view_migration",
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
