import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';

import 'attendance_test.dart' show fixtureCourse, FakeAttendanceBackend;

void main() {
  final meeting = AttendanceMeeting(
    course: fixtureCourse(),
    start: DateTime.utc(2030, 1, 7, 2),
    end: DateTime.utc(2030, 1, 7, 2, 45),
  );
  AttendanceTask task(DateTime created) => AttendanceTask(
        id: 'task',
        canvasId: '91',
        courseCode: 'bound',
        createdAt: created,
        state: 'UNNORMAL',
        serverActive: true,
      );
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('window includes exactly five minutes before and after actual lesson',
      () {
    expect(meeting.detectionStart, DateTime.utc(2030, 1, 7, 1, 55));
    expect(meeting.detectionEnd, DateTime.utc(2030, 1, 7, 2, 50));
    expect(
        meeting.contains(
            meeting.detectionStart.subtract(const Duration(microseconds: 1))),
        isFalse);
    expect(meeting.contains(meeting.detectionStart), isTrue);
    expect(meeting.contains(meeting.end), isTrue);
    expect(
        meeting.contains(
            meeting.detectionEnd.subtract(const Duration(microseconds: 1))),
        isTrue);
    expect(meeting.contains(meeting.detectionEnd), isFalse);
    expect(meeting.start, DateTime.utc(2030, 1, 7, 2));
    expect(meeting.key, '91:${meeting.start.millisecondsSinceEpoch}');
  });

  test('native polling and submission receive the same expanded window', () {
    expect(meeting.toMap()['start'],
        meeting.detectionStart.millisecondsSinceEpoch);
    expect(meeting.toMap()['end'], meeting.detectionEnd.millisecondsSinceEpoch);
    expect(meeting.toMap()['recordStart'],
        meeting.recordStart.millisecondsSinceEpoch);
    expect(
        task(meeting.detectionStart).eligible(meeting, meeting.detectionStart),
        isTrue);
    expect(
        task(meeting.end.add(const Duration(minutes: 3)))
            .eligible(meeting, meeting.end.add(const Duration(minutes: 4))),
        isTrue);
    expect(
        task(meeting.recordStart.subtract(const Duration(seconds: 1)))
            .eligible(meeting, meeting.start),
        isFalse);
    expect(
        task(meeting.start).eligible(meeting, meeting.detectionEnd), isFalse);
  });

  test('expanded window can cross civil midnight without altering lesson date',
      () {
    final midnight = AttendanceMeeting(
      course: fixtureCourse(),
      start: DateTime.utc(2030, 1, 6, 16, 3), // Shanghai 00:03
      end: DateTime.utc(2030, 1, 6, 16, 50),
    );
    expect(midnight.contains(DateTime.utc(2030, 1, 6, 15, 58)), isTrue);
    expect(midnight.contains(DateTime.utc(2030, 1, 6, 15, 57, 59)), isFalse);
  });

  testWidgets('enters at boundary, polls every 30 seconds, stops at end',
      (tester) async {
    var now = meeting.detectionStart.subtract(const Duration(seconds: 1));
    final backend = FakeAttendanceBackend();
    final controller = AttendanceController(backend: backend, clock: () => now);
    addTearDown(controller.dispose);
    await controller.restore();
    await controller.updateSchedule('fixture', [meeting]);
    await controller.setEnabled(true);
    await tester.pump();
    expect(backend.polls, 0);
    now = meeting.detectionStart;
    await tester.pump(const Duration(seconds: 1));
    expect(backend.polls, 1);
    now = now.add(const Duration(seconds: 29));
    await tester.pump(const Duration(seconds: 29));
    expect(backend.polls, 1);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(backend.polls, 2);
    now = meeting.end;
    await controller.check();
    expect(backend.polls, 3);
    now = meeting.detectionEnd;
    await tester.pump(const Duration(seconds: 30));
    expect(backend.polls, 3);
    expect(controller.phase, AttendancePhase.waiting);
    await controller.setEnabled(false);
  });

  testWidgets('request duration does not add to 30 second cadence; no overlap',
      (tester) async {
    var now = meeting.start;
    final gate = Completer<List<AttendanceTask>>();
    final backend = FakeAttendanceBackend()..pollGate = gate;
    final controller = AttendanceController(backend: backend, clock: () => now);
    addTearDown(controller.dispose);
    await controller.restore();
    await controller.updateSchedule('fixture', [meeting]);
    await controller.setEnabled(true);
    await tester.pump();
    expect(backend.polls, 1);
    await controller.check();
    controller.setForeground(true);
    expect(backend.polls, 1);
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    gate.complete([]);
    await tester.pump();
    now = now.add(const Duration(seconds: 24));
    await tester.pump(const Duration(seconds: 24));
    expect(backend.polls, 1);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(backend.polls, 2);
    controller.setForeground(false);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(backend.polls, 2); // Native JobScheduler owns background work.
    controller.setForeground(true);
    await tester.pump();
    expect(backend.polls, 3);
    await controller.setEnabled(false);
  });

  testWidgets(
      'failure backs off and network recovery resumes 30 second polling',
      (tester) async {
    var now = meeting.start;
    final backend = FakeAttendanceBackend()
      ..failure = const AttendanceFailure(AttendancePhase.failed, 'offline');
    final controller = AttendanceController(backend: backend, clock: () => now);
    addTearDown(controller.dispose);
    await controller.restore();
    await controller.updateSchedule('fixture', [meeting]);
    await controller.setEnabled(true);
    await tester.pump();
    expect(backend.polls, 1);
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(backend.polls, 2);
    backend.failure = null;
    now = now.add(const Duration(seconds: 59));
    await tester.pump(const Duration(seconds: 59));
    expect(backend.polls, 2);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(backend.polls, 3);
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(backend.polls, 4);
    await controller.setEnabled(false);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(backend.polls, 4);
  });

  testWidgets('task dedup remains valid during ten minute post-class window',
      (tester) async {
    var now = meeting.end.subtract(const Duration(minutes: 1));
    final backend = FakeAttendanceBackend()..tasks = [task(meeting.start)];
    final controller = AttendanceController(backend: backend, clock: () => now);
    addTearDown(controller.dispose);
    await controller.restore();
    await controller.updateSchedule('fixture', [meeting]);
    await controller.setEnabled(true);
    await tester.pump();
    expect(controller.pending, isNotNull);
    await controller.cancel();
    now = meeting.end.add(const Duration(minutes: 3));
    await controller.check();
    expect(controller.pending, isNull);
    expect(backend.acknowledgments, ['91:task']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('autoAttendanceSeen'),
        contains('${meeting.detectionEnd.millisecondsSinceEpoch}'));
    await controller.setEnabled(false);
  });
}
