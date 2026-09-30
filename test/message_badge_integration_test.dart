import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/pages/home_page.dart';
import 'package:jiaotong_course/services/message_feed.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('message tab follows Canvas arrivals and read state',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const item = CanvasItem(
      id: 'notice-1',
      title: '新的课程通知',
      messageHtml: '',
      type: '通知',
      courseName: '课程一',
      createdAt: '2026-09-24T08:00:00Z',
      htmlUrl: '',
    );
    final app = AppController(NotificationService())
      ..username = 'badge-ui'
      ..loggedIn = true
      ..courses = [];
    await tester.pumpWidget(MaterialApp(home: HomePage(app: app)));
    expect(find.text('1'), findsNothing);

    app.canvas = CanvasSnapshot(
      dashboardItems: const [item],
      courses: const [],
      syncedAt: DateTime(2026, 9, 24),
    );
    app.updateCanvasSyncProgress(CanvasSyncStage.details, '测试消息到达');
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    final key = buildMessageFeed(app.canvas, app.courses).single.key;
    await app.markMessageRead(key);
    await tester.pump();
    expect(find.text('1'), findsNothing);
    expect(app.unreadMessageCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}
