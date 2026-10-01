Map<String, dynamic>? _safeMap(dynamic value) {
  if (value is! Map) return null;
  try {
    return Map<String, dynamic>.from(value);
  } catch (_) {
    return null;
  }
}

List<dynamic> _safeList(dynamic value) =>
    value is List ? List<dynamic>.from(value) : const [];

String _safeText(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final result = value.toString().trim();
  return result.isEmpty ? fallback : result;
}

List<T> _safeItems<T>(
  dynamic value,
  T Function(Map<String, dynamic>) parser,
) {
  final result = <T>[];
  for (final item in _safeList(value)) {
    final map = _safeMap(item);
    if (map == null) continue;
    try {
      result.add(parser(map));
    } catch (_) {
      // A malformed Canvas row must not make the complete snapshot unusable.
    }
  }
  return result;
}

class CanvasItem {
  const CanvasItem({
    required this.id,
    required this.title,
    required this.messageHtml,
    required this.type,
    required this.courseName,
    required this.createdAt,
    required this.htmlUrl,
    this.assetId = '',
    this.courseId = '',
    this.assetType = '',
    this.contextType = '',
  });

  final String id, title, messageHtml, type, courseName, createdAt, htmlUrl;
  final String assetId, courseId, assetType, contextType;

  factory CanvasItem.fromMap(Map<String, dynamic> map) => CanvasItem(
        id: _safeText(map['id'] ?? map['asset_id']),
        title: _safeText(
          map['title'] ?? map['subject'] ?? map['message'],
          'Canvas 通知',
        ),
        messageHtml:
            _safeText(map['messageHtml'] ?? map['message'] ?? map['summary']),
        type: _safeText(map['type'] ?? map['activity_type'], '通知'),
        courseName: _safeText(
          map['courseName'] ?? map['context_name'] ?? map['course_name'],
        ),
        createdAt: _safeText(
          map['createdAt'] ??
              map['created_at'] ??
              map['posted_at'] ??
              map['updated_at'],
        ),
        htmlUrl: _safeText(map['htmlUrl'] ?? map['html_url'] ?? map['url']),
        assetId: _safeText(map['assetId'] ?? map['asset_id']),
        courseId: _safeText(
          map['courseId'] ??
              map['course_id'] ??
              (('${map['contextType'] ?? map['context_type']}').toLowerCase() ==
                      'course'
                  ? map['context_id']
                  : null),
        ),
        assetType: _safeText(map['assetType'] ?? map['asset_type']),
        contextType: _safeText(map['contextType'] ?? map['context_type']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'messageHtml': messageHtml,
        'type': type,
        'courseName': courseName,
        'createdAt': createdAt,
        'htmlUrl': htmlUrl,
        'assetId': assetId,
        'courseId': courseId,
        'assetType': assetType,
        'contextType': contextType,
      };
}

class CanvasPerson {
  const CanvasPerson({
    required this.id,
    required this.name,
    required this.role,
    this.email = '',
    this.loginId = '',
    this.avatarUrl = '',
  });

  final String id, name, role, email, loginId, avatarUrl;

  factory CanvasPerson.fromMap(Map<String, dynamic> map) {
    var role = _safeText(map['role']);
    for (final enrollment in _safeList(map['enrollments'])) {
      final value = _safeMap(enrollment);
      if (value == null) continue;
      role = _safeText(value['role'] ?? value['type'], role);
      if (role.isNotEmpty) break;
    }
    return CanvasPerson(
      id: _safeText(map['id']),
      name: _safeText(map['name'] ?? map['short_name'], '未命名成员'),
      role: role,
      email: _safeText(map['email']),
      loginId: _safeText(map['loginId'] ?? map['login_id']),
      avatarUrl: _safeText(map['avatarUrl'] ??
          map['avatar_url'] ??
          map['avatar_image_url'] ??
          (_safeMap(map['avatar'])?['url'] ?? map['avatar'])),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'role': role,
        'email': email,
        'loginId': loginId,
        'avatarUrl': avatarUrl,
      };
}

/// Stable role grouping: preserve the API order within each group.
List<CanvasPerson> canvasPeopleInRoleOrder(List<CanvasPerson> people) {
  int group(CanvasPerson person) {
    final role = person.role.toLowerCase();
    if (role.contains('teacher') || role.contains('教师')) return 0;
    if (role.contains('ta') || role.contains('助教')) return 1;
    if (role.contains('student') || role.contains('学生')) return 2;
    return 3;
  }

  return [
    for (var groupIndex = 0; groupIndex < 4; groupIndex++)
      for (final person in people)
        if (group(person) == groupIndex) person,
  ];
}

class CanvasCourseData {
  const CanvasCourseData({
    required this.id,
    required this.name,
    required this.courseCode,
    required this.syllabusHtml,
    required this.announcements,
    required this.people,
    this.sisCourseId = '',
    this.integrationId = '',
    this.peopleError = '',
    this.announcementsError = '',
    this.syllabusError = '',
  });

  final String id, name, courseCode, syllabusHtml;
  final String sisCourseId, integrationId;
  final List<CanvasItem> announcements;
  final List<CanvasPerson> people;
  final String peopleError, announcementsError, syllabusError;

  factory CanvasCourseData.fromMap(Map<String, dynamic> map) {
    final errors = _safeMap(map['errors']) ?? const <String, dynamic>{};
    final id = _safeText(map['id']);
    final name = _safeText(map['name'], '未命名 Canvas 课程');
    final parsedAnnouncements = _safeItems(
      map['announcements'],
      (item) => CanvasItem.fromMap({
        ...item,
        'courseId': item['courseId'] ?? item['course_id'] ?? id,
        'courseName': item['courseName'] ?? item['course_name'] ?? name,
        'assetId': item['assetId'] ?? item['asset_id'] ?? item['id'],
      }),
    );
    return CanvasCourseData(
      id: id,
      name: name,
      courseCode: _safeText(map['courseCode'] ?? map['course_code']),
      sisCourseId: _safeText(map['sisCourseId'] ?? map['sis_course_id']),
      integrationId: _safeText(map['integrationId'] ?? map['integration_id']),
      syllabusHtml: _safeText(map['syllabusHtml'] ?? map['syllabus_body']),
      // The API request is scoped to this course. Do not let an unexpected
      // cross-course row leak into a different course's detail page.
      announcements: parsedAnnouncements
          .where((item) => item.courseId.isEmpty || item.courseId == id)
          .toList(growable: false),
      people: _safeItems(map['people'], CanvasPerson.fromMap),
      peopleError: _safeText(errors['people'] ?? map['peopleError']),
      announcementsError:
          _safeText(errors['announcements'] ?? map['announcementsError']),
      syllabusError: _safeText(errors['syllabus'] ?? map['syllabusError']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'courseCode': courseCode,
        'sisCourseId': sisCourseId,
        'integrationId': integrationId,
        'syllabusHtml': syllabusHtml,
        'announcements': announcements.map((item) => item.toMap()).toList(),
        'people': people.map((person) => person.toMap()).toList(),
        'errors': {
          'people': peopleError,
          'announcements': announcementsError,
          'syllabus': syllabusError,
        },
      };

  CanvasCourseData withAnnouncements(List<CanvasItem> items) =>
      CanvasCourseData(
        id: id,
        name: name,
        courseCode: courseCode,
        sisCourseId: sisCourseId,
        integrationId: integrationId,
        syllabusHtml: syllabusHtml,
        syllabusError: syllabusError,
        people: people,
        peopleError: peopleError,
        announcements: items,
      );

  CanvasCourseData mergeDetails(CanvasCourseData previous) => CanvasCourseData(
        id: id,
        name: name,
        courseCode: courseCode,
        sisCourseId: sisCourseId,
        integrationId: integrationId,
        syllabusHtml:
            syllabusError.isEmpty ? syllabusHtml : previous.syllabusHtml,
        announcements:
            announcementsError.isEmpty ? announcements : previous.announcements,
        people: peopleError.isEmpty ? people : previous.people,
        syllabusError: syllabusError,
        announcementsError: announcementsError,
        peopleError: peopleError,
      );

  CanvasCourseData withCachedDetails(CanvasCourseData? previous) {
    if (previous == null) return this;
    return CanvasCourseData(
      id: id,
      name: name,
      courseCode: courseCode,
      sisCourseId: sisCourseId,
      integrationId: integrationId,
      syllabusHtml: previous.syllabusHtml,
      announcements: previous.announcements,
      people: previous.people,
      syllabusError: previous.syllabusError,
      announcementsError: previous.announcementsError,
      peopleError: previous.peopleError,
    );
  }
}

class CanvasSnapshot {
  const CanvasSnapshot({
    required this.dashboardItems,
    required this.courses,
    required this.syncedAt,
    this.dashboardError = '',
  });

  final List<CanvasItem> dashboardItems;
  final List<CanvasCourseData> courses;
  final DateTime syncedAt;
  final String dashboardError;

  factory CanvasSnapshot.empty() => CanvasSnapshot(
      dashboardItems: const [], courses: const [], syncedAt: DateTime(1970));

  factory CanvasSnapshot.fromMap(Map<String, dynamic> map) => CanvasSnapshot(
        dashboardItems: _safeItems(
          map['dashboardItems'] ?? map['dashboard_notifications'],
          CanvasItem.fromMap,
        ),
        courses: _safeItems(map['courses'], CanvasCourseData.fromMap),
        syncedAt: DateTime.tryParse(
                _safeText(map['syncedAt'] ?? map['exported_at'])) ??
            DateTime.now(),
        dashboardError: _safeText(
          map['dashboardError'] ?? map['dashboard_notifications_error'],
        ),
      );

  Map<String, dynamic> toMap() => {
        'dashboardItems': dashboardItems.map((item) => item.toMap()).toList(),
        'courses': courses.map((course) => course.toMap()).toList(),
        'syncedAt': syncedAt.toIso8601String(),
        'dashboardError': dashboardError,
      };

  CanvasCourseData? courseById(String? id) {
    if (id == null) return null;
    for (final course in courses) {
      if (course.id == id) return course;
    }
    return null;
  }

  CanvasSnapshot mergeCatalog(CanvasSnapshot catalog) => CanvasSnapshot(
        dashboardItems: dashboardItems,
        dashboardError: dashboardError,
        syncedAt: catalog.syncedAt,
        courses: [
          for (final course in catalog.courses)
            course.withCachedDetails(courseById(course.id)),
        ],
      );

  CanvasSnapshot mergeRefresh(CanvasSnapshot refreshed) => CanvasSnapshot(
        dashboardItems: refreshed.dashboardError.isEmpty
            ? refreshed.dashboardItems
            : dashboardItems,
        dashboardError: refreshed.dashboardError,
        syncedAt: refreshed.syncedAt,
        courses: [
          for (final course in refreshed.courses)
            courseById(course.id) == null
                ? course
                : course.mergeDetails(courseById(course.id)!),
        ],
      );
}

class CanvasSyncException implements Exception {
  const CanvasSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reassembles chunked JavaScript bridge messages. Legacy one-message payloads
/// remain accepted so cached/older WebViews cannot break an in-progress sync.
class CanvasSyncAccumulator {
  final Map<String, Map<String, dynamic>> _courses = {};
  List<dynamic> _dashboard = const [];
  String _dashboardError = '';
  DateTime _syncedAt = DateTime.now();
  final List<String> diagnostics = [];

  void reset() {
    _courses.clear();
    _dashboard = const [];
    _dashboardError = '';
    _syncedAt = DateTime.now();
    diagnostics.clear();
  }

  CanvasSnapshot? add(Map<String, dynamic> message) {
    if (message.containsKey('ok')) {
      if (message['ok'] == true) return CanvasSnapshot.fromMap(message);
      throw CanvasSyncException(_safeText(message['error'], 'Canvas 返回了未知错误'));
    }

    final kind = _safeText(message['kind']);
    switch (kind) {
      case 'start':
        reset();
        return null;
      case 'dashboard':
        final items = _safeList(message['items']);
        _dashboard = message['append'] == true
            ? <dynamic>[..._dashboard, ...items]
            : items;
        final dashboardError = _safeText(message['error']);
        if (dashboardError.isNotEmpty) _dashboardError = dashboardError;
        return null;
      case 'course':
        final data = _safeMap(message['data']);
        if (data == null) return null;
        final id = _safeText(data['id']);
        if (id.isEmpty) return null;
        final existing = _courses.putIfAbsent(
            id,
            () => {
                  'id': id,
                  'announcements': <dynamic>[],
                  'people': <dynamic>[],
                  'errors': <String, dynamic>{},
                });
        final announcements = existing['announcements'];
        final people = existing['people'];
        existing.addAll(data);
        existing['announcements'] = announcements;
        existing['people'] = people;
        return null;
      case 'announcements':
      case 'people':
        final id = _safeText(message['courseId']);
        if (id.isEmpty) return null;
        final course = _courses.putIfAbsent(
            id,
            () => {
                  'id': id,
                  'announcements': <dynamic>[],
                  'people': <dynamic>[],
                  'errors': <String, dynamic>{},
                });
        final target = course[kind] as List<dynamic>;
        target.addAll(_safeList(message['items']));
        return null;
      case 'syllabus':
        final id = _safeText(message['courseId']);
        if (id.isEmpty) return null;
        final course = _courses.putIfAbsent(
            id,
            () => {
                  'id': id,
                  'announcements': <dynamic>[],
                  'people': <dynamic>[],
                  'errors': <String, dynamic>{},
                });
        course['syllabusHtml'] =
            _safeText(course['syllabusHtml']) + _safeText(message['text']);
        return null;
      case 'diagnostic':
        final detail = _safeText(message['error']);
        if (detail.isNotEmpty) diagnostics.add(detail);
        return null;
      case 'catalogComplete':
        _syncedAt = DateTime.now();
        return _snapshot();
      case 'fatal':
        final stage = _safeText(message['stage'], '读取');
        final endpoint = _safeText(message['endpoint']);
        final error = _safeText(message['error'], '未知错误');
        throw CanvasSyncException(
          '$stage失败：$error${endpoint.isEmpty ? '' : '（$endpoint）'}',
        );
      case 'complete':
        _syncedAt =
            DateTime.tryParse(_safeText(message['syncedAt'])) ?? DateTime.now();
        return _snapshot();
      default:
        return null;
    }
  }

  CanvasSnapshot _snapshot() => CanvasSnapshot.fromMap({
        'dashboardItems': _dashboard,
        'dashboardError': _dashboardError,
        'courses': _courses.values.toList(),
        'syncedAt': _syncedAt.toIso8601String(),
      });
}
