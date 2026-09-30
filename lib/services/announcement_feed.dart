import '../models/canvas_data.dart';
import '../models/course.dart';

class AnnouncementFeedEntry {
  const AnnouncementFeedEntry({
    required this.item,
    required this.courseName,
    this.timetableCourse,
    this.canvasCourseId = '',
    this.fromDashboard = false,
  });

  final CanvasItem item;
  final String courseName;
  final Course? timetableCourse;
  final String canvasCourseId;
  final bool fromDashboard;
}

/// Combines activity-stream notices with announcements from Canvas courses
/// that are reliably linked to a timetable course. Course announcements are
/// added first, so a dashboard copy never replaces the richer course entry.
List<AnnouncementFeedEntry> buildAnnouncementFeed(
  CanvasSnapshot snapshot,
  List<Course> timetableCourses,
) {
  final byCanvasId = <String, Course>{};
  final byNormalizedName = <String, List<Course>>{};
  for (final course in timetableCourses) {
    final canvasId = course.canvasCourseId?.trim() ?? '';
    if (canvasId.isNotEmpty) byCanvasId.putIfAbsent(canvasId, () => course);
    final name = _normalized(course.name);
    if (name.isNotEmpty) (byNormalizedName[name] ??= []).add(course);
  }

  final canvasCoursesByName = <String, List<CanvasCourseData>>{};
  for (final course in snapshot.courses) {
    final name = _normalized(course.name);
    if (name.isNotEmpty) (canvasCoursesByName[name] ??= []).add(course);
  }

  Course? uniqueTimetableMatch(String name) {
    final candidates = byNormalizedName[_normalized(name)];
    if (candidates == null || candidates.isEmpty) return null;
    final identities = <String, Course>{};
    for (final course in candidates) {
      identities.putIfAbsent(
        course.courseIdentity.isNotEmpty ? course.courseIdentity : course.id,
        () => course,
      );
    }
    return identities.length == 1 ? identities.values.first : null;
  }

  final linkedTimetable = <String, Course>{};
  final linkedCanvasByName = <String, CanvasCourseData>{};
  final entries = <String, AnnouncementFeedEntry>{};
  final seenIdentities = <String>{};
  for (final canvasCourse in snapshot.courses) {
    final name = _normalized(canvasCourse.name);
    final sameNameCanvasCourses = canvasCoursesByName[name] ?? const [];
    final linkedCourse = byCanvasId[canvasCourse.id] ??
        (sameNameCanvasCourses.length == 1
            ? uniqueTimetableMatch(canvasCourse.name)
            : null);
    if (linkedCourse == null) continue;

    linkedTimetable[canvasCourse.id] = linkedCourse;
    if (sameNameCanvasCourses.length == 1) {
      linkedCanvasByName[name] = canvasCourse;
    }
    for (final item in canvasCourse.announcements) {
      final courseName = item.courseName.trim().isNotEmpty
          ? item.courseName.trim()
          : canvasCourse.name;
      final entry = AnnouncementFeedEntry(
        item: item,
        courseName: courseName,
        timetableCourse: linkedCourse,
        canvasCourseId: canvasCourse.id,
      );
      _insertDeduplicated(entries, seenIdentities, entry);
    }
  }

  for (final item in snapshot.dashboardItems) {
    final canvasByContextId =
        item.courseId.isEmpty ? null : snapshot.courseById(item.courseId);
    final byContextId =
        item.courseId.isNotEmpty ? linkedTimetable[item.courseId] : null;
    final matchedCanvas =
        canvasByContextId ?? linkedCanvasByName[_normalized(item.courseName)];
    final timetableCourse = byContextId ??
        (matchedCanvas == null ? null : linkedTimetable[matchedCanvas.id]);
    final source =
        item.courseName.trim().isEmpty ? 'Canvas 控制面板' : item.courseName.trim();
    final entry = AnnouncementFeedEntry(
      item: item,
      courseName: source,
      timetableCourse: timetableCourse,
      canvasCourseId: matchedCanvas?.id ?? item.courseId,
      fromDashboard: true,
    );
    _insertDeduplicated(entries, seenIdentities, entry);
  }

  final result = entries.values.toList();
  result.sort((a, b) {
    final aDate = DateTime.tryParse(a.item.createdAt);
    final bDate = DateTime.tryParse(b.item.createdAt);
    if (aDate != null && bDate != null) return bDate.compareTo(aDate);
    if (aDate != null) return -1;
    if (bDate != null) return 1;
    return b.item.createdAt.compareTo(a.item.createdAt);
  });
  return result;
}

void _insertDeduplicated(
  Map<String, AnnouncementFeedEntry> entries,
  Set<String> seenIdentities,
  AnnouncementFeedEntry entry,
) {
  if (entries.values.any((existing) => _sameMessage(existing, entry))) return;
  // A primary item ID is scoped by origin. Canvas activity IDs and
  // announcement IDs are different namespaces and must not collide.
  final id = entry.item.id.trim();
  final primary = id.isNotEmpty
      ? '${entry.fromDashboard ? 'activity' : 'announcement'}:$id:'
          '${_courseIdentity(entry)}:${_normalized(entry.item.title)}:'
          '${_dateBucket(entry.item.createdAt)}'
      : 'content:${_normalized(entry.courseName)}:'
          '${_normalized(entry.item.title)}:${_dateBucket(entry.item.createdAt)}:'
          '${_normalized(entry.item.messageHtml)}';
  if (seenIdentities.contains(primary)) return;
  entries[primary] = entry;
  seenIdentities.add(primary);
}

bool _sameMessage(
  AnnouncementFeedEntry first,
  AnnouncementFeedEntry second,
) {
  final firstAsset = _assetIdentity(first);
  final secondAsset = _assetIdentity(second);
  if (firstAsset != null && firstAsset == secondAsset) return true;

  final firstUrl = _urlIdentity(first);
  final secondUrl = _urlIdentity(second);
  if (firstUrl != null && secondUrl != null) return firstUrl == secondUrl;
  if (firstAsset != null && secondAsset != null) return false;

  if (first.fromDashboard != second.fromDashboard) {
    final dashboard = first.fromDashboard ? first : second;
    if (!_isAnnouncementActivity(dashboard.item)) return false;
  } else {
    final firstId = first.item.id.trim();
    final secondId = second.item.id.trim();
    final firstCourseId = _courseIdentity(first);
    final secondCourseId = _courseIdentity(second);
    final sameCourse = firstCourseId == secondCourseId;
    if (firstId.isNotEmpty && secondId.isNotEmpty) {
      if (firstId != secondId) return false;
      // Course-scoped Canvas IDs are stable announcement identities. Activity
      // stream IDs without a course context can be reused for different events,
      // so those still need the title/date check below.
      if (sameCourse && firstCourseId.isNotEmpty) return true;
    }
  }

  final firstCourse = _courseIdentity(first);
  final secondCourse = _courseIdentity(second);
  if (firstCourse.isNotEmpty &&
      secondCourse.isNotEmpty &&
      firstCourse != secondCourse) {
    return false;
  }
  final sameCourse = firstCourse.isNotEmpty && firstCourse == secondCourse ||
      _normalized(first.courseName) == _normalized(second.courseName);
  final sameTitle = _normalized(first.item.title).isNotEmpty &&
      _normalized(first.item.title) == _normalized(second.item.title);
  final sameDate = _dateBucket(first.item.createdAt).isNotEmpty &&
      _dateBucket(first.item.createdAt) == _dateBucket(second.item.createdAt);
  if (!sameCourse || !sameTitle || !sameDate) return false;

  if (first.fromDashboard != second.fromDashboard) return true;
  final firstBody = _normalized(first.item.messageHtml);
  final secondBody = _normalized(second.item.messageHtml);
  return firstBody == secondBody;
}

String _courseIdentity(AnnouncementFeedEntry entry) {
  final id = entry.canvasCourseId.isNotEmpty
      ? entry.canvasCourseId
      : entry.item.courseId;
  return id.trim();
}

String? _assetIdentity(AnnouncementFeedEntry entry) {
  final assetId = entry.item.assetId.trim();
  final courseId = _courseIdentity(entry);
  if (assetId.isEmpty || courseId.isEmpty) return null;
  return '$courseId:$assetId';
}

String? _urlIdentity(AnnouncementFeedEntry entry) {
  final item = entry.item;
  final url = Uri.tryParse(item.htmlUrl.trim());
  if (url == null) return null;
  final path = url.path.replaceFirst('/api/v1', '');
  final match = RegExp(
    r'/(?:discussion_topics|announcements)/(\d+)(?:/|$)',
    caseSensitive: false,
  ).firstMatch(path);
  if (match == null) return null;
  final courseFromPath = RegExp(r'/courses/([^/]+)', caseSensitive: false)
      .firstMatch(path)
      ?.group(1);
  final courseId = _courseIdentity(entry).isNotEmpty
      ? _courseIdentity(entry)
      : (courseFromPath ?? '');
  return '${courseId.isEmpty ? '' : '$courseId:'}${match.group(1)}';
}

bool _isAnnouncementActivity(CanvasItem item) =>
    RegExp(r'announcement|discussion.?topic|公告', caseSensitive: false)
        .hasMatch('${item.type} ${item.assetType}');

/* List<String> _identityKeys(AnnouncementFeedEntry entry) {
  final item = entry.item;
  final courseId = entry.canvasCourseId.isNotEmpty
      ? entry.canvasCourseId
      : item.courseId;
  final result = <String>[];
  final assetId = item.assetId.trim();
  if (assetId.isNotEmpty && courseId.isNotEmpty) {
    result.add('asset:$courseId:$assetId');
  }

  final url = Uri.tryParse(item.htmlUrl.trim());
  if (url != null) {
    final path = url.path.replaceFirst('/api/v1', '');
    final match = RegExp(
      r'/(?:discussion_topics|announcements)/(\d+)(?:/|$)',
      caseSensitive: false,
    ).firstMatch(path);
    if (match != null) {
      result.add('url:${courseId.isEmpty ? '' : '$courseId:'}${match.group(1)}');
    }
  }

  final isAnnouncement = !entry.fromDashboard ||
      RegExp(r'announcement|discussion.?topic|公告', caseSensitive: false)
          .hasMatch('${item.type} ${item.assetType}');
  final title = _normalized(item.title);
  final date = _dateBucket(item.createdAt);
  if (isAnnouncement && title.isNotEmpty && date.isNotEmpty) {
    result.add('course-title:$courseId:$title:$date');
  }

  // Same-source duplicate activity rows can be collapsed by their event ID;
  // this alias is deliberately origin-scoped to keep notices distinct from
  // course announcement IDs.
  if (item.id.trim().isNotEmpty) {
    result.add('${entry.fromDashboard ? 'activity' : 'announcement'}-id:${item.id.trim()}');
  }
  if (result.isEmpty) {
    result.add('content:${_normalized(entry.courseName)}:$title:$date:'
        '${_normalized(item.messageHtml)}');
  }
  return result;
} */

String _dateBucket(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value.trim();
  final utc = date.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

String _normalized(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll(RegExp(r'&(?:nbsp|amp|lt|gt|quot);'), '')
    .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');
