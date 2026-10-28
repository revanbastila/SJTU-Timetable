import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';
import 'attendance_records_test.dart' show RecordBackend;
import 'attendance_record_execution_test.dart' show ExecutionRecords;
import 'attendance_test.dart' show fixtureCourse;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final meeting = AttendanceMeeting(
    course: fixtureCourse(start: 600, end: 705),
    start: DateTime.utc(2026, 10, 28, 2), // Shanghai 10:00
    end: DateTime.utc(2026, 10, 28, 3, 45),
  );
  AttendanceRecord row(DateTime created,
          {String state = 'UNNORMAL', String id = '91'}) =>
      AttendanceRecord(
          key: '$id:early', canvasId: id, createdAt: created, state: state);
  final early = row(DateTime.utc(2026, 10, 28, 1, 41));
  Future<AttendanceController> setup(RecordBackend b) async {
    final c = AttendanceController(backend: b, clock: () => b.now);
    addTearDown(c.dispose);
    await c.restore();
    await c.updateSchedule('fixture', [meeting]);
    await c.setEnabled(true);
    return c;
  }

  test('creation lookback is independent of the live polling window', () {
    final now = meeting.detectionStart;
    expect(early.relevant(meeting, now), true);
    expect(early.relevant(meeting, now.subtract(const Duration(seconds: 1))),
        false);
    expect(early.relevant(meeting, meeting.detectionEnd), false);
    expect(row(meeting.recordStart).relevant(meeting, now), true);
    expect(
        row(meeting.recordStart.subtract(const Duration(seconds: 1)))
            .relevant(meeting, now),
        false);
    expect(
        row(now.add(const Duration(seconds: 1))).relevant(meeting, now), false);
    expect(row(early.createdAt, id: '92').relevant(meeting, now), false);
    expect(row(early.createdAt, state: 'NORMAL').relevant(meeting, now), false);
    expect(
        row(early.createdAt.subtract(const Duration(days: 1)))
            .relevant(meeting, now),
        false);
    expect(meeting.toMap()['recordStart'],
        DateTime.utc(2026, 10, 28, 1, 30).millisecondsSinceEpoch);
  });

  testWidgets('09:41 record first prompts at 09:55 and expires at 11:50',
      (t) async {
    final b = ExecutionRecords()
      ..now = DateTime.utc(2026, 10, 28, 1, 54, 59)
      ..rows = [early];
    final c = await setup(b);
    await c.inspectManually(meeting);
    expect(c.pendingRecord, isNull);
    expect(c.recordStatus(meeting), contains('尚未到课程检测时间'));
    b.now = meeting.detectionStart;
    await t.pump(const Duration(seconds: 1));
    expect(c.pendingRecord?.key, early.key);
    await c.recordDisplayed(early.key);
    expect(await c.authorizeExecution(), true);
    c.report(AttendancePhase.waitingLive, '直播尚未开始', operation: c.operation);
    b.now = b.now.add(const Duration(minutes: 3));
    await t.pump(const Duration(minutes: 3));
    expect(c.executing, true);
    expect(c.phase, AttendancePhase.waitingLive);
    expect(b.attempts, 0);
    b.now = meeting.detectionEnd;
    await c.check();
    expect(c.executing, false);
    expect(c.pendingRecord, isNull);
    await c.setEnabled(false);
  });

  testWidgets(
      'manual and automatic reads promote one reminder; explicit retry bypasses display dedup',
      (t) async {
    final b = ExecutionRecords()..now = meeting.start;
    final c = await setup(b);
    await t.pump();
    b.rows = [early];
    final gate = Completer<AttendanceSnapshot>();
    b.gate = gate;
    final manual = c.inspectManually(meeting);
    final auto = c.check();
    gate.complete(
        AttendanceSnapshot(canvasId: '91', checkedAt: b.now, records: [early]));
    await Future.wait([manual, auto]);
    expect(c.pendingRecord?.key, early.key);
    expect(b.claimed, {early.key});
    await c.recordDisplayed(early.key);
    c.dismissRecord();
    await c.inspectManually(meeting);
    expect(c.pendingRecord, isNull);
    expect(c.executableRecord(meeting)?.key, early.key);
    expect(await c.retryExecution(early, meeting), true);
    expect(await c.retryExecution(early, meeting), false);
    c.scanning(operation: c.operation);
    c.acceptQr(
        'https://mlearning.sjtu.edu.cn/lms/mobile2/forscan/?courseCode=course&signHistoryId=task&rollCallToken=fresh&fromType=scanRollCall',
        operation: c.operation);
    await t.pump();
    expect(b.attempts, 1);
    expect(c.phase, AttendancePhase.succeeded);
    await c.setEnabled(false);
  });
}
