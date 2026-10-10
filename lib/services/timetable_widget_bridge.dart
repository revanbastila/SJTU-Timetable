import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';
import '../models/course.dart';
import '../models/teaching_calendar.dart';

/// Sends a privacy-minimal timetable snapshot to the native Android widget.
/// The snapshot contains timetable fields only; credentials and web sessions
/// are never copied into widget storage.
class TimetableWidgetBridge {
  static const _channel = MethodChannel('cn.sjtu.jiaotong_course/widget');

  AppController? _app;
  Timer? _debounce;
  String? _lastSnapshot;
  String? _pendingSnapshot;
  bool _syncing = false;
  // Cache only calculation/encoding; native delivery still retries after a
  // failed channel call. Read flags and sync progress do not change a schedule.
  (List<Course>, TeachingCalendar, DateTime, int, TeachingSemester?)? _inputs;
  Map<String, int> _colors = const {};
  String? _calculatedSnapshot;
  ValueChanged<String>? onOpenCourse;

  void attach(AppController app) {
    detach();
    _app = app;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openCourse' && call.arguments is String) {
        onOpenCourse?.call(call.arguments as String);
      }
    });
    app.addListener(_onAppChanged);
    _onAppChanged();
  }

  void detach() {
    _debounce?.cancel();
    _app?.removeListener(_onAppChanged);
    _app = null;
    _pendingSnapshot = null;
    _inputs = null;
    _calculatedSnapshot = null;
    _lastSnapshot = null;
  }

  void _onAppChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(syncNow());
    });
  }

  Future<void> syncNow() async {
    final app = _app;
    if (app == null) return;
    final termStart = app.termStart;
    final inputs = (
      app.courses,
      app.teachingCalendar,
      termStart,
      app.totalWeeks,
      app.currentSemester
    );
    final snapshot =
        inputs == _inputs && mapEquals(_colors, app.courseColorValues)
            ? _calculatedSnapshot!
            : _calculateSnapshot(app, termStart);
    _inputs = inputs;
    _colors = Map.of(app.courseColorValues);
    _calculatedSnapshot = snapshot;
    if (snapshot == _lastSnapshot || snapshot == _pendingSnapshot) return;
    _pendingSnapshot = snapshot;
    if (!_syncing) await _drainSnapshots();
  }

  String _calculateSnapshot(AppController app, DateTime termStart) {
    Map<String, Object?> serialize(Course course) => <String, Object?>{
          'id': course.id,
          'name': course.name,
          'location': course.location,
          'teacher': course.teacher,
          'startHour': course.startHour,
          'startMinute': course.startMinute,
          'endHour': course.endHour,
          'endMinute': course.endMinute,
          'widgetColor': app.courseColorValue(course),
        };
    final courses = <Map<String, Object?>>[];
    final refs = <(String, String, String, String, String, int, int), int>{};
    int courseRef(Course course) => refs.putIfAbsent((
          course.id,
          course.courseIdentity,
          course.name,
          course.teacher,
          course.location,
          course.startMinutes,
          course.endMinutes
        ), () {
          courses.add(serialize(course));
          return courses.length - 1;
        });
    for (final course in app.courses.where((course) => course.hasSchedule)) {
      courseRef(course);
    }
    final dates = <String, DateTime>{
      for (final date
          in app.teachingCalendar.datesForTerm(termStart, app.totalWeeks))
        calendarDateKey(date): date,
      for (final rule in app.teachingCalendar.rules.values)
        calendarDateKey(rule.date): rule.date,
    };
    // Store dated results for the complete term, so native midnight/boot
    // updates do not need Flutter or a second holiday interpreter.
    final effectiveDays = <String, Object?>{
      for (final entry in dates.entries)
        entry.key: {
          'academicWeek': app.teachingCalendar
              .weekForDate(entry.value, termStart, app.totalWeeks),
          'courseRefs': app
              .getEffectiveCoursesForDate(entry.value)
              .map(courseRef)
              .toList(),
          'emptyMessage':
              app.teachingCalendar.ruleFor(entry.value)?.emptyMessage,
        },
    };
    final snapshot = jsonEncode(<String, Object?>{
      // Course metadata crosses the channel once; dates refer to that catalog.
      'schema': 3,
      'calendarVersion': app.teachingCalendar.version,
      'effectiveDays': effectiveDays,
      'hasTimetable': courses.isNotEmpty,
      'termLabel': app.currentSemester?.name ??
          '${termStart.year}${termStart.month >= 7 ? '秋季学期' : '春季学期'}',
      'courses': courses,
    });
    final today = calendarDateKey(shanghaiNow());
    debugPrint('[calendar] widget snapshot: today=$today '
        'effective courses=${app.getEffectiveCoursesForDate(shanghaiNow()).length} '
        'version=${app.teachingCalendar.version}');
    return snapshot;
  }

  Future<void> _drainSnapshots() async {
    _syncing = true;
    try {
      while (_pendingSnapshot != null) {
        final snapshot = _pendingSnapshot!;
        _pendingSnapshot = null;
        try {
          await _channel.invokeMethod<void>(
            'updateSnapshot',
            <String, Object?>{'snapshot': snapshot},
          );
          _lastSnapshot = snapshot;
        } on MissingPluginException {
          // Android-only; leave the successful snapshot unset so a later
          // attach/update can retry when the platform channel is available.
        } catch (error) {
          debugPrint('Timetable widget update failed: ${error.runtimeType}');
        }
      }
    } finally {
      _syncing = false;
      // A state change may have arrived at the edge of the previous drain.
      if (_pendingSnapshot != null) unawaited(_drainSnapshots());
    }
  }

  Future<void> consumePendingCourse() async {
    try {
      final id = await _channel.invokeMethod<String>('consumePendingCourseId');
      if (id != null && id.isNotEmpty) onOpenCourse?.call(id);
    } on MissingPluginException {
      // Not available on other platforms.
    } catch (error) {
      debugPrint(
          'Timetable widget launch handoff failed: ${error.runtimeType}');
    }
  }
}
