import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/teaching_calendar.dart';

class TeachingCalendarRepository {
  static const url =
      'https://raw.githubusercontent.com/revanbastila/sjtu-calendar-data/main/calendar.json';
  static const cacheKey = 'teachingCalendarJson_v1';
  TeachingCalendarRepository({Future<String> Function()? fetch})
      : _fetch = fetch ?? _download;
  final Future<String> Function() _fetch;
  Future<TeachingCalendar?>? _pending;
  bool lastRefreshSucceeded = false;

  TeachingCalendar readCache(SharedPreferences prefs) {
    try {
      final text = prefs.getString(cacheKey);
      final cached = text == null
          ? const TeachingCalendar.empty()
          : TeachingCalendar.parse(text);
      debugPrint('[calendar] cache: ${text == null ? "missing" : "loaded"}; '
          'version=${cached.version} updated_at=${cached.updatedAt} rules=${cached.rules.length}');
      return cached;
    } catch (error) {
      debugPrint('[calendar] cache parse error: $error');
      return const TeachingCalendar.empty();
    }
  }

  Future<TeachingCalendar?> refresh(TeachingCalendar current) =>
      _pending ??= _refresh(current).whenComplete(() => _pending = null);

  Future<TeachingCalendar?> _refresh(TeachingCalendar current) async {
    var stage = 'network';
    lastRefreshSucceeded = false;
    try {
      final text = await _fetch();
      stage = 'parse';
      final calendar = TeachingCalendar.parse(text);
      debugPrint('[calendar] parsed: version=${calendar.version} '
          'updated_at=${calendar.updatedAt} rules loaded=${calendar.rules.length} '
          'digest=${calendar.fingerprint}');
      if (calendar.version == current.version &&
          calendar.fingerprint == current.fingerprint) {
        lastRefreshSucceeded = true;
        debugPrint('[calendar] cache is current');
        return null;
      }
      if (calendar.version == current.version) {
        debugPrint(
            '[calendar] same version but changed content; repairing stale cache');
      }
      stage = 'cache write';
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(cacheKey, text)) {
        throw const FileSystemException('calendar cache write failed');
      }
      lastRefreshSucceeded = true;
      debugPrint('[calendar] cache saved; applying downloaded rules');
      return calendar;
    } catch (error) {
      debugPrint('[calendar] $stage error: $error; previous cache retained');
      return null;
    }
  }

  static Future<String> _download() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      debugPrint('[calendar] fetch URL: $url');
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      debugPrint('[calendar] fetch: ${response.statusCode}');
      if (response.statusCode != 200) {
        throw HttpException('calendar HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const FormatException('calendar exceeds size limit');
        }
      }
      final text = utf8.decode(bytes);
      debugPrint('[calendar] response bytes=${bytes.length}; preview: '
          '${text.substring(0, text.length > 200 ? 200 : text.length)}');
      return text;
    } finally {
      client.close(force: true);
    }
  }
}
