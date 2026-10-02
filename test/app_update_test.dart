import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/app_update.dart';
import 'package:jiaotong_course/services/android_update_bridge.dart';
import 'package:jiaotong_course/services/github_release_api.dart';
import 'package:jiaotong_course/services/update_manager.dart';
import 'package:jiaotong_course/widgets/app_update_ui.dart';

Map<String, dynamic> asset(String name, {String? url}) => {
      'name': name,
      'size': 100,
      'browser_download_url': url ??
          'https://github.com/campus/course/releases/download/v1.15/$name',
      'state': 'uploaded',
    };
UpdateInfo release(
        {String tag = 'v1.15', List<Map<String, dynamic>>? assets}) =>
    UpdateInfo.fromRelease({
      'tag_name': tag,
      'name': 'Course',
      'body': '- Fix\n* Improve',
      'published_at': '2026-09-30T00:00:00Z',
      'html_url': 'https://github.com/campus/course/releases/tag/$tag',
      'assets': assets ?? [asset('course-release.apk')]
    }, 'campus', 'course');

class Repository implements ReleaseRepository {
  int calls = 0;
  Future<UpdateInfo> Function() response = () async => release();
  @override
  Future<UpdateInfo> latest() {
    calls++;
    return response();
  }
}

class Platform implements UpdatePlatform {
  int downloads = 0, installs = 0, settings = 0, releasePages = 0;
  String installResult = 'opened';
  bool failInstall = false;
  Map<String, dynamic> value = {'status': 'idle'};
  Completer<void>? downloadGate;
  @override
  Future<AppVersion> version() async => const AppVersion('1.14.17', 57);
  @override
  Future<Map<String, dynamic>> state() async => value;
  @override
  Future<Map<String, dynamic>> download(UpdateInfo info) async {
    downloads++;
    await downloadGate?.future;
    value = {'status': 'downloading', 'bytes': 25, 'total': 100};
    return value;
  }

  @override
  Future<String> install() async {
    installs++;
    if (failInstall) throw const UpdateException('APK 校验失败，请重新下载');
    if (installResult == 'opened') {
      value = {...value, 'installDispatched': true};
    }
    return installResult;
  }

  @override
  Future<void> allowInstall() async {
    settings++;
  }

  @override
  Future<void> openRelease(String url) async {
    releasePages++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Repository repository;
  late Platform platform;
  late UpdateManager manager;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = Repository();
    platform = Platform();
    manager = UpdateManager(
        repository: repository, platform: platform, configured: true);
  });
  tearDown(() => manager.dispose());

  test('numeric segments, prefixes, trailing zero and four-part versions', () {
    for (final pair in [
      ('1.10', '1.9'),
      ('v1.10.1', '1.10'),
      ('2.0', '1.99'),
      ('1.14.17', '1.14.16.1'),
      ('1.14.21.1', '1.14.21'),
      ('1.14.22', '1.14.21.1')
    ]) {
      expect(
          ReleaseVersion.parse(pair.$1)!
              .compareTo(ReleaseVersion.parse(pair.$2)!),
          greaterThan(0));
    }
    expect(
        ReleaseVersion.parse('V1.10.0')!
            .compareTo(ReleaseVersion.parse('1.10')!),
        0);
    for (final tag in ['', 'latest', 'v1.a', '1.10-beta', '1..10']) {
      expect(ReleaseVersion.parse(tag), isNull);
    }
  });
  test('APK preference, first fallback and Release fields', () {
    final info = release(assets: [
      asset('arm.apk'),
      asset('universal.apk'),
      asset('release.apk')
    ]);
    expect(info.apkName, 'universal.apk');
    expect(info.releaseName, 'Course');
    expect(info.apkSize, 100);
    expect(info.publishedAt, isNotNull);
    expect(info.releaseNotes, contains('Improve'));
    expect(release(assets: [asset('arm.apk'), asset('x86.apk')]).apkName,
        'arm.apk');
  });
  test('missing or untrusted APK never becomes downloadable', () {
    expect(release(assets: []).hasApk, false);
    for (final url in [
      'http://github.com/campus/course/releases/download/v1.15/a.apk',
      'https://github.com/other/course/releases/download/v1.15/a.apk',
      'https://github.com.evil.test/campus/course/releases/download/v1.15/a.apk',
      'https://github.com/campus/course/blob/main/a.apk'
    ]) {
      expect(release(assets: [asset('a.apk', url: url)]).hasApk, false);
    }
    expect(() => release(tag: 'latest'), throwsA(isA<UpdateException>()));
  });
  test('manual latest and new version checks', () async {
    repository.response = () async => release(tag: 'v1.14.17');
    expect((await manager.check())!.isNew, false);
    expect(manager.available, isNull);
    repository.response = () async => release();
    expect((await manager.check())!.isNew, true);
    expect(manager.available, isNotNull);
    expect(manager.automaticPromptPending, false);
  });
  test('network failure: manual message, automatic silent', () async {
    repository.response =
        () async => throw const UpdateException('无法连接 GitHub，请稍后重试');
    await expectLater(manager.check(), throwsA(isA<UpdateException>()));
    expect(await manager.check(automatic: true), isNull);
    expect(manager.checking, false);
    expect(manager.noticeSerial, 0);
  });
  test(
      'every cold start checks; obsolete check timestamp does not throttle; once per run',
      () async {
    SharedPreferences.setMockInitialValues({
      'lastUpdateCheckTime': DateTime.now().millisecondsSinceEpoch,
    });
    expect((await manager.check(automatic: true))!.isNew, true);
    expect(manager.automaticPromptPending, true);
    manager.automaticPromptShown = true;
    manager.automaticPromptPending = false;
    expect(await manager.check(automatic: true), isNull);
    final second = UpdateManager(
        repository: repository, platform: platform, configured: true);
    try {
      expect((await second.check(automatic: true))!.isNew, true);
      expect(second.automaticPromptPending, true);
      expect(repository.calls, 2);
      await second.check();
      expect(repository.calls, 3);
    } finally {
      second.dispose();
    }
  });
  test('concurrent checks share one request', () async {
    final gate = Completer<UpdateInfo>();
    repository.response = () => gate.future;
    final first = manager.check();
    final second = manager.check();
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls, 1);
    gate.complete(release());
    await Future.wait([first, second]);
  });
  test(
      'defer mutes automatic prompts for 24 hours across cold starts, not manual checks',
      () async {
    final start = DateTime.utc(2026, 10, 2);
    final first = UpdateManager(
        repository: repository,
        platform: platform,
        configured: true,
        clock: () => start);
    await first.check(automatic: true);
    await first.deferUpdate();
    first.dispose();
    for (final hours in [1, 23, 24]) {
      final coldStart = UpdateManager(
          repository: repository,
          platform: platform,
          configured: true,
          clock: () => start.add(Duration(hours: hours)));
      try {
        expect((await coldStart.check(automatic: true))!.isNew, true);
        expect(coldStart.automaticPromptPending, hours >= 24);
        expect((await coldStart.check())!.isNew, true);
      } finally {
        coldStart.dispose();
      }
    }
    expect(repository.calls, 7);
  });
  test('same or older release stays silent on cold start', () async {
    for (final tag in ['v1.14.17', 'v1.14.16']) {
      final coldStart = UpdateManager(
          repository: repository, platform: platform, configured: true);
      repository.response = () async => release(tag: tag);
      try {
        expect((await coldStart.check(automatic: true))!.isNew, false);
        expect(coldStart.automaticPromptPending, false);
        expect(coldStart.noticeSerial, 0);
      } finally {
        coldStart.dispose();
      }
    }
  });
  test('draft and prerelease never become an update', () {
    for (final field in ['draft', 'prerelease']) {
      expect(
          () => UpdateInfo.fromRelease({
                'tag_name': 'v1.15',
                field: true,
                'html_url': release().releasePageUrl,
                'assets': [],
              }, 'campus', 'course'),
          throwsA(isA<UpdateException>()));
    }
  });
  testWidgets(
      'root observer does not block content; prompts once across route recreation',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final gate = Completer<UpdateInfo>();
    repository.response = () => gate.future;
    Widget root() => MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('login content')),
        builder: (_, child) => Stack(fit: StackFit.expand, children: [
              Positioned.fill(child: child!),
              UpdateObserver(navigatorKey: key, manager: manager),
            ]));
    await tester.pumpWidget(root());
    await tester.pump();
    expect(find.text('login content').hitTestable(), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    gate.complete(release(tag: 'v1.14.22'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本：1.14.22'), findsOneWidget);
    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();
    key.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('other page'))));
    await tester.pumpAndSettle();
    await tester.pumpWidget(root());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('update without APK opens release page', (tester) async {
    await manager.initialize();
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold();
    })));
    final dialog = showUpdateDialog(context, manager, release(assets: []));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    await dialog;
    expect(platform.releasePages, 1);
    expect(platform.downloads, 0);
  });
  test('missing APK displays an actionable failure without download', () async {
    await expectLater(
        manager.download(release(assets: [])), throwsA(isA<UpdateException>()));
    expect(platform.downloads, 0);
  });
  test('download deduplication, progress and failure recovery', () async {
    platform.downloadGate = Completer<void>();
    final first = manager.download(release());
    await manager.download(release());
    expect(platform.downloads, 1);
    platform.downloadGate!.complete();
    await first;
    expect(manager.progress, 25);
    platform.value = {'status': 'failed', 'error': '下载已取消，请重试'};
    await manager.refreshDownload();
    expect(manager.notice, '下载已取消，请重试');
    expect(manager.downloading, false);
  });
  test('permission return installs existing APK without another download',
      () async {
    platform.value = {'status': 'ready'};
    platform.installResult = 'permissionRequired';
    await manager.initialize();
    expect(manager.permissionNeeded, true);
    await manager.allowInstall();
    expect(platform.settings, 1);
    platform.installResult = 'opened';
    manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(platform.installs, 2);
    expect(platform.downloads, 0);
    await manager.refreshDownload();
    expect(platform.installs, 2);
  });
  test('invalid APK leaves a stable retryable failure', () async {
    platform.value = {'status': 'ready'};
    platform.failInstall = true;
    await manager.initialize();
    expect(manager.downloadStatus, 'failed');
    expect(manager.notice, contains('校验失败'));
  });
  testWidgets('long notes retain buttons in light/dark blue/red themes',
      (tester) async {
    await manager.initialize();
    for (final brightness in Brightness.values) {
      for (final seed in [Colors.blue, Colors.red]) {
        late BuildContext context;
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                    seedColor: seed, brightness: brightness)),
            home: Builder(builder: (value) {
              context = value;
              return const Scaffold();
            })));
        final info = UpdateInfo(
            version: 'v1.15',
            releaseName: 'Course',
            releaseNotes: List.filled(100, '- Long update note').join('\n'),
            publishedAt: null,
            releasePageUrl: release().releasePageUrl,
            apkName: 'release.apk',
            apkUrl: release().apkUrl,
            apkSize: 100);
        final dialog = showUpdateDialog(context, manager, info);
        await tester.pumpAndSettle();
        expect(find.text('立即更新').hitTestable(), findsOneWidget);
        expect(find.text('稍后再说').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('稍后再说'));
        await tester.pumpAndSettle();
        await dialog;
      }
    }
  });
}
