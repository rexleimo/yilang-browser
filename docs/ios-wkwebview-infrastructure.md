# iOS WKWebView 隐私隔离与截图接入方案

## 当前检查结论

当前 iOS Runner 使用 `webview_flutter: ^4.8.0`，由
`webview_flutter_wkwebview` 创建并持有 `WKWebView`。Flutter 侧只保存
`WebViewController`，项目没有自建 `WKWebView`、`WKWebViewConfiguration` 或
`FlutterPlatformView`。

Runner 当前状态：

- iOS deployment target 为 15.0，Swift 5.0。
- `ios/Runner/AppDelegate.swift` 只注册 `GeneratedPluginRegistrant`，没有自定义
  `FlutterMethodChannel`。
- `GeneratedPluginRegistrant.m` 已接入 `WebViewFlutterPlugin`，不应直接修改该生成文件。
- Flutter 侧的 `_saveScreenshot()` 对 `RepaintBoundary` 调用 `RenderRepaintBoundary.toImage()`。
  这只能可靠地得到 Flutter 当前布局中的可见区域，不是 WKWebView 原生快照，也没有长截图能力。
- “无痕”标签目前仍由 webview_flutter 的默认配置创建；关闭时调用
  `clearCache()` 和 `clearLocalStorage()` 不能保证 cookie、IndexedDB、Service Worker、
  HTTP cache 等数据在共享默认数据仓库中不留痕。

## 为什么目前不能安全直接接入

不能从 `WebViewController` 反向取得 webview_flutter 内部的 `WKWebView`。因此在现有
`WebViewWidget` 上从 `AppDelegate` 添加一个 channel，无法可靠地把调用路由到正确的 tab，
也无法为某一个 tab 设置 `WKWebViewConfiguration.websiteDataStore`。通过遍历 Flutter
view 层级、查找私有对象或修改 Pods 都是不稳定且不可接受的接入方式。

所以本次只准备方案，没有声称已经完成原生隔离或长截图接入。现有可见区域截图仍可继续使用，
但应把它当作 Flutter 渲染树截图，而不是隐私隔离或 WKWebView 长截图基础设施。

## 精确原生 API 方案

需要把浏览器 tab 从 `webview_flutter` 迁移为一个自有的 iOS platform view（或者维护一个
fork/插件，让 `WKWebView` 在创建时接受 configuration）。每个 tab 创建时固定配置，不要
在页面加载后切换 data store：

```swift
import WebKit

func makeConfiguration(isPrivate: Bool) -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = isPrivate
        ? .nonPersistent()
        : .default()
    // 严格无痕 tab 不与普通 tab 共享进程池。
    configuration.processPool = isPrivate
        ? WKProcessPool()
        : sharedPersistentProcessPool
    configuration.allowsInlineMediaPlayback = true
    return configuration
}
```

持久 tab 使用 `.default()`；无痕 tab 必须从创建开始使用 `.nonPersistent()`，关闭时先移除
引用再销毁 view。若产品要求登录态也完全隔离，应为每个无痕会话使用独立
`WKProcessPool`，而不是只清理缓存。退出或清除持久浏览数据时使用：

```swift
let types = WKWebsiteDataStore.allWebsiteDataTypes()
WKWebsiteDataStore.default().removeData(
    ofTypes: types,
    modifiedSince: Date.distantPast
) { /* completion */ }
```

不要把该清理调用当作无痕实现；无痕实现的关键是创建前选定
`WKWebsiteDataStore.nonPersistent()`。

### Platform view / channel 接入点

建议新增 `ios/Runner/IsolatedWebViewPlatformView.swift` 和
`ios/Runner/IsolatedWebViewFactory.swift`，通过 `FlutterPlatformViewsController` 注册
factory。factory 的 `createArgsCodec` 使用 `FlutterStandardMessageCodec`，创建参数至少包含：

```text
id: Int64
url: String
private: Bool
userAgent: String?
```

Flutter 侧改为 `UiKitView(viewType: "yilan.wkwebview", creationParams: ...)`，并通过
`MethodChannel("yilan.wkwebview/<id>")` 调用导航、后退、刷新、可见截图和长截图。不要修改
`ios/Runner/GeneratedPluginRegistrant.m`；在 `AppDelegate.didInitializeImplicitFlutterEngine`
中注册自定义 factory/channel，或将其做成正式 Flutter plugin 后由生成注册器接入。

channel 必须检查 tab id 与拥有者，并只允许白名单方法：

```text
loadRequest(url)
canGoBack()
goBack()
reload()
visibleSnapshot(pixelRatio)
longSnapshot(maxPixelHeight)
destroy()
```

不得开放任意 JavaScript、任意 data store 类型清理或任意文件路径给 Flutter 调用方。

## 可见区域截图

在原生 view 已经可见并完成布局后使用公开 API：

```swift
func visibleSnapshot(of webView: WKWebView,
                    pixelRatio: CGFloat) async throws -> Data {
    let configuration = WKSnapshotConfiguration()
    configuration.rect = webView.bounds
    configuration.snapshotWidth = NSNumber(
        value: Double(webView.bounds.width * pixelRatio)
    )
    let image = try await webView.takeSnapshot(configuration: configuration)
    guard let data = image.pngData() else { throw SnapshotError.encodingFailed }
    return data
}
```

实际实现需在主线程执行，并限制 `pixelRatio`（例如 1...3）及 PNG 大小；结果应以临时文件
或受控 `Uint8List` 返回，不能把敏感截图写入 `Documents` 后永久保留。当前 Flutter
`RenderRepaintBoundary` 方案可以保留作为非原生 fallback，但不要与上述 API 混用或宣称等价。

## 长截图基础设施

长截图不能简单使用一次 `toImage()`。原生实现应：

1. `evaluateJavaScript` 读取页面布局尺寸（至少 `document.documentElement.scrollWidth`、
   `scrollHeight`），同时读取 `webView.scrollView.contentSize` 作上限校验。
2. 限制总像素数和总高度，例如 `maxPixelHeight`、最大 50 MP，超过则返回受控错误。
3. 按固定高度分片；每片通过 `WKSnapshotConfiguration.rect` 调用 `takeSnapshot`。
4. 对每片进行 `CGImage`/`UIGraphicsImageRenderer` 拼接；不要让 Flutter 一次性创建超大
   `ui.Image`。
5. 分片之间等待滚动和下一帧布局，处理 lazy loading；如页面含 fixed/sticky 元素，需产品
   决定是否在 JS 注入的临时样式中隐藏它们，否则会重复出现在每片中。
6. 失败时释放所有中间 image/data，并删除临时文件。

长截图不是完全无副作用：滚动可能触发懒加载、广告刷新或页面状态变化。隐私 tab 的截图
必须明确由用户触发，且不进入历史、分享预览缓存或分析日志。

## 所需改动清单

1. 将 `webview_flutter` 的 iOS tab 渲染替换为自有 platform view，或 fork 插件增加
   configuration / data store 创建参数。
2. 新增 Swift platform-view factory、tab 生命周期管理、上述白名单 channel 和错误码。
3. 将 `BrowserPage` 的 `_BrowserTab` 保存 native view/channel id；创建 private tab 时传入
   `private: true`，关闭 tab 时先调用 `destroy`，再移除 Flutter widget。
4. 将 `_saveScreenshot()` 拆为 `visibleSnapshot` 与 `longSnapshot` 两个明确操作；原生返回
   临时文件路径或 bytes，并在分享/保存后清理临时文件。
5. 更新 iOS Runner 测试：验证 private tab 使用 non-persistent store、普通 tab 使用 default
   store、channel 拒绝未知 tab id、截图尺寸上限和销毁后的调用错误。
6. 在真机上验证 cookie、localStorage、IndexedDB、Service Worker、下载、媒体播放、横竖屏
   和页面懒加载；模拟器验证不足以覆盖 WKWebView 的所有行为。

在完成第 1 步之前，不应把当前实现标记为“隐私数据隔离”或“长截图已支持”。
