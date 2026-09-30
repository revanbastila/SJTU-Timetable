# 1.14.17 GitHub Releases 更新功能

## 配置与发布

入口：我的 → 右上角设置 → 关于 → 检查更新。当前版本来自 Android 已安装包的 versionName/versionCode。

`lib/services/update_config.dart` 集中保存更新源，当前设为 `revanbastila/SJTU-Timetable`。无需 Token。也可通过构建参数覆盖：

```powershell
./scripts/build_apk.ps1 -Offline -GitHubOwner YOUR_OWNER -GitHubRepo YOUR_REPO
```

当前 APK 如从 GitHub main 构建，会使用以上更新源。自动检查每 24 小时最多一次，网络失败静默；手动检查不受限频。

版本配置：`pubspec.yaml` 的 `version: 1.14.18+59`。加号前为 versionName，加号后为 versionCode。以后每次发布必须增大 versionCode，版本名按数字段增加。支持 v/V 前缀、两段、三段和历史四段版本名。

在对应公开仓库的 Releases 页面创建正式 Release，tag 如 `v1.14.18`，填写标题和更新说明，将同一 applicationId、同一证书签名且 versionCode 更大的 APK 上传为附件，然后 Publish release。不能标记 Draft 或 Prerelease。更新说明支持换行、普通文本、- / * / • 列表；长内容可滚动。

附件文件名以 `.apk` 结尾；推荐 `jiaotong_course-1.14.18-release.apk` 或包含 `universal` 的文件名。存在多个合法 APK 时优先第一个包含 release/universal 的文件，否则选第一个合法 APK。不要同时上传多个不同签名的安装包。没有 APK 时显示明确提示，并禁用立即更新。

## 文件与架构

新增：

- `lib/models/app_update.dart`：版本比较、Release 数据模型与 APK 选择。
- `lib/services/update_config.dart`：公开仓库、限频和地址校验。
- `lib/services/github_release_api.dart`：异步 GitHub API，连接/读取超时、响应上限和错误处理。
- `lib/services/android_update_bridge.dart`：Flutter 与 Android 更新专用通道。
- `lib/services/update_manager.dart`：检查、生命周期、下载进度、安装和提示状态。
- `lib/widgets/app_update_ui.dart`：设置入口、主题弹窗、启动监听与当前版本显示。
- `android/app/src/main/kotlin/cn/sjtu/jiaotong_course/AppUpdateBridge.kt`：DownloadManager、APK 校验、系统安装和未知来源设置。
- `android/app/src/main/res/xml/update_provider_paths.xml`：限定 APK 共享目录。
- `test/app_update_test.dart`：更新流程、版本、安全地址和主题弹窗测试。
- `test/github_release_api_test.dart`：官方接口、请求头、超时/网络与 HTTP 错误测试。
- 本文档。

修改：`lib/pages/home_shell.dart`、`lib/pages/settings_page.dart`、`android/app/src/main/kotlin/cn/sjtu/jiaotong_course/MainActivity.kt`、`android/app/src/main/AndroidManifest.xml`、`pubspec.yaml`、`scripts/build_apk.ps1`、`test/week_widget_test.dart`。

没有新增网络库，没有修改 Canvas、头像来源/缓存、课表或小组件逻辑。项目使用 Dart HttpClient、SharedPreferences、Android DownloadManager；最低 Android 24。

## 下载和安装

下载在 Android 本机的应用专属外部目录：

```text
/storage/emulated/0/Android/data/cn.sjtu.jiaotong_course/files/Download/updates/<随机目录>/<Release 原始文件名>.apk
```

文件名仅过滤非法路径字符。下载任务和安装状态持久化，离开页面不取消系统下载，返回前台恢复查询。手动点击可重新打开已下载包的安装流程。失败时可以重新下载。

FileProvider authority：`${applicationId}.updates.fileprovider`，不导出，允许临时 URI 授权；只共享 `Download/updates/` 子目录。安装使用 content URI、APK MIME、FLAG_GRANT_READ_URI_PERMISSION 和 ClipData。不会通过 file URI 启动安装，不会静默安装。

Manifest 新增 REQUEST_INSTALL_PACKAGES。Android 8+ 使用 canRequestPackageInstalls；未授权显示说明和“前往设置”，跳到当前包的 ACTION_MANAGE_UNKNOWN_APP_SOURCES。授权返回后使用已下载 APK 继续安装，无需重新下载。用户可取消。

下载 URL 必须为配置仓库的 HTTPS GitHub Release 附件地址；DownloadManager 按正常 TLS 校验处理 GitHub 的附件重定向。无外部 Intent 任意安装 URL 入口。安装前检查文件大小、可识别 APK、applicationId、递增 versionCode、相同签名；Release 提供 sha256 digest 时也校验摘要。

## 签名

当前 `android/app/build.gradle` 的 release 仍使用 `signingConfigs.debug`。E 盘项目目录内尚无正式签名 keystore，本次没有生成/删除/替换密钥。因此 `1.14.18+59` 尚未完成正式签名、打包或 GitHub Release。配置固定正式签名密钥后再发布；不能直接换证书覆盖已有用户安装。此前旧电脑 1.14.14 与迁移后密钥不同，无法直接覆盖该旧证书版本；后续版本必须持续使用同一正式证书。

不要提交 keystore、密码或 Token。当前没有 GitHub Actions；本次未新增 CI。将来可单独配置 tag 触发 Flutter release 构建，把固定签名材料放 GitHub Secrets，以临时文件提供给 Gradle，再创建 Release 并上传 APK。

## 验证步骤与范围

自动检查在首帧后异步执行，24 小时最多一次；失败静默；同次运行新版提示只显示一次，点击以后再说不会重新弹出。手动检查不受限频影响。

已通过 128 项测试（原有 110 项 + 新增 18 项）；flutter analyze 无问题；release APK 实际构建成功。单元/控件测试验证数字版本比较、最新版/新版、缺 APK、不可信来源、网络失败、检查与下载去重、限频、取消下载提示、权限返回复用 APK、安装校验失败，以及浅/深色蓝/红主题长弹窗按钮可见。现有测试覆盖 Canvas 返回、头像缓存、课表、消息、日程、主题和小组件等既有逻辑。APK 已核对 versionName=1.14.17、versionCode=57、minSdk=24、FileProvider 及安装权限；证书 SHA-256 与 1.14.16.1 一致。

真实端到端验收需要先配置公开仓库：在 MuMu/手机安装同一证书的旧版，将更大 versionCode 的新版上传 Release；依次检查最新版/新版、断网手动和自动、无附件、下载进度/文件、关闭未知来源权限、授权返回、系统更新确认、取消安装、切后台/重启/Activity 重建。模拟流程测试不等于真实网络下载和系统安装已验收。

本次尝试通过 MuMuManager 启动并安装：启动返回成功，但设备状态始终为 is_android_started=false / is_process_started=false，安装返回 errcode=-201。未完成 MuMu 实际安装、系统安装页与账号功能的实机回归；这些需要模拟器恢复运行并配置真实公开 Release 后验收。

交付 APK 已重新构建包含主界面空白修复；SHA-256：`F89D149D932EE685168C2BF6220F79662D388C4B300E6EA30B3FF73C902FE9AE`。签名证书 SHA-256：`0f6875165f273a8d6f3554199cef461da657e000dbaf26544049e876efcdc4f2`，与上一版一致。随后 MuMu 安装、启动成功，用户人工确认三个主页面内容均正常；更新下载与系统安装端到端测试仍需配置真实仓库后进行。

交付位置：`E:\Codex\https-yjsxk-sjtu-edu-cn-yjsxkapp\outputs\jiaotong_course-1.14.17.apk`。构建、缓存和文档全部保存在 E 盘指定项目目录。
