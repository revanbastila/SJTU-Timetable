import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_update.dart';
import '../services/update_manager.dart';

String readableReleaseNotes(String notes) => notes
    .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ')
    .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
    .replaceAll('**', '')
    .trim();

Future<void> showUpdateDialog(
    BuildContext context, UpdateManager manager, UpdateInfo info) async {
  if (manager.dialogVisible) return;
  manager.dialogVisible = true;
  try {
    final update = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final date = info.publishedAt?.toLocal();
          final notes = readableReleaseNotes(info.releaseNotes);
          return AlertDialog(
            title: Text('发现新版本 ${info.displayVersion}'),
            content: SizedBox(
                width: 360,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(dialogContext).height * .5),
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('当前版本：v${manager.current?.name ?? "未知"}'),
                        const SizedBox(height: 16),
                        const Text('更新内容：'),
                        const SizedBox(height: 8),
                        Text(notes.isEmpty ? '此次发布未提供更新说明' : notes),
                        const SizedBox(height: 16),
                        if (info.hasApk)
                          Text(
                              'APK 大小：${(info.apkSize / 1024 / 1024).toStringAsFixed(1)} MB')
                        else
                          const Text('当前版本已发布，但未找到可下载的 APK'),
                        if (date != null)
                          Text(
                              '发布时间：${date.year}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")}'),
                        TextButton(
                            onPressed: () => manager.openRelease(info),
                            child: const Text('查看发布页面')),
                      ])),
                )),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('以后再说')),
              FilledButton(
                  onPressed: info.hasApk && !manager.downloading
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('立即更新')),
            ],
          );
        });
    if (update == true) {
      try {
        await manager.download(info);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
              content: Text(UpdateManager.messageFor(error, '下载失败，请重试'))));
        }
      }
    }
  } finally {
    manager.dialogVisible = false;
  }
}

Future<void> showInstallPermissionDialog(
    BuildContext context, UpdateManager manager) async {
  if (manager.permissionPromptShown) return;
  manager.permissionPromptShown = true;
  final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
            title: const Text('允许安装应用更新'),
            content: const Text('需要允许“交大课表”安装应用更新，请在系统设置中开启“允许来自此来源的应用”。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('以后再说')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('前往设置')),
            ],
          ));
  if (allow == true) await manager.allowInstall();
}

class UpdateObserver extends StatefulWidget {
  const UpdateObserver({super.key});
  @override
  State<UpdateObserver> createState() => _UpdateObserverState();
}

class _UpdateObserverState extends State<UpdateObserver> {
  final manager = UpdateManager.instance;
  int _noticeSerial = 0;
  bool _scheduled = false;
  @override
  void initState() {
    super.initState();
    _noticeSerial = manager.noticeSerial;
    manager.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await manager.initialize();
      // Network work starts after the first frame and never holds up boot.
      if (mounted) unawaited(manager.check(automatic: true));
      _changed();
    });
  }

  void _changed() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduled = false;
      if (!mounted) return;
      if (manager.noticeSerial != _noticeSerial) {
        _noticeSerial = manager.noticeSerial;
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(manager.notice)));
      }
      if (WidgetsBinding.instance.lifecycleState != null &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      if (manager.permissionNeeded &&
          !manager.permissionPromptShown &&
          !manager.dialogVisible) {
        await showInstallPermissionDialog(context, manager);
      } else if (manager.automaticPromptPending &&
          !manager.automaticPromptShown &&
          !manager.dialogVisible) {
        final info = manager.available;
        if (info == null) return;
        manager.automaticPromptShown = true;
        manager.automaticPromptPending = false;
        await showUpdateDialog(context, manager, info);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    manager.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class UpdateSettingsEntry extends StatefulWidget {
  const UpdateSettingsEntry({super.key});
  @override
  State<UpdateSettingsEntry> createState() => _UpdateSettingsEntryState();
}

class _UpdateSettingsEntryState extends State<UpdateSettingsEntry> {
  final manager = UpdateManager.instance;
  @override
  void initState() {
    super.initState();
    unawaited(manager.initialize());
  }

  Future<void> _check() async {
    if (manager.downloadStatus == 'ready') {
      manager.permissionPromptShown = false;
      await manager.install();
      if (mounted && manager.permissionNeeded) {
        await showInstallPermissionDialog(context, manager);
      }
      return;
    }
    try {
      final result = await manager.check();
      if (!mounted || result == null) return;
      if (result.isNew) {
        // A manual prompt also satisfies the automatic once-per-run prompt.
        manager.automaticPromptShown = true;
        manager.automaticPromptPending = false;
        await showUpdateDialog(context, manager, result.info);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已是最新版本\n当前版本：v${manager.current?.name ?? "未知"}')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UpdateManager.messageFor(error, '检查更新失败，请检查网络后重试'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final downloading = manager.downloading;
        final title = manager.checking
            ? '正在检查更新……'
            : downloading
                ? '正在下载更新……${manager.progress == null ? "" : " ${manager.progress}%"}'
                : '检查更新';
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: const Text('当前版本',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Text(manager.current?.name ?? '读取中')),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: manager.checking || downloading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.system_update_outlined),
                  title: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: manager.downloadStatus == 'ready' ||
                          manager.downloadStatus == 'failed' ||
                          manager.available != null
                      ? Text(manager.downloadStatus == 'ready'
                          ? 'APK 已下载，点击继续安装'
                          : manager.downloadStatus == 'failed'
                              ? manager.notice
                              : manager.available != null
                                  ? '发现新版本 ${manager.available!.displayVersion}'
                                  : '')
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: manager.checking || downloading ? null : _check),
              if (downloading)
                LinearProgressIndicator(
                    value: manager.progress == null
                        ? null
                        : manager.progress! / 100),
            ]);
      });
}

class CurrentAppVersionLabel extends StatelessWidget {
  const CurrentAppVersionLabel({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: UpdateManager.instance,
      builder: (context, _) => Text(
          '交大课表  ·  ${UpdateManager.instance.current == null ? "版本信息不可用" : "v${UpdateManager.instance.current!.name}"}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)));
}
