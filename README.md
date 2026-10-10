# 交大课表 · 精简结构测试版

基于已完成的 1.14.23 精简结构测试版继续开发。本版 Android 版本为 `1.14.23.1+77`，包名 `cn.sjtu.jiaotong_course.slimtest`，应用名称「交大课表·精简测试」。使用现有 Android Debug 测试证书，可以覆盖升级上一版精简测试包。

## 交付与审查文档

- [功能、网络接口、原生通道与架构审查](docs/architecture-audit.md)
- [源码接口定位清单](docs/interface-inventory.md)
- [修改文件清单](docs/change-manifest.md)
- [APK、签名与测试核验记录](docs/delivery-verification.md)
- [按处理器架构打包与更新选择](docs/apk-packaging.md)

四个 APK 位于本源码目录的上一级，文件名为 `jiaotong_course-1.14.23.1-slim-test-{架构}.apk`。架构分别为 `universal`、`arm64-v8a`、`armeabi-v7a`、`x86_64`。选择设备支持的架构包即可安装，无需同时安装多个 APK。原正式版及上一版精简测试源码、APK 均保留，本次未发布至 GitHub。

## 实际改动

消息合并结果统一缓存；根界面仅响应自身依赖；小组件使用课程目录与日期引用，减少重复计算和传输；常用网站使用一份配置与一个打开入口；删除无调用方接口和临时颜色比较开关；业务快照仅保存在 SQLite，旧偏好快照仅迁移一次。完整行为与测量条件见审查文档。

## 使用

测试包可与正式包同时安装，登录、缓存和小组件彼此独立，首次使用需要重新登录。回退时打开原正式应用即可。测试包不能使用正式仓库 APK 覆盖升级，原有包名与签名验证继续保留。

## 构建

在当前源码目录运行 PowerShell：

```powershell
. ./scripts/project_env.ps1
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
./scripts/build_apk.ps1 -Offline
```

脚本复用指定 E 盘工作区中的 Flutter、Android SDK、JDK、缓存以及 `work/android-user/debug.keystore`。构建采用 release 编译模式及测试证书，先生成通用 APK，再以 `--split-per-abi` 生成三个可独立安装的架构 APK。所有包保持 versionCode 77。`pubspec.yaml` 保留 Flutter 三段版本 `1.14.23+77`，Android 显示版本由 `android/version-name.txt` 和脚本的 `--build-name` 设置为 `1.14.23.1`。

## 验证范围

静态检查通过，188 项自动化测试通过，包含匹配架构、通用包、ABI 优先顺序、只有不兼容附件、旧附件命名及原生桥接等测试。构建与签名结果见交付记录。尚未在本轮进行 MuMu、手机或校园账号联网实测。
