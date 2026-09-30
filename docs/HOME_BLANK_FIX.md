# 登录后主内容空白：定位与修复

## 已确认根因

1.14.17 在 HomeShell 的 Scaffold.body Stack 中加入非 Positioned 的 UpdateObserver。它返回 SizedBox.shrink；Stack 默认 fit=StackFit.loose，而原有三个页面都在 Positioned.fill 内。

Flutter RenderStack 使用非定位子节点决定自身尺寸。新增的零尺寸监听器使 Stack 收缩为 0×0；IndexedStack 和三个页面随之收到零尺寸约束。底部导航位于独立的 bottomNavigationBar，因此仍显示。周课表还因零宽度派生出负宽度约束。

在修改前运行真实 HomeShell 控件测试，Flutter 输出：

```text
[home-layout] IndexedStack=Size(0.0, 0.0)
BoxConstraints has a negative minimum width.
BoxConstraints(w=-64.4, 0.0<=h<=Infinity; NOT NORMALIZED)
SingleChildScrollView: lib/pages/week_page.dart:234
```

## 最小修复

- `lib/pages/home_shell.dart`：主 Stack 使用 StackFit.expand，占满 Scaffold 提供的内容区；Canvas 初始化的首帧回调增加 mounted 检查。
- `lib/widgets/session_sync_agent.dart`：后台 WebView 初始化改为受保护的异步过程，捕获控制器创建与异步设置/加载错误；失败时隐藏后台组件并返回不可用同步结果，保留前台页面；每次异步完成检查 mounted。
- 新增 `test/home_shell_visibility_test.dart`：真实 HomeShell 的三栏目可见性、更新服务失败、Canvas 同步控制器创建失败、异步初始化失败及退出页面后的回调安全。

没有回滚版本，没有改动头像、Canvas 前台页面/返回逻辑、课表业务、成员排序、主题或更新功能。

## 验证与日志

修复后同一控件测试输出 IndexedStack=Size(800.0, 524.0)，日程/周课表/我的都通过实际命中可见性检查。flutter analyze 无问题，全量 132 项测试通过。

日志在指定 E 盘项目目录：

- `work/temp/home-shell-before-fix.log`：修复前零尺寸与 Flutter 异常堆栈。
- `work/temp/home-shell-before-isolation.log`：注入 Canvas 初始化错误后的异常证据。
- `work/temp/home-shell-after-layout-fix.log`：布局修复通过。
- `work/temp/home-shell-full-tests.log`：修复后全量测试通过。

ADB 设备查询失败（Cannot mkdir '\\.android': Permission denied），现有 adb.log 也记录连接模拟器端口被拒绝。本次未获得设备端 Logcat，未启动 MuMu，未安装 APK。根据用户要求，代码与本地验证完成后暂停，等待明确的“开始测试”指令。

## 用户授权后的打包与 MuMu 测试

用户随后明确授权“打包apk并开始测试”。已重新构建并替换 outputs/jiaotong_course-1.14.17.apk，包含本次修复，版本仍为 1.14.17+57，签名证书与此前版本一致。APK SHA-256：`F89D149D932EE685168C2BF6220F79662D388C4B300E6EA30B3FF73C902FE9AE`。

MuMu APK 安装命令返回包名 cn.sjtu.jiaotong_course，APP 启动命令 errcode=0。自动截图初次与恢复后均超时，ADB / shell 无法连接，未取得设备端 Logcat。因此请用户在模拟器中手动切换三个页面核验。

用户明确反馈：“三个页面内容均正常显示”。日程、周课表、我的恢复显示，本次主界面空白问题通过用户在 MuMu 中的人工验收。未声称完成 Canvas、头像、更新下载安装的实机回归。
