import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/course.dart';
import '../models/teaching_calendar.dart';

enum ReminderMode { off, push, alarm }

class NotificationSyncReport {
  const NotificationSyncReport(this.failures);
  final List<String> failures;
  bool get succeeded => failures.isEmpty;
}

class NotificationService {
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  Future<void> _syncTail = Future<void>.value();
  TeachingCalendar calendar = const TeachingCalendar.empty();

  Future<void> initialize() =>
      _initialization ??= _initialize().catchError((Object error) {
        _initialization = null;
        throw error;
      });

  Future<void> _initialize() async {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {}
    const android = AndroidInitializationSettings('ic_notification');
    await plugin.initialize(const InitializationSettings(android: android));
  }

  Future<bool> requestPermissions(ReminderMode mode) async {
    await initialize();
    if (mode == ReminderMode.off) return false;
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final notificationAllowed = await android?.requestNotificationsPermission();
    if (notificationAllowed == false) {
      throw StateError('请在系统设置中允许交大课表发送通知');
    }
    if (await android?.canScheduleExactNotifications() == false) {
      await android?.requestExactAlarmsPermission();
    }
    return await android?.canScheduleExactNotifications() ?? true;
  }

  Future<NotificationSyncReport> sync(
    List<Course> courses,
    ReminderMode mode, {
    DateTime? termStart,
    int totalWeeks = 18,
    int reminderMinutes = 15,
  }) {
    // Serialize snapshots: a slow earlier refresh must not cancel a newer one.
    final snapshot = List<Course>.of(courses);
    final calendarSnapshot = calendar;
    final now = DateTime.now();
    final firstMonday =
        termStart ?? DateTime(now.year, now.month, now.day - now.weekday + 1);
    final result = _syncTail.then((_) => _sync(snapshot, mode,
        effectiveCalendar: calendarSnapshot,
        termStart: firstMonday,
        totalWeeks: totalWeeks,
        reminderMinutes: reminderMinutes));
    _syncTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<NotificationSyncReport> _sync(
    List<Course> courses,
    ReminderMode mode, {
    required DateTime termStart,
    required int totalWeeks,
    required int reminderMinutes,
    required TeachingCalendar effectiveCalendar,
  }) async {
    await initialize();
    final failures = <String>[];
    if (mode == ReminderMode.off) {
      await plugin.cancelAll();
      return NotificationSyncReport(failures);
    }
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (await android?.areNotificationsEnabled() == false) {
      return const NotificationSyncReport(['请在系统设置中允许交大课表发送通知']);
    }
    final exactAlarmAllowed =
        await android?.canScheduleExactNotifications() ?? true;
    final old = await plugin.pendingNotificationRequests();
    final retained = <int>{};
    var scheduledCount = 0;
    final desired = <int, ({Course course, DateTime date})>{};
    final now = tz.TZDateTime.now(tz.local);
    final dates = <String, DateTime>{
      for (var offset = 0; offset < totalWeeks * 7; offset++)
        calendarDateKey(DateTime(
                termStart.year, termStart.month, termStart.day + offset)):
            DateTime(termStart.year, termStart.month, termStart.day + offset),
      for (final rule in effectiveCalendar.rules.values)
        calendarDateKey(rule.date): rule.date,
    };
    for (final date in dates.values) {
      for (final course in effectiveCalendar.getEffectiveCoursesForDate(
          date, courses, termStart, totalWeeks)) {
        final at = tz.TZDateTime(tz.local, date.year, date.month, date.day,
                course.startHour, course.startMinute)
            .subtract(Duration(minutes: reminderMinutes));
        if (!at.isAfter(now)) continue;
        final id = _notificationId(course, calendarDateKey(date));
        desired[id] = (course: course, date: date);
      }
    }
    retained.addAll(desired.keys);
    // Cancel invalid dates before any new schedule. A failed new schedule
    // must never preserve an old holiday/no-class alarm.
    for (final entry in old) {
      if (!retained.contains(entry.id)) await plugin.cancel(entry.id);
    }
    for (final entry in desired.entries) {
      try {
        if (await _scheduleForDate(entry.value.course, mode, entry.value.date,
            entry.key, reminderMinutes, exactAlarmAllowed)) {
          scheduledCount++;
        }
      } catch (error) {
        failures.add('“${entry.value.course.name}”提醒安排失败');
        debugPrint('[course-reminder] schedule failed: ${error.runtimeType}');
      }
    }
    if (scheduledCount > 0) {
      try {
        final pending = await plugin.pendingNotificationRequests();
        if (pending.isEmpty) failures.add('系统未保存课程提醒');
      } catch (error, stack) {
        debugPrint('Notification verification failed: $error\n$stack');
      }
    }
    if (!exactAlarmAllowed) {
      failures.add('请允许“闹钟和提醒”权限，否则课程提醒可能延迟');
    }
    debugPrint(
        '[course-reminder] scheduled=$scheduledCount exact=$exactAlarmAllowed mode=${mode.name}');
    return NotificationSyncReport(failures);
  }

  Future<bool> _scheduleForDate(
    Course course,
    ReminderMode mode,
    DateTime date,
    int id,
    int reminderMinutes,
    bool exactAlarmAllowed,
  ) async {
    final scheduled = tz.TZDateTime(tz.local, date.year, date.month, date.day,
            course.startHour, course.startMinute)
        .subtract(Duration(minutes: reminderMinutes));
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return false;
    final details = reminderDetails(mode);
    await plugin.zonedSchedule(
      id,
      '$reminderMinutes 分钟后上课',
      '${course.name} · ${course.location}',
      scheduled,
      NotificationDetails(android: details),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: exactAlarmAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
    return true;
  }

  int _notificationId(Course course, String occurrence) {
    final value = '${course.courseIdentity}|${course.weekday}|'
        '${course.startMinutes}|$occurrence';
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }

  // Channel properties are immutable on Android. New IDs repair the old
  // ordinary-sound alarm channel without changing users' other channels.
  @visibleForTesting
  AndroidNotificationDetails reminderDetails(ReminderMode mode) {
    final alarm = mode == ReminderMode.alarm;
    return AndroidNotificationDetails(
      alarm ? 'course_alarm_v2' : 'course_push_v2',
      alarm ? '闹钟提醒' : '推送提醒',
      icon: 'ic_notification',
      channelDescription: '交大课表上课提醒',
      importance: alarm ? Importance.max : Importance.high,
      priority: alarm ? Priority.max : Priority.high,
      category: alarm
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      sound: alarm
          ? const UriAndroidNotificationSound(
              'content://settings/system/alarm_alert')
          : null,
      audioAttributesUsage: alarm
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
      additionalFlags: alarm ? Int32List.fromList([4]) : null,
      playSound: true,
      enableVibration: true,
      ticker: '交大课表',
    );
  }

  @visibleForTesting
  Future<void> scheduleProbe(ReminderMode mode, DateTime at, int id) async {
    await initialize();
    final exact = await requestPermissions(mode);
    await plugin.zonedSchedule(
        id,
        '上课提醒测试 · ${mode.name}',
        '短时间提醒验证',
        tz.TZDateTime.from(at, tz.local),
        NotificationDetails(android: reminderDetails(mode)),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime);
  }
}
