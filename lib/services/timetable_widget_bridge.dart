import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';

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
  ValueChanged<String>? onOpenCourse;

  void attach(AppController app) {
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
    final courses = app.courses
        .where((course) => course.hasSchedule)
        .map(
          (course) => <String, Object?>{
            'id': course.id,
            'name': course.name,
            'location': course.location,
            'weekday': course.weekday,
            'activeWeeks': course.activeWeeks,
            'startHour': course.startHour,
            'startMinute': course.startMinute,
            'endHour': course.endHour,
            'endMinute': course.endMinute,
            'widgetColor': app.courseColorValue(course),
          },
        )
        .toList(growable: false);
    final snapshot = jsonEncode(<String, Object?>{
      'schema': 1,
      'hasTimetable': courses.isNotEmpty,
      'termStart':
          '${termStart.year.toString().padLeft(4, '0')}-${termStart.month.toString().padLeft(2, '0')}-${termStart.day.toString().padLeft(2, '0')}',
      'totalWeeks': app.totalWeeks,
      'termLabel': '${termStart.year}${termStart.month >= 7 ? '秋季学期' : '春季学期'}',
      'courses': courses,
    });
    if (snapshot == _lastSnapshot || snapshot == _pendingSnapshot) return;
    _pendingSnapshot = snapshot;
    if (!_syncing) await _drainSnapshots();
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
