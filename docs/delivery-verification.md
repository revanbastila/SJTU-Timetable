# 1.14.23.1 精简测试版交付核验

日期：2026-10-04。基于上一版完整精简测试源码，输出目录为 `E:/Codex/https-yjsxk-sjtu-edu-cn-yjsxkapp/outputs/`。

## 版本与签名

- versionName：`1.14.23.1`；versionCode：`77`。
- 包名：`cn.sjtu.jiaotong_course.slimtest`；应用名称：交大课表·精简测试。
- 四个 APK 使用相同的既有 Android Debug 测试证书，未使用正式签名，未生成新的密钥。
- 证书 SHA-256：`0f6875165f273a8d6f3554199cef461da657e000dbaf26544049e876efcdc4f2`。
- `aapt dump badging` 核对每个包的包名与版本，`apksigner verify --print-certs` 校验全部通过；ZIP 内原生库核对与文件名指定架构一致，架构包只含一套库。
- 四个包均可独立安装；只需选择设备支持的一个。可以覆盖升级上一版 `1.14.23+76` 精简测试包，继续与正式包独立存储。

## 文件大小

| 文件名 | 字节 | MiB |
|---|---:|---:|
| `jiaotong_course-1.14.23.1-slim-test-arm64-v8a.apk` | 20,757,920 | 19.80 |
| `jiaotong_course-1.14.23.1-slim-test-armeabi-v7a.apk` | 18,281,324 | 17.43 |
| `jiaotong_course-1.14.23.1-slim-test-x86_64.apk` | 22,307,228 | 21.27 |
| `jiaotong_course-1.14.23.1-slim-test-universal.apk` | 57,992,198 | 55.31 |

与上一版通用测试包的 57,992,194 字节相比，ARM64 包减少约 64.2%。这是通过排除该设备不需要的架构程序库实现，未删除业务功能。通用包继续保留三套库，体积没有明显减少。

SHA-256：

| 架构 | 校验值 |
|---|---|
| ARM64 | `9DA12B7EC48F9C10F1C0ECBF6B26E6840D5BAFCC619C758C7BC93CFEBB23A8D8` |
| ARM32 | `75DA78715241692BA22D22EE20FA0B90409228267F65F2E240C533A289B09F64` |
| x86_64 | `4CD6227BCDEE918EC095128D10F4B79C152197DA6BE32FAE00B306FB0E08D852` |
| 通用 | `0ABA9ECC583FF762FE545DB42C41DE23D2DC9A34BDFF08525CA1D4FFAD71404A` |

## 检查与测试

- 静态检查：No issues found。
- 全部 Flutter 测试：188 项通过；包含新增的架构选择、未知架构、通用附件、仅有不兼容附件、ABI 优先顺序、旧命名兼容、原生读取与 API 串联验证。
- 通用与三个架构 APK 均成功构建。
- 本轮没有在 MuMu 或手机安装、启动和校园账号登录实测。

日志位于工作区 `work/`：`slim-abi-analyze.log`、`slim-abi-tests.log`、`build-1.14.23.1-slim-test.log`、`slim-abi-apk-verification.json`。

## 源码与原版本

新完整源码：`outputs/SJTU-Timetable-1.14.23.1-slim-test/`。构建命令与更新附件命名要求见 README 与 `apk-packaging.md`。

上一版源码 `outputs/SJTU-Timetable-1.14.23-slim-test/` 和 APK 未覆盖；上一版 APK SHA-256 仍为 `14BD43F5A2F88703E819956D0D1104D27BB62DEB9E159AC9F437BA293B5E2AD1`。

正式源码 `outputs/jiaotong_course_app/` 的 Git 工作区保持干净。正式 APK SHA-256 仍为 `447D24CBC44C9B7212FC8BDF8032995CE0F80BE9B0AF37491910AAC05C214FFB`。

本次未提交、推送或发布 GitHub。测试包继续保留正式 APK 的包名、签名与版本校验，不能使用正式仓库 APK 覆盖升级测试包。
