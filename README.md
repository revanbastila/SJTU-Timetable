# 交大课表 1.14.27.4 · 测试 A

当前测试版本 **1.14.27.4（91）**，基于 1.14.27.3 修复自动签到检测与入口异常。沿用 `test/1.14.26` 分支，安装包见下方预发布。

- [下载测试安装包](https://github.com/revanbastila/SJTU-Timetable/releases/tag/v1.14.27.4-test)
- [修改、安装方式和验收限制](docs/TEST-1.14.27.4.md)

本版分别处理课程入口错误、查询状态、提醒展示和执行状态；前后台共享每门课程请求和下一次检查时间，失败按课程独立退避，页面支持原地重试。**真机前后台连续检测与自动签到全链路尚待实测**；不能确认二维码任务关联时停止提交。

自动化验证包含原有回归、新增异步恢复与主题切换测试，以及直接运行原生调度源码的 JVM 并发验证。后台需要常驻通知与必要系统授权，并受省电与服务时限约束。307 项 Flutter 测试、13 项 JavaScript 检查和原生并发验证通过。

包名 `cn.sjtu.jiaotong_course.slimtest.a`，沿用测试签名，与正式版独立安装。源码不含签名私钥、账号或会话信息。配置自己的Flutter/Android SDK/JDK和测试签名后可本地构建；不同签名不能覆盖已安装测试包。

本机重建：软件目录下 `work/build_114274.ps1`（通用包）或 `work/build_114274.ps1 -Split`（分架构包）。Android 显示版本由 `android/version-name.txt` 指定；`pubspec.yaml` 使用三段版本 `1.14.27+91`。原生调度验证：`scripts/verify_attendance_native.ps1`。
