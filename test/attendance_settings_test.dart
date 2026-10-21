import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/app_theme.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/pages/settings_page.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';
import 'package:jiaotong_course/widgets/attendance_observer.dart';
import 'attendance_test.dart' show FakeAttendanceBackend, fixtureCourse;
import 'support/memory_database.dart';
import 'week_display_mode_test.dart' show QuietNotifications;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('cn.sjtu.jiaotong_course/attendance'),
            (call) async =>
                call.method == 'notificationPermission' ? false : null);
  });
  testWidgets(
      'switch is above About, persists and reports denied notifications',
      (tester) async {
    final app = AppController(QuietNotifications(), database: MemoryDatabase());
    await app.attendance.restore();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SettingsPage(app: app, advanced: true))));
    await tester.scrollUntilVisible(
        find.byKey(const Key('auto-attendance-settings')), 350);
    await tester.scrollUntilVisible(find.text('关于'), 150);
    expect(
        tester.getTopLeft(find.byKey(const Key('auto-attendance-settings'))).dy,
        lessThan(tester.getTopLeft(find.text('关于')).dy));
    final toggle = find.byType(Switch);
    await tester.ensureVisible(toggle);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
        (await SharedPreferences.getInstance())
            .getBool('autoAttendanceEnabled'),
        isTrue);
    expect(app.attendance.detail, contains('通知未开启'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(app.attendance.phase, AttendancePhase.off);
    expect(
        (await SharedPreferences.getInstance())
            .getBool('autoAttendanceEnabled'),
        isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
  testWidgets('all six themes adapt light/dark without changing switch state',
      (tester) async {
    final app = AppController(QuietNotifications(), database: MemoryDatabase());
    await app.attendance.restore();
    for (final choice in AppThemeChoice.values) {
      app.themeChoice = choice;
      for (final brightness in Brightness.values) {
        final theme = ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: choice.primaryFor(brightness),
                brightness: brightness));
        await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Scaffold(body: SettingsPage(app: app, advanced: true))));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
            find.byKey(const Key('auto-attendance-settings')), 350);
        final toggle = find.byType(Switch);
        await tester.ensureVisible(toggle);
        expect(tester.widget<Switch>(toggle).value, isFalse);
        expect(Theme.of(tester.element(toggle)).brightness, brightness);
        expect(Theme.of(tester.element(toggle)).colorScheme.primary,
            theme.colorScheme.primary);
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
  testWidgets(
      'foreground consent has two actions and closes when feature disabled',
      (tester) async {
    final now = DateTime.utc(2030, 1, 7, 0, 15);
    final meeting = AttendanceMeeting(
        course: fixtureCourse(),
        start: DateTime.utc(2030, 1, 7),
        end: DateTime.utc(2030, 1, 7, 1));
    final backend = FakeAttendanceBackend()
      ..tasks = [
        AttendanceTask(
            id: 'task-1',
            canvasId: '91',
            courseCode: 'bound-course',
            createdAt: DateTime.utc(2030, 1, 7, 0, 5),
            state: 'UNNORMAL',
            serverActive: true)
      ];
    final c = AttendanceController(backend: backend, clock: () => now);
    final app = AppController(QuietNotifications(),
        database: MemoryDatabase(), attendance: c);
    await c.restore();
    await c.updateSchedule('fixture-account', [meeting]);
    await c.setEnabled(true);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: FilledButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => AttendanceConsentDialog(app: app)),
                    child: const Text('show'))))));
    await tester.pump();
    expect(identical(app.attendance,c),isTrue);
    expect(c.phase,AttendancePhase.pending);
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.text('发现课程签到'), findsOneWidget);
    expect(find.text('执行签到'), findsOneWidget);
    expect(find.text('暂不执行'), findsOneWidget);
    expect(backend.submits, 0);
    await c.setEnabled(false);
    expect(c.phase,AttendancePhase.off);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(backend.submits, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}
