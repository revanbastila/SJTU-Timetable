import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';
import 'package:jiaotong_course/services/attendance_native.dart';
import 'attendance_test.dart' show fixtureCourse, FakeAttendanceBackend;

class RecordBackend extends FakeAttendanceBackend
    implements AttendanceRecordBackend {
  List<AttendanceRecord> rows = [];
  DateTime now = DateTime.utc(2026, 10, 21, 0);
  String failureCode = '';
  int reads = 0, notices = 0;
  final Set<String> claimed = {};
  Completer<AttendanceSnapshot>? gate;
  @override
  Future<AttendanceSnapshot> inspectRecords(AttendanceMeeting m,
      {bool manual = false}) async {
    reads++;
    if (gate != null) {
      final g = gate!;
      gate = null;
      return g.future;
    }
    return AttendanceSnapshot(
        canvasId: m.canvasId,
        checkedAt: now,
        records: rows,
        failure: failureCode);
  }

  @override
  Future<bool> claimRecord(AttendanceRecord r, AttendanceMeeting m,
          {required bool foreground}) async =>
      claimed.add(r.key);
  @override
  Future<void> setRecordForeground(bool value) async {}

  @override
  Future<void> acknowledgeRecord(AttendanceRecord record) async {}

  @override
  Future<void> notifyRecord(AttendanceRecord r, AttendanceMeeting m) async {
    notices++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final start = DateTime.utc(2026, 10, 21, 0);
  final meeting = AttendanceMeeting(
      course: fixtureCourse(),
      start: start,
      end: start.add(const Duration(minutes: 100)));
  AttendanceRecord row(String id, DateTime date, String state) =>
      AttendanceRecord(
          key: '91:$id', canvasId: '91', createdAt: date, state: state);
  List<AttendanceRecord> screenshot() => [
        row('old3', DateTime.utc(2026, 9, 16, 0, 0, 47), 'UNNORMAL'),
        row('last', DateTime.utc(2026, 10, 21, 23 - 24, 51, 10), 'NORMAL'),
        row('old1', DateTime.utc(2026, 9, 29, 23, 48, 1), 'UNNORMAL'),
        row('previous', DateTime.utc(2026, 10, 13, 23, 56, 35), 'NORMAL'),
        row('old2', DateTime.utc(2026, 9, 22, 23, 49, 57), 'UNNORMAL'),
      ];
  Future<AttendanceController> setup(RecordBackend b,
      {bool enable = true}) async {
    final c = AttendanceController(backend: b, clock: () => b.now);
    await c.restore();
    await c.updateSchedule('fixture-account', [meeting]);
    if (enable) await c.setEnabled(true);
    addTearDown(c.dispose);
    return c;
  }

  test(
      'screenshot dates sort by Shanghai time; signed latest ignores old absences',
      () {
    final snapshot = AttendanceSnapshot(
        canvasId: '91',
        checkedAt: DateTime.utc(2026, 10, 21, 2, 48),
        records: screenshot());
    expect(snapshot.records, hasLength(5));
    expect(snapshot.latest!.key, '91:last');
    expect(snapshot.summary, '最近一次签到：10月21日07:51，已签到');
    expect(snapshot.phase, AttendancePhase.completed);
    expect(snapshot.records.where((r) => r.relevant(meeting, start)), isEmpty);
  });
  test('history, unknown status and unavailable opening are distinguished', () {
    AttendanceSnapshot snapshot(List<AttendanceRecord> rows,
            {String failure = ''}) =>
        AttendanceSnapshot(
            canvasId: '91', checkedAt: start, records: rows, failure: failure);
    expect(snapshot([]).phase, AttendancePhase.noNew);
    expect(
        snapshot([
          row('old', start.subtract(const Duration(days: 7)), 'UNNORMAL')
        ]).phase,
        AttendancePhase.history);
    expect(snapshot([row('today', start, 'UNNORMAL')]).summary,
        contains('开放状态未确认'));
    expect(snapshot([row('unknown', start, 'NEW_STATE')]).latest!.unsigned,
        isFalse);
    expect(
        snapshot([], failure: 'canvas_login').summary, contains('重新登录 Canvas'));
    expect(snapshot([], failure: 'no_entry').phase, AttendancePhase.noEntry);
    expect(snapshot([], failure: 'network').phase, AttendancePhase.failed);
    expect(
        snapshot([], failure: 'session_login').summary, contains('签到系统会话已失效'));
  });
  testWidgets('signed latest and historical absences never produce reminders',
      (tester) async {
    final b = RecordBackend()..rows = screenshot();
    final c = await setup(b);
    await tester.pump();
    expect(c.phase, AttendancePhase.completed);
    expect(c.pendingRecord, isNull);
    expect(b.claimed, isEmpty);
    expect(b.submits, 0);
    expect(b.polls, 0);
    await c.setEnabled(false);
  });
  testWidgets(
      'already published unsigned record prompts with unknown availability only once',
      (tester) async {
    final b = RecordBackend()
      ..rows = [
        row('existing', start.subtract(const Duration(minutes: 9)), 'UNNORMAL')
      ];
    final c = await setup(b);
    await tester.pump();
    expect(c.pendingRecord!.key, '91:existing');
    expect(c.detail, contains('开放状态未确认'));
    expect(await c.authorizeExecution(), isFalse);
    expect(b.submits, 0);
    c.dismissRecord();
    await c.check();
    expect(c.pendingRecord, isNull);
    expect(b.claimed, {'91:existing'});
    await c.setEnabled(false);
  });
  testWidgets(
      'two same-day records remain separate; later completion closes reminder',
      (tester) async {
    final b = RecordBackend()
      ..now = start.add(const Duration(minutes: 10))
      ..rows = [
        row('a', start, 'UNNORMAL'),
        row('b', start.add(const Duration(minutes: 5)), 'UNNORMAL')
      ];
    final c = await setup(b);
    await tester.pump();
    expect(c.pendingRecord!.key, '91:b');
    c.dismissRecord();
    await c.check();
    expect(c.pendingRecord!.key, '91:a');
    b.rows = [
      row('a', start, 'NORMAL'),
      row('b', start.add(const Duration(minutes: 5)), 'NORMAL')
    ];
    await c.check();
    expect(c.pendingRecord, isNull);
    expect(c.phase, AttendancePhase.completed);
    expect(b.submits, 0);
    await c.setEnabled(false);
  });
  testWidgets(
      'manual fresh read works outside window and while automatic switch is off',
      (tester) async {
    final b = RecordBackend()
      ..now = start.add(const Duration(hours: 8))
      ..rows = screenshot();
    final c = await setup(b, enable: false);
    await c.inspectManually(meeting);
    expect(b.reads, 1);
    expect(c.detail, contains('07:51，已签到'));
    await c.inspectManually(meeting);
    expect(b.reads, 2);
    expect(b.claimed, isEmpty);
    expect(b.submits, 0);
  });
  testWidgets(
      'actual scheduler checks records at 30 seconds and recovers after outage',
      (tester) async {
    final b = RecordBackend();
    final c = await setup(b);
    await tester.pump();
    expect(b.reads, 1);
    b.now = b.now.add(const Duration(seconds: 29));
    await tester.pump(const Duration(seconds: 29));
    expect(b.reads, 1);
    b.failureCode = 'network';
    b.now = b.now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(b.reads, 2);
    expect(c.phase, AttendancePhase.failed);
    b.failureCode = '';
    b.now = b.now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(b.reads, 3);
    expect(c.phase, AttendancePhase.noNew);
    await c.setEnabled(false);
    await tester.pump(const Duration(minutes: 1));
    expect(b.reads, 3);
  });
  testWidgets(
      'manual and scheduled inspections share one in-flight course request',
      (tester) async {
    final b = RecordBackend();
    final c = await setup(b);
    await tester.pump();
    final gate = Completer<AttendanceSnapshot>();
    b.gate = gate;
    final manual = c.inspectManually(meeting);
    final auto = c.check();
    expect(b.reads, 2);
    gate.complete(
        AttendanceSnapshot(canvasId: '91', checkedAt: b.now, records: []));
    await manual;
    await auto;
    expect(b.reads, 2);
    await c.setEnabled(false);
  });
  test('native bridge maps student records and rejects another course payload',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var id = '91';
    messenger.setMockMethodCallHandler(
        NativeAttendanceBackend.channel,
        (call) async => {
              'status': 'ok',
              'courseId': id,
              'checkedAt': start.millisecondsSinceEpoch,
              'records': [
                {
                  'key': '$id:opaque',
                  'createdAt': start
                      .subtract(const Duration(minutes: 9))
                      .millisecondsSinceEpoch,
                  'state': 'NORMAL',
                  'availability': 'unknown'
                }
              ],
            });
    addTearDown(() => messenger.setMockMethodCallHandler(
        NativeAttendanceBackend.channel, null));
    final backend = NativeAttendanceBackend();
    expect((await backend.inspectRecords(meeting)).summary, contains('已签到'));
    id = '92';
    expect((await backend.inspectRecords(meeting)).failure, 'format');
  });
}
