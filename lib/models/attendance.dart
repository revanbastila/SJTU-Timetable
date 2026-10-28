import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:timezone/timezone.dart' as tz;

import 'course.dart';
import 'teaching_calendar.dart';

enum AttendancePhase {
  off,
  waiting,
  checking,
  pending,
  openingLive,
  waitingLive,
  scanning,
  submitting,
  succeeded,
  needsLogin,
  cancelled,
  expired,
  failed,
  limited,
  completed,
  noNew,
  history,
  unknownOpen,
  noEntry,
}

extension AttendancePhaseLabel on AttendancePhase {
  String get label => switch (this) {
        AttendancePhase.off => '已关闭',
        AttendancePhase.waiting => '等待上课',
        AttendancePhase.checking => '正在检测签到',
        AttendancePhase.pending => '发现签到，等待执行',
        AttendancePhase.openingLive => '正在打开直播',
        AttendancePhase.waitingLive => '等待直播开始',
        AttendancePhase.scanning => '正在识别二维码',
        AttendancePhase.submitting => '正在提交',
        AttendancePhase.succeeded => '签到成功',
        AttendancePhase.needsLogin => '需要重新登录',
        AttendancePhase.cancelled => '已取消',
        AttendancePhase.expired => '已过期',
        AttendancePhase.failed => '失败',
        AttendancePhase.limited => '检测暂不可用',
        AttendancePhase.completed => '最近签到已完成',
        AttendancePhase.noNew => '当前没有新签到',
        AttendancePhase.history => '仅有历史未签到记录',
        AttendancePhase.unknownOpen => '未签到，开放状态未知',
        AttendancePhase.noEntry => '课程未提供点名签到',
      };
}

class AttendanceMeeting {
  const AttendanceMeeting({
    required this.course,
    required this.start,
    required this.end,
  });
  final Course course;
  final DateTime start, end;
  String get canvasId => course.canvasCourseId ?? '';
  String get key => '$canvasId:${start.toUtc().millisecondsSinceEpoch}';
  // Expand only after consecutive lessons have been merged. Actual lesson
  // bounds and the meeting identity remain unchanged.
  DateTime get detectionStart => start.subtract(const Duration(minutes: 5));
  DateTime get detectionEnd => end.add(const Duration(minutes: 5));
  // A teacher can create the sign record before the live/detection window.
  DateTime get recordStart => start.subtract(const Duration(minutes: 30));
  bool contains(DateTime now) =>
      !now.isBefore(detectionStart) && now.isBefore(detectionEnd);
  Map<String, Object?> toMap() => {
        'key': key,
        'courseId': canvasId,
        'name': course.name,
        'start': detectionStart.toUtc().millisecondsSinceEpoch,
        'end': detectionEnd.toUtc().millisecondsSinceEpoch,
        'recordStart': recordStart.toUtc().millisecondsSinceEpoch,
      };
}

/// Uses the same effective dated courses as the timetable, including remote
/// no-class/makeup rules and the course's actual active week list. The system
/// instant is interpreted in the timetable's existing Asia/Shanghai zone,
/// so changing the phone's display zone does not shift the class itself.
class AttendanceSchedule {
  static List<AttendanceMeeting> meetings(
    DateTime instant,
    List<Course> Function(DateTime) effective, {
    int days = 1,
  }) {
    shanghaiNow(); // Initialize the existing time-zone database once.
    final zone = tz.getLocation('Asia/Shanghai');
    final day = tz.TZDateTime.from(instant.toUtc(), zone);
    final result = <AttendanceMeeting>[];
    for (var offset = -1; offset < days; offset++) {
      final date = tz.TZDateTime(zone, day.year, day.month, day.day + offset);
      final rows = effective(date)
          .where(
            (c) =>
                c.hasSchedule &&
                RegExp(r'^\d+$').hasMatch(c.canvasCourseId ?? ''),
          )
          .toList()
        ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
      for (final course in rows) {
        final start = tz.TZDateTime(
          zone,
          date.year,
          date.month,
          date.day,
          course.startHour,
          course.startMinute,
        ).toUtc();
        final end = tz.TZDateTime(
          zone,
          date.year,
          date.month,
          date.day,
          course.endHour,
          course.endMinute,
        ).toUtc();
        final previousIndex = result.lastIndexWhere(
          (m) =>
              m.canvasId == course.canvasCourseId &&
              m.course.courseIdentity == course.courseIdentity &&
              calendarDateKey(m.start) == calendarDateKey(start),
        );
        final previous = previousIndex < 0 ? null : result[previousIndex];
        final consecutive = previous != null &&
            previous.canvasId == course.canvasCourseId &&
            previous.course.courseIdentity == course.courseIdentity &&
            calendarDateKey(previous.start) == calendarDateKey(start) &&
            (start.isBefore(previous.end) ||
                start == previous.end ||
                (course.firstPeriod > 0 &&
                    previous.course.lastPeriod > 0 &&
                    course.firstPeriod == previous.course.lastPeriod + 1));
        if (consecutive) {
          result[previousIndex] = AttendanceMeeting(
            course: course,
            start: previous.start,
            end: end.isAfter(previous.end) ? end : previous.end,
          );
        } else {
          result.add(AttendanceMeeting(course: course, start: start, end: end));
        }
      }
    }
    return result;
  }
}

class AttendanceTask {
  const AttendanceTask({
    required this.id,
    required this.canvasId,
    required this.courseCode,
    required this.createdAt,
    required this.state,
    required this.serverActive,
    this.expiresAt,
  });
  final String id, canvasId, courseCode, state;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool serverActive;
  String get key => '$canvasId:$id';
  bool eligible(AttendanceMeeting meeting, DateTime now) =>
      meeting.contains(now) &&
      canvasId == meeting.canvasId &&
      id.isNotEmpty &&
      courseCode.isNotEmpty &&
      serverActive &&
      state == 'UNNORMAL' &&
      !createdAt.isBefore(meeting.recordStart) &&
      createdAt.isBefore(meeting.detectionEnd) &&
      !createdAt.isAfter(now) &&
      (expiresAt == null || now.isBefore(expiresAt!));
}

/// Sensitive QR parameters are deliberately absent from toString()/logs.
class AttendanceQr {
  AttendanceQr._(this.uri, this.courseCode, this.taskId, this.token);
  final Uri uri;
  final String courseCode, taskId, token;
  String get fingerprint =>
      sha256.convert(utf8.encode(uri.toString())).toString();
  static AttendanceQr parse(String input) {
    if (input.length > 8192) throw const FormatException('二维码内容过长');
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'mlearning.sjtu.edu.cn' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !['/lms/mobile2/forscan/', '/lms/mobile2/forscan'].contains(uri.path)) {
      throw const FormatException('不是受支持的交大签到二维码');
    }
    String required(String key) {
      final values = uri.queryParametersAll[key];
      if (values == null || values.length != 1 || values.single.isEmpty) {
        throw const FormatException('签到二维码参数不完整或重复');
      }
      return values.single;
    }

    final code = required('courseCode');
    final id = required('signHistoryId');
    final token = required('rollCallToken');
    if (required('fromType') != 'scanRollCall' ||
        !RegExp(r'^[A-Za-z0-9._~-]{1,128}$').hasMatch(code) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        !RegExp(r'^[A-Za-z0-9._~-]{1,4096}$').hasMatch(token)) {
      throw const FormatException('签到二维码参数无效');
    }
    return AttendanceQr._(uri, code, id, token);
  }

  bool matches(AttendanceTask task) =>
      taskId == task.id && courseCode == task.courseCode;
  @override
  String toString() => 'AttendanceQr(<redacted>)';
}

enum AttendanceSubmitResult { success, expired, needsLogin, rejected, unknown }

/// Current official mobile front-end accepts resultCode 200, then reads
/// body.status. HTTP 200 or a message containing "200" is never sufficient.
AttendanceSubmitResult parseAttendanceResult(int httpStatus, Object? body) {
  if (httpStatus == 401 || httpStatus == 403) {
    return AttendanceSubmitResult.needsLogin;
  }
  if (httpStatus != 200 || body is! Map) return AttendanceSubmitResult.unknown;
  final code = body['resultCode'];
  if (code == 10001 || code == '10001' || code == 10005 || code == '10005') {
    return AttendanceSubmitResult.needsLogin;
  }
  if (code != 200 && code != '200') return AttendanceSubmitResult.rejected;
  final data = body['body'];
  if (data is! Map) return AttendanceSubmitResult.unknown;
  return switch (data['status']) {
    'NORMAL' || 'EXISTED' => AttendanceSubmitResult.success,
    'EXPIRED' => AttendanceSubmitResult.expired,
    _ => AttendanceSubmitResult.unknown,
  };
}

/// Student record identity is opaque: never use it as a QR/submission task ID.
class AttendanceRecord {
  const AttendanceRecord({
    required this.key,
    required this.canvasId,
    required this.createdAt,
    required this.state,
  });
  final String key, canvasId, state;
  final DateTime createdAt;
  bool get completed => ['NORMAL', 'AMEND', 'LATE'].contains(state);
  bool get unsigned => state == 'UNNORMAL';
  String get stateLabel => switch (state) {
        'NORMAL' => '已签到',
        'AMEND' => '补签',
        'LATE' => '迟到',
        'UNNORMAL' => '未签到',
        _ => '签到状态未识别',
      };
  bool relevant(AttendanceMeeting meeting, DateTime now) =>
      canvasId == meeting.canvasId &&
      unsigned &&
      meeting.contains(now) &&
      !createdAt.isBefore(meeting.recordStart) &&
      createdAt.isBefore(meeting.detectionEnd) &&
      !createdAt.isAfter(now);
}

class AttendanceSnapshot {
  AttendanceSnapshot({
    required this.canvasId,
    required this.checkedAt,
    required List<AttendanceRecord> records,
    this.failure = '',
    this.warning = '',
    this.nextCheckDelay,
  }) : records = List.unmodifiable(
          [...records]..sort((a, b) {
              final order = b.createdAt.compareTo(a.createdAt);
              return order == 0 ? a.key.compareTo(b.key) : order;
            }),
        );
  final String canvasId, failure, warning;
  final DateTime checkedAt;
  final Duration? nextCheckDelay;
  final List<AttendanceRecord> records;
  AttendanceRecord? get latest => records.isEmpty ? null : records.first;
  bool get successful => failure.isEmpty;
  AttendancePhase get phase {
    if (failure == 'no_entry') return AttendancePhase.noEntry;
    if ([
      'canvas_login',
      'session_login',
      'connect_required',
    ].contains(failure)) {
      return AttendancePhase.needsLogin;
    }
    if (!successful) return AttendancePhase.failed;
    final row = latest;
    if (row == null) return AttendancePhase.noNew;
    if (row.completed) return AttendancePhase.completed;
    if (!row.unsigned) return AttendancePhase.unknownOpen;
    shanghaiNow();
    final zone = tz.getLocation('Asia/Shanghai');
    final date = tz.TZDateTime.from(row.createdAt, zone);
    final now = tz.TZDateTime.from(checkedAt, zone);
    return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day
        ? AttendancePhase.unknownOpen
        : AttendancePhase.history;
  }

  String get summary {
    if (!successful) {
      return switch (failure) {
        'no_entry' => '当前 Canvas 课程没有点名签到入口',
        'canvas_login' => 'Canvas 登录已失效，请重新登录 Canvas',
        'connect_required' => '请打开本课程点名签到，完成正常授权连接',
        'session_login' => '签到系统会话已失效，请重新连接本课程点名签到',
        'permission' => '当前账号无权读取该课程签到记录',
        'network' => '网络请求失败，将按退避间隔重试',
        'timeout' => '网络请求超时，将按退避间隔重试',
        'server' => '签到服务暂时异常，请稍后重试',
        'records_limit' => '记录分页超过读取上限，无法确认最新记录',
        'format' => '签到记录格式无法解析，请重新连接后重试',
        _ => '签到服务未成功返回记录，请稍后重新检查',
      };
    }
    final row = latest;
    if (row == null) return '当前没有发现新的签到';
    shanghaiNow();
    final date = tz.TZDateTime.from(
      row.createdAt,
      tz.getLocation('Asia/Shanghai'),
    );
    final label =
        '${date.month}月${date.day}日${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '最近一次签到：$label，${row.stateLabel}'
        '${row.unsigned ? (phase == AttendancePhase.history ? '；历史记录，当前无需提醒' : '；开放状态未确认，请进入页面核实') : ''}'
        '${warning.isEmpty ? '' : '；$warning'}';
  }
}
