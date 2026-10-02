# 本地版本交付与重建

## 1.14.21.1

- Android versionName：`1.14.21.1`（`android/version-name.txt`）。
- Android versionCode：`65`（`pubspec.yaml` 的 `+65`）。
- 每次冷启动检查最新正式 GitHub Release，不阻塞启动；同一进程最多自动提示一次。
- “稍后再说”将推迟时间保存到 SharedPreferences，24 小时内不再自动提示；手动检查不受限制。
- 更新说明来自 Release Notes；有 APK 时使用现有下载/系统安装流程，没有 APK 时打开该 Release 页面。

## 1.14.22

- 基于已经保留的 1.14.21.1，继续保留其更新检测和 24 小时推迟策略。
- Android versionName：`1.14.22`，versionCode：`66`。
- 仅“常用网站”切换为三列九宫格，保留原 ListTile 数据、网址和所有点击回调。
- 快速恢复列表：在 `lib/pages/settings_page.dart` 的“常用网站”卡片将 `useWebsiteGrid: true` 改为 `false`，不需重写路由。

## 在本电脑重建

源码目录保持位于本工作区 `outputs` 下，脚本复用工作区 `work` 内的工具和缓存：

```powershell
.\scripts\build_apk.ps1 -Offline
```

本机各源码目录的 `android/key.properties` 为忽略的本地配置，共用原正式密钥；密钥、密码和配置不提交 Git、不打包进源码归档。换电脑需自行配置同一正式签名，并安装 Flutter / Android SDK / JDK。

两个 APK 沿用 `cn.sjtu.jiaotong_course` 和同一正式证书，属于同一个应用，不能同时安装。Android 通常禁止较低 versionCode 覆盖较高版本；较早 APK 作为归档，完整源码状态可直接打开重建。卸载再安装旧版会丢失本地应用数据，应由用户自行决定。

本次提交、标签和源码目录只保存在本机，不推送 GitHub。
