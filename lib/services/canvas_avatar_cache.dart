import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'canvas_avatar.dart';

typedef CanvasAvatarHeadersProvider = Future<Map<String, String>> Function(
    Uri uri);
typedef CanvasAvatarBytesLoader = Future<Uint8List?> Function(
    Uri uri, Map<String, String> headers);

class CanvasAvatarCacheEntry {
  const CanvasAvatarCacheEntry({required this.file, required this.fetchedAt});

  final File file;
  final DateTime fetchedAt;
}

/// Deduplicates avatar requests and persists the last good image across app
/// process restarts. A stale file remains usable while its replacement loads.
class CanvasAvatarCache {
  CanvasAvatarCache._({
    required Future<Directory> Function() directoryProvider,
    required CanvasAvatarHeadersProvider headersProvider,
    required CanvasAvatarBytesLoader bytesLoader,
    required DateTime Function() clock,
    required this.refreshInterval,
  })  : _directoryProvider = directoryProvider,
        _headersProvider = headersProvider,
        _bytesLoader = bytesLoader,
        _clock = clock;

  static final instance = CanvasAvatarCache._(
    directoryProvider: getApplicationSupportDirectory,
    headersProvider: canvasAvatarHeaders,
    bytesLoader: _loadImageBytes,
    clock: DateTime.now,
    refreshInterval: const Duration(hours: 12),
  );

  factory CanvasAvatarCache.forTesting({
    required Future<Directory> Function() directoryProvider,
    required CanvasAvatarHeadersProvider headersProvider,
    required CanvasAvatarBytesLoader bytesLoader,
    DateTime Function()? clock,
    Duration refreshInterval = const Duration(hours: 12),
  }) =>
      CanvasAvatarCache._(
        directoryProvider: directoryProvider,
        headersProvider: headersProvider,
        bytesLoader: bytesLoader,
        clock: clock ?? DateTime.now,
        refreshInterval: refreshInterval,
      );

  final Future<Directory> Function() _directoryProvider;
  final CanvasAvatarHeadersProvider _headersProvider;
  final CanvasAvatarBytesLoader _bytesLoader;
  final DateTime Function() _clock;
  final Duration refreshInterval;
  final Map<String, CanvasAvatarCacheEntry> _entries = {};
  final Map<String, Future<CanvasAvatarCacheEntry?>> _entryReads = {};
  final Map<String, Future<CanvasAvatarCacheEntry?>> _downloads = {};
  final Map<String, DateTime> _failedUntil = {};
  Future<Directory>? _cacheDirectory;

  Future<Directory> _directory() => _cacheDirectory ??= () async {
        final base = await _directoryProvider();
        final directory = Directory(p.join(base.path, 'canvas_avatars'));
        await directory.create(recursive: true);
        return directory;
      }();

  String _key(Uri uri) =>
      sha256.convert(utf8.encode(uri.toString())).toString();

  Future<CanvasAvatarCacheEntry?> read(Uri uri) async {
    final key = _key(uri);
    final inMemory = _entries[key];
    if (inMemory != null && await inMemory.file.exists()) return inMemory;

    final pendingRead = _entryReads.putIfAbsent(key, () => _readEntry(key));
    final entry = await pendingRead;
    if (entry != null && await entry.file.exists()) {
      _entries[key] = entry;
      return entry;
    }
    return null;
  }

  bool isStale(CanvasAvatarCacheEntry entry) =>
      _clock().difference(entry.fetchedAt) >= refreshInterval;

  Future<CanvasAvatarCacheEntry?> download(Uri uri) async {
    final key = _key(uri);
    final active = _downloads[key];
    if (active != null) return active;

    final failedUntil = _failedUntil[key];
    if (failedUntil != null && _clock().isBefore(failedUntil)) return null;

    final request = _downloadAndPersist(uri, key).catchError((Object error) {
      _failedUntil[key] = _clock().add(const Duration(minutes: 5));
      return null;
    });
    _downloads[key] = request;
    try {
      return await request;
    } finally {
      if (identical(_downloads[key], request)) _downloads.remove(key);
    }
  }

  Future<void> evict(Uri uri, {File? expectedFile}) async {
    final key = _key(uri);
    final entry = await read(uri);
    if (expectedFile != null && entry?.file.path != expectedFile.path) return;
    _entries.remove(key);
    _entryReads[key] = Future<CanvasAvatarCacheEntry?>.value(null);
    final directory = await _directory();
    final manifest = File(p.join(directory.path, '$key.json'));
    if (entry != null && await entry.file.exists()) await entry.file.delete();
    if (await manifest.exists()) await manifest.delete();
  }

  Future<CanvasAvatarCacheEntry?> _readEntry(String key) async {
    try {
      final directory = await _directory();
      final manifest = File(p.join(directory.path, '$key.json'));
      if (!await manifest.exists()) return null;
      final value = jsonDecode(await manifest.readAsString());
      if (value is! Map<String, dynamic>) return null;
      final filename = value['file'];
      final fetchedAt = DateTime.tryParse('${value['fetchedAt'] ?? ''}');
      if (filename is! String ||
          p.basename(filename) != filename ||
          fetchedAt == null) {
        return null;
      }
      final file = File(p.join(directory.path, filename));
      if (!await file.exists()) return null;
      return CanvasAvatarCacheEntry(file: file, fetchedAt: fetchedAt);
    } catch (_) {
      return null;
    }
  }

  Future<CanvasAvatarCacheEntry?> _downloadAndPersist(
    Uri uri,
    String key,
  ) async {
    final headers = await _headersProvider(uri);
    final bytes = await _bytesLoader(uri, headers);
    if (bytes == null || bytes.isEmpty) {
      _failedUntil[key] = _clock().add(const Duration(minutes: 5));
      return null;
    }

    final directory = await _directory();
    final contentHash = sha256.convert(bytes).toString();
    final filename = '$key-$contentHash.img';
    final file = File(p.join(directory.path, filename));
    if (!await file.exists()) {
      final temporary = File(p.join(directory.path, '.$filename.tmp'));
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    }

    final fetchedAt = _clock();
    final entry = CanvasAvatarCacheEntry(file: file, fetchedAt: fetchedAt);
    final manifest = File(p.join(directory.path, '$key.json'));
    final temporaryManifest = File('${manifest.path}.tmp');
    await temporaryManifest.writeAsString(
      jsonEncode({'file': filename, 'fetchedAt': fetchedAt.toIso8601String()}),
      flush: true,
    );
    if (await manifest.exists()) await manifest.delete();
    await temporaryManifest.rename(manifest.path);

    _entries[key] = entry;
    _entryReads[key] = Future<CanvasAvatarCacheEntry?>.value(entry);
    _failedUntil.remove(key);
    return entry;
  }
}

Future<Uint8List?> _loadImageBytes(
  Uri uri,
  Map<String, String> headers,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 15));
    for (final header in headers.entries) {
      request.headers.set(header.key, header.value);
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok ||
        !(response.headers.contentType?.mimeType.startsWith('image/') ??
            false) ||
        response.contentLength > 8 * 1024 * 1024) {
      await response.drain<void>();
      return null;
    }

    final bytes = BytesBuilder(copy: false);
    var tooLarge = false;
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 8 * 1024 * 1024) {
        tooLarge = true;
        break;
      }
      bytes.add(chunk);
    }
    return tooLarge ? null : bytes.takeBytes();
  } finally {
    client.close(force: true);
  }
}
