package cn.sjtu.jiaotong_course

import android.app.Activity
import android.app.DownloadManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** DownloadManager owns background work; preferences survive Activity/process
 * recreation. Only this internal Flutter channel can supply a release URL. */
class AppUpdateBridge(activity: Activity) {
    private val activityRef = WeakReference(activity)
    private val app = activity.applicationContext
    private val prefs = app.getSharedPreferences("app_updates", Context.MODE_PRIVATE)
    private val downloads = app.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val installBusy = AtomicBoolean(false)
    @Volatile private var foreground = false

    fun onResume() {
        foreground = true
        if (prefs.getBoolean("pendingInstall", false) && canInstall()) install(null)
    }

    fun onPause() { foreground = false }
    fun dispose() { foreground = false; activityRef.clear(); worker.shutdown() }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "version" -> safely(result) {
                val info = installedInfo()
                result.success(mapOf("name" to (info.versionName ?: ""), "code" to versionCode(info)))
            }
            "state" -> async(result) { result.success(state()) }
            "download" -> async(result) { result.success(download(call)) }
            "install" -> install(result)
            "allowInstall" -> safely(result) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success(null)
                } else {
                    val activity = activityRef.get() ?: error("当前页面已关闭，请返回应用后重试")
                    prefs.edit().putBoolean("pendingInstall", true).apply()
                    activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${app.packageName}")))
                    result.success(null)
                }
            }
            "openRelease" -> safely(result) {
                val url = call.argument<String>("url") ?: error("发布页面不可用")
                val uri = Uri.parse(url)
                val owner = call.argument<String>("owner") ?: ""
                val repo = call.argument<String>("repo") ?: ""
                val parts = uri.pathSegments
                require(trustedHttps(uri) && uri.host == "github.com" && parts.size >= 4 &&
                    parts[0].equals(owner, true) && parts[1].equals(repo, true) && parts[2] == "releases") {
                    "发布页面不属于配置的 GitHub 仓库"
                }
                val activity = activityRef.get() ?: error("当前页面已关闭")
                activity.startActivity(Intent(Intent.ACTION_VIEW, uri))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun safely(result: MethodChannel.Result?, block: () -> Unit) {
        try { block() } catch (error: Exception) {
            result?.error("update_error", error.message ?: "更新操作失败，请重试", null)
        }
    }

    private fun async(result: MethodChannel.Result, block: () -> Unit) {
        if (worker.isShutdown) { result.error("activity_closed", "当前页面已关闭，请返回应用后重试", null); return }
        worker.execute {
            // MethodChannel.Result supports replies from a worker thread.
            safely(result, block)
        }
    }

    private fun trustedHttps(uri: Uri) = uri.scheme == "https" && uri.port == -1 &&
        uri.userInfo.isNullOrEmpty()

    private fun trustedAsset(uri: Uri, owner: String, repo: String): Boolean {
        val parts = uri.pathSegments
        return owner.matches(Regex("[A-Za-z0-9][A-Za-z0-9-]*")) &&
            repo.matches(Regex("[A-Za-z0-9_.-]+")) && repo != "." && repo != ".." &&
            trustedHttps(uri) && uri.host == "github.com" && parts.size == 6 &&
            parts[0].equals(owner, true) && parts[1].equals(repo, true) &&
            parts[2] == "releases" && parts[3] == "download" &&
            parts[4].isNotEmpty() && parts[5].endsWith(".apk", true)
    }

    private fun download(call: MethodCall): Map<String, Any> {
        val url = call.argument<String>("url") ?: error("当前版本已发布，但未找到可下载的 APK")
        val uri = Uri.parse(url)
        val owner = call.argument<String>("owner") ?: ""
        val repo = call.argument<String>("repo") ?: ""
        require(trustedAsset(uri, owner, repo)) { "APK 下载地址不属于配置的 GitHub Release" }
        val current = state()
        if (current["status"] == "downloading") return current
        if (current["status"] == "ready" && prefs.getString("url", "") == url) return current
        val size = call.argument<Number>("size")?.toLong() ?: 0L
        require(size > 0) { "APK 大小无效，请检查发布附件" }
        val originalName = call.argument<String>("name") ?: "update.apk"
        val name = originalName.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").take(160)
        require(name.endsWith(".apk", true)) { "发布附件不是 APK" }
        val root = app.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: error("无法访问下载目录，请稍后重试")
        val destination = File(root, "updates/${UUID.randomUUID()}/$name")
        require(destination.parentFile?.mkdirs() == true) { "无法创建 APK 下载目录" }
        val previousId = prefs.getLong("downloadId", -1L)
        if (previousId != -1L) downloads.remove(previousId)
        val request = DownloadManager.Request(uri)
            .setTitle("交大课表应用更新")
            .setDescription("正在下载更新……")
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationUri(Uri.fromFile(destination))
        // DownloadManager follows GitHub's signed HTTPS asset redirects with
        // normal TLS verification; no credentials or certificate bypasses.
        val id = downloads.enqueue(request)
        prefs.edit().clear().putLong("downloadId", id).putString("file", destination.absolutePath)
            .putString("url", url).putString("name", name).putLong("size", size)
            .putString("digest", call.argument<String>("digest") ?: "")
            .putLong("baseCode", versionCode(installedInfo()))
            .putBoolean("installDispatched", false).apply()
        return state()
    }

    private fun state(): Map<String, Any> {
        val id = prefs.getLong("downloadId", -1L)
        if (id == -1L) return mapOf("status" to "idle")
        if (versionCode(installedInfo()) > prefs.getLong("baseCode", Long.MAX_VALUE)) {
            prefs.edit().clear().apply()
            return mapOf("status" to "idle")
        }
        prefs.getString("failureMessage", null)?.let {
            return mapOf("status" to "failed", "error" to it)
        }
        downloads.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
            if (cursor == null || !cursor.moveToFirst()) {
                return mapOf("status" to "failed", "error" to "下载已取消，请重试")
            }
            val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val bytes = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                val file = apkFile()
                if (!file.isFile || file.length() != prefs.getLong("size", -1L)) {
                    return mapOf("status" to "failed", "error" to "APK 文件不存在或下载不完整，请重新下载")
                }
                return mapOf("status" to "ready", "bytes" to bytes, "total" to total,
                    "installDispatched" to prefs.getBoolean("installDispatched", false))
            }
            if (status == DownloadManager.STATUS_FAILED) {
                return mapOf("status" to "failed", "error" to "下载失败，请重试")
            }
            return mapOf("status" to "downloading", "bytes" to bytes, "total" to total)
        }
    }

    private fun apkFile(): File {
        val path = prefs.getString("file", null) ?: error("APK 文件不存在，请重新下载")
        val downloadsRoot = app.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: error("无法访问下载目录，请重新下载")
        val root = File(downloadsRoot, "updates").canonicalFile
        val file = File(path).canonicalFile
        require(file.path.startsWith(root.path + File.separator)) { "APK 文件路径无效，请重新下载" }
        return file
    }

    @Suppress("DEPRECATION")
    private fun installedInfo(): PackageInfo = app.packageManager.getPackageInfo(app.packageName,
        if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES)

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Set<String> {
        val certs = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return certs?.map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }?.toSet() ?: emptySet()
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
    private fun canInstall() = Build.VERSION.SDK_INT < 26 || app.packageManager.canRequestPackageInstalls()

    private fun validateApk(file: File) {
        require(file.isFile && file.length() == prefs.getLong("size", -1L)) {
            "APK 文件不存在或下载不完整，请重新下载"
        }
        val digest = prefs.getString("digest", "") ?: ""
        if (digest.startsWith("sha256:")) {
            val checksum = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) { val count = input.read(buffer); if (count < 0) break; checksum.update(buffer, 0, count) }
            }
            require(hex(checksum.digest()).equals(digest.removePrefix("sha256:"), true)) {
                "APK 校验失败，请重新下载"
            }
        }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val downloaded = app.packageManager.getPackageArchiveInfo(file.path, flags)
            ?: error("APK 下载不完整或无法识别，请重新下载")
        val installed = installedInfo()
        require(downloaded.packageName == app.packageName) { "APK 不属于交大课表，请检查 Release 附件" }
        require(versionCode(downloaded) > versionCode(installed)) { "APK versionCode 必须高于当前版本，请检查 Release 附件" }
        val currentSignatures = signatures(installed)
        require(currentSignatures.isNotEmpty() && currentSignatures == signatures(downloaded)) {
            "APK 签名与当前应用不一致，无法覆盖升级，请联系发布者"
        }
    }

    private fun install(result: MethodChannel.Result?) {
        if (!installBusy.compareAndSet(false, true)) { result?.success("waitingForeground"); return }
        if (worker.isShutdown) { installBusy.set(false); result?.success("waitingForeground"); return }
        worker.execute {
            try {
                require(state()["status"] == "ready") { "APK 文件不存在或下载未完成，请重新下载" }
                val file = apkFile()
                validateApk(file)
                prefs.edit().putBoolean("pendingInstall", true).apply()
                main.post {
                    try {
                        val activity = activityRef.get()
                        when {
                            activity == null || activity.isFinishing || !foreground -> result?.success("waitingForeground")
                            !canInstall() -> result?.success("permissionRequired")
                            else -> {
                                // Persist before launching to avoid duplicate installers on resume.
                                val uri = FileProvider.getUriForFile(app, "${app.packageName}.updates.fileprovider", file)
                                val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                intent.clipData = ClipData.newRawUri("APK", uri)
                                prefs.edit().putBoolean("installDispatched", true).putBoolean("pendingInstall", false).apply()
                                activity.startActivity(intent)
                                result?.success("opened")
                            }
                        }
                    } catch (error: Exception) {
                        prefs.edit().putBoolean("installDispatched", false).putBoolean("pendingInstall", false)
                            .putString("failureMessage", "无法打开安装程序，请重新下载").apply()
                        result?.error("install_failed", "无法打开安装程序，请重新下载", null)
                    } finally { installBusy.set(false) }
                }
            } catch (error: Exception) {
                prefs.edit().putBoolean("pendingInstall", false).putBoolean("installDispatched", true)
                    .putString("failureMessage", error.message ?: "无法打开安装程序，请重新下载").apply()
                result?.error("invalid_apk", error.message ?: "无法打开安装程序，请重新下载", null)
                installBusy.set(false)
            }
        }
    }
}
