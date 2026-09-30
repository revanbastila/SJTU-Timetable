import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_update.dart';
import 'update_config.dart';

abstract class ReleaseRepository {
  Future<UpdateInfo> latest();
}

class GitHubReleaseApi implements ReleaseRepository {
  GitHubReleaseApi(
      {this.owner = UpdateConfig.githubOwner,
      this.repo = UpdateConfig.githubRepo,
      HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;
  final String owner, repo;
  final HttpClient Function() _clientFactory;

  @override
  Future<UpdateInfo> latest() async {
    if (!UpdateConfig.validRepository(owner, repo)) {
      throw const UpdateException('尚未配置 GitHub 更新仓库');
    }
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri =
          Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest');
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'JiaotongCourse-Android');
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
          throw const UpdateException('未找到公开仓库或正式 Release，请检查更新源配置');
        }
        throw const UpdateException('无法连接 GitHub，请稍后重试');
      }
      final bytes = <int>[];
      await (() async {
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 4 * 1024 * 1024) {
            throw const UpdateException('GitHub 返回的更新信息过大');
          }
          bytes.addAll(chunk);
        }
      })()
          .timeout(const Duration(seconds: 15));
      final body = utf8.decode(bytes);
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        throw const UpdateException('无法识别 GitHub 更新信息');
      }
      return UpdateInfo.fromRelease(json, owner, repo);
    } on UpdateException {
      rethrow;
    } on SocketException {
      throw const UpdateException('无法连接 GitHub，请稍后重试');
    } on TimeoutException {
      throw const UpdateException('检查更新失败，请检查网络后重试');
    } catch (_) {
      throw const UpdateException('检查更新失败，请检查网络后重试');
    } finally {
      client.close(force: true);
    }
  }
}
