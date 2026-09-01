# 一览 Yilan

> 一款 iOS 原生风格的移动浏览器，以书签管理为核心体验。

![Flutter](https://img.shields.io/badge/Flutter-3.22+-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.3+-0175C5?logo=dart)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-brightgreen)

## 功能特性

### 书签管理
- iOS 风格的网格书签页，支持多页翻页
- 长按拖动排序、合并建文件夹
- 多选批量操作（移动、删除）
- 新建文件夹收纳

### 浏览器核心
- 基于 `webview_flutter`，iOS 使用 WKWebView / Android 使用系统 WebView
- 多标签页管理，支持无痕浏览
- 地址栏自动补全、搜索引擎切换
- 页面内查找（关键词高亮）

### 面板工具
- 保存页面截图（长截图）
- 分享页面
- 翻译为中文
- 收藏网页 / 加入阅读清单
- 历史记录 / 阅读清单列表
- 下载中心
- 浏览器设置

### 设计亮点
- 动态主题色 —— 状态栏颜色跟随网页 `<meta name="theme-color">` 自动变化
- 阅读清单支持离线归档
- 标签页预览卡片（带截图 + 圆角裁切）
- 暗色模式支持

## 项目结构

```
lib/
├── main.dart                          # 入口 + AppShell 路由
├── core/
│   ├── logic/board_model.dart         # 书签数据模型（BoardModel）
│   ├── models/
│   │   ├── bookmark.dart              # 书签实体（BookmarkItem / BookmarkFolder）
│   │   └── download_task.dart         # 下载任务模型
│   ├── storage/
│   │   ├── bookmark_store.dart        # SharedPreferences 书签持久化
│   │   └── download_task_store.dart   # 下载任务持久化
│   └── widgets/
│       ├── app_shell.dart             # 底部导航壳
│       └── browser_chrome.dart        # 浏览器 UI 组件（Omnibox / Toolbar / Sheet）
├── features/
│   ├── bookmark_desktop/              # 首页书签网格
│   │   ├── bookmark_desktop_page.dart
│   │   └── widgets/
│   │       ├── bookmark_tile.dart     # 书签磁贴
│   │       ├── edit_bar.dart          # 编辑栏
│   │       └── folder_overlay.dart    # 文件夹弹层
│   ├── browser/                       # 浏览器页面
│   │   ├── browser_page.dart          # 主浏览器（标签页 / 工具栏 / 导航）
│   │   ├── browser_collections_page.dart  # 历史 / 阅读清单列表页
│   │   ├── browser_history.dart       # 历史记录工具
│   │   ├── browser_javascript.dart    # 页面内查找 JS 注入
│   │   ├── browser_navigation.dart    # 地址归一化 / 搜索引擎
│   │   ├── browser_data_store.dart    # 浏览器数据持久化
│   │   ├── offline_archive_service.dart # 阅读清单离线归档
│   │   └── screenshot_service.dart    # 截图服务
│   ├── downloads/                     # 下载功能
│   │   ├── download_controller.dart   # 下载控制器
│   │   └── download_center_page.dart  # 下载中心页面
│   └── settings/                      # 设置页
│       └── settings_page.dart
└── theme/
    └── app_theme.dart                 # 主题 / Design Tokens
```

## 技术栈

| 模块 | 方案 |
|------|------|
| UI 框架 | Flutter (Material 3) |
| 浏览内核 | webview_flutter 4.x |
| 本地存储 | SharedPreferences (JSON) |
| 系统分享 | share_plus |
| 文件路径 | path_provider |
| 下载管理 | MethodChannel → Android 系统下载器 |
| 状态管理 | InheritedWidget + ChangeNotifier |

## 快速开始

```bash
# 安装依赖
flutter pub get

# 运行（iOS 模拟器）
flutter run -d ios

# 运行（Android 模拟器）
flutter run -d android

# 运行测试
flutter test

# 静态分析
dart analyze lib/
```

## 截图

| 首页 | 浏览器 | 面板 |
|------|--------|------|
| 书签网格 + 多页翻页 | 多标签页 + 动态主题色 | 工具列表 + 滚动条 |

## 构建

```bash
# iOS Release
flutter build ios --release

# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release
```

## License

MIT
