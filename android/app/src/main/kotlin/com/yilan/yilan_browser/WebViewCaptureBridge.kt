package com.yilan.yilan_browser

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.util.Base64
import android.webkit.WebView
import java.io.ByteArrayOutputStream
import kotlin.math.ceil
import kotlin.math.min

/** Native, viewport-sized capture used by an Android WebView host. */
object WebViewCaptureBridge {

    fun captureLong(webView: WebView, maxHeightPx: Int = 12000): String {
        check(Looper.myLooper() == Looper.getMainLooper()) {
            "WebView capture must run on the main thread"
        }
        val oldScroll = webView.scrollY
        val width = webView.width
        val viewportHeight = webView.height
        require(width > 0 && viewportHeight > 0) { "WebView is not laid out" }

        val scale = webView.resources.displayMetrics.density * webView.scale
        val contentHeight = ceil(webView.contentHeight * scale).toInt()
        val outputHeight = min(contentHeight.coerceAtLeast(viewportHeight), maxHeightPx)
        val result = Bitmap.createBitmap(width, outputHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)
        var destinationTop = 0
        try {
            while (destinationTop < outputHeight) {
                val scrollY = (destinationTop / scale).toInt()
                webView.scrollTo(0, scrollY)
                canvas.save()
                canvas.translate(0f, -destinationTop.toFloat())
                webView.draw(canvas)
                canvas.restore()
                destinationTop += viewportHeight
            }
            val output = ByteArrayOutputStream()
            result.compress(Bitmap.CompressFormat.PNG, 100, output)
            return Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
        } finally {
            webView.scrollTo(0, oldScroll)
            result.recycle()
        }
    }

}