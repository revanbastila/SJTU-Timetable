package cn.sjtu.jiaotong_course

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.*
import org.json.JSONObject
import org.json.JSONTokener
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Read the authenticated course's own navigation when its JSON tabs fail.
 * This never invents tool IDs or follows a tool before user confirmation. */
object AttendanceCourseEntries {
    private val main = Handler(Looper.getMainLooper())
    // WebView creation/SSO is bounded and serialized independently of record HTTP.
    @Synchronized fun discover(c: Context, id: String, valid: () -> Boolean): JSONObject {
        check(Looper.myLooper() != Looper.getMainLooper())
        val latch = CountDownLatch(1)
        var outcome = JSONObject().put("status", "network")
        val deadline = android.os.SystemClock.elapsedRealtime() + 15_000
        main.post {
            if (!valid() || android.os.SystemClock.elapsedRealtime() >= deadline) { latch.countDown(); return@post }
            val callbacks = Handler(Looper.getMainLooper())
            var web: WebView? = null
            var done = false
            fun finish(result: JSONObject) {
                if (done) return
                done = true; outcome = result
                callbacks.removeCallbacksAndMessages(null)
                web?.apply { stopLoading(); destroy() }; web = null
                latch.countDown()
            }
            fun fail(reason: String) = finish(JSONObject().put("status", reason))
            try {
                web = WebView(c.applicationContext).apply {
                    settings.javaScriptEnabled = true; settings.domStorageEnabled = true
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                }
                val inspect = object : Runnable {
                    override fun run() {
                        if (done) return
                        if (!valid()) { fail("cancelled"); return }
                        val uri = Uri.parse(web?.url ?: "")
                        if (uri.host == "jaccount.sjtu.edu.cn" ||
                            (uri.host == "oc.sjtu.edu.cn" && uri.path.orEmpty().startsWith("/login"))) {
                            fail("canvas_login"); return
                        }
                        if (uri.scheme == "https" && uri.host == "oc.sjtu.edu.cn" && uri.path == "/courses/$id") {
                            web?.evaluateJavascript("""
                              (() => {
                                const nav=document.querySelector('#section-tabs');
                                if(!nav || !window.ENV || !ENV.current_user_id) return null;
                                return JSON.stringify({status:'ok',links:[...nav.querySelectorAll('a[href]')].map(a=>({label:a.textContent,href:a.href}))});
                              })()
                            """.trimIndent()) { raw ->
                                if (done) return@evaluateJavascript
                                try {
                                    val data = JSONObject(JSONTokener(raw).nextValue() as String)
                                    val result = JSONObject().put("status", "ok").put("source", "course_navigation")
                                    val links = data.getJSONArray("links")
                                    for (i in 0 until links.length()) {
                                        val row = links.getJSONObject(i)
                                        put(result, id, row.optString("label"), row.optString("href"))
                                    }
                                    finish(result)
                                } catch (_: Exception) { /* Wait for the actual course navigation. */ }
                            }
                        }
                        callbacks.postDelayed(this, 400)
                    }
                }
                web!!.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        if (request.url.scheme != "https") { fail("format"); return true }
                        return false
                    }
                    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                        if (request.isForMainFrame) fail("network")
                    }
                    override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                        if (request.isForMainFrame) fail(when(response.statusCode) { 401 -> "canvas_login"; 403 -> "permission"; else -> "server" })
                    }
                }
                callbacks.postDelayed({ fail("network") }, 14_000)
                callbacks.post(inspect)
                web!!.loadUrl("https://oc.sjtu.edu.cn/courses/$id")
            } catch (_: Exception) { fail("format") }
        }
        latch.await(16, TimeUnit.SECONDS)
        return outcome
    }

    fun put(out: JSONObject, id: String, text: String, url: String) {
        val uri = try { Uri.parse(java.net.URL(java.net.URL("https://oc.sjtu.edu.cn/"), url).toString()) } catch (_: Exception) { return }
        if (uri.scheme != "https" || uri.host != "oc.sjtu.edu.cn" || uri.port !in listOf(-1,443) || uri.userInfo != null ||
            !uri.path.orEmpty().matches(Regex("/courses/$id/external_tools/[0-9]+"))) return
        val label = text.replace(Regex("[\\s（）()·]"), "")
        val clean = uri.buildUpon().clearQuery().fragment(null).build().toString()
        if (label == "点名签到") out.put("attendanceUrl", clean)
        if (label.contains("课堂视频") && label.contains("新版") && !label.contains("旧版")) out.put("liveUrl", clean)
    }
}
