> 本文是上一版 1.14.23+76 精简结构测试版的审查快照。本轮 1.14.23.1+77 的新增接口、文件变化与构建结果见 apk-packaging.md 和 delivery-verification.md；此前结构精简记录继续保留。
# 本次改动文件清单

比较对象：正式源码 jiaotong_course_app 与独立精简源码。只列业务源码、测试和构建配置；构建产物与工具缓存不计入源码。

| 文件 | 原行数 | 测试版行数 | 状态 |
|---|---:|---:|---|
| `android/app/build.gradle` | 74 | 52 | 修改 |
| `android/app/src/main/AndroidManifest.xml` | 75 | 75 | 修改 |
| `android/app/src/main/kotlin/cn/sjtu/jiaotong_course/MainActivity.kt` | 289 | 279 | 修改 |
| `android/app/src/main/kotlin/cn/sjtu/jiaotong_course/TimetableWidgetProvider.kt` | 482 | 423 | 修改 |
| `lib/main.dart` | 205 | 231 | 修改 |
| `lib/models/common_website.dart` | 0 | 94 | 新增 |
| `lib/models/course.dart` | 363 | 361 | 修改 |
| `lib/pages/home_page.dart` | 663 | 663 | 修改 |
| `lib/pages/settings_page.dart` | 863 | 659 | 修改 |
| `lib/services/android_web_history.dart` | 54 | 49 | 修改 |
| `lib/services/announcement_feed.dart` | 287 | 242 | 修改 |
| `lib/services/app_database.dart` | 173 | 190 | 修改 |
| `lib/services/message_feed.dart` | 91 | 84 | 修改 |
| `lib/services/timetable_widget_bridge.dart` | 158 | 186 | 修改 |
| `lib/state/app_controller.dart` | 1147 | 1114 | 修改 |
| `lib/widgets/common_website_grid.dart` | 145 | 128 | 修改 |
| `pubspec.yaml` | 33 | 33 | 修改 |
| `scripts/build_apk.ps1` | 67 | 67 | 修改 |
| `test/calendar_cache_repair_test.dart` | 61 | 63 | 修改 |
| `test/common_website_grid_test.dart` | 366 | 382 | 修改 |
| `test/home_shell_visibility_test.dart` | 161 | 163 | 修改 |
| `test/hot_path_benchmark_test.dart` | 0 | 152 | 新增 |
| `test/message_badge_integration_test.dart` | 49 | 50 | 修改 |
| `test/message_read_test.dart` | 148 | 151 | 修改 |
| `test/reminder_announcement_test.dart` | 221 | 222 | 修改 |
| `test/schedule_test.dart` | 657 | 657 | 修改 |
| `test/semester_calendar_test.dart` | 360 | 361 | 修改 |
| `test/slim_state_test.dart` | 0 | 227 | 新增 |
| `test/special_date_ui_test.dart` | 230 | 237 | 修改 |
| `test/support/memory_database.dart` | 0 | 69 | 新增 |
| `test/teaching_calendar_test.dart` | 304 | 307 | 修改 |
| `test/week_widget_test.dart` | 981 | 994 | 修改 |

Dart 业务源码与 Android Kotlin 源码合计：14575 → 14358 行。行数含注释，不能单独衡量性能或质量；具体收益见主文档的确定性测量。

测试目录中的内存数据库用于验证新的单一存储边界；原有测试不再依赖偏好设置里的重复快照。常用网站测试改为对数据配置断言，继续逐项检查九个导航目标与认证标志。

