import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/services/message_feed.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String legacyHash(String key) {
    var hash = 0xcbf29ce484222325;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  test('cached read item migrates while a later reused ID stays unread',
      () async {
    SharedPreferences.setMockInitialValues({
      'username': 'migration-test',
      'readCanvasMessages_migration-test': [legacyHash('canvas:reused')],
    });
    const earlier = CanvasItem(
      id: 'reused',
      title: '旧消息',
      messageHtml: '',
      type: '通知',
      courseName: '课程一',
      createdAt: '2026-09-20T08:00:00Z',
      htmlUrl: '',
    );
    const later = CanvasItem(
      id: 'reused',
      title: '新消息',
      messageHtml: '',
      type: '通知',
      courseName: '课程一',
      createdAt: '2026-09-21T08:00:00Z',
      htmlUrl: '',
    );
    final oldSnapshot = CanvasSnapshot(
        dashboardItems: const [earlier],
        courses: const [],
        syncedAt: DateTime(2026, 9, 20));
    final app = AppController(NotificationService())
      ..canvas = oldSnapshot
      ..courses = [];
    await app.bootstrap();
    expect(app.unreadMessageCount, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('readCanvasMessagesV2_migration-test'), isTrue);

    var notifications = 0;
    app.addListener(() => notifications++);
    final updated = CanvasSnapshot(
        dashboardItems: const [earlier, later],
        courses: const [],
        syncedAt: DateTime(2026, 9, 21));
    await app.saveSyncedData('migration-test', [], updated);
    expect(app.unreadMessageCount, 1);
    expect(notifications, greaterThan(0));
    final latest = buildMessageFeed(app.canvas, app.courses).first;
    await app.markMessageRead(latest.key);
    expect(app.unreadMessageCount, 0);

    final restarted = AppController(NotificationService())
      ..canvas = updated
      ..courses = [];
    await restarted.bootstrap();
    expect(restarted.unreadMessageCount, 0);
    app.dispose();
    restarted.dispose();
  });

  test('swipe read state updates the shared count and persists', () async {
    SharedPreferences.setMockInitialValues({'username': 'message-test'});
    const items = [
      CanvasItem(
        id: '1',
        title: '通知一',
        messageHtml: '',
        type: '公告',
        courseName: '课程甲',
        createdAt: '2026-09-20T08:00:00Z',
        htmlUrl: '',
      ),
      CanvasItem(
        id: '2',
        title: '通知二',
        messageHtml: '',
        type: '通知',
        courseName: '课程乙',
        createdAt: '2026-09-20T09:00:00Z',
        htmlUrl: '',
      ),
    ];
    AppController controller() => AppController(NotificationService())
      ..username = 'message-test'
      ..courses = []
      ..canvas = CanvasSnapshot(
        dashboardItems: items,
        courses: const [],
        syncedAt: DateTime(2026, 9, 20),
      );

    final app = controller();
    final feed = buildMessageFeed(app.canvas, app.courses);
    expect(app.unreadMessageCount, 2);
    await app.markMessageRead(feed.first.key);
    expect(app.unreadMessageCount, 1);
    await app.markAllMessagesRead();
    expect(app.unreadMessageCount, 0);
    await app.markAllMessagesRead();

    // A later Canvas sync must count only genuinely new messages.
    app.canvas = CanvasSnapshot(
      dashboardItems: [
        ...items,
        const CanvasItem(
          id: '3',
          title: '新通知',
          messageHtml: '',
          type: '通知',
          courseName: '课程乙',
          createdAt: '2026-09-21T09:00:00Z',
          htmlUrl: '',
        ),
      ],
      courses: const [],
      syncedAt: DateTime(2026, 9, 21),
    );
    expect(app.unreadMessageCount, 1);
    await app
        .markMessageRead(buildMessageFeed(app.canvas, app.courses).first.key);
    expect(app.unreadMessageCount, 0);

    final restarted = controller();
    // Bootstrap restores the same hashed read IDs from preferences.
    await restarted.bootstrap();
    restarted.canvas = app.canvas;
    restarted.courses = [];
    expect(restarted.unreadMessageCount, 0);
    app.dispose();
    restarted.dispose();
  });
}
