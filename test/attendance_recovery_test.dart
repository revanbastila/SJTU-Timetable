import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/pages/attendance_web_page.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'package:jiaotong_course/widgets/attendance_observer.dart';
import 'attendance_record_execution_test.dart' show ExecutionRecords;
import 'attendance_records_test.dart' show RecordBackend;
import 'attendance_test.dart' show fixtureCourse;
import 'support/memory_database.dart';
import 'week_display_mode_test.dart' show QuietNotifications;

class PresentationRecords extends ExecutionRecords
    implements AttendancePresentationBackend {
  int displayed = 0, handled = 0;
  @override
  Future<void> recordDisplayed(AttendanceRecord record) async {
    displayed++;
  }

  @override
  Future<void> acknowledgeRecord(AttendanceRecord record) async {
    handled++;
  }
}

class CourseRecords extends RecordBackend {
  Duration? nextDelay;
  final Map<String, List<DateTime>> starts = {};
  final Map<String, Completer<AttendanceSnapshot>> gates = {};
  final Set<String> broken = {};
  @override
  Future<AttendanceSnapshot> inspectRecords(AttendanceMeeting m,
      {bool manual = false}) async {
    starts.putIfAbsent(m.canvasId, () => []).add(now);
    if (gates.containsKey(m.canvasId)) return gates[m.canvasId]!.future;
    return AttendanceSnapshot(
        canvasId: m.canvasId,
        checkedAt: now,
        records: [],
        failure: broken.contains(m.canvasId) ? 'network' : '',
        nextCheckDelay: nextDelay);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final start = DateTime.utc(2026, 10, 21);
  AttendanceMeeting meeting([String id = '91']) => AttendanceMeeting(
      course: fixtureCourse(id: id),
      start: start,
      end: start.add(const Duration(hours: 2)));
  AttendanceRecord row({String state = 'UNNORMAL'}) => AttendanceRecord(
      key: '91:own', canvasId: '91', createdAt: start, state: state);
  Future<AttendanceController> setup(RecordBackend b,
      {List<AttendanceMeeting>? meetings, bool own = true}) async {
    final c = AttendanceController(backend: b, clock: () => b.now);
    await c.restore();
    await c.updateSchedule('account', meetings ?? [meeting()]);
    await c.setEnabled(true);
    if (own) addTearDown(c.dispose);
    return c;
  }

  testWidgets('late manual result cannot overwrite authorization or stop live',
      (t) async {
    final b = ExecutionRecords()..rows = [row()];
    final c = await setup(b);
    await t.pump();
    final gate = Completer<AttendanceSnapshot>();
    b.gate = gate;
    final manual = c.inspectManually(meeting());
    final authorize = c.authorizeExecution();
    expect(c.phase, AttendancePhase.openingLive);
    gate.complete(
        AttendanceSnapshot(canvasId: '91', checkedAt: start, records: [row()]));
    await manual;
    expect(await authorize, true);
    expect(c.executing, true);
    expect(c.phase, AttendancePhase.openingLive);
    await c.setEnabled(false);
  });
  testWidgets(
      'cancel while authorization awaits records never resurrects execution',
      (t) async {
    final b = ExecutionRecords()..rows = [row()];
    final c = await setup(b);
    await t.pump();
    final gate = Completer<AttendanceSnapshot>();
    b.gate = gate;
    final auth = c.authorizeExecution();
    await c.cancel();
    gate.complete(
        AttendanceSnapshot(canvasId: '91', checkedAt: start, records: [row()]));
    expect(await auth, false);
    expect(c.executing, false);
    expect(c.phase, AttendancePhase.cancelled);
    await c.setEnabled(false);
  });
  testWidgets(
      'old page errors and QR callbacks cannot change a retried operation',
      (t) async {
    final b = ExecutionRecords()..rows = [row()];
    final c = await setup(b);
    await t.pump();
    expect(await c.authorizeExecution(), true);
    final old = c.operation;
    c.report(AttendancePhase.failed, '临时入口失败', operation: old);
    await t.pump();
    expect(await c.retryExecution(row(), meeting()), true);
    expect(c.operation, isNot(old));
    c.report(AttendancePhase.failed, '旧页面错误', operation: old);
    c.scanning(operation: old);
    c.acceptQr(
        'https://mlearning.sjtu.edu.cn/lms/mobile2/forscan/?courseCode=course&signHistoryId=task&rollCallToken=fresh&fromType=scanRollCall',
        operation: old);
    expect(c.phase, AttendancePhase.openingLive);
    expect(b.attempts, 0);
    await c.setEnabled(false);
  });
  testWidgets('transient failed read retains last successful own records',
      (t) async {
    final b = RecordBackend()..rows = [row(state: 'NORMAL')];
    final c = await setup(b);
    await t.pump();
    b.failureCode = 'network';
    await c.inspectManually(meeting());
    expect(c.recordSnapshots['91']!.latest!.completed, true);
    expect(c.recordFailures['91']!.failure, 'network');
    b.failureCode = '';
    await c.inspectManually(meeting());
    expect(c.recordFailures, isEmpty);
    await c.setEnabled(false);
  });
  testWidgets(
      'broken course backs off independently while healthy course stays at 30 seconds',
      (t) async {
    final b = CourseRecords()..broken.add('91');
    final c = await setup(b, meetings: [meeting(), meeting('92')]);
    await t.pump();
    for (var i = 0; i < 3; i++) {
      b.now = b.now.add(const Duration(seconds: 30));
      await t.pump(const Duration(seconds: 30));
    }
    expect(
        b.starts['91']!.map((v) => v.difference(start).inSeconds), [0, 30, 90]);
    expect(b.starts['92']!.map((v) => v.difference(start).inSeconds),
        [0, 30, 60, 90]);
    b.broken.clear();
    b.now = b.now.add(const Duration(seconds: 120));
    await t.pump(const Duration(seconds: 120));
    final last = b.starts['91']!.last;
    b.now = b.now.add(const Duration(seconds: 30));
    await t.pump(const Duration(seconds: 30));
    expect(b.starts['91']!.last.difference(last).inSeconds, 30);
    await c.setEnabled(false);
  });
  testWidgets(
      'slow course never overlaps and does not block other course timers',
      (t) async {
    final slow = Completer<AttendanceSnapshot>();
    final b = CourseRecords()..gates['91'] = slow;
    final c = await setup(b, meetings: [meeting(), meeting('92')]);
    await t.pump();
    b.now = b.now.add(const Duration(seconds: 30));
    await t.pump(const Duration(seconds: 30));
    b.now = b.now.add(const Duration(seconds: 30));
    await t.pump(const Duration(seconds: 30));
    expect(b.starts['91'], hasLength(1));
    expect(b.starts['92'], hasLength(3));
    slow.complete(
        AttendanceSnapshot(canvasId: '91', checkedAt: b.now, records: []));
    await t.pump();
    await c.setEnabled(false);
  });
  testWidgets(
      'claim interrupted before rendering remains pending until foreground presentation',
      (t) async {
    final b = PresentationRecords()..rows = [row()];
    final c = await setup(b);
    await t.pump();
    expect(b.displayed, 0);
    c.setForeground(false);
    await c.recordDisplayed('91:own');
    expect(b.displayed, 0);
    c.setForeground(true);
    await t.pump();
    await c.recordDisplayed('91:own');
    expect(b.displayed, 1);
    expect(b.handled, 0);
    c.dismissRecord();
    await t.pump();
    expect(b.handled, 1);
    await c.setEnabled(false);
  });
  testWidgets(
      'foreground uses remaining native slot delay after background handover',
      (t) async {
    final b = CourseRecords()..nextDelay = const Duration(seconds: 20);
    final c = await setup(b);
    await t.pump();
    b.now = b.now.add(const Duration(seconds: 19));
    await t.pump(const Duration(seconds: 19));
    expect(b.starts['91'], hasLength(1));
    b.now = b.now.add(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(b.starts['91'], hasLength(2));
    await c.setEnabled(false);
  });
  for (final brightness in Brightness.values) {
    testWidgets(
        'entry error and in-place retry survive theme switch from $brightness',
        (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() async {
        final file = File('C:/Windows/Fonts/msyh.ttc');
        if (await file.exists()) {
          await (FontLoader('PreviewChinese')
                ..addFont(
                    file.readAsBytes().then((b) => ByteData.view(b.buffer))))
              .load();
        }
        final icons = File(
            '../../work/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
        if (await icons.exists()) {
          await (FontLoader('MaterialIcons')
                ..addFont(
                    icons.readAsBytes().then((b) => ByteData.view(b.buffer))))
              .load();
        }
      });
      final b = RecordBackend();
      final c = AttendanceController(backend: b, clock: () => b.now);
      await c.restore();
      await c.setEnabled(true);
      final app = AppController(QuietNotifications(),
          database: MemoryDatabase(), attendance: c);
      // No WebView is created on an entry error; changing the response exercises
      // the original course and operation through the actual retry control.
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final courses = <String>[];
      app.attendanceBackend;
      messenger.setMockMethodCallHandler(
          const MethodChannel('cn.sjtu.jiaotong_course/attendance'),
          (call) async {
        if (call.method == 'tabs') {
          courses.add((call.arguments as Map)['courseId']);
          return {'status': 'permission'};
        }
        return null;
      });
      Widget page(Brightness value) => RepaintBoundary(
          key: const Key('recovery-preview'),
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(brightness: value, fontFamily: 'PreviewChinese'),
              home: AttendanceWebPage(app: app, meeting: meeting())));
      await t.pumpWidget(page(brightness));
      await t.pumpAndSettle();
      expect(find.textContaining('无权访问这门课程'), findsWidgets);
      await t.tap(find.text('重试当前课程'));
      await t.pumpAndSettle();
      expect(courses, ['91', '91']);
      final other =
          brightness == Brightness.light ? Brightness.dark : Brightness.light;
      await t.pumpWidget(page(other));
      await t.pumpAndSettle();
      final context = t.element(find.text('重试当前课程'));
      expect(Theme.of(context).brightness, other);
      expect(t.takeException(), isNull);
      final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('recovery-preview')));
      await t.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('build/attendance-previews');
        await output.create(recursive: true);
        await File('${output.path}/entry-error-${other.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      await t.pumpWidget(const SizedBox.shrink());
      await c.setEnabled(false);
      app.dispose();
      messenger.setMockMethodCallHandler(
          const MethodChannel('cn.sjtu.jiaotong_course/attendance'), null);
    });
  }
  testWidgets(
      'queued reminder survives pause and renders only one dialog on resume',
      (t) async {
    final b = PresentationRecords()..rows = [row()];
    final c = await setup(b, own: false);
    await t.pump();
    final app = AppController(QuietNotifications(),
        database: MemoryDatabase(), attendance: c)
      ..loggedIn = true
      ..username = 'account';
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AttendanceObserver(app: app))));
    await t.pump();
    c.report(AttendancePhase.pending, '第一次通知');
    c.report(AttendancePhase.pending, '同帧重复通知');
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(b.displayed, 0);
    expect(c.pendingRecord, isNotNull);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(b.displayed, 1);
    await t.tap(find.text('暂不执行'));
    await t.pumpAndSettle();
    expect(b.handled, 1);
    expect(c.pendingRecord, isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await c.setEnabled(false);
    app.dispose();
  });
  test(
      'entry errors preserve distinct login, permission, timeout, service and parsing causes',
      () {
    expect(attendanceEntryFailure('canvas_login'), contains('登录已失效'));
    expect(attendanceEntryFailure('permission'), contains('无权访问'));
    expect(attendanceEntryFailure('timeout'), contains('超时'));
    expect(attendanceEntryFailure('network'), contains('网络连接失败'));
    expect(attendanceEntryFailure('server'), contains('服务暂时异常'));
    expect(attendanceEntryFailure('format'), contains('无法解析'));
  });
}
