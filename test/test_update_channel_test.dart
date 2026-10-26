import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/app_update.dart';
import 'package:jiaotong_course/services/android_update_bridge.dart';
import 'package:jiaotong_course/services/github_release_api.dart';
import 'package:jiaotong_course/services/update_config.dart';
import 'package:jiaotong_course/services/update_manager.dart';
import 'package:jiaotong_course/widgets/app_update_ui.dart';
import 'github_release_api_test.dart' show Client, Request, Response;
import 'app_update_test.dart' as fixtures;

Map<String, dynamic> manifest(
        {String version = '1.14.27.5',
        int code = 92,
        List<String> abis = const [
          'universal',
          'armeabi-v7a',
          'x86_64',
          'arm64-v8a'
        ]}) =>
    {
      'schemaVersion': 1,
      'channel': 'test-a',
      'packageName': UpdateConfig.testPackage,
      'versionName': version,
      'versionCode': code,
      'releaseTag': 'v$version-test',
      'releaseName': '交大课表 $version · 测试 A',
      'releaseNotes': '- 测试分支更新',
      'publishedAt': '2026-10-26T08:00:00Z',
      'releasePageUrl':
          'https://github.com/campus/course/releases/tag/v$version-test',
      'assets': <Map<String, dynamic>>[
        for (final abi in abis)
          {
            'abi': abi,
            'name': 'jiaotong_course-$version-test-$abi.apk',
            'size': 100,
            'sha256': List.filled(64, 'a').join(),
            'url':
                'https://github.com/campus/course/releases/download/v$version-test/jiaotong_course-$version-test-$abi.apk',
          }
      ],
    };
UpdateInfo parse(Map<String, dynamic> json,
        {List<String> abis = const ['arm64-v8a', 'armeabi-v7a']}) =>
    UpdateInfo.fromTestManifest(json, 'campus', 'course', supportedAbis: abis);

class TestPlatform extends fixtures.Platform {
  TestPlatform(
      [this.app = const AppVersion('1.14.27.4', 91,
          packageName: UpdateConfig.testPackage)]);
  final AppVersion app;
  @override
  Future<AppVersion> version() async => app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'test package reads a file at the exact test branch with fresh unauthenticated HTTP',
      () async {
    final client = Client(Request(Response(200, jsonEncode(manifest()))));
    final api = GitHubReleaseApi(
        owner: 'campus',
        repo: 'course',
        channel: UpdateChannel.installedApp,
        installedPackage: () async => UpdateConfig.testPackage,
        supportedAbis: () async => ['arm64-v8a'],
        clientFactory: () => client);
    final info = await api.latest();
    expect(client.uri!.host, 'raw.githubusercontent.com');
    expect(client.uri!.path,
        '/campus/course/refs/heads/test/1.14.26/updates/test-a.json');
    expect(client.uri!.queryParameters['_'], matches(RegExp(r'^\d+$')));
    expect(client.request.headers.values['Accept'], 'application/json');
    expect(client.request.headers.values['Cache-Control'], 'no-cache');
    expect(client.request.headers.values.containsKey('Authorization'), false);
    expect(client.request.followRedirects, false);
    expect(client.closed, true);
    expect(info.version, '1.14.27.5');
    expect(info.versionCode, 92);
    expect(info.channel, 'test-a');
    expect(info.apkName, endsWith('arm64-v8a.apk'));
    expect(info.apkDigest, 'sha256:${List.filled(64, 'a').join()}');
  });
  test(
      'official package still reads official latest without opting into prereleases',
      () async {
    final client = Client(Request(Response(
        200,
        jsonEncode({
          'tag_name': 'v1.14.23',
          'html_url': 'https://github.com/campus/course/releases/tag/v1.14.23',
          'assets': []
        }))));
    await GitHubReleaseApi(
        owner: 'campus',
        repo: 'course',
        channel: UpdateChannel.installedApp,
        installedPackage: () async => UpdateConfig.stablePackage,
        supportedAbis: () async => [],
        clientFactory: () => client).latest();
    expect(client.uri!.path, '/repos/campus/course/releases/latest');
    expect(
        client.request.headers.values['Accept'], 'application/vnd.github+json');
  });
  test('an unknown package cannot silently select official or test downloads',
      () async {
    final client = Client(Request(Response(200, '{}')));
    await expectLater(
        GitHubReleaseApi(
            owner: 'campus',
            repo: 'course',
            channel: UpdateChannel.installedApp,
            installedPackage: () async => 'other.package',
            clientFactory: () => client).latest(),
        throwsA(isA<UpdateException>()));
    expect(client.uri, isNull);
    expect(client.closed, true);
  });
  test('missing or invalid test file never falls back to formal latest',
      () async {
    for (final response in [
      Response(404, '{}'),
      Response(200, 'bad json'),
      Response(200, '{}'),
      Response(403, '{}')
    ]) {
      final client = Client(Request(response));
      await expectLater(
          GitHubReleaseApi(
              owner: 'campus',
              repo: 'course',
              channel: UpdateChannel.testA,
              clientFactory: () => client).latest(),
          throwsA(isA<UpdateException>()));
      expect(client.uri!.path,
          contains('/refs/heads/test/1.14.26/updates/test-a.json'));
      expect(client.closed, true);
    }
  });
  for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
    test('test update chooses $abi before universal', () {
      expect(parse(manifest(), abis: [abi]).apkName, endsWith('test-$abi.apk'));
    });
  }
  test('unknown architecture uses universal; incompatible split is rejected',
      () {
    expect(parse(manifest(), abis: ['riscv64']).apkName,
        endsWith('universal.apk'));
    expect(() => parse(manifest(abis: ['x86_64']), abis: ['arm64-v8a']),
        throwsA(isA<UpdateException>()));
  });
  test('versionCode prevents stale updates and allows a same-name rebuild', () {
    final info = parse(manifest());
    expect(info.isNewerThan(const AppVersion('1.14.27.4', 91)), true);
    expect(info.isNewerThan(const AppVersion('1.14.27.5', 91)), true);
    expect(info.isNewerThan(const AppVersion('1.14.27.5', 92)), false);
    expect(info.isNewerThan(const AppVersion('1.14.27.4', 93)), false);
    expect(info.isNewerThan(const AppVersion('1.14.27.6', 91)), false);
  });
  test('manifest binds schema, test channel, package, numeric version and tag',
      () {
    for (final changes in [
      {'schemaVersion': 2},
      {'channel': 'stable'},
      {'packageName': UpdateConfig.stablePackage},
      {'versionName': '1.14.27.5-test'},
      {'versionCode': 0},
      {'versionCode': 92.5},
      {'releaseTag': 'v1.14.27.5'},
      {
        'releasePageUrl':
            'https://github.com/other/course/releases/tag/v1.14.27.5-test'
      },
      {
        'releasePageUrl':
            'https://github.com/campus/course/releases/tag/v1.14.27.4-test'
      },
    ]) {
      expect(() => parse({...manifest(), ...changes}),
          throwsA(isA<UpdateException>()));
    }
  });
  test(
      'download metadata rejects other repositories, releases, formal APKs and missing hashes',
      () {
    for (final changes in [
      {
        'url':
            'http://github.com/campus/course/releases/download/v1.14.27.5-test/a.apk'
      },
      {
        'url':
            'https://github.com/other/course/releases/download/v1.14.27.5-test/a.apk'
      },
      {
        'url':
            'https://github.com/campus/course/releases/download/v1.14.27.4-test/a.apk'
      },
      {'name': 'formal-release.apk'},
      {'sha256': ''},
      {'sha256': 'not-a-hash'},
      {'size': 0},
      {'size': 100.5},
      {'abi': 'riscv64'},
    ]) {
      final json = manifest(abis: ['arm64-v8a']);
      (json['assets'] as List)[0] = <String, dynamic>{
        ...(json['assets'] as List).first,
        ...changes
      };
      expect(() => parse(json), throwsA(isA<UpdateException>()));
    }
    final duplicate = manifest(abis: ['arm64-v8a', 'arm64-v8a']);
    expect(() => parse(duplicate), throwsA(isA<UpdateException>()));
  });
  test(
      'startup and manual checks share the same test reader and equal build stays silent',
      () async {
    final client = Client(Request(Response(200, jsonEncode(manifest()))));
    final api = GitHubReleaseApi(
        owner: 'campus',
        repo: 'course',
        channel: UpdateChannel.installedApp,
        installedPackage: () async => UpdateConfig.testPackage,
        supportedAbis: () async => ['arm64-v8a'],
        clientFactory: () => client);
    final manager = UpdateManager(
        repository: api, platform: TestPlatform(), configured: true);
    expect((await manager.check(automatic: true))!.isNew, true);
    expect(manager.automaticPromptPending, true);
    expect((await manager.check())!.info.channel, 'test-a');
    manager.dispose();
    final current = UpdateManager(
        repository: fixtures.Repository()
          ..response = () async => parse(manifest()),
        platform: TestPlatform(const AppVersion('1.14.27.5', 92,
            packageName: UpdateConfig.testPackage)),
        configured: true);
    expect((await current.check(automatic: true))!.isNew, false);
    expect(current.automaticPromptPending, false);
    current.dispose();
  });
  test(
      'native bridge preserves package and exact manifest version for installation validation',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Map? download;
    messenger.setMockMethodCallHandler(AndroidUpdateBridge.channel,
        (call) async {
      if (call.method == 'version') {
        return {
          'name': '1.14.27.4',
          'code': 91,
          'packageName': UpdateConfig.testPackage
        };
      }
      if (call.method == 'download') download = call.arguments as Map;
      return <String, dynamic>{};
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(AndroidUpdateBridge.channel, null));
    final bridge = AndroidUpdateBridge();
    expect((await bridge.version()).packageName, UpdateConfig.testPackage);
    await bridge.download(parse(manifest()));
    expect(download!['versionCode'], 92);
    expect(download!['versionName'], '1.14.27.5');
    expect(download!['packageName'], UpdateConfig.testPackage);
    expect(download!['digest'], startsWith('sha256:'));
  });
  for (final brightness in Brightness.values) {
    testWidgets(
        'test update settings and manual prompt survive theme switch from $brightness',
        (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() async {
        for (final entry in {
          'PreviewChinese': 'C:/Windows/Fonts/msyh.ttc',
          'MaterialIcons':
              '../../work/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        }.entries) {
          final file = File(entry.value);
          if (await file.exists()) {
            await (FontLoader(entry.key)
                  ..addFont(
                      file.readAsBytes().then((b) => ByteData.view(b.buffer))))
                .load();
          }
        }
      });
      final repository = fixtures.Repository()
        ..response = () async => parse(manifest());
      final manager = UpdateManager(
          repository: repository, platform: TestPlatform(), configured: true);
      Widget page(Brightness value) => RepaintBoundary(
          key: const Key('update-preview'),
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                  fontFamily: 'PreviewChinese',
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.blue, brightness: value)),
              home: Scaffold(
                  body: Padding(
                      padding: const EdgeInsets.all(20),
                      child: UpdateSettingsEntry(manager: manager)))));
      await t.pumpWidget(page(brightness));
      await t.pumpAndSettle();
      expect(find.text('更新渠道：测试版'), findsOneWidget);
      final other =
          brightness == Brightness.light ? Brightness.dark : Brightness.light;
      await t.pumpWidget(page(other));
      await t.pumpAndSettle();
      await t.tap(find.text('检查更新'));
      await t.pumpAndSettle();
      expect(find.text('发现新版本：1.14.27.5'), findsOneWidget);
      expect(find.text('立即更新').hitTestable(), findsOneWidget);
      expect(Theme.of(t.element(find.text('立即更新'))).brightness, other);
      expect(t.takeException(), isNull);
      final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('update-preview')));
      await t.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('build/update-previews');
        await output.create(recursive: true);
        await File('${output.path}/update-test-${other.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      await t.tap(find.text('稍后再说'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox.shrink());
      manager.dispose();
    });
  }
}
