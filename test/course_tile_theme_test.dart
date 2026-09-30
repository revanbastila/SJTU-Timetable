import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/widgets/course_tile.dart';

void main() {
  testWidgets('highlighted course card follows the selected theme color',
      (tester) async {
    final course = Course.fromMap({
      'name': '刑事程序法',
      'teacher': '孙长永',
      'location': '教一楼300',
      'weekday': 1,
      'startPeriod': 3,
      'endPeriod': 4,
    });

    Future<(Color, Color, Color)> render(Color primary) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          colorScheme:
              ColorScheme.fromSeed(seedColor: primary, primary: primary),
        ),
        home: Scaffold(
          body: CourseTile(course: course, highlight: true),
        ),
      ));
      await tester.pumpAndSettle();
      final decorated = tester
          .widgetList<Container>(find.byType(Container))
          .map((item) => item.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((item) => item.border != null);
      final dot = tester
          .widgetList<Container>(find.byType(Container))
          .map((item) => item.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((item) => item.shape == BoxShape.circle);
      return (
        decorated.color!,
        (decorated.border! as Border).top.color,
        dot.color!,
      );
    }

    const blue = Color(0xFF315F86);
    const violet = Color(0xFF6D6382);
    final blueColors = await render(blue);
    final violetColors = await render(violet);

    expect(violetColors.$1, isNot(blueColors.$1));
    expect(violetColors.$2, isNot(blueColors.$2));
    expect(violetColors.$3, violet);
    expect(blueColors.$3, blue);
    expect(HSLColor.fromColor(violetColors.$1).lightness, greaterThan(.9));
  });

  testWidgets('regular course metadata and border follow the selected theme',
      (tester) async {
    final course = Course.fromMap({
      'name': '刑事程序法',
      'teacher': '孙长永',
      'location': '教一楼300',
      'weekday': 1,
      'startPeriod': 3,
      'endPeriod': 4,
    });

    Future<(Color, Color, Color, Color)> render(Color primary) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          colorScheme:
              ColorScheme.fromSeed(seedColor: primary, primary: primary),
          appBarTheme: AppBarTheme(foregroundColor: primary),
        ),
        home: Scaffold(body: CourseTile(course: course)),
      ));
      await tester.pumpAndSettle();
      final decorated = tester
          .widgetList<Container>(find.byType(Container))
          .map((item) => item.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((item) => item.border != null);
      return (
        tester.widget<Text>(find.text('10:00')).style!.color!,
        tester.widget<Text>(find.text('教一楼300')).style!.color!,
        tester.widget<Text>(find.text('孙长永')).style!.color!,
        (decorated.border! as Border).top.color,
      );
    }

    const blue = Color(0xFF315F86);
    const violet = Color(0xFF6D6382);
    final blueColors = await render(blue);
    final violetColors = await render(violet);
    expect(violetColors.$1, violet);
    expect(violetColors.$2, violet);
    expect(violetColors.$3, violet);
    expect(violetColors.$4, isNot(blueColors.$4));
  });
}
