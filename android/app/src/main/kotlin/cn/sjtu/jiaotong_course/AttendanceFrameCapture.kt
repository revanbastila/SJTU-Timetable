package cn.sjtu.jiaotong_course

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import com.google.zxing.*
import com.google.zxing.common.HybridBinarizer
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import androidx.webkit.ScriptHandler
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** Copies only the app's own visible video rectangle; no MediaProjection,
 * camera, accessibility service, protected-surface workaround or saved frames. */
class AttendanceFrameCapture(private val activity: MainActivity, private val engine: FlutterEngine) {
    private val generation = AtomicInteger()
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var busy = false
    private var closed = false
    private val scripts = mutableMapOf<Long,ScriptHandler>()
    fun cancel() { generation.incrementAndGet() }
    fun dispose() { closed = true; cancel(); scripts.values.forEach { it.remove() }; scripts.clear(); worker.shutdown() }
    fun installNavigation(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("webViewIdentifier")?.toLong()
        val web = id?.let { WebViewFlutterAndroidExternalApi.getWebView(engine,it) }
        if (id == null || web == null || !WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            result.success(false); return
        }
        scripts.remove(id)?.remove()
        // Preserve Canvas' real signed POST body and normal SSO. Only the
        // current course's standard LTI form changes its target to this view.
        val code = """
          (() => {
            if (!/^\/courses\/\d+\/external_tools\/\d+/.test(location.pathname)) return;
            const prepare = form => {
              try {
                const destination = new URL(form.action, location.href);
                const lti = form.querySelector('[name=lti_message_type],[name=id_token]');
                if (lti && destination.protocol === 'https:' &&
                    destination.hostname !== 'oc.sjtu.edu.cn') form.target = '_self';
              } catch (_) {}
            };
            for (const method of ['submit', 'requestSubmit']) {
              const original = HTMLFormElement.prototype[method];
              if (typeof original !== 'function') continue;
              HTMLFormElement.prototype[method] = function(...args) {
                prepare(this); return original.apply(this,args);
              };
            }
            document.addEventListener('submit', event => prepare(event.target),true);
          })();
        """.trimIndent()
        scripts[id] = WebViewCompat.addDocumentStartJavaScript(web,code,setOf("https://oc.sjtu.edu.cn"))
        result.success(true)
    }
    fun release(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("webViewIdentifier")?.toLong()
        id?.let {
            scripts.remove(it)?.remove()
            WebViewFlutterAndroidExternalApi.getWebView(engine,it)?.apply { stopLoading(); loadUrl("about:blank") }
        }
        cancel(); result.success(null)
    }
    fun capture(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 26) {
            result.error("capture_unavailable","当前系统不支持应用内画面采集",null); return
        }
        if (closed || busy || activity.isFinishing || activity.isDestroyed) { result.success(null); return }
        val id = call.argument<Number>("webViewIdentifier")?.toLong()
        val web = id?.let { WebViewFlutterAndroidExternalApi.getWebView(engine,it) }
        if (web == null || !web.isShown || web.width <= 0 || web.height <= 0) {
            result.error("video_unavailable","直播画面当前不可见",null); return
        }
        fun number(key: String) = call.argument<Number>(key)?.toDouble() ?: Double.NaN
        val x = number("x"); val y = number("y"); val w = number("width"); val h = number("height")
        if (listOf(x,y,w,h).any { !it.isFinite() } || x < 0 || y < 0 || w <= 0 || h <= 0 || x+w > 1.001 || y+h > 1.001) {
            result.error("video_bounds","无法确认直播画面范围",null); return
        }
        val location = IntArray(2); web.getLocationInWindow(location)
        val rect = Rect(location[0]+(x*web.width).toInt(),location[1]+(y*web.height).toInt(),
            location[0]+((x+w)*web.width).toInt(),location[1]+((y+h)*web.height).toInt())
        val decor = activity.window.decorView
        val clipped = rect.intersect(0,0,decor.width,decor.height)
        if (!clipped || rect.width() < 32 || rect.height() < 32) { result.success(null); return }
        val scale = minOf(1.0,1280.0/rect.width())
        val bitmap = Bitmap.createBitmap((rect.width()*scale).toInt(),(rect.height()*scale).toInt(),Bitmap.Config.ARGB_8888)
        val epoch = generation.get(); busy = true
        try {
            PixelCopy.request(activity.window,rect,bitmap,{ status ->
                if (closed || generation.get() != epoch || status != PixelCopy.SUCCESS) {
                    bitmap.recycle(); busy=false
                    if (status != PixelCopy.SUCCESS) result.error("capture_failed","无法取得直播画面，播放器可能受保护",null)
                    else result.success(null)
                    return@request
                }
                try { worker.execute {
                    var qr: String? = null
                    var black = true
                    try {
                        val pixels = IntArray(bitmap.width*bitmap.height)
                        bitmap.getPixels(pixels,0,bitmap.width,0,0,bitmap.width,bitmap.height)
                        var min = 255; var max = 0
                        for (i in pixels.indices step 257) {
                            val p = pixels[i]; val luma = (Color.red(p)*3+Color.green(p)*6+Color.blue(p))/10
                            min=minOf(min,luma); max=maxOf(max,luma)
                        }
                        black = max < 16 || max-min < 8
                        if (!black) {
                            val source = RGBLuminanceSource(bitmap.width,bitmap.height,pixels)
                            val reader = MultiFormatReader()
                            val decoded = reader.decode(BinaryBitmap(HybridBinarizer(source)),mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE)))
                            if (decoded.text.length <= 8192) qr=decoded.text
                            reader.reset()
                        }
                    } catch (_: NotFoundException) { /* A normal frame often has no QR. */ }
                    catch (_: Exception) { /* Never log frame content or decoded parameters. */ }
                    finally { bitmap.recycle() }
                    main.post {
                        busy=false
                        if (closed || generation.get()!=epoch) result.success(null)
                        else if (black) result.error("black_frame","未能取得有效视频画面",null)
                        else result.success(qr)
                    }
                } } catch (_: java.util.concurrent.RejectedExecutionException) {
                    bitmap.recycle(); busy=false; result.success(null)
                }
            },main)
        } catch (_: Exception) {
            bitmap.recycle(); busy=false
            result.error("capture_failed","无法取得直播画面",null)
        }
    }
}
