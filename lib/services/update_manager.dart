import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_update.dart';
import 'android_update_bridge.dart';
import 'github_release_api.dart';
import 'update_config.dart';

class UpdateCheckResult {
  const UpdateCheckResult(this.info, this.isNew);
  final UpdateInfo info;
  final bool isNew;
}

/// Shared by the startup observer and settings. UI recreation does not reset
/// the active check/download, the deferred prompt, or its once-per-run guard.
class UpdateManager extends ChangeNotifier with WidgetsBindingObserver {
  UpdateManager(
      {required this.repository,
      required this.platform,
      required this.configured,
      DateTime Function()? clock})
      : clock = clock ?? DateTime.now;
  static final instance = UpdateManager(
      repository: GitHubReleaseApi(),
      platform: AndroidUpdateBridge(),
      configured: UpdateConfig.configured);
  final ReleaseRepository repository;
  final UpdatePlatform platform;
  final bool configured;
  final DateTime Function() clock;
  AppVersion? current;
  UpdateInfo? available;
  bool checking = false;
  bool automaticPromptPending = false;
  bool automaticPromptShown = false;
  bool dialogVisible = false;
  bool permissionNeeded = false;
  bool permissionPromptShown = false;
  String downloadStatus = 'idle';
  int downloadedBytes = 0, totalBytes = 0;
  String notice = '';
  int noticeSerial = 0;
  Future<void>? _initialization;
  Future<UpdateCheckResult?>? _activeCheck;
  bool _automaticAttempted = false;
  bool _startingDownload = false, _polling = false, _installing = false;
  Timer? _timer;
  bool get downloading => _startingDownload || downloadStatus == 'downloading';
  int? get progress => totalBytes > 0
      ? (downloadedBytes * 100 ~/ totalBytes).clamp(0, 100)
      : null;

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      current = await platform.version();
    } catch (_) {/* Optional service unavailable. */}
    notifyListeners();
    await refreshDownload();
  }

  Future<UpdateCheckResult?> check({bool automatic = false}) async {
    if (automatic) {
      if (_automaticAttempted) return null;
      _automaticAttempted = true;
      if (!configured) return null;
      try {
        final prefs = await SharedPreferences.getInstance();
        final last = prefs.getInt('lastUpdateCheckTime');
        if (last != null &&
            clock().difference(DateTime.fromMillisecondsSinceEpoch(last)) <
                UpdateConfig.automaticCheckInterval) {
          return null;
        }
        await prefs.setInt(
            'lastUpdateCheckTime', clock().millisecondsSinceEpoch);
      } catch (_) {
        return null;
      }
    }
    final active = _activeCheck;
    if (active != null) return active;
    final work = _check(automatic);
    _activeCheck = work;
    try {
      return await work;
    } finally {
      if (identical(_activeCheck, work)) _activeCheck = null;
    }
  }

  Future<UpdateCheckResult?> _check(bool automatic) async {
    checking = true;
    notifyListeners();
    try {
      await initialize();
      if (!configured) throw const UpdateException('尚未配置 GitHub 更新仓库');
      final installed = ReleaseVersion.parse(current?.name ?? '');
      if (installed == null) throw const UpdateException('无法读取当前应用版本');
      final info = await repository.latest();
      final latest = ReleaseVersion.parse(info.version);
      if (latest == null) throw const UpdateException('无法识别最新版本号');
      final isNew = latest.compareTo(installed) > 0;
      available = isNew ? info : null;
      if (automatic && isNew && !automaticPromptShown) {
        automaticPromptPending = true;
      }
      return UpdateCheckResult(info, isNew);
    } catch (error) {
      if (automatic) return null;
      throw UpdateException(messageFor(error, '检查更新失败，请检查网络后重试'));
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> download(UpdateInfo info) async {
    if (downloading || _installing) return;
    if (!info.hasApk) throw const UpdateException('当前版本已发布，但未找到可下载的 APK');
    _startingDownload = true;
    permissionPromptShown = false;
    permissionNeeded = false;
    notifyListeners();
    try {
      await platform.download(info);
      _announce('正在下载更新……');
      await refreshDownload();
    } catch (error) {
      downloadStatus = 'failed';
      throw UpdateException(messageFor(error, '下载失败，请重试'));
    } finally {
      _startingDownload = false;
      notifyListeners();
    }
  }

  Future<void> refreshDownload() async {
    if (_polling) return;
    _polling = true;
    try {
      final state = await platform.state();
      final previous = downloadStatus;
      downloadStatus = state['status'] as String? ?? 'idle';
      downloadedBytes = (state['bytes'] as num?)?.toInt() ?? 0;
      totalBytes = (state['total'] as num?)?.toInt() ?? 0;
      if (downloadStatus == 'downloading') {
        _timer ??= Timer.periodic(
            const Duration(seconds: 1), (_) => unawaited(refreshDownload()));
      } else {
        _timer?.cancel();
        _timer = null;
      }
      if (downloadStatus == 'ready' &&
          state['installDispatched'] != true &&
          !permissionNeeded) {
        await install();
      } else if (downloadStatus == 'failed' && previous != 'failed') {
        _announce(state['error'] as String? ?? '下载失败，请重试');
      }
      notifyListeners();
    } catch (_) {
      /* DownloadManager retains work while the Activity is absent. */
    } finally {
      _polling = false;
    }
  }

  Future<void> install() async {
    if (_installing) return;
    _installing = true;
    try {
      final result = await platform.install();
      if (result == 'permissionRequired') {
        permissionNeeded = true;
      } else if (result == 'opened') {
        permissionNeeded = false;
      }
    } catch (error) {
      downloadStatus = 'failed';
      _announce(messageFor(error, '无法打开安装程序，请重新下载'));
    } finally {
      _installing = false;
      notifyListeners();
    }
  }

  Future<void> allowInstall() async {
    try {
      await platform.allowInstall();
    } catch (error) {
      _announce(messageFor(error, '无法打开系统设置，请在系统中允许安装未知应用'));
    }
  }

  Future<void> openRelease(UpdateInfo info) async {
    try {
      await platform.openRelease(info.releasePageUrl);
    } catch (_) {
      _announce('无法打开发布页面，请检查是否安装浏览器');
    }
  }

  void _announce(String message) {
    notice = message;
    noticeSerial++;
    notifyListeners();
  }

  static String messageFor(Object error, String fallback) {
    if (error is UpdateException) return error.message;
    if (error is PlatformException) return error.message ?? fallback;
    return fallback;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      permissionNeeded = false;
      unawaited(refreshDownload());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
