# 交大课表（Flutter Android）

上海交通大学研究生课表助手。应用通过内置 WebView 打开学校官方教务系统完成登录并读取课表；如学校要求验证码或其他安全验证，由用户在官方页面手动完成，应用不绕过校园系统的验证机制。

## 1.14.21.1 版本功能

### 登录与课表

- 使用 jAccount 登录研究生选课系统。可选择“记住本人”；账号密码由 Android 安全存储加密保存，不以明文写入应用偏好设置。退出登录会清理保存的凭据和 WebView 登录数据。
- 自动读取课程名称、教师、地点、时间和开课周次；支持单双周、间断周次以及手动选择教学周。
- 首页展示当天课程、正在上的课程或下一节课；周课表默认展示周一至周五，可横向查看周末，并可切换学期内各周。
- 按教学日历动态处理放假、停课和调休，日程、周课表、桌面组件和课程提醒共用实际日期课程；在线日历缓存到本地，离线时继续使用上次有效数据。
- 设置页可调整学期第 1 周周一日期和学期总周数（16–22 周）。
- SQLite 本地缓存支持离线查看。课表可手动刷新，也可按 15、30、60 或 120 分钟的间隔自动检查更新。

### Canvas 与消息

- 优先按 Canvas 课程目录匹配课表课程，也可以在课程详情中手动关联或解除关联。
- 后台分批同步 Canvas 公告、课程大纲和班级成员；同步失败时保留已缓存内容，课表仍可正常使用。
- 课程详情提供“公告 / 大纲 / 班级成员”标签，并可跳转到对应 Canvas 课程。
- 首页的“消息”页汇总 Canvas 通知与课程公告，显示未读数量并支持标记已读。
- 自动同步新公告并合并到对应课程和消息列表，保留去重、未读状态与发布时间排序。

### 提醒与桌面组件

- 可关闭课程提醒，或选择推送消息、闹钟提醒；提醒时间可设为上课前 5、10、15 或 30 分钟。
- 提供 Android 桌面课表组件，显示当天课程名称、时间、地点和教师；点选课程可进入应用中的课程详情。组件只接收课表字段，不读取账号密码或 WebView 登录信息。

### 交大服务与个性化

- “常用网站”按顺序提供 Canvas教学平台、研究生应用管理平台、图书馆、交大邮箱、交大云盘、校园地图、水源社区、选课社区和传承·交大。
- 需要登录的独立站点在其官方页面中完成认证；课程地点可直接打开交大地图。
- 支持跟随系统、浅色和深色模式，并提供经典蓝、交大红、雾青、鼠尾草、灰紫和岩蔷薇配色。
- 每次冷启动在后台通过 GitHub Releases 检查应用更新，读取发布说明并复用安全下载/安装流程；默认更新仓库为 `revanbastila/SJTU-Timetable`。选择“稍后再说”后 24 小时内不再自动提示，手动检查不受限制。
- 周课表的特殊日期标识与横向滑动提示适配当前主题，不改变课程布局。

## 构建

需要 Flutter stable、Android SDK 和 JDK 17。进入本目录后运行：

```powershell
flutter pub get
flutter run
flutter build apk --release
```

也可以使用项目构建脚本：

```powershell
.\scripts\build_apk.ps1
```

Android 版本名在 `android/version-name.txt` 维护（支持四段热修复版本）；递增的 `versionCode` 在 `pubspec.yaml` 的 `version` 字段加号后维护，该字段版本部分遵循 Dart 三段语义版本。正式 APK 使用固定 Release 签名；签名密钥及本地 `android/key.properties` 不进入仓库。

Release APK 通常生成在 `build/app/outputs/flutter-apk/app-release.apk`。脚本会从 `pubspec.yaml` 读取应用版本；若本机缺少 Android Gradle 工程文件，也会先初始化 Android 工程。

自动更新仓库可通过构建参数配置：

```powershell
flutter build apk --release --dart-define=GITHUB_OWNER=<仓库所有者> --dart-define=GITHUB_REPO=<仓库名>
```

## 诊断工具

`tools/share_inspector.py` 是传承·交大的独立诊断工具。用户在官方浏览器页面完成登录和必要验证后，工具仅导出传承·交大同源 JSON 响应；会移除 URL 查询参数，并对密码、Cookie、Token、会话和授权字段脱敏，不导出认证请求头或表单内容。

安装 Playwright 后可运行：

```powershell
pip install playwright
playwright install chromium
python tools/share_inspector.py --output share-diagnostic.json
```

## 说明

教务系统和 Canvas 页面由学校服务端动态提供。若页面结构调整导致字段无法识别，可检查 `lib/pages/portal_sync_page.dart` 与 `lib/services/portal_extractor.dart` 中的课表提取逻辑。
