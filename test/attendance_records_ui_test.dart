import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/pages/attendance_status_page.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'attendance_records_test.dart' show RecordBackend;
import 'attendance_record_execution_test.dart' show ExecutionRecords;
import 'attendance_test.dart' show fixtureCourse;
import 'support/memory_database.dart';
import 'week_display_mode_test.dart' show QuietNotifications;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    testWidgets(
        'early unsigned record has a consent entry across theme switching in $brightness',
        (tester) async {
      final time = DateTime.utc(2026, 10, 26, 1, 55); // Monday, Shanghai 09:55
      final course = fixtureCourse(
          start: 600, end: 705, weeks: List.generate(18, (i) => i + 1));
      final meeting = AttendanceMeeting(
          course: course,
          start: DateTime.utc(2026, 10, 26, 2),
          end: DateTime.utc(2026, 10, 26, 3, 45));
      final backend = ExecutionRecords()
        ..now = time
        ..rows = [
          AttendanceRecord(
              key: '91:early',
              canvasId: '91',
              createdAt: DateTime.utc(2026, 10, 26, 1, 41),
              state: 'UNNORMAL')
        ];
      final attendance =
          AttendanceController(backend: backend, clock: () => backend.now);
      final app = AppController(QuietNotifications(),
          database: MemoryDatabase(), attendance: attendance)
        ..termStart = DateTime(2026, 10, 26)
        ..totalWeeks = 18
        ..courses = [course];
      await attendance.restore();
      await attendance.updateSchedule('fixture', [meeting]);
      await attendance.setEnabled(true);
      await tester.pump();
      // Simulate dismissing a real earlier reminder; the explicit entry remains.
      await attendance.recordDisplayed('91:early');
      attendance.dismissRecord();
      Widget page(Brightness value) => MaterialApp(
          theme: ThemeData(brightness: value),
          home: AttendanceStatusPage(app: app));
      await tester.pumpWidget(page(brightness));
      await tester.pumpAndSettle();
      expect(find.textContaining('可执行签到，进入直播后等待'), findsWidgets);
      final entry = find.text('执行签到／重新尝试');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('未开播时等待'), findsOneWidget);
      expect(backend.attempts, 0);
      await tester.pumpWidget(page(
          brightness == Brightness.light ? Brightness.dark : Brightness.light));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('暂不执行'));
      await tester.pumpAndSettle();
      expect(attendance.executing, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await attendance.setEnabled(false);
      app.dispose();
    });
    testWidgets('manual latest record and refresh adapt to $brightness',
        (tester) async {
      final backend = RecordBackend()
        ..rows = [
          AttendanceRecord(
              key: '91:latest',
              canvasId: '91',
              createdAt: DateTime.utc(2026, 10, 20, 23, 51, 10),
              state: 'NORMAL')
        ];
      final attendance =
          AttendanceController(backend: backend, clock: () => backend.now);
      final app = AppController(QuietNotifications(),
          database: MemoryDatabase(), attendance: attendance);
      app.termStart =
          DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
      app.totalWeeks = 18;
      app.courses = [fixtureCourse(weeks: List.generate(18, (i) => i + 1))];
      await attendance.restore();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: AttendanceStatusPage(app: app)));
      await tester.pumpAndSettle();
      expect(find.text('最近一次签到：10月21日07:51，已签到'), findsWidgets);
      expect(backend.reads, 1);
      final refresh = find.text('重新检测');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(backend.reads, 2);
      expect(backend.submits, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    });
  }
}
