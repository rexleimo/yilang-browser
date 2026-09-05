package com.yilan.yilan_browser

import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.webkit.URLUtil
import android.webkit.WebView
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.yilan.yilan_browser/android_browser"
    private val screenshotChannelName = "com.yilan.yilan_browser/screenshot"
    private val fileProviderAuthority = "com.yilan.yilan_browser.fileprovider"

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enqueueDownload" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("invalid_url", "Download URL is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(enqueueDownload(
                                call.argument<String>("userAgent"),
                                url,
                                call.argument<String>("contentDisposition"),
                                call.argument<String>("mimeType"),
                                call.argument<String>("fileName"),
                            ))
                        } catch (error: Exception) {
                            result.error("download_failed", error.message, null)
                        }
                    }
                    "downloadStatus" -> {
                        val id = call.argument<Number>("id")?.toLong()
                        if (id == null) {
                            result.error("invalid_id", "Download id is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(downloadStatus(id))
                        } catch (error: Exception) {
                            result.error("download_failed", error.message, null)
                        }
                    }
                    "cancelDownload" -> {
                        val id = call.argument<String>("id")?.toLongOrNull()
                            ?: call.argument<Number>("id")?.toLong()
                        if (id == null) {
                            result.error("invalid_id", "Download id is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val removed = downloadManager().remove(id)
                            result.success(mapOf("removed" to removed))
                        } catch (error: Exception) {
                            result.error("download_failed", error.message, null)
                        }
                    }
                    "openDownload" -> {
                        val id = call.argument<String>("id")?.toLongOrNull()
                            ?: call.argument<Number>("id")?.toLong()
                        if (id == null) {
                            result.error("invalid_id", "Download id is empty", null)
                            return@setMethodCallHandler
                        }
                        openDownload(id, result)
                    }
                    "requestAppPermissions" -> {
                        val permissions = call.argument<List<String>>("permissions")
                            ?: emptyList()
                        val missing = permissions.filter {
                            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
                        }
                        if (missing.isEmpty()) {
                            result.success(mapOf("granted" to true))
                        } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                            result.success(mapOf("granted" to false))
                        } else {
                            pendingPermissionResult = result
                            requestPermissions(missing.toTypedArray(), permissionRequestCode)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenshotChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "captureVisible", "captureLong" -> {
                        val maxHeight = call.argument<Number>("maxHeight")?.toInt() ?: 12000
                        val url = call.argument<String>("url")
                        try {
                            val webView = findWebView(url)
                                ?: throw IllegalStateException("没有正在运行的网页可以截取")
                            val bytes = if (call.method == "captureLong") {
                                WebViewCaptureBridge.captureLong(webView, maxHeight)
                            } else {
                                WebViewCaptureBridge.captureVisible(webView)
                            }
                            result.success(mapOf("bytes" to bytes))
                        } catch (error: Throwable) {
                            result.error("capture_failed", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val pending = pendingPermissionResult
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pending?.success(mapOf("granted" to granted))
    }

    private val permissionRequestCode: Int
        get() = 4711

    private fun downloadManager(): DownloadManager =
        getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private fun enqueueDownload(userAgent: String?, url: String,
                                contentDisposition: String?, mimeType: String?,
                                fileNameHint: String?): Map<String, Any?> {
        val fileName = fileNameHint?.takeIf { it.isNotBlank() && !it.endsWith("/") }
            ?: URLUtil.guessFileName(url, contentDisposition, mimeType)
        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(false)
            setTitle(fileName)
            if (!userAgent.isNullOrBlank()) addRequestHeader("User-Agent", userAgent)
            if (!mimeType.isNullOrBlank()) setMimeType(mimeType)
            // Use the public Downloads provider; no storage permission is needed on modern Android.
            setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
        }
        val id = downloadManager().enqueue(request)
        val destination = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS)
        return mapOf(
            "id" to id,
            "fileName" to fileName,
            "localPath" to File(destination, fileName).absolutePath,
            "status" to "running",
            "downloadedBytes" to 0L,
        )
    }

    private fun downloadStatus(id: Long): Map<String, Any?> {
        val cursor = downloadManager().query(DownloadManager.Query().setFilterById(id))
        if (cursor == null || !cursor.moveToFirst()) {
            // 系统里已经查不到这条任务：多半被用户在系统下载管理里删掉了。
            return mapOf("id" to id, "status" to "cancelled")
        }
        val statusIndex = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
        val bytesIndex = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
        val totalIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
        val localUriIndex = cursor.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI)
        val reasonIndex = cursor.getColumnIndex(DownloadManager.COLUMN_REASON)
        val status = when (cursor.getInt(statusIndex)) {
            DownloadManager.STATUS_SUCCESSFUL -> "completed"
            DownloadManager.STATUS_FAILED -> "failed"
            DownloadManager.STATUS_PAUSED -> "paused"
            DownloadManager.STATUS_RUNNING -> "running"
            else -> "queued"
        }
        val bytes = if (bytesIndex >= 0) cursor.getLong(bytesIndex) else 0L
        val total = if (totalIndex >= 0) cursor.getLong(totalIndex) else -1L
        val localUri = if (localUriIndex >= 0) cursor.getString(localUriIndex) else null
        val reason = if (reasonIndex >= 0) cursor.getString(reasonIndex) else null
        cursor.close()
        return mapOf(
            "id" to id,
            "status" to status,
            "downloadedBytes" to bytes,
            "totalBytes" to if (total > 0) total else null,
            "localPath" to localUri?.let { stripFileScheme(it) },
            "error" to if (status == "failed") (reason ?: "下载失败") else null,
        )
    }

    private fun openDownload(id: Long, result: MethodChannel.Result) {
        val cursor = downloadManager().query(DownloadManager.Query().setFilterById(id))
        var localUri: String? = null
        var mimeType: String? = null
        if (cursor != null && cursor.moveToFirst()) {
            val localUriIndex = cursor.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI)
            val mimeIndex = cursor.getColumnIndex(DownloadManager.COLUMN_MEDIA_TYPE)
            if (localUriIndex >= 0) localUri = cursor.getString(localUriIndex)
            if (mimeIndex >= 0) mimeType = cursor.getString(mimeIndex)
            cursor.close()
        }
        val path = localUri?.let { stripFileScheme(it) }
        if (path == null || !File(path).exists()) {
            result.error("file_missing", "下载文件不存在或已被移动", null)
            return
        }
        val contentUri = FileProvider.getUriForFile(this, fileProviderAuthority, File(path))
        val type = mimeType?.takeIf { it.isNotBlank() } ?: URLUtil.guessFileName(path, null, null)
            .let { name ->
                val extension = name.substringAfterLast('.', "").lowercase()
                when (extension) {
                    "apk" -> "application/vnd.android.package-archive"
                    "pdf" -> "application/pdf"
                    "zip" -> "application/zip"
                    else -> "application/octet-stream"
                }
            }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, type)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
            result.success(mapOf("opened" to true))
        } catch (error: ActivityNotFoundException) {
            result.error("no_viewer", "没有可以打开这类文件的应用", null)
        }
    }

    /** 追加当前标签页的 URL，方便在多个 WebView 里挑出要截取的那一个。 */
    private fun findWebView(currentUrl: String?): WebView? {
        val candidates = collectWebViewCandidates()
        if (candidates.isEmpty()) return null
        if (!currentUrl.isNullOrBlank()) {
            candidates.firstOrNull { it.url == currentUrl }?.let { return it }
            val host = Uri.parse(currentUrl).host
            if (!host.isNullOrBlank()) {
                candidates.firstOrNull {
                    Uri.parse(it.url).host?.endsWith(host) == true
                }?.let { return it }
            }
        }
        // 兜底：取内容最高的那个（通常是正在展示的长页面）。
        return candidates.maxByOrNull { it.contentHeight }
    }

    private fun collectWebViewCandidates(): List<WebView> {
        val found = LinkedHashSet<WebView>()
        window?.decorView?.let { collectWebViews(it, found) }
        try {
            val registry = flutterEngine?.plugins
            val plugin = registry?.get(
                Class.forName("io.flutter.plugins.webviewflutter.WebViewFlutterPlugin")
                    .asSubclass(FlutterPlugin::class.java))
            if (plugin != null) {
                val manager = plugin.javaClass
                    .getMethod("getInstanceManager")
                    .invoke(plugin)
                val field = manager.javaClass.getDeclaredField("weakInstances")
                field.isAccessible = true
                @Suppress("UNCHECKED_CAST")
                val instances = field.get(manager) as Map<Long, Any>
                for (value in instances.values) {
                    val instance = (value as? java.lang.ref.Reference<*>)?.get() ?: value
                    if (instance is WebView) found.add(instance)
                }
            }
        } catch (_: Throwable) {
            // 插件内部结构变化时静默放弃；视图树扫描的结果仍然可用。
        }
        return found.filter { it.width > 0 && it.height > 0 }
    }

    private fun collectWebViews(view: android.view.View, sink: MutableSet<WebView>) {
        if (view is WebView) {
            sink.add(view)
            return
        }
        if (view is android.view.ViewGroup) {
            for (index in 0 until view.childCount) {
                collectWebViews(view.getChildAt(index), sink)
            }
        }
    }

    private fun stripFileScheme(raw: String): String? {
        if (!raw.startsWith("file://")) return raw
        return try {
            Uri.parse(raw).path
        } catch (_: Exception) {
            null
        }
    }
}
