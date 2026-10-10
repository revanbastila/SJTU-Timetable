import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/app_update.dart';
import 'package:jiaotong_course/services/android_update_bridge.dart';

UpdateInfo select(
  List<String> names,
  List<String> abis,
) => UpdateInfo.fromRelease(
  {
    'tag_name': 'v1.14.23.1',
    'html_url': 'https://github.com/campus/course/releases/tag/v1.14.23.1',
    'assets': [
      for (final name in names)
        {
          'name': name,
          'size': 100,
          'browser_download_url':
              'https://github.com/campus/course/releases/download/v1.14.23.1/$name',
        },
    ],
  },
  'campus',
  'course',
  supportedAbis: abis,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const names = [
    'course-universal.apk',
    'course-armeabi-v7a-release.apk',
    'course-x86_64-release.apk',
    'course-arm64-v8a-release.apk',
  ];
  for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
    test(
      '$abi selects matching split before universal regardless of order',
      () {
        expect(select(names, [abi]).apkName, 'course-$abi-release.apk');
        expect(
          select(names.reversed.toList(), [abi]).apkName,
          'course-$abi-release.apk',
        );
      },
    );
  }
  test('device ABI order prefers native before translated or 32-bit', () {
    expect(
      select(names, ['arm64-v8a', 'armeabi-v7a']).apkName,
      'course-arm64-v8a-release.apk',
    );
    expect(
      select(names, ['x86_64', 'arm64-v8a']).apkName,
      'course-x86_64-release.apk',
    );
    expect(
      select(['course-armeabi-v7a.apk'], ['arm64-v8a', 'armeabi-v7a']).apkName,
      'course-armeabi-v7a.apk',
    );
  });
  test('unknown ABI or missing matching split selects universal', () {
    expect(select(names, []).apkName, 'course-universal.apk');
    expect(select(names, ['riscv64']).apkName, 'course-universal.apk');
    expect(
      select(
        ['course-x86_64.apk', 'course-universal.apk'],
        ['arm64-v8a'],
      ).apkName,
      'course-universal.apk',
    );
  });
  test('incompatible splits never become downloadable', () {
    expect(select(['course-x86_64.apk'], ['arm64-v8a']).hasApk, false);
    expect(select(['course-arm64-v8a.apk'], []).hasApk, false);
    expect(select(['course-x86_64.apk'], ['x86']).hasApk, false);
  });
  test('legacy unlabelled release APK remains usable', () {
    expect(
      select(
        ['course-x86_64.apk', 'course-release.apk'],
        ['arm64-v8a'],
      ).apkName,
      'course-release.apk',
    );
  });
  test('common architecture aliases and case are recognized', () {
    expect(select(['course-ARM64.apk'], ['arm64-v8a']).hasApk, true);
    expect(select(['course-armv7.apk'], ['armeabi-v7a']).hasApk, true);
    expect(select(['course-amd64.apk'], ['x86_64']).hasApk, true);
    expect(select(['course-x86.apk'], ['x86_64', 'x86']).hasApk, true);
  });
  test('native bridge preserves supported ABI preference order', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidUpdateBridge.channel, (
      call,
    ) async {
      expect(call.method, 'supportedAbis');
      return ['x86_64', 'arm64-v8a'];
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(AndroidUpdateBridge.channel, null),
    );
    expect(await AndroidUpdateBridge.supportedAbis(), ['x86_64', 'arm64-v8a']);
  });
}
