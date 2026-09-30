import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/pages/home_page.dart';

void main() {
  final current = Course.fromMap({
    'name': '刑事程序法',
    'weekday': 1,
    'startPeriod': 3,
    'endPeriod': 4,
  });
  final later = Course.fromMap({
    'name': '企业法',
    'weekday': 1,
    'startPeriod': 7,
    'endPeriod': 8,
  });

  test('featured course reports an ongoing class before the next class', () {
    final featured = featuredCourseAt(
      [current, later],
      DateTime(2026, 9, 21, 10, 30),
    );

    expect(featured.course?.name, '刑事程序法');
    expect(featured.isInClass, isTrue);
  });

  test('featured course reports the next class between lessons', () {
    final featured = featuredCourseAt(
      [current, later],
      DateTime(2026, 9, 21, 12),
    );

    expect(featured.course?.name, '企业法');
    expect(featured.isInClass, isFalse);
  });
}
