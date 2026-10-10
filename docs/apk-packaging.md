# 1.14.23.1 精简测试版：按处理器架构打包

本轮在上一版精简测试源码上增加打包与更新附件选择，不改变现有页面、登录、课表、教学日历和 Canvas 的实现。2026-10-04。

## 四种独立 APK

`scripts/build_apk.ps1 -Offline` 先构建通用 APK，再执行 `--split-per-abi`。输出文件均在 `outputs/` 下：

- `jiaotong_course-1.14.23.1-slim-test-universal.apk`：包含 ARM64、ARM32、x86_64。
- `jiaotong_course-1.14.23.1-slim-test-arm64-v8a.apk`：ARM64。
- `jiaotong_course-1.14.23.1-slim-test-armeabi-v7a.apk`：ARM32。
- `jiaotong_course-1.14.23.1-slim-test-x86_64.apk`：x86_64。

每个都是可独立安装的完整 APK，不是必须组合安装的 split APK 分片。设备只安装匹配的一个即可。通用包用于不确定设备架构的情况。模拟器应以实际支持的 ABI 为准。

四个包具有相同包名、证书、versionName 和 versionCode。`android/gradle.properties` 设置 `force-version-code-ignoring-abi=true`，防止 Flutter 为各 ABI 自动增加不同的 versionCode，保证后续通用包仍能正常升级架构包。下一版应统一增加构建号。

## GitHub 更新选择

原生更新通道新增 `supportedAbis`，返回 `Build.SUPPORTED_ABIS` 的原始顺序。GitHubReleaseApi 获取正式 Release 后，把设备 ABI 交给同一 UpdateInfo 解析器。

选择顺序：

1. 继续校验配置仓库、HTTPS、APK 扩展名、上传状态与正数大小。
2. 按 Android 给出的 ABI 优先顺序选择匹配架构附件。
3. 没有匹配架构时选择通用附件；旧版没有架构标签的 APK 按原发布格式继续支持。
4. 只有明确不兼容的架构附件时，不提供其下载地址，沿用“未找到可下载的 APK”的提示。

附件应在名称中明确使用 `arm64-v8a`、`armeabi-v7a`、`x86_64` 或 `universal`。同时识别 arm64/aarch64、armv7、amd64 等常见别名。ARM32 只有出现在设备支持列表中时才会被选中；x86 不会误匹配 x86_64。

下载、文件校验、包名/签名/版本校验和 Android 系统安装确认流程继续使用原实现。测试包与正式仓库包名/证书不同，不能使用正式 APK 覆盖升级测试包；校验未放宽。本次没有发布 GitHub。

## 本轮改动文件

| 文件 | 改动 |
|---|---|
| `scripts/build_apk.ps1` | 输出通用包和三个独立架构包 |
| `android/gradle.properties` | 禁止 ABI 自动抬高 versionCode |
| `android/version-name.txt`、`pubspec.yaml` | Android 版本 1.14.23.1，构建号 77 |
| `android/app/src/main/kotlin/cn/sjtu/jiaotong_course/AppUpdateBridge.kt` | 返回设备 ABI 列表 |
| `lib/services/android_update_bridge.dart` | 读取同一更新通道的 ABI |
| `lib/services/github_release_api.dart` | 传递 ABI 至解析器 |
| `lib/models/app_update.dart` | 匹配架构、排除不兼容附件、选择通用包 |
| `test/apk_architecture_test.dart` | 架构与桥接测试 |
| `test/github_release_api_test.dart` | 验证 API 与设备 ABI 选择串联 |
| `README.md`、`docs/` | 新版交付说明，保留前一版结构审查记录 |

## 验证

静态检查无问题，全部 188 项 Flutter 测试通过。具体文件体积、签名、包名与版本检查见 `delivery-verification.md`。前一版 `architecture-audit.md`、`interface-inventory.md` 和 `change-manifest.md` 保留作为结构精简基线记录；本轮新增接口与文件变动以本文为准。
