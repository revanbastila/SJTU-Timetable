import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/pages/attendance_web_page.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';
import 'package:jiaotong_course/services/attendance_native.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'attendance_record_execution_test.dart' show ExecutionRecords;
import 'attendance_test.dart' show fixtureCourse;
import 'common_web_navigation_test.dart'
    show BrowserPlatform, BrowserController;
import 'support/memory_database.dart';
import 'week_display_mode_test.dart' show QuietNotifications;

class LivePlatform extends BrowserPlatform {
  late LiveController live;
  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    live = LiveController(params);
    controllers.add(live);
    return live;
  }
}

class LiveController extends BrowserController {
  LiveController(PlatformWebViewControllerCreationParams params)
      : super(params, 1);
  bool playing = false;
  int samples = 0, refreshes = 0;
  @override
  Future<void> setMediaPlaybackRequiresUserGesture(bool value) async {}
  @override
  Future<void> reload() async {
    refreshes++;
    delegate.started?.call(url);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    if (!playing) {
      return jsonEncode({
        'playing': false,
        'liveState': 'notStarted',
        'viewState': 'discovering',
        'message': '直播尚未开始，正在等待'
      });
    }
    return jsonEncode({
      'playing': true,
      'frameKey': 'ppt',
      'time': ++samples,
      'x': 0,
      'y': 0,
      'width': 1,
      'height': 1,
      'viewState': 'ready',
      'message': '已选择 PPT／电脑画面，正在识别二维码'
    });
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    testWidgets(
        'visible waiting exceeds two minutes then resumes capture and submit in $brightness',
        (t) async {
      final start = DateTime.utc(2026, 10, 28, 2);
      final meeting = AttendanceMeeting(
          course: fixtureCourse(),
          start: start,
          end: start.add(const Duration(hours: 1)));
      final record = AttendanceRecord(
          key: '91:early',
          canvasId: '91',
          createdAt: start.subtract(const Duration(minutes: 19)),
          state: 'UNNORMAL');
      final b = ExecutionRecords()
        ..now = start
        ..rows = [record];
      final c = AttendanceController(backend: b, clock: () => b.now);
      await c.restore();
      await c.updateSchedule('fixture', [meeting]);
      await c.setEnabled(true);
      await t.pump();
      expect(await c.authorizeExecution(), true);
      final platform = LivePlatform();
      WebViewPlatform.instance = platform;
      var captures = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeAttendanceBackend.channel,
          (call) async {
        if (call.method == 'tabs') {
          return {
            'status': 'ok',
            'liveUrl': 'https://oc.sjtu.edu.cn/courses/91/external_tools/777'
          };
        }
        if (call.method == 'captureQr') {
          captures++;
          return 'https://mlearning.sjtu.edu.cn/lms/mobile2/forscan/?courseCode=course&signHistoryId=task&rollCallToken=fresh&fromType=scanRollCall';
        }
        return null;
      });
      final app = AppController(QuietNotifications(),
          database: MemoryDatabase(), attendance: c);
      Widget page(Brightness value) => MaterialApp(
          theme: ThemeData(brightness: value),
          home: AttendanceWebPage(app: app, meeting: meeting, execute: true));
      await t.pumpWidget(page(brightness));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(c.phase, AttendancePhase.waitingLive);
      b.now = start.add(const Duration(minutes: 3));
      await t.pump(const Duration(minutes: 3));
      expect(c.executing, true);
      expect(captures, 0);
      expect(b.attempts, 0);
      await t.pumpWidget(page(
          brightness == Brightness.light ? Brightness.dark : Brightness.light));
      await t.pump();
      expect(find.text('刷新直播'), findsOneWidget);
      await platform.live.navigate('https://v.sjtu.edu.cn/play/fixture');
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('刷新直播'));
      await t.pump();
      expect(platform.live.refreshes, 1);
      platform.live.playing = true;
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(captures, 1);
      expect(b.attempts, 1);
      expect(c.phase, AttendancePhase.succeeded);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await c.setEnabled(false);
      app.dispose();
      messenger.setMockMethodCallHandler(NativeAttendanceBackend.channel, null);
    });
  }
}
