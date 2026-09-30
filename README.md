# 交大课表（Flutter Android）

一个蓝白风格的上海交通大学研究生课表助手。它通过应用内 WebView 打开学校官方教务系统完成登录，在登录后的页面中读取课表；遇到验证码时由用户手工完成，不绕过校园系统的安全验证。

## 1.10 已实现

- 学号/密码登录入口，密码不落盘。
- 首页显示今天的课程、下一节课、地点和老师。
- 自动计算教学周并支持手动切换第 1–18 周，支持单双周和间断周次。
- 默认完整显示周一至周五，横向滑动可查看周末；课程块显示课程、教师和地点。
- Canvas 课程目录优先匹配并缓存，公告、大纲和成员在后台分批同步，弱网失败不会清空旧数据。
- 今天页提供“今日课程 / 公告”双标签，课程详情提供 Canvas 三标签。
- SQLite 离线缓存以及自动/手动课程关联。
- 课表每 15/30/60/120 分钟自动检查更新。
- 上课前 15 分钟的推送消息或闹钟提醒，可选择关闭、推送、闹钟三种模式。
- 蓝白校园视觉主题和离线可打包的“交”字图标。
- 设置页可调整学期第一周日期和总周数。
- 设置页可进入水源社区、传承·交大和选课社区；独立站点凭据只由其官方页面处理。

`tools/share_inspector.py` 是传承·交大的独立脱敏诊断工具，只导出同源 JSON 结构，不导出密码、Cookie、Token 或认证请求头。

## 本机配置与构建

需要 Flutter stable、Android SDK、JDK 17。进入本目录后执行：

```powershell
flutter create --platforms=android .
flutter pub get
flutter run
flutter build apk --release
```

也可以直接运行项目内的 PowerShell 构建脚本：

```powershell
.\scripts\build_apk.ps1
```

生成文件通常位于：

```text
build/app/outputs/flutter-apk/app-release.apk
```

如果首次构建提示缺少 Flutter SDK，请先安装 Flutter stable，并确保 `flutter doctor` 中 Android toolchain 通过。Android 工程使用 Flutter 官方 Gradle 插件结构，适配 AndroidX。

## 说明

课表页面是由学校系统动态渲染的，`lib/pages/portal_sync_page.dart` 中的 DOM 提取脚本针对常见表格结构做了通用解析。如果学校改版后课表字段没有被识别，可在该文件的 `_extractCourses` 中补充字段选择器；无需改变 UI 和提醒逻辑。
