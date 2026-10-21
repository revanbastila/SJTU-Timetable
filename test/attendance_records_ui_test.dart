import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/pages/attendance_status_page.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'attendance_records_test.dart' show RecordBackend;
import 'attendance_test.dart' show fixtureCourse;
import 'support/memory_database.dart';
import 'week_display_mode_test.dart' show QuietNotifications;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
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
