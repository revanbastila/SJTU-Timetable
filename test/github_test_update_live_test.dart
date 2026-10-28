import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/app_update.dart';
import 'package:jiaotong_course/services/github_release_api.dart';
import 'package:jiaotong_course/services/update_config.dart';

void main() {
  test('published test branch is readable through the production update reader',
      () async {
    final info = await GitHubReleaseApi(
        channel: UpdateChannel.installedApp,
        installedPackage: () async => UpdateConfig.testPackage,
        supportedAbis: () async => ['arm64-v8a', 'armeabi-v7a']).latest();
    expect(info.channel, 'test-a');
    expect(info.packageName, UpdateConfig.testPackage);
    expect(info.versionCode, greaterThanOrEqualTo(96));
    expect(info.apkName, endsWith('test-arm64-v8a.apk'));
    expect(info.apkSize, greaterThan(0));
    expect(info.apkDigest, matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
    expect(
        info.isNewerThan(const AppVersion('1.14.27.6', 93,
            packageName: UpdateConfig.testPackage)),
        true);
    expect(
        info.isNewerThan(const AppVersion('1.14.27.7', 94,
            packageName: UpdateConfig.testPackage)),
        true);
    expect(
        info.isNewerThan(const AppVersion('1.14.27.8', 95,
            packageName: UpdateConfig.testPackage)),
        true);
    expect(
        info.isNewerThan(AppVersion(info.version, info.versionCode!,
            packageName: UpdateConfig.testPackage)),
        false);
    final data = {
      'source': 'GitHub test/1.14.26 updates/test-a.json',
      'realNetwork': true,
      'reader': 'GitHubReleaseApi installedApp',
      'packageNameInjectedWithoutDevice': UpdateConfig.testPackage,
      'versionName': info.version,
      'versionCode': info.versionCode,
      'apkName': info.apkName,
      'apkSize': info.apkSize,
      'apkDigest': info.apkDigest,
      'apkUrl': info.apkUrl,
      'olderSimulatedBuildDetectsUpdate': true,
      'olderSimulatedVersions': [
        '1.14.27.6 (93)',
        '1.14.27.7 (94)',
        '1.14.27.8 (95)'
      ],
      'sameSimulatedBuildIsCurrent': true,
      'realPhoneInstallationVerified': false
    };
    final file = File('build/update-live-verification.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    // Safe output contains public release metadata only.
    // ignore: avoid_print
    print(jsonEncode(data));
  }, skip: !const bool.fromEnvironment('RUN_GITHUB_TEST_UPDATE_PROBE'));
}
