/// Core layer public API（logic / models / storage / widgets / metrics）。
library;
export 'metrics.dart';
export 'logic/app_update.dart';
export 'logic/board_model.dart';
export 'logic/search_engines.dart';
export 'logic/search_suggest.dart';
export 'models/bookmark.dart';
export 'models/download_task.dart';
export 'storage/bookmark_codec.dart';
export 'storage/bookmark_store.dart';
export 'storage/download_task_store.dart';
export 'storage/favicon_service.dart';
export 'storage/sqlite_bookmark_store.dart';
export 'widgets/app_shell.dart';
export 'widgets/browser_chrome.dart';
export 'widgets/ui_kit.dart';