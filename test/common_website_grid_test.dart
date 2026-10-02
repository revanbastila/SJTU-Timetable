import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/app_theme.dart';
import 'package:jiaotong_course/pages/authenticated_web_page.dart';
import 'package:jiaotong_course/pages/settings_page.dart';
import 'package:jiaotong_course/services/canvas_extractor.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'package:jiaotong_course/widgets/common_website_grid.dart';

const names = [
  'Canvas教学平台',
  '研究生应用管理平台',
  '图书馆',
  '交大邮箱',
  '交大云盘',
  '校园地图',
  '水源社区',
  '选课社区',
  '传承·交大'
];

// Capture the actual navigation callback's destination without running an
// external school's WebView or asking for campus credentials in unit tests.
class RecordingNavigator extends Navigator {
  const RecordingNavigator({super.key, required super.onGenerateRoute});
  @override
  NavigatorState createState() => RecordingNavigatorState();
}

class RecordingNavigatorState extends NavigatorState {
  final pages = <AuthenticatedWebPage>[];
  @override
  Future<T?> push<T extends Object?>(Route<T> route) async {
    if (route is MaterialPageRoute<T>) {
      final page = route.builder(context);
      if (page is AuthenticatedWebPage) pages.add(page);
    }
    return null;
  }
}

void main() {
  testWidgets(
      'all nine tiles use original destinations and authentication options',
      (tester) async {
    final app = AppController(NotificationService());
    final navigator = GlobalKey<RecordingNavigatorState>();
    await tester.pumpWidget(MaterialApp(
        home: RecordingNavigator(
      key: navigator,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: SettingsPage(app: app))),
    )));
    final urls = [
      canvasSsoUrl,
      graduateSchoolUrl,
      sjtuLibraryUrl,
      sjtuMailUrl,
      sjtuCloudDriveUrl,
      sjtuMapUrl,
      shuiyuanUrl,
      courseCommunityUrl,
      heritageSjtuUrl
    ];
    final hosts = [
      'oc.sjtu.edu.cn',
      'yjs.sjtu.edu.cn',
      'www.lib.sjtu.edu.cn',
      'mail.sjtu.edu.cn',
      'pan.sjtu.edu.cn',
      'map.sjtu.edu.cn',
      'shuiyuan.sjtu.edu.cn',
      'course.sjtu.plus',
      'share.dyweb.sjtu.cn'
    ];
    for (var i = 0; i < names.length; i++) {
      final tile = find.byKey(ValueKey('website-grid-tile-$i'));
      expect(find.descendant(of: tile, matching: find.text(names[i])),
          findsOneWidget);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final page = navigator.currentState!.pages.last;
      expect(page.title, names[i]);
      expect(page.initialUrl, urls[i]);
      expect(page.targetHost, hosts[i]);
      expect(page.app, same(app));
      expect(page.showCloseButton, true);
      expect(page.webHistory, true);
      expect(page.authenticationRequired, ![5, 7].contains(i));
      expect(page.preferSsoLogin, [1, 3, 4, 6, 8].contains(i));
      expect(page.canvasSite, i == 0);
      expect(page.ssoFallbackUrl, i == 0 ? canvasSsoUrl : '');
      expect(page.librarySite, i == 2);
      expect(page.mailSite, i == 3);
      expect(page.allowHttpTarget, [2, 3].contains(i));
      expect(page.enableGeolocation, i == 5);
      expect(tester.takeException(), isNull);
    }
    expect(navigator.currentState!.pages.length, 9);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets(
      'three columns, correct order, wrapped labels and all themes at narrow widths',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in [320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 1000);
      for (final choice in AppThemeChoice.values) {
        for (final brightness in Brightness.values) {
          final scheme = ColorScheme.fromSeed(
              seedColor: choice.primaryFor(brightness), brightness: brightness);
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: MediaQuery(
                data: MediaQueryData(
                    size: Size(width, 1000),
                    textScaler: TextScaler.linear(1.5)),
                child: Scaffold(
                    body: SingleChildScrollView(
                        child: Padding(
                  padding: const EdgeInsets.all(44),
                  child: CommonWebsiteGrid(tiles: [
                    for (final name in names)
                      ListTile(
                          leading: const Icon(Icons.language, size: 38),
                          title: Text(name),
                          onTap: () {}),
                  ]),
                )))),
          ));
          await tester.pumpAndSettle();
          for (var i = 0; i < names.length; i++) {
            final tile = find.byKey(ValueKey('website-grid-tile-$i'));
            final rect = tester.getRect(tile);
            final labelRect = tester.getRect(find.text(names[i]));
            expect(rect.contains(labelRect.topLeft), true);
            expect(
                rect.contains(labelRect.bottomRight - const Offset(.01, .01)),
                true);
            final label = tester.widget<Text>(find.text(names[i]));
            expect(label.maxLines, isNull);
            expect(label.overflow, isNull);
            expect(tester.widget<Material>(tile).color,
                scheme.surfaceContainerLow);
            if (i % 3 > 0) {
              final previous = tester
                  .getRect(find.byKey(ValueKey('website-grid-tile-${i - 1}')));
              expect(rect.top, previous.top);
              expect(rect.height, previous.height);
              expect(rect.left, greaterThan(previous.right));
            } else if (i > 0) {
              final previousRow = tester
                  .getRect(find.byKey(ValueKey('website-grid-tile-${i - 3}')));
              expect(rect.left, previousRow.left);
              expect(rect.top, greaterThan(previousRow.bottom));
            }
          }
          expect(tester.takeException(), isNull,
              reason: '${choice.name} $brightness width=$width');
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
