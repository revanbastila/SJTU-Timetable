import '../services/update_config.dart';

class AppVersion {
  const AppVersion(this.name, this.code);
  final String name;
  final int code;
}

class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.parts);
  final List<BigInt> parts;

  static ReleaseVersion? parse(String raw) {
    final text = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (!RegExp(r'^\d+(?:\.\d+)+$').hasMatch(text)) return null;
    return ReleaseVersion(text.split('.').map(BigInt.parse).toList());
  }

  @override
  int compareTo(ReleaseVersion other) {
    final length = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < length; i++) {
      final left = i < parts.length ? parts[i] : BigInt.zero;
      final right = i < other.parts.length ? other.parts[i] : BigInt.zero;
      final order = left.compareTo(right);
      if (order != 0) return order;
    }
    return 0;
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseName,
    required this.releaseNotes,
    required this.publishedAt,
    required this.releasePageUrl,
    this.apkName = '',
    this.apkUrl = '',
    this.apkSize = 0,
    this.apkDigest = '',
  });
  final String version, releaseName, releaseNotes, releasePageUrl;
  final String apkName, apkUrl, apkDigest;
  final DateTime? publishedAt;
  final int apkSize;
  bool get hasApk => apkUrl.isNotEmpty;
  String get displayVersion => 'v${version.replaceFirst(RegExp(r'^[vV]'), '')}';

  factory UpdateInfo.fromRelease(
    Map<String, dynamic> json,
    String owner,
    String repo, {
    List<String> supportedAbis = const [],
  }) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    if (ReleaseVersion.parse(tag) == null) {
      throw const UpdateException('无法识别最新版本号');
    }
    if (json['draft'] == true || json['prerelease'] == true) {
      throw const UpdateException('尚无正式发布版本');
    }
    final page = Uri.tryParse(json['html_url'] as String? ?? '');
    if (page == null || !UpdateConfig.trustedReleasePage(page, owner, repo)) {
      throw const UpdateException('发布页面不属于配置的 GitHub 仓库');
    }
    final candidates = <Map<String, dynamic>>[];
    for (final asset
        in json['assets'] is List ? json['assets'] as List : const []) {
      if (asset is! Map) continue;
      final row = Map<String, dynamic>.from(asset);
      final name = row['name'] as String? ?? '';
      final url = Uri.tryParse(row['browser_download_url'] as String? ?? '');
      if (name.toLowerCase().endsWith('.apk') &&
          url != null &&
          UpdateConfig.trustedAsset(url, owner, repo) &&
          (row['size'] is num && (row['size'] as num) > 0) &&
          (row['state'] == null || row['state'] == 'uploaded')) {
        candidates.add(row);
      }
    }
    // Android supplies ABIs in device preference order. A matching small APK
    // precedes universal; explicitly incompatible architectures are excluded.
    Map<String, dynamic>? selected;
    for (final abi in supportedAbis) {
      selected = _preferredAsset(
        candidates.where(
          (asset) => _assetAbis(asset['name'] as String).contains(abi),
        ),
      );
      if (selected != null) break;
    }
    selected ??= _preferredAsset(
      candidates.where((asset) => _assetAbis(asset['name'] as String).isEmpty),
    );
    return UpdateInfo(
      version: tag,
      releaseName: json['name'] as String? ?? tag,
      releaseNotes: json['body'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      releasePageUrl: page.toString(),
      apkName: selected?['name'] as String? ?? '',
      apkUrl: selected?['browser_download_url'] as String? ?? '',
      apkSize: (selected?['size'] as num?)?.toInt() ?? 0,
      apkDigest: selected?['digest'] as String? ?? '',
    );
  }

  static Map<String, dynamic>? _preferredAsset(
    Iterable<Map<String, dynamic>> assets,
  ) {
    final rows = assets.toList();
    for (final label in ['universal', 'release']) {
      for (final asset in rows) {
        if ((asset['name'] as String).toLowerCase().contains(label)) {
          return asset;
        }
      }
    }
    return rows.isEmpty ? null : rows.first;
  }

  static Set<String> _assetAbis(String name) {
    final text = name.toLowerCase();
    bool has(String pattern) => RegExp(
      '(^|[^a-z0-9])(?:$pattern)'
      r'(?=$|[^a-z0-9])',
    ).hasMatch(text);
    final abis = <String>{};
    if (has('arm64-v8a|arm64|aarch64')) abis.add('arm64-v8a');
    if (has('armeabi-v7a|armeabi|armv7|arm-v7')) abis.add('armeabi-v7a');
    if (has('x86_64|x86-64|amd64')) {
      abis.add('x86_64');
    } else if (has('x86|i686')) {
      abis.add('x86');
    }
    return abis;
  }
}
