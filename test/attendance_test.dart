import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/models/teaching_calendar.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';

Course fixtureCourse(
        {String id = '91',
        int start = 480,
        int end = 525,
        List<int> weeks = const [1, 3]}) =>
    Course(
        id: 'lesson-$start',
        name: '测试课程',
        teacher: '教师',
        location: '教室',
        time: 'fixture',
        weekday: 1,
        startHour: start ~/ 60,
        startMinute: start % 60,
        endHour: end ~/ 60,
        endMinute: end % 60,
        activeWeeks: weeks,
        rawWeekText: 'fixture',
        courseIdentity: 'stable-course',
        canvasCourseId: id);

class FakeAttendanceBackend implements AttendanceBackend {
  List<AttendanceTask> tasks = [];
  int polls = 0,
      submits = 0,
      verifications = 0,
      cancels = 0,
      notifications = 0,
      concurrent = 0,
      peak = 0;
  bool confirmed = true;
  final List<bool> configurations = [];
  final List<String> acknowledgments = [];
  Completer<List<AttendanceTask>>? pollGate;
  Completer<AttendanceSubmitResult>? submitGate;
  final List<AttendanceSubmitResult> results = [];
  AttendanceFailure? failure;
  @override
  Future<List<AttendanceTask>> poll(AttendanceMeeting m) async {
    polls++;
    if (failure != null) throw failure!;
    if (pollGate != null) {
      final gate = pollGate!;
      pollGate = null;
      return gate.future;
    }
    return tasks;
  }

  @override
  Future<AttendanceSubmitResult> submit(
      AttendanceTask task, AttendanceQr qr) async {
    submits++;
    concurrent++;
    if (concurrent > peak) peak = concurrent;
    try {
      if (submitGate != null) {
        final gate = submitGate!;
        submitGate = null;
        return await gate.future;
      }
      return results.isEmpty
          ? AttendanceSubmitResult.success
          : results.removeAt(0);
    } finally {
      concurrent--;
    }
  }

  @override
  Future<bool> verify(AttendanceTask task) async {
    verifications++;
    return confirmed;
  }

  @override
  Future<void> configure(
      bool enabled, String account, List<AttendanceMeeting> meetings) async {
    configurations.add(enabled);
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> notifyTask(
      AttendanceTask task, AttendanceMeeting meeting) async {
    notifications++;
  }

  @override
  Future<void> acknowledge(String key, DateTime until) async {
    acknowledgments.add(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final term = DateTime(2030, 1, 7);
  final now = DateTime.utc(2030, 1, 7, 0, 15);
  AttendanceMeeting meeting() => AttendanceMeeting(
      course: fixtureCourse(),
      start: DateTime.utc(2030, 1, 7),
      end: DateTime.utc(2030, 1, 7, 1));
  AttendanceTask task(
          {String id = 'task-1',
          String canvasId = '91',
          String state = 'UNNORMAL',
          bool active = true,
          DateTime? created,
          DateTime? expires}) =>
      AttendanceTask(
          id: id,
          canvasId: canvasId,
          courseCode: 'bound-course',
          createdAt: created ?? DateTime.utc(2030, 1, 7, 0, 5),
          state: state,
          serverActive: active,
          expiresAt: expires);
  String qr([String token = 'fresh']) =>
      'https://mlearning.sjtu.edu.cn/lms/mobile2/forscan/?fromType=scanRollCall&signHistoryId=task-1&rollCallToken=$token&courseCode=bound-course';
  Future<void> flush() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<AttendanceController> enabled(FakeAttendanceBackend backend,
      {DateTime Function()? clock}) async {
    final c = AttendanceController(backend: backend, clock: clock ?? () => now);
    await c.restore();
    await c.updateSchedule('fixture-account', [meeting()]);
    await c.setEnabled(true);
    await flush();
    addTearDown(c.dispose);
    return c;
  }

  test('QR URI parsing permits arbitrary parameter order and redacts token',
      () {
    final parsed = AttendanceQr.parse(qr());
    expect(parsed.matches(task()), isTrue);
    expect(parsed.toString(), isNot(contains('fresh')));
    expect(
        parsed.fingerprint, isNot(AttendanceQr.parse(qr('new')).fingerprint));
  });
  for (final bad in [
    'http://mlearning.sjtu.edu.cn',
    'https://mlearning.sjtu.edu.cn.evil.example',
    'https://user@mlearning.sjtu.edu.cn',
    'https://mlearning.sjtu.edu.cn:444'
  ]) {
    test(
        'QR rejects origin $bad',
        () => expect(
            () => AttendanceQr.parse(
                qr().replaceFirst('https://mlearning.sjtu.edu.cn', bad)),
            throwsFormatException));
  }
  test(
      'QR rejects duplicated/missing parameters, fragments and other scan modes',
      () {
    for (final raw in [
      '${qr()}&courseCode=other',
      '${qr()}#route',
      qr().replaceAll('scanRollCall', 'scanPoll'),
      qr().replaceAll('rollCallToken=fresh&', ''),
      qr().replaceAll('/forscan/', '/other/')
    ]) {
      expect(() => AttendanceQr.parse(raw), throwsFormatException);
    }
    expect(AttendanceQr.parse(qr()).matches(task(id: 'another')), isFalse);
  });
  test(
      'strict business result rejects HTTP-only, message-only and unknown statuses',
      () {
    expect(
        parseAttendanceResult(200, {
          'resultCode': '200',
          'body': {'status': 'NORMAL'}
        }),
        AttendanceSubmitResult.success);
    expect(parseAttendanceResult(200, {'message': '200 操作成功'}),
        AttendanceSubmitResult.rejected);
    expect(
        parseAttendanceResult(500, {
          'resultCode': 200,
          'body': {'status': 'NORMAL'}
        }),
        AttendanceSubmitResult.unknown);
    expect(
        parseAttendanceResult(200, {
          'resultCode': 200,
          'body': {'status': 'UNKNOWN'}
        }),
        AttendanceSubmitResult.unknown);
    expect(
        parseAttendanceResult(200, {
          'resultCode': 200,
          'body': {'status': 'EXPIRED'}
        }),
        AttendanceSubmitResult.expired);
    expect(parseAttendanceResult(200, {'resultCode': 10001}),
        AttendanceSubmitResult.needsLogin);
  });
  test(
      'existing effective calendar controls weeks, holidays, makeup and no-class',
      () {
    final cal = TeachingCalendar.parse(jsonEncode({
      'version': 1,
      'rules': [
        {'date': '2030-01-07', 'type': 'holiday'},
        {'date': '2030-01-08', 'type': 'no_class'},
        {
          'date': '2030-01-12',
          'type': 'makeup',
          'use_weekday': 1,
          'use_week': 3
        },
      ]
    }));
    List<Course> effective(DateTime d) =>
        cal.getEffectiveCoursesForDate(d, [fixtureCourse()], term, 4);
    expect(
        AttendanceSchedule.meetings(now, effective)
            .where((m) => m.contains(now)),
        isEmpty);
    final makeup = DateTime.utc(2030, 1, 12, 0, 10);
    expect(
        AttendanceSchedule.meetings(makeup, effective)
            .where((m) => m.contains(makeup)),
        hasLength(1));
    final even = DateTime.utc(2030, 1, 14, 0, 10);
    expect(
        AttendanceSchedule.meetings(even, effective)
            .where((m) => m.contains(even)),
        isEmpty);
  });
  test('consecutive periods merge by stable course identity and Canvas ID', () {
    final rows = [fixtureCourse(), fixtureCourse(start: 535, end: 580)];
    List<Course> effective(DateTime d) => const TeachingCalendar.empty()
        .getEffectiveCoursesForDate(d, rows, term, 4);
    final list = AttendanceSchedule.meetings(now, effective);
    expect(list, hasLength(1));
    expect(list.single.start, DateTime.utc(2030, 1, 7));
    expect(list.single.end, DateTime.utc(2030, 1, 7, 1, 40));
    expect(list.single.contains(list.single.end), isTrue);
    expect(list.single.contains(list.single.detectionEnd), isFalse);
  });
  test('UTC civil-date crossing and no mapping never infer a course by name',
      () {
    final lateUtc = DateTime.utc(2030, 1, 6, 23, 59);
    List<Course> effective(DateTime d) => const TeachingCalendar.empty()
        .getEffectiveCoursesForDate(d, [fixtureCourse()], term, 4);
    final list = AttendanceSchedule.meetings(lateUtc, effective);
    expect(list.single.start, DateTime.utc(2030, 1, 7));
    expect(AttendanceSchedule.meetings(now, (_) => [fixtureCourse(id: '')]),
        isEmpty);
  });
  test(
      'eligibility excludes history, other courses, completed, expired and inactive tasks',
      () {
    expect(task().eligible(meeting(), now), isTrue);
    for (final value in [
      task(canvasId: '92'),
      task(state: 'NORMAL'),
      task(active: false),
      task(created: now.subtract(const Duration(days: 1))),
      task(expires: now),
      task(created: now.add(const Duration(minutes: 1)))
    ]) {
      expect(value.eligible(meeting(), now), isFalse);
    }
  });
  test('default off persists; no class means no network polling', () async {
    final b = FakeAttendanceBackend();
    final c = AttendanceController(backend: b, clock: () => now);
    addTearDown(c.dispose);
    await c.restore();
    expect(c.enabled, isFalse);
    await c.setEnabled(true);
    await flush();
    expect(b.polls, 0);
    expect(c.phase, AttendancePhase.waiting);
    expect(
        (await SharedPreferences.getInstance())
            .getBool('autoAttendanceEnabled'),
        isTrue);
    await c.setEnabled(false);
    expect(c.phase, AttendancePhase.off);
  });
  test(
      'already-published still-active task prompts once; checking never submits',
      () async {
    final b = FakeAttendanceBackend()..tasks = [task()];
    final c = await enabled(b);
    expect(c.phase, AttendancePhase.pending);
    expect(b.submits, 0);
    expect(b.acknowledgments, ['91:task-1']);
    await c.cancel();
    await c.check();
    expect(c.pending, isNull);
    expect(b.submits, 0);
  });
  test('consent rechecks active state and prevents expired task execution',
      () async {
    final b = FakeAttendanceBackend()..tasks = [task()];
    final c = await enabled(b);
    b.tasks = [];
    expect(await c.authorizeExecution(), isFalse);
    expect(c.phase, AttendancePhase.expired);
    expect(b.submits, 0);
  });
  test(
      'new QR frames continue while one submit is pending; expiry uses freshest token',
      () async {
    final b = FakeAttendanceBackend()..tasks = [task()];
    final c = await enabled(b);
    expect(await c.authorizeExecution(), isTrue);
    final gate = Completer<AttendanceSubmitResult>();
    b.submitGate = gate;
    c.acceptQr(qr('old'));
    await flush();
    expect(c.phase, AttendancePhase.submitting);
    c.acceptQr(qr('new'));
    expect(b.submits, 1);
    gate.complete(AttendanceSubmitResult.expired);
    await flush();
    expect(b.submits, 2);
    expect(b.peak, 1);
    expect(c.phase, AttendancePhase.succeeded);
    expect(b.verifications, 1);
  });
  test('wrong-course QR is ignored and success requires own-state verification',
      () async {
    final b = FakeAttendanceBackend()
      ..tasks = [task()]
      ..confirmed = false;
    final c = await enabled(b);
    await c.authorizeExecution();
    c.acceptQr(qr().replaceAll('bound-course', 'unrelated'));
    await flush();
    expect(b.submits, 0);
    c.acceptQr(qr());
    await flush();
    expect(c.phase, AttendancePhase.failed);
    expect(c.detail, contains('尚未确认'));
  });
  test('completed task dedup and QR attempts never cross accounts', () async {
    final b = FakeAttendanceBackend()..tasks = [task()];
    final c = await enabled(b);
    await c.authorizeExecution();
    c.acceptQr(qr());
    await flush();
    expect(c.phase, AttendancePhase.succeeded);
    await c.updateSchedule('another-account', [meeting()]);
    await flush();
    expect(c.phase, AttendancePhase.pending);
    await c.authorizeExecution();
    c.acceptQr(qr());
    await flush();
    expect(c.phase, AttendancePhase.succeeded);
    expect(b.submits, 2);
  });
  test('cancel during submission prevents late success and additional requests',
      () async {
    final b = FakeAttendanceBackend()..tasks = [task()];
    final c = await enabled(b);
    await c.authorizeExecution();
    final gate = Completer<AttendanceSubmitResult>();
    b.submitGate = gate;
    c.acceptQr(qr());
    await flush();
    await c.cancel();
    gate.complete(AttendanceSubmitResult.success);
    c.acceptQr(qr('later'));
    await flush();
    expect(c.phase, AttendancePhase.cancelled);
    expect(b.submits, 1);
    expect(b.verifications, 0);
  });
  test(
      'same expired token is not re-submitted; distinct token attempts are bounded',
      () async {
    final b = FakeAttendanceBackend()
      ..tasks = [task()]
      ..results.addAll(List.filled(4, AttendanceSubmitResult.expired));
    final c = await enabled(b);
    await c.authorizeExecution();
    for (final value in ['one', 'one', 'two', 'three', 'four']) {
      c.acceptQr(qr(value));
      await flush();
    }
    expect(b.submits, 3);
    expect(c.phase, AttendancePhase.failed);
  });
  test(
      'in-flight foreground discovery delivers notification after backgrounding',
      () async {
    final b = FakeAttendanceBackend();
    final c = await enabled(b);
    final gate = Completer<List<AttendanceTask>>();
    b.pollGate = gate;
    final check = c.check();
    c.setForeground(false);
    gate.complete([task()]);
    await check;
    expect(c.phase, AttendancePhase.pending);
    expect(b.notifications, 1);
  });
  test(
      'class end and disable cancel pending tasks and clear sensitive candidates',
      () async {
    var clock = now;
    final b = FakeAttendanceBackend()..tasks = [task()];
    final c = await enabled(b, clock: () => clock);
    await c.authorizeExecution();
    clock = meeting().detectionEnd;
    await c.check();
    expect(c.phase, AttendancePhase.waiting);
    expect(c.pending, isNull);
    await c.setEnabled(false);
    expect(b.configurations.last, isFalse);
    expect(c.enabled, isFalse);
  });
  test('login/permission/network limitations do not manufacture a task',
      () async {
    for (final phase in [AttendancePhase.needsLogin, AttendancePhase.limited]) {
      final b = FakeAttendanceBackend()
        ..failure = AttendanceFailure(phase, '受限');
      final c = await enabled(b);
      expect(c.phase, phase);
      expect(c.pending, isNull);
      expect(b.submits, 0);
      await c.setEnabled(false);
    }
  });
}
