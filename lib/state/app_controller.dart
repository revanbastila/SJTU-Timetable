import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/app_theme.dart';
import '../models/canvas_data.dart';
import '../models/course.dart';
import '../models/week_rules.dart';
import '../services/app_database.dart';
import '../services/course_matcher.dart';
import '../services/message_feed.dart';
import '../services/credential_store.dart';
import '../services/notification_service.dart';
import '../services/canvas_announcement_sync.dart';
import '../models/teaching_calendar.dart';
import '../services/teaching_calendar_repository.dart';

class SyncBundle {
  const SyncBundle(this.courses, this.canvas);
  final List<Course> courses;
  final CanvasSnapshot canvas;
}

class SyncSaveResult {
  const SyncSaveResult({required this.dataSaved, this.notificationWarning});
  final bool dataSaved;
  final String? notificationWarning;
}

typedef SyncLoader = Future<SyncBundle?> Function();

enum CanvasSyncStage { idle, connecting, matching, details, complete, failed }

class AppController extends ChangeNotifier {
  static const _verifiedProfileSource = 'wdpyjh-wdxx-v1';

  AppController(
    this.notifications, {
    AppDatabase? database,
    CredentialStore? credentialStore,
    TeachingCalendarRepository? calendarRepository,
  })  : database = database ?? AppDatabase(),
        calendarRepository = calendarRepository ?? TeachingCalendarRepository(),
        credentialStore = credentialStore ?? SecureCredentialStore();

  final NotificationService notifications;
  final TeachingCalendarRepository calendarRepository;
  TeachingCalendar teachingCalendar = const TeachingCalendar.empty();
  Timer? _calendarRefreshTimer;
  Timer? _calendarDayTimer;
  Timer? _calendarRetryTimer;
  int _calendarRetries = 0;
  bool _calendarSyncStarted = false;
  bool _disposed = false;
  final AppDatabase database;
  final CredentialStore credentialStore;
  List<Course> courses = Course.demo();
  CanvasSnapshot canvas = CanvasSnapshot.empty();
  Map<String, String> courseMappings = {};
  Map<String, int> courseColorValues = {};
  String username = '';
  String studentNumber = '';
  String studentName = '';
  String studentCollege = '';
  String _sessionUsername = '';
  String _sessionPassword = '';
  bool loggedIn = false;
  bool rememberMe = false;
  bool refreshing = false;
  CanvasSyncStage canvasSyncStage = CanvasSyncStage.idle;
  String canvasSyncMessage = '';
  int canvasSyncCompleted = 0;
  int canvasSyncTotal = 0;
  AppThemeChoice themeChoice = AppThemeChoice.sjtuBlue;
  InterfaceMode interfaceMode = InterfaceMode.system;
  int refreshMinutes = 30;
  int reminderMinutes = 15;
  ReminderMode reminderMode = ReminderMode.off;
  DateTime lastUpdated = DateTime.now();
  DateTime termStart = DateTime(2026, 9, 14);
  int totalWeeks = 18;
  int selectedWeek = 1;
  Timer? _timer;
  Timer? _termReminderTimer;
  Future<void>? _logoutCleanup;
  Future<void>? _activeRefresh;
  DateTime? _lastCanvasFullSync;
  SyncLoader? _loader;
  Completer<void>? _loaderReady;
  Completer<bool>? _catalogReady;
  int _sessionGeneration = 0;
  int get sessionGeneration => _sessionGeneration;

  Future<void> saveStudentNumberForSession(
    String account,
    String number,
    int generation,
  ) =>
      saveStudentProfileForSession(account, number, '', generation);

  Future<void> saveStudentProfileForSession(
    String account,
    String number,
    String name,
    int generation, {
    String college = '',
  }) async {
    final validNumber = RegExp(r'^\d{8,15}$').hasMatch(number);
    final validName = RegExp(r'^[\u4e00-\u9fff·]{2,12}$').hasMatch(name);
    final cleanCollege = college.trim();
    final validCollege = RegExp(r'^[\u4e00-\u9fff·（）()A-Za-z0-9\s-]{2,40}$')
        .hasMatch(cleanCollege);
    if ((!validNumber && !validName && !validCollege) ||
        generation != _sessionGeneration ||
        !loggedIn ||
        username != account) {
      return;
    }
    if (validNumber) studentNumber = number;
    if (validName) studentName = name;
    if (validCollege) studentCollege = cleanCollege;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation == _sessionGeneration && loggedIn && username == account) {
        if (validNumber) {
          await prefs.setString('studentNumber_$account', number);
        }
        if (validName) await prefs.setString('studentName_$account', name);
        if (validCollege) {
          await prefs.setString('studentCollege_$account', cleanCollege);
        }
        await prefs.setString(
            'studentProfileSource_$account', _verifiedProfileSource);
      }
    } catch (error) {
      debugPrint(
        '[portal-profile] student profile cache unavailable: '
        '${error.runtimeType}',
      );
    }
  }

  int _termUpdateGeneration = 0;
  Set<String> _readMessageIds = {};

  String get _readMessagesKey => 'readCanvasMessages_$username';
  String get _readMessagesV2Key => 'readCanvasMessagesV2_$username';
  String get _readMessagesV3Key => 'readCanvasMessagesV3_$username';

  String _messageId(String key) {
    // Keep message content out of preferences while retaining a stable ID.
    var hash = 0xcbf29ce484222325;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  int get unreadMessageCount => buildMessageFeed(
        canvas,
        courses,
      )
          .where((entry) => !_readMessageIds.contains(_messageId(entry.key)))
          .length;

  bool isMessageRead(String key) => _readMessageIds.contains(_messageId(key));

  Future<void> _migrateReadMessageKeys(SharedPreferences prefs) async {
    if (username.isEmpty || prefs.getBool(_readMessagesV3Key) == true) return;
    // Migrate only items present in the cached snapshot. Preserve both the
    // previous ID-only keys and the 1.14.11 content keys while moving to
    // course-scoped announcement IDs.
    final entries = buildMessageFeed(canvas, courses);
    final previousCount = _readMessageIds.length;
    for (final entry in entries) {
      if (_readMessageIds.contains(_messageId(entry.key)) ||
          _readMessageIds.contains(_messageId(entry.legacyV2Key)) ||
          _readMessageIds.contains(_messageId(entry.legacyKey))) {
        _readMessageIds.add(_messageId(entry.key));
      }
    }
    if (_readMessageIds.length != previousCount) {
      await prefs.setStringList(_readMessagesKey, _readMessageIds.toList());
    }
    await prefs.setBool(_readMessagesV2Key, true);
    await prefs.setBool(_readMessagesV3Key, true);
  }

  Future<void> markMessageRead(String key) async {
    if (username.isEmpty || !_readMessageIds.add(_messageId(key))) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_readMessagesKey, _readMessageIds.toList());
  }

  Future<void> markAllMessagesRead() async {
    if (username.isEmpty) return;
    final before = _readMessageIds.length;
    _readMessageIds.addAll(
      buildMessageFeed(canvas, courses).map((entry) => _messageId(entry.key)),
    );
    if (_readMessageIds.length == before) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_readMessagesKey, _readMessageIds.toList());
  }

  Future<void> markCanvasItemRead(CanvasItem item) async {
    for (final entry in buildMessageFeed(canvas, courses)) {
      final candidate = entry.canvasItem;
      if (candidate == null) continue;
      final sameCourse = item.courseId.isEmpty ||
          candidate.courseId.isEmpty ||
          item.courseId == candidate.courseId;
      final sameAsset = item.assetId.isNotEmpty &&
          candidate.assetId.isNotEmpty &&
          item.assetId == candidate.assetId &&
          sameCourse;
      final sameId =
          item.id.isNotEmpty && candidate.id == item.id && sameCourse;
      final sameUrl = item.htmlUrl.isNotEmpty &&
          candidate.htmlUrl.isNotEmpty &&
          _canvasTopicUrl(item.htmlUrl) == _canvasTopicUrl(candidate.htmlUrl) &&
          sameCourse;
      final sameContent = sameCourse &&
          candidate.title == item.title &&
          candidate.createdAt == item.createdAt &&
          candidate.messageHtml == item.messageHtml;
      if (sameAsset || sameId || sameUrl || sameContent) {
        await markMessageRead(entry.key);
        return;
      }
    }
  }

  String _canvasTopicUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw.trim();
    return '${uri.host}${uri.path}'.replaceFirst('/api/v1', '');
  }

  static const List<int> _coursePalette = [
    0xFF168C82,
    0xFF4359C7,
    0xFF0878BD,
    0xFFD97706,
    0xFF783CB5,
    0xFFC52676,
    0xFF398566,
    0xFFB74B3A,
    0xFF536D2E,
    0xFF8E4A86,
    0xFF176B87,
    0xFF9A5A18,
    0xFF5B57A6,
    0xFF00796B,
    0xFFA53D5D,
    0xFF3F6F3A,
  ];

  int get currentAcademicWeek =>
      academicWeekFor(shanghaiNow(), termStart, totalWeeks);
  int? get currentAcademicWeekInTerm =>
      academicWeekInTerm(shanghaiNow(), termStart, totalWeeks);
  String get currentTermStatus =>
      calendarCivilDate(shanghaiNow()).isBefore(termStart) ? '学期未开始' : '学期已结束';
  List<Course> coursesForWeek(int week) =>
      courses.where((course) => course.isActiveInWeek(week)).toList();
  List<Course> getEffectiveCoursesForDate(DateTime date) => teachingCalendar
      .getEffectiveCoursesForDate(date, courses, termStart, totalWeeks);
  List<Course> effectiveCoursesForWeek(int week) {
    final monday = mondayForAcademicWeek(termStart, week);
    return [
      for (var offset = 0; offset < 7; offset++)
        ...getEffectiveCoursesForDate(
                DateTime(monday.year, monday.month, monday.day + offset))
            .map((course) => course.copyWith(weekday: offset + 1))
    ];
  }

  void startTeachingCalendarSync() {
    if (_calendarSyncStarted || _disposed) return;
    _calendarSyncStarted = true;
    _logCalendarState('startup cache');
    unawaited(refreshTeachingCalendar());
    _calendarRefreshTimer = Timer.periodic(const Duration(minutes: 30),
        (_) => unawaited(refreshTeachingCalendar()));
    _scheduleCalendarMidnight();
  }

  void _scheduleCalendarMidnight() {
    _calendarDayTimer?.cancel();
    final now = shanghaiNow();
    final next = nextShanghaiMidnight(now);
    _calendarDayTimer = Timer(next.difference(now), () {
      if (_disposed) return;
      notifyListeners();
      _scheduleCalendarMidnight();
    });
  }

  Future<void> refreshTeachingCalendar() async {
    final updated = await calendarRepository.refresh(teachingCalendar);
    if (_disposed) return;
    if (!calendarRepository.lastRefreshSucceeded && _calendarRetries < 3) {
      final delay = const [
        Duration(seconds: 15),
        Duration(minutes: 1),
        Duration(minutes: 5)
      ][_calendarRetries++];
      _calendarRetryTimer?.cancel();
      _calendarRetryTimer =
          Timer(delay, () => unawaited(refreshTeachingCalendar()));
      debugPrint('[calendar] retry scheduled in ${delay.inSeconds}s');
    } else if (calendarRepository.lastRefreshSucceeded) {
      _calendarRetries = 0;
      _calendarRetryTimer?.cancel();
    }
    if (updated == null ||
        _disposed ||
        updated.fingerprint == teachingCalendar.fingerprint) {
      _logCalendarState('refresh unchanged/failed');
      return;
    }
    teachingCalendar = updated;
    notifications.calendar = updated;
    _logCalendarState('memory updated');
    // The widget listener publishes the same dated calculations as the UI.
    notifyListeners();
    await restoreReminders();
  }

  void _logCalendarState(String stage) {
    final today = shanghaiNow();
    debugPrint(
        '[calendar] $stage version=${teachingCalendar.version} updated_at=${teachingCalendar.updatedAt} rules loaded=${teachingCalendar.rules.length}');
    debugPrint(
        '[calendar] today: ${calendarDateKey(today)} timezone=Asia/Shanghai '
        'matched rule: ${teachingCalendar.ruleFor(today)?.type ?? "none"} '
        'effective courses: ${getEffectiveCoursesForDate(today).length} raw courses: ${courses.length}');
  }

  CanvasCourseData? canvasCourseFor(Course course) =>
      canvas.courseById(course.canvasCourseId);

  void _logCanvasCourseMatches(
    String stage,
    List<Course> timetableCourses,
    CanvasSnapshot snapshot,
  ) {
    final logged = <String>{};
    for (final course in timetableCourses) {
      if (!course.hasSchedule || !logged.add(course.courseIdentity)) continue;
      final canvasId = course.canvasCourseId?.trim() ?? '';
      final data = snapshot.courseById(canvasId);
      debugPrint(
        '[canvas-match] stage=$stage '
        'portalCourse="${course.name}" '
        'portalId="${course.sourceCourseId.isNotEmpty ? course.sourceCourseId : course.id}" '
        'canvasCourseId=${canvasId.isEmpty ? 'unmatched' : canvasId} '
        'canvasName="${data?.name ?? ''}" '
        'match=${data == null ? 'failed' : 'ok'} '
        'announcementCount=${data?.announcements.length ?? 0} '
        'announcementError=${data?.announcementsError.isNotEmpty ?? false}',
      );
    }
  }

  String get sessionUsername =>
      _sessionUsername.isEmpty ? username : _sessionUsername;
  String get sessionPassword => _sessionPassword;

  Future<void> awaitSessionCleanup() => _logoutCleanup ?? Future<void>.value();

  void retainSessionCredentials(String account, String password) {
    _sessionUsername = account.trim();
    _sessionPassword = password;
  }

  int courseColorValue(Course course) {
    _ensureCourseColors(courses);
    return courseColorValues[course.courseIdentity] ?? _coursePalette.first;
  }

  Future<void> bootstrap() async {
    try {
      await notifications.initialize();
    } catch (error, stack) {
      debugPrint('Notification initialization failed: $error\n$stack');
    }
    final prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username') ?? '';
    teachingCalendar = calendarRepository.readCache(prefs);
    notifications.calendar = teachingCalendar;
    if (prefs.getString('studentProfileSource_$username') ==
        _verifiedProfileSource) {
      studentNumber = prefs.getString('studentNumber_$username') ?? '';
      studentName = prefs.getString('studentName_$username') ?? '';
      studentCollege = prefs.getString('studentCollege_$username') ?? '';
    }
    _readMessageIds = prefs.getStringList(_readMessagesKey)?.toSet() ?? {};
    rememberMe = prefs.getBool('rememberMe') ?? false;
    loggedIn = rememberMe && username.isNotEmpty;
    if (!loggedIn) unawaited(CanvasAnnouncementSync.disable());
    if (rememberMe) {
      try {
        final credentials = await credentialStore.read();
        if (credentials != null &&
            (username.isEmpty || credentials.username == username)) {
          _sessionUsername = credentials.username;
          _sessionPassword = credentials.password;
          if (username.isEmpty) username = credentials.username;
        }
      } catch (error, stack) {
        debugPrint('Secure credential restore failed: $error\n$stack');
      }
    }
    refreshMinutes = prefs.getInt('refreshMinutes') ?? 30;
    reminderMinutes = (prefs.getInt('reminderMinutes') ?? 15).clamp(1, 120);
    themeChoice = AppThemeChoiceStyle.fromStorage(
      prefs.getString('themeChoice'),
    );
    interfaceMode = InterfaceModeStyle.fromStorage(
      prefs.getString('interfaceMode'),
    );
    final reminderIndex = prefs.getInt('reminderMode') ?? 0;
    reminderMode = ReminderMode
        .values[reminderIndex.clamp(0, ReminderMode.values.length - 1)];
    totalWeeks = (prefs.getInt('totalWeeks') ?? 18).clamp(1, 30);
    termStart = DateTime.tryParse(prefs.getString('termStart') ?? '') ??
        DateTime(2026, 9, 14);
    lastUpdated = DateTime.tryParse(prefs.getString('lastUpdated') ?? '') ??
        DateTime.now();
    selectedWeek = currentAcademicWeek;

    await database.initialize();
    try {
      courseMappings = await database.loadMappings();
      courseColorValues = await database.loadCourseColors();
      final storedCourses = await database.loadCourses(totalWeeks: totalWeeks);
      final storedCanvas = await database.loadCanvas();
      if (storedCourses != null) courses = storedCourses;
      if (storedCanvas != null) canvas = storedCanvas;
    } catch (_) {}

    if (courses.isEmpty) {
      final cached = prefs.getString('courses');
      if (cached != null) {
        try {
          final decoded = jsonDecode(cached);
          if (decoded is List) {
            courses = [
              for (var i = 0; i < decoded.length; i++)
                if (decoded[i] is Map)
                  Course.fromMap(
                    _migrate(
                      Map<String, dynamic>.from(decoded[i] as Map),
                      prefs.getInt('courseSchema') ?? 1,
                    ),
                    index: i,
                    totalWeeks: totalWeeks,
                  ),
            ];
            await database.replaceAll(courses, canvas, courseMappings);
          }
        } catch (_) {}
      }
    }
    if (canvas.courses.isEmpty && canvas.dashboardItems.isEmpty) {
      final cachedCanvas = prefs.getString('canvas');
      if (cachedCanvas != null) {
        try {
          final decoded = jsonDecode(cachedCanvas);
          if (decoded is Map) {
            canvas = CanvasSnapshot.fromMap(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      }
    }
    if (courseColorValues.isEmpty) {
      final cachedColors = prefs.getString('courseColors');
      if (cachedColors != null) {
        try {
          final decoded = jsonDecode(cachedColors);
          if (decoded is Map) {
            courseColorValues = {
              for (final entry in decoded.entries)
                if (int.tryParse('${entry.value}') != null)
                  '${entry.key}': int.parse('${entry.value}'),
            };
          }
        } catch (_) {}
      }
    }
    if (courses.isNotEmpty && canvas.courses.isNotEmpty) {
      final previousLinks = {
        for (final course in courses) course.id: course.canvasCourseId ?? '',
      };
      courses = CourseMatcher.apply(
        courses,
        canvas.courses,
        manualMappings: courseMappings,
      );
      final linksChanged = courses.any(
        (course) => previousLinks[course.id] != (course.canvasCourseId ?? ''),
      );
      if (linksChanged) await _persistCourses();
    }
    await _migrateReadMessageKeys(prefs);
    _ensureCourseColors(courses);
    _restartTimer();
    if (loggedIn && reminderMode != ReminderMode.off) {
      await _syncNotificationsSafely(
        courses,
        reminderMode,
        termStart: termStart,
        totalWeeks: totalWeeks,
      );
    }
    notifyListeners();
  }

  Future<void> login(
    String value,
    List<Course> loaded, {
    bool remember = false,
  }) async {
    await saveSyncedData(
      value,
      loaded.isEmpty ? Course.demo() : loaded,
      canvas,
      remember: remember,
    );
  }

  Future<SyncSaveResult> saveSyncedData(
    String value,
    List<Course> loaded,
    CanvasSnapshot canvasSnapshot, {
    bool remember = false,
    String studentNumber = '',
    String studentName = '',
  }) async {
    final normalizedUsername = value.trim();
    if (username != normalizedUsername) {
      final prefs = await SharedPreferences.getInstance();
      final verified = prefs.getString(
            'studentProfileSource_$normalizedUsername',
          ) ==
          _verifiedProfileSource;
      this.studentNumber = verified
          ? prefs.getString('studentNumber_$normalizedUsername') ?? ''
          : '';
      this.studentName = verified
          ? prefs.getString('studentName_$normalizedUsername') ?? ''
          : '';
      studentCollege = verified
          ? prefs.getString('studentCollege_$normalizedUsername') ?? ''
          : '';
      _readMessageIds = prefs
              .getStringList('readCanvasMessages_$normalizedUsername')
              ?.toSet() ??
          {};
    }
    if (!loggedIn || username != normalizedUsername) _sessionGeneration++;
    username = normalizedUsername;
    if (RegExp(r'^\d{8,15}$').hasMatch(studentNumber)) {
      this.studentNumber = studentNumber;
    }
    if (RegExp(r'^[\u4e00-\u9fff·]{2,12}$').hasMatch(studentName)) {
      this.studentName = studentName;
    }
    loggedIn = true;
    rememberMe = remember;
    canvas = canvasSnapshot;
    courses = CourseMatcher.apply(
      loaded,
      canvas.courses,
      manualMappings: courseMappings,
    );
    if (normalizedUsername.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await _migrateReadMessageKeys(prefs);
    }
    _ensureCourseColors(courses);
    lastUpdated = DateTime.now();
    _restartTimer();
    await _persist();
    try {
      if (rememberMe && _sessionPassword.isNotEmpty) {
        await credentialStore.write(username, _sessionPassword);
      } else if (!rememberMe) {
        await credentialStore.clear();
      }
    } catch (error, stack) {
      debugPrint('Secure credential update failed: $error\n$stack');
    }
    notifyListeners();
    final warning = await _syncNotificationsSafely(
      courses,
      reminderMode,
      termStart: termStart,
      totalWeeks: totalWeeks,
    );
    return SyncSaveResult(dataSaved: true, notificationWarning: warning);
  }

  void registerLoader(SyncLoader loader) {
    _loader = loader;
    final ready = _loaderReady;
    _loaderReady = null;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  void unregisterLoader(SyncLoader loader) {
    if (identical(_loader, loader)) _loader = null;
  }

  Future<bool> initializeCanvasAfterLogin() async {
    if (!loggedIn) return false;
    final hasCache = canvas.courses.isNotEmpty;
    // A recently completed snapshot is already usable. Avoid immediately
    // repeating the same network pass when the shell is recreated.
    if (hasCache &&
        _lastCanvasFullSync != null &&
        DateTime.now().difference(_lastCanvasFullSync!) <
            const Duration(minutes: 2)) {
      return true;
    }
    try {
      if (_loader == null) {
        final ready = _loaderReady ??= Completer<void>();
        await ready.future.timeout(const Duration(seconds: 8));
      }
      final catalogReady = _catalogReady = Completer<bool>();
      unawaited(refreshNow());
      if (hasCache) return true;
      return await catalogReady.future.timeout(
        const Duration(seconds: 55),
        onTimeout: () => canvas.courses.isNotEmpty,
      );
    } catch (error, stack) {
      debugPrint(
        '[canvas-init] automatic initialization failed: '
        '$error\n$stack',
      );
      return false;
    }
  }

  void updateCanvasSyncProgress(
    CanvasSyncStage stage,
    String message, {
    int completed = 0,
    int total = 0,
  }) {
    if (!loggedIn) return;
    canvasSyncStage = stage;
    canvasSyncMessage = message;
    canvasSyncCompleted = completed;
    canvasSyncTotal = total;
    notifyListeners();
  }

  Future<void> applyCanvasCatalog(CanvasSnapshot catalog) async {
    if (!loggedIn) return;
    if (catalog.courses.isEmpty) {
      _logCanvasCourseMatches('catalog-empty', courses, catalog);
      return;
    }
    final generation = _sessionGeneration;
    final mergedCanvas = canvas.mergeCatalog(catalog);
    final matchedCourses = CourseMatcher.apply(
      courses,
      mergedCanvas.courses,
      manualMappings: courseMappings,
    );
    if (generation != _sessionGeneration || !loggedIn) return;
    canvas = mergedCanvas;
    courses = matchedCourses;
    _logCanvasCourseMatches('catalog', courses, mergedCanvas);
    _ensureCourseColors(courses);
    canvasSyncStage = CanvasSyncStage.details;
    canvasSyncMessage = '正在同步课程内容';
    await _persist();
    if (generation != _sessionGeneration || !loggedIn) return;
    final ready = _catalogReady;
    if (ready != null && !ready.isCompleted) ready.complete(true);
    notifyListeners();
  }

  Future<void> applyAnnouncementUpdates(
      Map<String, dynamic> data, int generation) async {
    if (generation != _sessionGeneration || !loggedIn) return;
    final updated = CanvasAnnouncementSync.merge(canvas, data);
    if (identical(updated, canvas)) return;
    canvas = updated;
    notifyListeners();
    try {
      await _persist();
    } catch (error) {
      debugPrint(
          '[canvas-announcements] cache save failed: ${error.runtimeType}');
    }
  }

  Future<void> refreshNow() {
    if (!loggedIn || _loader == null) return Future<void>.value();
    final active = _activeRefresh;
    if (active != null) return active;
    final future = _runRefreshNow();
    _activeRefresh = future;
    return future.whenComplete(() {
      if (identical(_activeRefresh, future)) _activeRefresh = null;
    });
  }

  Future<void> _runRefreshNow() async {
    final generation = _sessionGeneration;
    final loader = _loader!;
    refreshing = true;
    notifyListeners();
    try {
      final bundle = await loader();
      if (generation != _sessionGeneration || !loggedIn) return;
      if (bundle != null && bundle.courses.isNotEmpty) {
        courses = CourseMatcher.apply(
          bundle.courses,
          bundle.canvas.courses,
          manualMappings: courseMappings,
        );
        _ensureCourseColors(courses);
        canvas = canvas.mergeRefresh(bundle.canvas);
        _logCanvasCourseMatches('details', courses, canvas);
        debugPrint(
          '[canvas-messages] total='
          '${buildMessageFeed(canvas, courses).length} '
          'unread=$unreadMessageCount',
        );
        lastUpdated = DateTime.now();
        await _persist();
        await _syncNotificationsSafely(
          courses,
          reminderMode,
          termStart: termStart,
          totalWeeks: totalWeeks,
        );
        canvasSyncStage = CanvasSyncStage.complete;
        canvasSyncMessage = 'Canvas 同步完成';
        _lastCanvasFullSync = DateTime.now();
      } else {
        debugPrint('[canvas-sync] no complete Canvas snapshot was returned');
        canvasSyncStage = CanvasSyncStage.failed;
        canvasSyncMessage = 'Canvas 暂未完成同步';
      }
    } catch (error, stack) {
      debugPrint('[canvas-sync] refresh failed: $error\n$stack');
    } finally {
      if (generation == _sessionGeneration) {
        refreshing = false;
        final ready = _catalogReady;
        if (ready != null && !ready.isCompleted) {
          ready.complete(canvas.courses.isNotEmpty);
        }
        _catalogReady = null;
        notifyListeners();
      }
    }
  }

  Future<void> mapCourseToCanvas(Course course, String? canvasCourseId) async {
    if (canvasCourseId == null) {
      courseMappings.remove(course.courseIdentity);
    } else {
      courseMappings[course.courseIdentity] = canvasCourseId;
      await database.saveMapping(course.courseIdentity, canvasCourseId);
    }
    courses = [
      for (final item in courses)
        if (item.courseIdentity == course.courseIdentity)
          item.copyWith(
            canvasCourseId: canvasCourseId,
            clearCanvasCourse: canvasCourseId == null,
          )
        else
          item,
    ];
    await _persistCourses();
    notifyListeners();
  }

  void selectWeek(int value) {
    selectedWeek = value.clamp(1, totalWeeks);
    notifyListeners();
  }

  void selectWeekForToday({DateTime? now}) {
    final value = academicWeekFor(now ?? shanghaiNow(), termStart, totalWeeks);
    if (selectedWeek == value) return;
    selectedWeek = value;
    notifyListeners();
  }

  Future<void> setTerm(DateTime firstMonday, int weeks) async {
    final generation = ++_termUpdateGeneration;
    termStart = DateTime(firstMonday.year, firstMonday.month, firstMonday.day);
    totalWeeks = weeks.clamp(1, 30);
    selectedWeek = currentAcademicWeek;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (generation != _termUpdateGeneration) return;
    await prefs.setString('termStart', termStart.toIso8601String());
    await prefs.setInt('totalWeeks', totalWeeks);
    if (generation != _termUpdateGeneration ||
        reminderMode == ReminderMode.off) {
      return;
    }
    _termReminderTimer?.cancel();
    _termReminderTimer = Timer(const Duration(milliseconds: 250), () {
      if (generation != _termUpdateGeneration || !loggedIn) return;
      unawaited(
        _syncNotificationsSafely(
          courses,
          reminderMode,
          termStart: termStart,
          totalWeeks: totalWeeks,
        ),
      );
    });
  }

  Future<void> setRefreshMinutes(int value) async {
    refreshMinutes = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('refreshMinutes', value);
    _restartTimer();
    notifyListeners();
  }

  Future<void> setThemeChoice(AppThemeChoice value) async {
    if (themeChoice == value) return;
    themeChoice = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeChoice', value.storageKey);
  }

  Future<void> setInterfaceMode(InterfaceMode value) async {
    if (interfaceMode == value) return;
    interfaceMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('interfaceMode', value.storageKey);
  }

  Future<String?> setReminderMode(ReminderMode mode) async {
    if (mode != ReminderMode.off) {
      try {
        await notifications.requestPermissions(mode);
      } catch (_) {
        return '请在系统设置中允许交大课表发送通知后重试';
      }
    }
    _termReminderTimer?.cancel();
    reminderMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminderMode', mode.index);
    final warning = await _syncNotificationsSafely(
      courses,
      reminderMode,
      termStart: termStart,
      totalWeeks: totalWeeks,
    );
    notifyListeners();
    return warning;
  }

  Future<void> restoreReminders() async {
    if (!loggedIn || reminderMode == ReminderMode.off) return;
    await _syncNotificationsSafely(courses, reminderMode,
        termStart: termStart, totalWeeks: totalWeeks);
  }

  Future<void> setReminderMinutes(int value) async {
    reminderMinutes = value.clamp(1, 120);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminderMinutes', reminderMinutes);
    if (reminderMode != ReminderMode.off) {
      await _syncNotificationsSafely(
        courses,
        reminderMode,
        termStart: termStart,
        totalWeeks: totalWeeks,
      );
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(minutes: refreshMinutes),
      (_) => refreshNow(),
    );
  }

  Future<void> logout() {
    unawaited(CanvasAnnouncementSync.disable());
    final signedOutUsername = username;
    _sessionGeneration++;
    _timer?.cancel();
    _termReminderTimer?.cancel();
    loggedIn = false;
    rememberMe = false;
    refreshing = false;
    canvasSyncStage = CanvasSyncStage.idle;
    canvasSyncMessage = '';
    canvasSyncCompleted = 0;
    canvasSyncTotal = 0;
    username = '';
    studentNumber = '';
    studentName = '';
    studentCollege = '';
    _readMessageIds = {};
    _sessionUsername = '';
    _sessionPassword = '';
    _loader = null;
    _activeRefresh = null;
    _lastCanvasFullSync = null;
    final loaderReady = _loaderReady;
    _loaderReady = null;
    if (loaderReady != null && !loaderReady.isCompleted) loaderReady.complete();
    final catalogReady = _catalogReady;
    _catalogReady = null;
    if (catalogReady != null && !catalogReady.isCompleted) {
      catalogReady.complete(false);
    }
    courses = [];
    canvas = CanvasSnapshot.empty();
    courseMappings = {};
    courseColorValues = {};
    selectedWeek = currentAcademicWeek;
    notifyListeners();

    final cleanup = _completeLogoutCleanup(signedOutUsername);
    _logoutCleanup = cleanup;
    return cleanup.whenComplete(() {
      if (identical(_logoutCleanup, cleanup)) _logoutCleanup = null;
    });
  }

  Future<void> _completeLogoutCleanup(String signedOutUsername) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rememberMe', false);
      await prefs.remove('username');
      await prefs.remove('studentNumber_$signedOutUsername');
      await prefs.remove('studentName_$signedOutUsername');
      await prefs.remove('studentCollege_$signedOutUsername');
      await prefs.remove('studentProfileSource_$signedOutUsername');
      await prefs.remove('courses');
      await prefs.remove('canvas');
      await prefs.remove('courseColors');
      await prefs.remove('lastUpdated');
    } catch (_) {}
    try {
      await database.clear();
    } catch (_) {}
    try {
      await credentialStore.clear();
    } catch (error, stack) {
      debugPrint('Secure credential cleanup failed: $error\n$stack');
    }
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
    try {
      final cleaner = WebViewController();
      await cleaner.clearCache();
      await cleaner.clearLocalStorage();
    } catch (_) {}
    await _syncNotificationsSafely(
      [],
      ReminderMode.off,
      termStart: termStart,
      totalWeeks: totalWeeks,
    );
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rememberMe', rememberMe);
    await prefs.setInt('courseSchema', 5);
    await prefs.setString('username', username);
    if (studentNumber.isNotEmpty) {
      await prefs.setString('studentNumber_$username', studentNumber);
    }
    if (studentName.isNotEmpty) {
      await prefs.setString('studentName_$username', studentName);
    }
    if (studentCollege.isNotEmpty) {
      await prefs.setString('studentCollege_$username', studentCollege);
    }
    await prefs.setString('lastUpdated', lastUpdated.toIso8601String());
    await prefs.setString(
      'courses',
      jsonEncode(courses.map((course) => course.toMap()).toList()),
    );
    await prefs.setString('canvas', jsonEncode(canvas.toMap()));
    await prefs.setString('courseColors', jsonEncode(courseColorValues));
    await database.replaceAll(courses, canvas, courseMappings);
    await database.saveCourseColors(courseColorValues);
  }

  Future<void> _persistCourses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'courses',
      jsonEncode(courses.map((course) => course.toMap()).toList()),
    );
    await prefs.setString('courseColors', jsonEncode(courseColorValues));
    await database.saveCourses(courses);
    await database.saveCourseColors(courseColorValues);
  }

  Future<String?> _syncNotificationsSafely(
    List<Course> values,
    ReminderMode mode, {
    required DateTime termStart,
    required int totalWeeks,
  }) async {
    try {
      notifications.calendar = teachingCalendar;
      final report = await notifications.sync(
        values,
        mode,
        termStart: termStart,
        totalWeeks: totalWeeks,
        reminderMinutes: reminderMinutes,
      );
      if (!report.succeeded) {
        debugPrint(
          'Notification refresh warnings: ${report.failures.join('; ')}',
        );
        return report.failures.join('；');
      }
    } catch (error, stack) {
      debugPrint('Notification refresh failed: $error\n$stack');
      return '课程提醒更新失败';
    }
    return null;
  }

  void _ensureCourseColors(List<Course> values) {
    final identities = <String>[];
    for (final course in values) {
      if (course.courseIdentity.isNotEmpty &&
          !identities.contains(course.courseIdentity)) {
        identities.add(course.courseIdentity);
      }
    }
    final used = <int>{};
    var ordinal = 0;
    for (final identity in identities) {
      final saved = courseColorValues[identity];
      if (saved != null && used.add(saved)) continue;
      int candidate;
      do {
        candidate = _generatedCourseColor(ordinal++);
      } while (used.contains(candidate));
      courseColorValues[identity] = candidate;
      used.add(candidate);
    }
  }

  static int _generatedCourseColor(int index) {
    if (index < _coursePalette.length) return _coursePalette[index];
    final hue = (index * 137.507764).remainder(360);
    return HSVColor.fromAHSV(1, hue, 0.68, 0.66).toColor().toARGB32();
  }

  static Map<String, dynamic> _migrate(Map<String, dynamic> map, int version) {
    if (version >= 2) return map;
    return Map<String, dynamic>.from(map)
      ..remove('weekday')
      ..remove('startHour')
      ..remove('startMinute')
      ..remove('endHour')
      ..remove('endMinute');
  }

  @override
  void dispose() {
    _disposed = true;
    _calendarRefreshTimer?.cancel();
    _calendarDayTimer?.cancel();
    _calendarRetryTimer?.cancel();
    _timer?.cancel();
    _termReminderTimer?.cancel();
    super.dispose();
  }
}
