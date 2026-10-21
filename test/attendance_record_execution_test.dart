import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';
import 'attendance_records_test.dart' show RecordBackend;
import 'attendance_test.dart' show fixtureCourse;

class ExecutionRecords extends RecordBackend
    implements AttendanceRecordExecutionBackend {
  int attempts = 0;
  AttendanceFailure? rejection;
  Completer<AttendanceSubmitResult>? executionGate;
  bool signOnSuccess = true;
  @override
  Future<AttendanceSubmitResult> submitRecord(AttendanceRecord record,
      AttendanceMeeting meeting, AttendanceQr qr) async {
    attempts++;
    if (rejection != null) throw rejection!;
    final result = executionGate == null
        ? AttendanceSubmitResult.success
        : await executionGate!.future;
    if (result == AttendanceSubmitResult.success && signOnSuccess) {
      rows = [
        AttendanceRecord(
            key: record.key,
            canvasId: record.canvasId,
            createdAt: record.createdAt,
            state: 'NORMAL')
      ];
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final time = DateTime.utc(2026, 10, 21, 0);
  final meeting = AttendanceMeeting(
      course: fixtureCourse(),
      start: time,
      end: time.add(const Duration(minutes: 45)));
  const qr =
      'https://mlearning.sjtu.edu.cn/lms/mobile2/forscan/?courseCode=course&signHistoryId=task&rollCallToken=fresh&fromType=scanRollCall';
  Future<AttendanceController> setup(ExecutionRecords b) async {
    b.rows = [
      AttendanceRecord(
          key: '91:own', canvasId: '91', createdAt: time, state: 'UNNORMAL')
    ];
    final c = AttendanceController(backend: b, clock: () => b.now);
    await c.restore();
    await c.updateSchedule('account', [meeting]);
    await c.setEnabled(true);
    return c;
  }

  testWidgets(
      'discovery cannot submit; explicit execution rechecks own state and confirms success',
      (t) async {
    final b = ExecutionRecords();
    final c = await setup(b);
    await t.pump();
    c.acceptQr(qr);
    await t.pump();
    expect(b.attempts, 0);
    expect(await c.authorizeExecution(), true);
    expect(c.phase, AttendancePhase.openingLive);
    c.scanning();
    c.acceptQr(qr);
    await t.pump();
    expect(b.attempts, 1);
    expect(c.phase, AttendancePhase.succeeded);
    expect(c.pendingRecord, isNull);
    await c.setEnabled(false);
  });
  testWidgets('unknown task association stops without declaring success',
      (t) async {
    final b = ExecutionRecords()
      ..rejection =
          const AttendanceFailure(AttendancePhase.limited, '无法确认任务关联');
    final c = await setup(b);
    await t.pump();
    await c.authorizeExecution();
    c.acceptQr(qr);
    await t.pump();
    expect(c.phase, AttendancePhase.limited);
    expect(c.detail, contains('无法确认任务关联'));
    expect(b.attempts, 1);
    c.acceptQr(qr);
    await t.pump();
    expect(b.attempts, 1);
    await c.setEnabled(false);
  });
  testWidgets(
      'new frames never create parallel submissions and cancellation invalidates completion',
      (t) async {
    final b = ExecutionRecords()
      ..executionGate = Completer<AttendanceSubmitResult>();
    final c = await setup(b);
    await t.pump();
    await c.authorizeExecution();
    c.acceptQr(qr);
    await t.pump();
    c.acceptQr(qr.replaceAll('fresh', 'newer'));
    await t.pump();
    expect(b.attempts, 1);
    await c.setEnabled(false);
    b.executionGate!.complete(AttendanceSubmitResult.success);
    await t.pump();
    expect(c.phase, AttendancePhase.off);
    expect(c.pendingRecord, isNull);
    expect(b.attempts, 1);
  });
  testWidgets('server response alone cannot prove the student signed',
      (t) async {
    final b = ExecutionRecords()..signOnSuccess = false;
    final c = await setup(b);
    await t.pump();
    await c.authorizeExecution();
    c.acceptQr(qr);
    await t.pump();
    expect(c.phase, AttendancePhase.failed);
    expect(c.detail, contains('尚未确认'));
    await c.setEnabled(false);
  });
  testWidgets('a completed or out-of-window record cannot start live execution',
      (t) async {
    final b = ExecutionRecords();
    final c = await setup(b);
    await t.pump();
    b.rows = [
      AttendanceRecord(
          key: '91:own', canvasId: '91', createdAt: time, state: 'NORMAL')
    ];
    expect(await c.authorizeExecution(), false);
    expect(b.attempts, 0);
    await c.setEnabled(false);
  });
  testWidgets(
      'live failure releases the pending record and permits a later task',
      (t) async {
    final b = ExecutionRecords();
    final c = await setup(b);
    await t.pump();
    expect(await c.authorizeExecution(), true);
    c.report(AttendancePhase.failed, '直播未开始');
    await t.pump();
    expect(c.pendingRecord, isNull);
    expect(c.pendingMeeting, isNull);
    expect(c.phase, AttendancePhase.failed);
    expect(c.detail, '直播未开始');
    b.rows = [
      AttendanceRecord(
          key: '91:next', canvasId: '91', createdAt: time, state: 'UNNORMAL')
    ];
    await c.check();
    expect(c.pendingRecord?.key, '91:next');
    await c.setEnabled(false);
  });
}
