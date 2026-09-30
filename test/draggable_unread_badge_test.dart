import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/widgets/draggable_unread_badge.dart';

void main() {
  testWidgets('badge follows drag and springs back below the threshold', (
    tester,
  ) async {
    var dismissals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DraggableUnreadBadge(
              count: 3,
              onDismiss: () async => dismissals++,
              child: const Icon(Icons.today),
            ),
          ),
        ),
      ),
    );
    final badge = find.text('3');
    final origin = tester.getCenter(badge);
    final dot = tester.widget<SizedBox>(
      find.ancestor(of: badge, matching: find.byType(SizedBox)).first,
    );
    expect(dot.width, 18);
    expect(dot.height, 18);
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(23, 0));
    await gesture.moveBy(const Offset(-15, 0));
    await tester.pump();
    expect(tester.getCenter(badge).dx, greaterThan(origin.dx + 5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getCenter(badge).dx, closeTo(origin.dx, 1));
    expect(dismissals, 0);
  });

  testWidgets('burst finishes before marking read and both badges update', (
    tester,
  ) async {
    final count = ValueNotifier<int>(3);
    var dismissals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: count,
            builder: (context, value, _) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var index = 0; index < 2; index++)
                  DraggableUnreadBadge(
                    count: value,
                    onDismiss: () async {
                      dismissals++;
                      count.value = 0;
                    },
                    child: const Icon(Icons.today),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final badge = find.text('3').first;
    final origin = tester.getCenter(badge);
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(64, 0));
    await tester.pump();
    expect(tester.getCenter(badge).dx, greaterThan(origin.dx + 50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(dismissals, 0);
    await tester.pumpAndSettle();
    expect(dismissals, 1);
    expect(find.text('3'), findsNothing);
    count.dispose();
  });

  testWidgets('short vertical drag bursts and clears both unread counts', (
    tester,
  ) async {
    final count = ValueNotifier<int>(2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: count,
            builder: (_, value, __) => Row(
              children: [
                for (var i = 0; i < 2; i++)
                  DraggableUnreadBadge(
                    count: value,
                    onDismiss: () async => count.value = 0,
                    child: const Icon(Icons.today),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final badge = find.text('2').first;
    final origin = tester.getCenter(badge);
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    expect(tester.getCenter(badge).dy, greaterThan(origin.dy + 18));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(count.value, 0);
    expect(find.text('2'), findsNothing);
    count.dispose();
  });

  testWidgets(
    'message tab badge stays inside the tab bar and remains draggable',
    (tester) async {
      var count = 2;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultTabController(
              length: 2,
              child: TabBar(
                tabs: [
                  const Tab(text: '今日课程'),
                  Tab(
                    child: Center(
                      child: DraggableUnreadBadge(
                        count: count,
                        onDismiss: () async {
                          count = 0;
                        },
                        badgeTop: 2,
                        badgeRight: 0,
                        child: const SizedBox(
                          width: 76,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.only(right: 36),
                            child: Center(child: Text('消息')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final tab = tester.getRect(find.byType(TabBar));
      final badge = find.text('2');
      final badgeRect = tester.getRect(badge);
      expect(tab.contains(badgeRect.center), isTrue);
      expect(badgeRect.top, greaterThanOrEqualTo(tab.top));
      final gesture = await tester.startGesture(badgeRect.center);
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-44, 0));
      await tester.pump();
      expect(
        tester.getCenter(badge).dx,
        lessThanOrEqualTo(badgeRect.center.dx - 40),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(count, 0);
    },
  );
}
