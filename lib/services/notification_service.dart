import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/course.dart';

enum ReminderMode { off, push, alarm }

class NotificationSyncReport {
  const NotificationSyncReport(this.failures);
  final List<String> failures;
  bool get succeeded => failures.isEmpty;
}

class NotificationService {
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {}
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    await plugin.initialize(const InitializationSettings(android: android));
  }

  Future<bool> requestPermissions(ReminderMode mode) async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final notificationAllowed = await android?.requestNotificationsPermission();
    if (notificationAllowed == false) {
      throw StateError('notification permission was denied');
    }
    if (mode != ReminderMode.alarm) return false;
    await android?.requestExactAlarmsPermission();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  Future<NotificationSyncReport> sync(
    List<Course> courses,
    ReminderMode mode, {
    DateTime? termStart,
    int totalWeeks = 18,
    int reminderMinutes = 15,
  }) async {
    final failures = <String>[];
    try {
      await plugin.cancelAll();
    } catch (error, stack) {
      failures.add('清理旧提醒失败');
      debugPrint('Notification cancelAll failed: $error\n$stack');
    }
    if (mode == ReminderMode.off) return NotificationSyncReport(failures);
    var exactAlarmAllowed = false;
    try {
      exactAlarmAllowed = await requestPermissions(mode);
    } catch (error, stack) {
      failures.add('提醒权限申请失败');
      debugPrint('Notification permission request failed: $error\n$stack');
    }
    var scheduledCount = 0;
    for (final course in courses) {
      if (!course.hasSchedule) continue;
      try {
        if (termStart == null) {
          await _scheduleWeekly(
            course,
            mode,
            reminderMinutes,
            exactAlarmAllowed,
          );
          scheduledCount++;
          continue;
        }
        for (final week in course.activeWeeks) {
          if (week < 1 || week > totalWeeks) continue;
          final scheduled = await _scheduleForWeek(
            course,
            mode,
            termStart,
            week,
            reminderMinutes,
            exactAlarmAllowed,
          );
          if (scheduled) scheduledCount++;
        }
      } catch (error, stack) {
        failures.add('“${course.name}”提醒安排失败');
        debugPrint(
            'Notification schedule failed for ${course.id}: $error\n$stack');
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
    return NotificationSyncReport(failures);
  }

  Future<void> _scheduleWeekly(
    Course course,
    ReminderMode mode,
    int reminderMinutes,
    bool exactAlarmAllowed,
  ) async {
    final now = tz.TZDateTime.now(tz.local);
    var daysUntil = (course.weekday - now.weekday) % 7;
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month,
        now.day + daysUntil, course.startHour, course.startMinute);
    scheduled = scheduled.subtract(Duration(minutes: reminderMinutes));
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 7));
    }
    final alarm = mode == ReminderMode.alarm;
    final details = AndroidNotificationDetails(
      alarm ? 'course_alarm' : 'course_push',
      alarm ? '闹钟提醒' : '推送提醒',
      icon: 'ic_notification',
      channelDescription: '交大课表上课提醒',
      importance: alarm ? Importance.max : Importance.defaultImportance,
      priority: alarm ? Priority.max : Priority.defaultPriority,
      playSound: true,
      enableVibration: true,
      ticker: '交大课表',
    );
    await plugin.zonedSchedule(
      _notificationId(course, 'weekly'),
      '$reminderMinutes 分钟后上课',
      '${course.name} · ${course.location}',
      scheduled,
      NotificationDetails(android: details),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: alarm && exactAlarmAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<bool> _scheduleForWeek(
    Course course,
    ReminderMode mode,
    DateTime termStart,
    int week,
    int reminderMinutes,
    bool exactAlarmAllowed,
  ) async {
    final alarm = mode == ReminderMode.alarm;
    final date = DateTime(termStart.year, termStart.month,
        termStart.day + (week - 1) * 7 + course.weekday - 1);
    final scheduled = tz.TZDateTime(tz.local, date.year, date.month, date.day,
            course.startHour, course.startMinute)
        .subtract(Duration(minutes: reminderMinutes));
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return false;
    final details = AndroidNotificationDetails(
      alarm ? 'course_alarm' : 'course_push',
      alarm ? '闹钟提醒' : '推送提醒',
      icon: 'ic_notification',
      channelDescription: '交大课表上课提醒',
      importance: alarm ? Importance.max : Importance.defaultImportance,
      priority: alarm ? Priority.max : Priority.defaultPriority,
      playSound: true,
      enableVibration: true,
      ticker: '交大课表',
    );
    await plugin.zonedSchedule(
      _notificationId(course, 'week-$week'),
      '$reminderMinutes 分钟后上课',
      '${course.name} · ${course.location}',
      scheduled,
      NotificationDetails(android: details),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: alarm && exactAlarmAllowed
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
}
