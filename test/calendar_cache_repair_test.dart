import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/teaching_calendar.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/services/teaching_calendar_repository.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'teaching_calendar_test.dart' show lesson;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final text = jsonEncode({
    'version': 1,
    'updated_at': '2026-10-01',
    'rules': [
      {'date': '2026-10-01', 'type': 'holiday'},
      {'date': '2026-10-10', 'type': 'makeup', 'use_weekday': 2, 'use_week': 4},
    ]
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('UTC instant and civil date both match October 1 in Shanghai', () {
    final calendar = TeachingCalendar.parse(text);
    expect(calendarDateKey(DateTime.utc(2026, 9, 30, 18)), '2026-10-01');
    expect(calendar.ruleFor(DateTime.utc(2026, 9, 30, 18))?.type, 'holiday');
    expect(calendar.ruleFor(DateTime(2026, 10, 1, 23))?.type, 'holiday');
    expect(calendar.updatedAt, '2026-10-01');
  });
  test('same-version stale cache repairs memory and notifies existing pages',
      () async {
    final old = TeachingCalendar.parse('{"version":1,"rules":[]}');
    SharedPreferences.setMockInitialValues(
        {TeachingCalendarRepository.cacheKey: '{"version":1,"rules":[]}'});
    final app = AppController(NotificationService(),
        calendarRepository: TeachingCalendarRepository(fetch: () async => text))
      ..teachingCalendar = old
      ..termStart = DateTime(2026, 9, 14)
      ..courses = [
        lesson('Thursday', 4, [3, 4]),
        lesson('Tuesday', 2, [4])
      ];
    var notified = 0;
    app.addListener(() => notified++);
    final date = DateTime(2026, 10, 1);
    expect(app.getEffectiveCoursesForDate(date), hasLength(1));
    await app.refreshTeachingCalendar();
    expect(app.teachingCalendar.version, '1');
    expect(app.teachingCalendar.fingerprint, isNot(old.fingerprint));
    expect(app.getEffectiveCoursesForDate(date), isEmpty);
    expect(
        app.effectiveCoursesForWeek(3).where((c) => c.weekday == 4), isEmpty);
    expect(app.getEffectiveCoursesForDate(DateTime(2026, 10, 8)), hasLength(1));
    expect(app.getEffectiveCoursesForDate(DateTime(2026, 10, 10)).single.name,
        'Tuesday');
    expect(notified, 1);
    await app.refreshTeachingCalendar();
    expect(notified, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TeachingCalendarRepository.cacheKey), text);
    app.dispose();
  });
}
