# 交大课表 1.14.26 · A 分支后续测试版

本分支为 `test/1.14.26`，由此前 `test/1.14.24a` 更名，保留 1.14.24a、1.14.25 的迭代历史。正式版本使用 `main` 和正式 Release。

本版仅修复常用网站共用 WebView 导航：准确重试目标页面，取消过期回调和认证任务，保留网页历史及登录会话。保留 1.14.25 已完成的双日历悬浮按钮、课表间距、学期日期、设置菜单及其他功能。

## 下载与安装

- [1.14.26 测试 Release](https://github.com/revanbastila/SJTU-Timetable/releases/tag/v1.14.26-test)
- Android 版本 `1.14.26+82`，包名 `cn.sjtu.jiaotong_course.slimtest.a`，应用名「交大课表·测试A」。沿用测试签名，可覆盖安装 1.14.25 测试 A。
- 常见手机选择 ARM64，架构不确定选择通用 APK。与正式版独立安装，测试版数据与正式版分开。

## 修改与验证

- [本版发布说明](docs/TEST-1.14.26.md)
- [根因、代码位置与逐站验收状态](docs/1.14.26-WebView修复与验收.md)
- 236 项 Flutter 测试、12 项 JavaScript 检查和静态分析通过；真实 Android、网站登录和网络恢复验收按用户安排稍后进行。

## 本地构建

在本机配置 Flutter、Android SDK、JDK 及自己的测试签名后，运行项目脚本：

```powershell
. ./scripts/project_env.ps1
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
./scripts/build_apk.ps1 -Offline
```

仓库与发布附件不含签名私钥、账号凭据或构建缓存。不同签名生成的 APK 无法直接覆盖本测试包。
