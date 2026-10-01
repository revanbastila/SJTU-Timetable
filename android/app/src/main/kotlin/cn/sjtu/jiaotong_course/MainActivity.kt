package cn.sjtu.jiaotong_course

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.net.Uri
import android.util.Log
import android.webkit.WebView
import android.webkit.CookieManager
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val updateBridge by lazy { AppUpdateBridge(this) }
    private val permissionChannel = "cn.sjtu.jiaotong_course/permissions"
    private val webHistoryChannel = "cn.sjtu.jiaotong_course/web_history"
    private val locationRequestCode = 7103
    private var pendingLocationResult: MethodChannel.Result? = null
    private var widgetChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        persistWidgetCourseIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val courseId = persistWidgetCourseIntent(intent)
        if (courseId != null) {
            getSharedPreferences(TimetableWidgetProvider.PREFS, MODE_PRIVATE)
                .edit()
                .remove(TimetableWidgetProvider.PENDING_COURSE_ID)
                .apply()
            widgetChannel?.invokeMethod("openCourse", courseId)
        }
    }

    private fun persistWidgetCourseIntent(intent: Intent?): String? {
        val courseId = intent?.getStringExtra(TimetableWidgetProvider.EXTRA_COURSE_ID)
            ?.takeIf { it.isNotBlank() } ?: return null
        getSharedPreferences(TimetableWidgetProvider.PREFS, MODE_PRIVATE)
            .edit()
            .putString(TimetableWidgetProvider.PENDING_COURSE_ID, courseId)
            .apply()
        return courseId
    }

    private fun sameHistoryPage(first: String?, second: String?): Boolean {
        if (first == null || second == null) return false
        val left = Uri.parse(first)
        val right = Uri.parse(second)
        return left.scheme.equals(right.scheme, ignoreCase = true) &&
            left.host.equals(right.host, ignoreCase = true) &&
            left.path?.trimEnd('/') == right.path?.trimEnd('/') &&
            left.encodedQuery == right.encodedQuery &&
            left.encodedFragment == right.encodedFragment
    }

    private fun goBackToTarget(
        webView: WebView,
        targetUrl: String,
        stepwise: Boolean,
        result: MethodChannel.Result
    ) {
        val handler = Handler(Looper.getMainLooper())
        val deadline = SystemClock.uptimeMillis() + 8000
        val walker = object : Runnable {
            var waitingForIndex: Int? = null
            var waitCount = 0

            override fun run() {
                if (SystemClock.uptimeMillis() > deadline) {
                    result.error("invalid_history", "History step timed out", null)
                    return
                }
                val history = webView.copyBackForwardList()
                if (sameHistoryPage(history.currentItem?.url, targetUrl)) {
                    result.success(null)
                    return
                }
                val waiting = waitingForIndex
                if (waiting != null) {
                    if (history.currentIndex < waiting) {
                        waitingForIndex = null
                        waitCount = 0
                    } else if (waitCount++ < 20) {
                        handler.postDelayed(this, 50)
                        return
                    } else {
                        result.error("invalid_history", "History index did not move", null)
                        return
                    }
                }
                val targetIndex = (history.currentIndex - 1 downTo 0)
                    .firstOrNull { index ->
                        sameHistoryPage(history.getItemAtIndex(index)?.url, targetUrl)
                    }
                if (targetIndex == null) {
                    result.error("invalid_history", "Target left the history stack", null)
                    return
                }
                val offset = targetIndex - history.currentIndex
                webView.stopLoading()
                if (!stepwise && webView.canGoBackOrForward(offset)) {
                    webView.goBackOrForward(offset)
                    result.success(null)
                } else if (webView.canGoBack()) {
                    Log.i("WebHistory", "step index=${history.currentIndex} " +
                        "target=$targetIndex")
                    webView.goBack()
                    waitingForIndex = history.currentIndex
                    handler.postDelayed(this, 50)
                } else {
                    result.error("invalid_history", "No native back step available", null)
                }
            }
        }
        webView.stopLoading()
        walker.run()
    }

    override fun onPause() {
        updateBridge.onPause()
        CookieManager.getInstance().flush()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        updateBridge.onResume()
    }

    override fun onDestroy() {
        updateBridge.dispose()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CanvasAnnouncementSync.bind(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "cn.sjtu.jiaotong_course/updates").setMethodCallHandler(updateBridge::handle)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            webHistoryChannel
        ).setMethodCallHandler { call, result ->
            if (call.method == "canvasCookies") {
                val url = call.argument<String>("url")
                val uri = url?.let(Uri::parse)
                if (uri?.scheme == "https" && uri.host == "oc.sjtu.edu.cn") {
                    result.success(CookieManager.getInstance().getCookie(url) ?: "")
                } else {
                    result.error("invalid_avatar_host", "Canvas cookie host required", null)
                }
                return@setMethodCallHandler
            }
            val identifier = call.argument<Number>("webViewIdentifier")?.toLong()
            val webView = identifier?.let {
                WebViewFlutterAndroidExternalApi.getWebView(flutterEngine, it)
            }
            if (webView == null) {
                result.error("webview_unavailable", "WebView is no longer available", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "stopLoading" -> {
                    webView.stopLoading()
                    result.success(null)
                }
                "stopAndSnapshot" -> {
                    webView.stopLoading()
                    val history = webView.copyBackForwardList()
                    result.success(mapOf(
                        "currentIndex" to history.currentIndex,
                        "urls" to (0 until history.size).map { index ->
                            history.getItemAtIndex(index)?.url
                        }
                    ))
                }
                "goBackOrForward" -> {
                    val offset = call.argument<Int>("offset")
                    if (offset == null || offset >= 0 ||
                        !webView.canGoBackOrForward(offset)) {
                        result.error("invalid_history", "Back entry is unavailable", null)
                    } else {
                        webView.goBackOrForward(offset)
                        result.success(null)
                    }
                }
                "goBackTo" -> {
                    val targetUrl = call.argument<String>("targetUrl")
                    if (targetUrl != null) {
                        goBackToTarget(webView, targetUrl,
                            call.argument<Boolean>("stepwise") == true, result)
                    } else {
                        result.error("invalid_history", "Missing history target", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cn.sjtu.jiaotong_course/widget"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateSnapshot" -> {
                        val snapshot = call.argument<String>("snapshot")
                        if (snapshot.isNullOrBlank()) {
                            result.error("invalid_snapshot", "Missing timetable data", null)
                        } else {
                            getSharedPreferences(TimetableWidgetProvider.PREFS, MODE_PRIVATE)
                                .edit()
                                .putString(TimetableWidgetProvider.SNAPSHOT, snapshot)
                                .apply()
                            TimetableWidgetProvider.updateAll(this)
                            result.success(null)
                        }
                    }
                    "consumePendingCourseId" -> {
                        val preferences = getSharedPreferences(
                            TimetableWidgetProvider.PREFS,
                            MODE_PRIVATE
                        )
                        val pending = preferences.getString(
                            TimetableWidgetProvider.PENDING_COURSE_ID,
                            null
                        )
                        preferences.edit()
                            .remove(TimetableWidgetProvider.PENDING_COURSE_ID)
                            .apply()
                        result.success(pending)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            permissionChannel
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestLocationPermission") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED ||
                checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            ) {
                result.success(true)
                return@setMethodCallHandler
            }
            if (pendingLocationResult != null) {
                result.success(false)
                return@setMethodCallHandler
            }
            pendingLocationResult = result
            requestPermissions(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                locationRequestCode
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != locationRequestCode) return
        val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
        pendingLocationResult?.success(granted)
        pendingLocationResult = null
    }
}
