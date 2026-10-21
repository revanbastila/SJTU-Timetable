package cn.sjtu.jiaotong_course

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.*
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Normal Canvas LTI launch using the app's existing CookieManager profile.
 * Used once on missing/expired binding, never on every record poll. It cannot
 * fill passwords, solve challenges, capture video or submit attendance. */
object AttendanceSessionResolver {
    private val main = Handler(Looper.getMainLooper())
    data class Session(val code: String = "", val token: String = "", val reason: String = "session_login")
    fun resolve(c: Context, launch: String, valid: () -> Boolean): Session {
        check(Looper.myLooper() != Looper.getMainLooper())
        val latch = CountDownLatch(1)
        var outcome = Session(reason="connect_required")
        val deadline=System.currentTimeMillis()+20_000
        main.post {
            if (System.currentTimeMillis()>=deadline || !valid()) { latch.countDown(); return@post }
            if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) { latch.countDown(); return@post }
            var done = false
            var web: WebView? = null
            val callbacks = Handler(Looper.getMainLooper())
            fun finish(value: Session) {
                if (done) return
                done = true; outcome = value
                callbacks.removeCallbacksAndMessages(null)
                web?.apply { stopLoading(); loadUrl("about:blank"); destroy() }; web = null
                latch.countDown()
            }
            try {
                web = WebView(c.applicationContext).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                }
                WebViewCompat.addDocumentStartJavaScript(web!!, """
                    (()=>{
                      const prepare=f=>{try{const u=new URL(f.action,location.href);
                        if(f.querySelector('[name=lti_message_type],[name=id_token]')&&u.protocol==='https:'&&u.hostname!=='oc.sjtu.edu.cn')f.target='_self';}catch(_){}};
                      for(const k of ['submit','requestSubmit']){const old=HTMLFormElement.prototype[k];if(old)HTMLFormElement.prototype[k]=function(...a){prepare(this);return old.apply(this,a)}}
                      document.addEventListener('submit',e=>prepare(e.target),true);
                    })()
                """.trimIndent(), setOf("https://oc.sjtu.edu.cn"))
                val inspect = object : Runnable {
                    override fun run() {
                        if(done) return
                        if(!valid()) { finish(Session(reason="cancelled")); return }
                        val uri=Uri.parse(web?.url ?: "")
                        if(uri.host=="jaccount.sjtu.edu.cn" || (uri.host=="oc.sjtu.edu.cn" && uri.path.orEmpty().startsWith("/login"))) {
                            web?.evaluateJavascript("!!document.querySelector('input[type=password],input[name=captcha]')") { raw ->
                                if(raw=="true") finish(Session(reason="canvas_login"))
                            }
                        }
                        if(uri.scheme=="https" && uri.host=="mlearning.sjtu.edu.cn" && uri.path.orEmpty().startsWith("/lms/rollcall/")) {
                            web?.evaluateJavascript("(location.protocol==='https:' && location.host==='mlearning.sjtu.edu.cn' && location.pathname.startsWith('/lms/rollcall/')) ? JSON.stringify({courseCode:new URL(location.href).searchParams.get('courseCode')||'',token:window.RollCall_Access_Token||''}) : null") { raw ->
                                if(done) return@evaluateJavascript
                                try {
                                    val value=JSONObject(org.json.JSONTokener(raw).nextValue() as String)
                                    val code=value.optString("courseCode"); val token=value.optString("token")
                                    if(code.matches(Regex("[A-Za-z0-9._~-]{1,128}")) && token.length in 16..16384 && !token.contains('\n') && !token.contains('\r')) {
                                        finish(Session(code,token,"")); return@evaluateJavascript
                                    }
                                } catch(_: Exception) {}
                            }
                        }
                        callbacks.postDelayed(this,500)
                    }
                }
                web!!.webViewClient=object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        val uri=request.url
                        if(uri.scheme!="https" && uri.scheme!="about") { finish(Session(reason="connect_required"));return true }
                        return false
                    }
                    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                        if(request.isForMainFrame) finish(Session(reason="network"))
                    }
                }
                callbacks.postDelayed({ finish(Session(reason="connect_required")) },18_000)
                callbacks.post(inspect)
                web!!.loadUrl(launch)
            } catch(_: Exception) { finish(Session(reason="connect_required")) }
        }
        if(!latch.await(20,TimeUnit.SECONDS)) return Session(reason="network")
        return outcome
    }
}
