import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../models/canvas_data.dart';

class CanvasAnnouncementSync {
  static const _channel =
      MethodChannel('cn.sjtu.jiaotong_course/announcements');

  static Future<void> configure(
          String account, List<CanvasCourseData> courses) =>
      _channel.invokeMethod<void>('configure', {
        'account': account.isEmpty
            ? ''
            : sha256.convert(utf8.encode(account)).toString(),
        'catalog': jsonEncode([
          for (final course in courses) {'id': course.id, 'name': course.name},
        ]),
      }).timeout(const Duration(seconds: 8));

  static Future<void> disable() async {
    try {
      await configure('', const []);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> read({bool refresh = false}) async {
    final text = await _channel
        .invokeMethod<String>(refresh ? 'refresh' : 'cached')
        .timeout(const Duration(seconds: 150));
    return Map<String, dynamic>.from(
        jsonDecode(text ?? '{"courses":[]}') as Map);
  }

  /// Incremental notices preserve old announcements, people, syllabus and IDs
  /// used by the existing read/unread feed. An unchanged poll keeps identity.
  static CanvasSnapshot merge(
      CanvasSnapshot cached, Map<String, dynamic> data) {
    final updates = <String, Map<String, dynamic>>{};
    for (final value
        in data['courses'] is List ? data['courses'] as List : const []) {
      if (value is Map) {
        updates['${value['id']}'] = Map<String, dynamic>.from(value);
      }
    }
    var changed = false;
    final courses = [
      for (final course in cached.courses)
        (() {
          final update = updates[course.id];
          if (update == null || update['announcements'] is! List) return course;
          final unique = <String, CanvasItem>{};
          String identity(CanvasItem item) => item.assetId.isNotEmpty
              ? item.assetId
              : item.id.isNotEmpty
                  ? item.id
                  : '${item.htmlUrl}|${item.title}|${item.createdAt}';
          for (final item in course.announcements) {
            unique[identity(item)] = item;
          }
          for (final value in update['announcements'] as List) {
            if (value is! Map) continue;
            final item = CanvasItem.fromMap({
              ...Map<String, dynamic>.from(value),
              'courseId': course.id,
              'courseName': course.name,
              'assetId': value['assetId'] ?? value['id'],
              'type': '公告',
            });
            if (item.id.isEmpty && item.assetId.isEmpty) continue;
            unique[identity(item)] = item;
          }
          final items = unique.values.toList()
            ..sort((a, b) {
              final date = (DateTime.tryParse(b.createdAt) ?? DateTime(1970))
                  .compareTo(DateTime.tryParse(a.createdAt) ?? DateTime(1970));
              return date != 0 ? date : identity(a).compareTo(identity(b));
            });
          if (jsonEncode(items.map((item) => item.toMap()).toList()) ==
              jsonEncode(
                  course.announcements.map((item) => item.toMap()).toList())) {
            return course;
          }
          changed = true;
          return course.withAnnouncements(items);
        })(),
    ];
    return changed
        ? CanvasSnapshot(
            dashboardItems: cached.dashboardItems,
            courses: courses,
            syncedAt: DateTime.now(),
            dashboardError: cached.dashboardError)
        : cached;
  }
}
