# 测试 A 更新渠道

测试 A 根据 Android 实际包名 `cn.sjtu.jiaotong_course.slimtest.a` 选择更新源。启动时与设置页手动检查共用读取器，读取仓库 `revanbastila/SJTU-Timetable` 的 `test/1.14.26` 分支文件 `updates/test-a.json`。正式包名继续查询正式 Latest；测试文件缺失、网络错误或内容无效时提示失败，不回退到正式包。

更新请求直接读取 GitHub 测试分支原始文件，避免共享出口的匿名 REST API 额度耗尽导致 403。每次请求附加新的 `_` 参数并设置 `Cache-Control: no-cache`：

```text
GET https://raw.githubusercontent.com/revanbastila/SJTU-Timetable/refs/heads/test/1.14.26/updates/test-a.json?_=<本次请求时间>
Accept: application/json
Cache-Control: no-cache
```

清单格式为 `schemaVersion: 1`、`channel: test-a`、固定测试包名、数字 `versionName`、递增整数 `versionCode`、与版本一致的 `releaseTag: v<版本>-test`、发布说明、日期和 `assets`。每个安装包包含 `abi`、`name`、`size`、`sha256` 和该仓库 Release 的 `url`。客户端按设备 ABI 顺序优先选分架构包，未匹配时选择 universal。清单不得缺失哈希、重复 ABI，或引用其他仓库、版本及正式安装包。

测试版比较 versionCode，并要求显示版本不倒退；同名版本重新构建时可通过递增 versionCode 更新。同一构建不会重复提示。下载继续使用 Android DownloadManager，安装前校验文件大小、SHA-256、实际包名、清单指定的准确版本、递增版本号和现有签名。用户确认后进入系统安装流程；“稍后再说”及下载恢复策略沿用原实现。

## 发布顺序

1. 构建并验证测试 APK，递增 versionCode。
2. 提交源码，创建以该源码提交为目标的测试预发布，上传安装包并核对 GitHub 的大小及 SHA-256。
3. 公开预发布并确认下载附件可用。
4. 最后更新 `updates/test-a.json` 并推送到测试分支，使客户端只看到已有可下载附件的版本。清单更新提交可以晚于源码标签提交。

安装包中的更新地址固定指向测试分支，后续版本发布不需要修改客户端。1.14.27.4 及更早版本未实现此渠道，需要先手动覆盖安装 1.14.27.6；之后即可通过测试分支清单检查测试更新。

联网验收可单独运行：

```powershell
flutter test --no-pub --dart-define=RUN_GITHUB_TEST_UPDATE_PROBE=true test/github_test_update_live_test.dart --reporter expanded
```

该验收直接运行生产读取器并访问真实公开清单，注入测试包名和 ABI，以模拟旧构建/当前构建验证版本判断；不等同于真机下载及覆盖安装验收。

1.14.27.5 的早期读取器使用 Contents API；若该版遇到 API 额度错误，可直接手动覆盖安装 1.14.27.6。源码标签中的清单是发布前快照，当前测试分支在附件可下载后以独立提交激活新版本清单。
