import 'dart:async';

import 'package:flutter/services.dart';

import '../models/attendance.dart';
import 'attendance_controller.dart';

class NativeAttendanceBackend
    implements
        AttendanceBackend,
        AttendanceRecordBackend,
        AttendanceRecordExecutionBackend,
        AttendancePresentationBackend {
  static const channel = MethodChannel('cn.sjtu.jiaotong_course/attendance');
  bool _foreground = true;
  final StreamController<String> _events = StreamController.broadcast();
  Stream<String> get events => _events.stream;
  NativeAttendanceBackend() {
    channel.setMethodCallHandler((call) async {
      if (['timeChanged', 'openPending', 'updated'].contains(call.method)) {
        _events.add(call.method);
      }
    });
  }
  Future<Map<String, dynamic>> _map(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    final data = await channel.invokeMapMethod<String, dynamic>(method, args);
    if (data == null) {
      throw const AttendanceFailure(AttendancePhase.limited, '当前设备暂不支持此功能');
    }
    return data;
  }

  @override
  Future<AttendanceSnapshot> inspectRecords(
    AttendanceMeeting meeting, {
    bool manual = false,
  }) async {
    try {
      final data = await _map('records', {
        'courseId': meeting.canvasId,
        'name': meeting.course.name,
        'manual': manual,
      }).timeout(const Duration(seconds: 85));
      final records = <AttendanceRecord>[];
      if (data['status'] == 'ok') {
        if (data['courseId'] != meeting.canvasId || data['records'] is! List) {
          throw const FormatException();
        }
        for (final row in data['records']) {
          if (row is! Map ||
              row['key'] is! String ||
              !(row['key'] as String).startsWith('${meeting.canvasId}:') ||
              row['createdAt'] is! int ||
              row['state'] is! String) {
            throw const FormatException();
          }
          records.add(
            AttendanceRecord(
              key: row['key'],
              canvasId: meeting.canvasId,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                row['createdAt'],
                isUtc: true,
              ),
              state: row['state'],
            ),
          );
        }
      }
      return AttendanceSnapshot(
        canvasId: meeting.canvasId,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(
          data['checkedAt'] is int
              ? data['checkedAt']
              : DateTime.now().millisecondsSinceEpoch,
          isUtc: true,
        ),
        records: records,
        nextCheckDelay: data['nextCheckDelayMs'] is int
            ? Duration(
                milliseconds:
                    (data['nextCheckDelayMs'] as int).clamp(1, 300000))
            : null,
        failure: data['status'] == 'ok' ? '' : '${data['status'] ?? 'format'}',
        warning: (data['invalidRecords'] is int && data['invalidRecords'] > 0)
            ? '部分记录格式异常，未用于提醒'
            : '',
      );
    } on PlatformException catch (error) {
      return AttendanceSnapshot(
          canvasId: meeting.canvasId,
          checkedAt: DateTime.now(),
          records: [],
          failure: error.code == 'cancelled' ? 'cancelled' : 'network');
    } on TimeoutException {
      return AttendanceSnapshot(
        canvasId: meeting.canvasId,
        checkedAt: DateTime.now(),
        records: [],
        failure: 'network',
      );
    } catch (_) {
      return AttendanceSnapshot(
        canvasId: meeting.canvasId,
        checkedAt: DateTime.now(),
        records: [],
        failure: 'format',
      );
    }
  }

  @override
  Future<bool> claimRecord(
    AttendanceRecord record,
    AttendanceMeeting meeting, {
    required bool foreground,
  }) async =>
      await channel.invokeMethod<bool>('claimRecord', {
        'courseId': meeting.canvasId,
        'recordKey': record.key,
        'foreground': foreground,
      }) ??
      false;

  @override
  Future<void> setRecordForeground(bool value) async {
    _foreground = value;
    try {
      await channel.invokeMethod<void>('recordForeground', value);
    } catch (_) {
      /* Background JobScheduler remains system-controlled. */
    }
  }

  @override
  Future<void> acknowledgeRecord(AttendanceRecord record) async {
    try {
      await channel.invokeMethod<void>('ackRecord', {'recordKey': record.key});
    } catch (_) {
      /* Already-consumed reminder remains persistently deduplicated. */
    }
  }

  @override
  Future<void> notifyRecord(
    AttendanceRecord record,
    AttendanceMeeting meeting,
  ) =>
      channel.invokeMethod<void>('notifyRecord', {
        'courseId': meeting.canvasId,
        'recordKey': record.key,
        'name': meeting.course.name,
      });

  @override
  Future<List<AttendanceTask>> poll(AttendanceMeeting meeting) async {
    final data = await _map('poll', meeting.toMap());
    if (data['status'] != 'ok') {
      throw AttendanceFailure(
        data['status'] == 'login'
            ? AttendancePhase.needsLogin
            : AttendancePhase.limited,
        data['status'] == 'login' ? '请先连接当前课程的点名签到' : '无法确认当前签到，请打开点名签到检查',
      );
    }
    final tasks = <AttendanceTask>[];
    for (final raw
        in data['tasks'] is List ? data['tasks'] as List : const []) {
      if (raw is! Map || raw['id'] is! String || raw['createdAt'] is! int) {
        continue;
      }
      tasks.add(
        AttendanceTask(
          id: raw['id'],
          canvasId: meeting.canvasId,
          courseCode: '${raw['courseCode'] ?? ''}',
          state: '${raw['state'] ?? ''}',
          serverActive: raw['serverActive'] == true,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            raw['createdAt'],
            isUtc: true,
          ),
          expiresAt: raw['expiresAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(
                  raw['expiresAt'],
                  isUtc: true,
                )
              : null,
        ),
      );
    }
    return tasks;
  }

  @override
  Future<AttendanceSubmitResult> submit(
    AttendanceTask task,
    AttendanceQr qr,
  ) async {
    final data = await _map('submit', {
      'courseId': task.canvasId,
      'taskId': task.id,
      'courseCode': task.courseCode,
      'qr': qr.uri.toString(),
    });
    if (data['status'] == 'login') return AttendanceSubmitResult.needsLogin;
    return parseAttendanceResult(
      data['httpStatus'] is int ? data['httpStatus'] : 0,
      data['body'],
    );
  }

  @override
  Future<AttendanceSubmitResult> submitRecord(
    AttendanceRecord record,
    AttendanceMeeting meeting,
    AttendanceQr qr,
  ) async {
    final data = await _map('submitRecord', {
      'courseId': meeting.canvasId,
      'recordKey': record.key,
      'qr': qr.uri.toString(),
    });
    final status = data['status'];
    if (status == 'session_login' || status == 'canvas_login') {
      return AttendanceSubmitResult.needsLogin;
    }
    if (status == 'unverified_task') {
      throw const AttendanceFailure(
        AttendancePhase.limited,
        '无法确认二维码与本次签到的关联，请在学校页面核实',
      );
    }
    if (status == 'wrong_course') {
      throw const AttendanceFailure(AttendancePhase.failed, '二维码不属于当前课程，已停止提交');
    }
    if (status != 'ok') {
      throw const AttendanceFailure(
        AttendancePhase.failed,
        '签到请求未获确认，请检查网络或学校页面',
      );
    }
    return parseAttendanceResult(200, data['body']);
  }

  Future<Map<String, dynamic>> monitorStatus() => _map('monitorStatus');
  Future<void> openExactAlarmSettings() =>
      channel.invokeMethod<void>('exactAlarmSettings');

  @override
  Future<bool> verify(AttendanceTask task) async {
    final result = await _map('verify', {
      'courseId': task.canvasId,
      'taskId': task.id,
      'courseCode': task.courseCode,
    });
    if (result['status'] == 'login') {
      throw const AttendanceFailure(AttendancePhase.needsLogin, '请完成签到系统登录后再试');
    }
    return result['confirmed'] == true;
  }

  @override
  Future<void> configure(
    bool enabled,
    String account,
    List<AttendanceMeeting> meetings,
  ) async {
    await channel.invokeMethod<void>('configure', {
      'enabled': enabled,
      'account': account,
      'foreground': _foreground,
      'meetings': meetings.map((m) => m.toMap()).toList(),
    });
  }

  @override
  Future<void> cancel() async {
    try {
      await channel
          .invokeMethod<void>('cancel')
          .timeout(const Duration(seconds: 3));
    } on MissingPluginException {
      /* No native resources exist on this platform. */
    } on PlatformException {
      /* Teardown is idempotent. */
    } on TimeoutException {
      /* An already dead activity cannot keep capturing. */
    }
  }

  @override
  Future<void> notifyTask(
    AttendanceTask task,
    AttendanceMeeting meeting,
  ) async {
    await channel.invokeMethod<void>('notify', {
      'key': task.key,
      'courseName': meeting.course.name,
    });
  }

  @override
  Future<void> acknowledge(String taskKey, DateTime until) =>
      channel.invokeMethod<void>('acknowledge', {
        'key': taskKey,
        'until': until.millisecondsSinceEpoch,
      });
  Future<Map<String, dynamic>> tabs(String courseId, {bool refresh = false}) =>
      _map('tabs', {
        'courseId': courseId,
        'refresh': refresh,
      }).timeout(const Duration(seconds: 40));

  @override
  Future<void> recordDisplayed(AttendanceRecord record) =>
      channel.invokeMethod<void>('recordDisplayed', {'recordKey': record.key});
  Future<void> saveConnection(
    String canvasId,
    String courseCode,
    String token,
  ) async {
    await channel.invokeMethod<void>('connect', {
      'courseId': canvasId,
      'courseCode': courseCode,
      'token': token,
    });
  }

  Future<bool> notificationPermission() async =>
      await channel.invokeMethod<bool>('notificationPermission') ?? false;
  Future<void> openNotificationSettings() =>
      channel.invokeMethod<void>('notificationSettings');
  Future<String?> captureQr(int webViewId, Map<String, Object?> rect) =>
      channel.invokeMethod<String>('captureQr', {
        'webViewIdentifier': webViewId,
        ...rect,
      });
  Future<bool> installLtiNavigation(int id) async =>
      await channel.invokeMethod<bool>('installLtiNavigation', {
        'webViewIdentifier': id,
      }) ??
      false;
  Future<void> releaseWeb(int id) =>
      channel.invokeMethod<void>('releaseWeb', {'webViewIdentifier': id});
}
