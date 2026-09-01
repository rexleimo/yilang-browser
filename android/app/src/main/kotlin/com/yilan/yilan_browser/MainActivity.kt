package com.yilan.yilan_browser

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment

import android.webkit.URLUtil
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.yilan.yilan_browser/android_browser"

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
                            result.success(enqueueDownload(call.argument<String>("userAgent"), url,
                                call.argument<String>("contentDisposition"), call.argument<String>("mimeType")))
                        } catch (error: Exception) {
                            result.error("download_failed", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun enqueueDownload(userAgent: String?, url: String,
                                contentDisposition: String?, mimeType: String?): Long {
        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(false)
            setTitle(URLUtil.guessFileName(url, contentDisposition, mimeType))
            if (!userAgent.isNullOrBlank()) addRequestHeader("User-Agent", userAgent)
            if (!mimeType.isNullOrBlank()) setMimeType(mimeType)
            // Use the public Downloads provider; no storage permission is needed on modern Android.
            setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS,
                URLUtil.guessFileName(url, contentDisposition, mimeType))
        }
        return (getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager).enqueue(request)
    }
}
