import 'package:flutter/services.dart';
import '../models/app_update.dart';
import 'update_config.dart';

abstract class UpdatePlatform {
  Future<AppVersion> version();
  Future<Map<String, dynamic>> download(UpdateInfo info);
  Future<Map<String, dynamic>> state();
  Future<String> install();
  Future<void> allowInstall();
  Future<void> openRelease(String url);
}

class AndroidUpdateBridge implements UpdatePlatform {
  static const channel = MethodChannel('cn.sjtu.jiaotong_course/updates');
  @override
  Future<AppVersion> version() async {
    final value = await channel.invokeMapMethod<String, dynamic>('version');
    if (value == null) throw const UpdateException('无法读取当前应用版本');
    return AppVersion(value['name'] as String, (value['code'] as num).toInt());
  }

  @override
  Future<Map<String, dynamic>> download(UpdateInfo info) async =>
      Map<String, dynamic>.from(
          await channel.invokeMapMethod<String, dynamic>('download', {
                'owner': UpdateConfig.githubOwner,
                'repo': UpdateConfig.githubRepo,
                'url': info.apkUrl,
                'name': info.apkName,
                'size': info.apkSize,
                'digest': info.apkDigest,
              }) ??
              const {});
  @override
  Future<Map<String, dynamic>> state() async => Map<String, dynamic>.from(
      await channel.invokeMapMethod<String, dynamic>('state') ?? const {});
  @override
  Future<String> install() async =>
      await channel.invokeMethod<String>('install') ?? 'failed';
  @override
  Future<void> allowInstall() => channel.invokeMethod<void>('allowInstall');
  @override
  Future<void> openRelease(String url) =>
      channel.invokeMethod<void>('openRelease', {
        'url': url,
        'owner': UpdateConfig.githubOwner,
        'repo': UpdateConfig.githubRepo,
      });
}
