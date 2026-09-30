import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/canvas_avatar_cache.dart';

void main() {
  late Directory root;
  late DateTime now;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('canvas-avatar-cache-');
    now = DateTime.utc(2026, 9, 30);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  CanvasAvatarCache createCache({
    required CanvasAvatarBytesLoader loader,
    Duration refreshInterval = const Duration(hours: 12),
  }) =>
      CanvasAvatarCache.forTesting(
        directoryProvider: () async => root,
        headersProvider: (_) async => const {'Cookie': 'canvas-session'},
        bytesLoader: loader,
        clock: () => now,
        refreshInterval: refreshInterval,
      );

  test('coalesces simultaneous downloads and reads cached image after restart',
      () async {
    var requests = 0;
    final uri = Uri.parse('https://oc.sjtu.edu.cn/avatar/17.png');
    final firstCache = createCache(loader: (_, headers) async {
      expect(headers['Cookie'], 'canvas-session');
      requests++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return Uint8List.fromList([1, 2, 3, 4]);
    });

    final results = await Future.wait([
      firstCache.download(uri),
      firstCache.download(uri),
    ]);
    expect(requests, 1);
    expect(results[0]?.file.path, results[1]?.file.path);
    expect(await results.first!.file.readAsBytes(), [1, 2, 3, 4]);

    final restartedCache = createCache(loader: (_, __) async {
      requests++;
      return Uint8List.fromList([9]);
    });
    final cached = await restartedCache.read(uri);
    expect(cached?.file.path, results.first?.file.path);
    expect(requests, 1);
  });

  test('refreshes stale content using a new file while preserving old image',
      () async {
    var payload = Uint8List.fromList([1, 2, 3]);
    final uri = Uri.parse('https://oc.sjtu.edu.cn/avatar/18.png');
    final cache = createCache(
      refreshInterval: const Duration(hours: 1),
      loader: (_, __) async => Uint8List.fromList(payload),
    );

    final initial = await cache.download(uri);
    expect(initial, isNotNull);
    now = now.add(const Duration(hours: 2));
    final stale = await cache.read(uri);
    expect(cache.isStale(stale!), isTrue);

    payload = Uint8List.fromList([4, 5, 6]);
    final updated = await cache.download(uri);
    expect(updated, isNotNull);
    expect(updated!.file.path, isNot(stale.file.path));
    expect(await stale.file.readAsBytes(), [1, 2, 3]);
    expect(await updated.file.readAsBytes(), [4, 5, 6]);
  });

  test('remembers a failed URL briefly instead of retrying on rebuild',
      () async {
    var requests = 0;
    final uri = Uri.parse('https://oc.sjtu.edu.cn/avatar/19.png');
    final cache = createCache(loader: (_, __) async {
      requests++;
      return null;
    });

    expect(await cache.download(uri), isNull);
    expect(await cache.download(uri), isNull);
    expect(requests, 1);

    now = now.add(const Duration(minutes: 6));
    expect(await cache.download(uri), isNull);
    expect(requests, 2);
  });
}
