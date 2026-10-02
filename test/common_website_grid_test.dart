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
  '图书馆',
  '交大邮箱',
  '交大云盘',
  '校园地图',
  '水源社区',
  '选课社区',
  '传承·交大',
  '研究生应用管理平台'
];

String shortcutName(int index) => index == 0
    ? 'Canvas'
    : names[index] == '传承·交大'
        ? '传承交大'
        : names[index];

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
      if (page is AuthenticatedWebPage) {
        pages.add(page);
        return null;
      }
    }
    return super.push(route);
  }
}

void main() {
  testWidgets(
      'section baselines, compact website header and balanced bottom inset',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1200);
    final app = AppController(NotificationService())
      ..studentName = '测试姓名'
      ..studentNumber = '123456789012'
      ..studentCollege = '测试学院';
    for (final advanced in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SettingsPage(app: app, advanced: advanced))));
      await tester.pumpAndSettle();
      final sections = advanced
          ? ['我的账号', '数据同步', '应用外观', '上课提醒', '关于']
          : ['我的信息', '常用网站', '设置'];
      for (final name in sections) {
        final surface = find.byKey(ValueKey('setting-surface-$name'));
        await tester.ensureVisible(surface);
        await tester.pumpAndSettle();
        final rect = tester.getRect(surface);
        final heading =
            tester.getRect(find.byKey(ValueKey('setting-heading-$name')));
        expect(heading.left - rect.left, closeTo(12, .01), reason: name);
        final icons = find.descendant(of: surface, matching: find.byType(Icon));
        if (name != '常用网站' && name != '关于') {
          expect(tester.getRect(icons.first).left - rect.left, closeTo(12, .01),
              reason: name);
        }
        if (name == '我的信息') {
          final divider = tester.getRect(
              find.descendant(of: surface, matching: find.byType(Divider)));
          expect(rect.right - divider.right, closeTo(8, .01));
        }
        if (name == '常用网站') {
          final first =
              tester.getRect(find.byKey(const ValueKey('website-grid-tile-0')));
          final last =
              tester.getRect(find.byKey(const ValueKey('website-grid-tile-7')));
          expect(first.left - rect.left, closeTo(12, .01));
          expect(rect.right - last.right, closeTo(12, .01));
          expect(rect.bottom - last.bottom, closeTo(12, .01));
          final title = find.text('常用网站');
          final titleRect = tester.getRect(title);
          expect(titleRect.top - rect.top, inInclusiveRange(14, 19));
          expect(first.top - titleRect.bottom, inInclusiveRange(14, 19));
          final more = find.text('更多 >');
          final titleBox = tester.renderObject<RenderBox>(title);
          final moreBox = tester.renderObject<RenderBox>(more);
          expect(
              titleRect.top +
                  titleBox.getDryBaseline(
                      titleBox.constraints, TextBaseline.alphabetic)!,
              closeTo(
                  tester.getRect(more).top +
                      moreBox.getDryBaseline(
                          moreBox.constraints, TextBaseline.alphabetic)!,
                  .01));
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets('all shortcut glyphs grow 1.1 with tracking at 0.9',
      (tester) async {
    // Four-character samples avoid Ahem's unusually wide Latin glyphs.
    final samples = ['教学平台', '校园图书', ...names.skip(2).take(6)];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DefaultTextStyle(
      style: const TextStyle(fontSize: 14, letterSpacing: 1),
      child: Center(
          child: SizedBox(
              width: 300,
              child: CommonWebsiteGrid(tiles: [
                for (final name in samples)
                  ListTile(
                      title: Text(name), leading: const Icon(Icons.language)),
              ]))),
    ))));
    final side = (300.0 - 18) / 4;
    for (var i = 0; i < 8; i++) {
      final labelFinder = find.descendant(
          of: find.byKey(ValueKey('website-grid-tile-$i')),
          matching: find.byType(Text));
      final text = tester.widget<Text>(labelFinder);
      expect(text.style!.fontSize, closeTo(side / 5.6 * 1.1, .01));
      expect(text.style!.letterSpacing, closeTo(.9, .01));
      expect(text.style!.fontWeight, FontWeight.w400);
      final tile = tester.getRect(find.byKey(ValueKey('website-grid-tile-$i')));
      final label = tester.getRect(labelFinder);
      expect(label.center.dx, closeTo(tile.center.dx, .01));
      final slot = tester.getRect(find.byKey(ValueKey('website-icon-slot-$i')));
      final oldLabelCenterY = (slot.bottom + 4 + tile.bottom - 4) / 2;
      expect(label.center.dy, closeTo(oldLabelCenterY, .01));
    }
  });

  testWidgets('temporary title toggle changes only shortcut label colors',
      (tester) async {
    final app = AppController(NotificationService());
    final scheme = ColorScheme.fromSeed(seedColor: Colors.red);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: Scaffold(body: SettingsPage(app: app))));
    final title = find.text('常用网站');
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    final label = find.text('传承交大');
    final original = tester.widget<Text>(label).style!;
    final originalRect = tester.getRect(label);
    final icon = tester.getRect(find.byKey(const ValueKey('website-icon-0')));
    for (final themeColor in [true, false]) {
      await tester.tap(title);
      await tester.pump();
      final style = tester.widget<Text>(label).style!;
      expect(style.color, themeColor ? scheme.primary : scheme.onSurface);
      expect(style.fontSize, original.fontSize);
      expect(style.fontWeight, original.fontWeight);
      expect(tester.getRect(label), originalRect);
      expect(
          tester.getRect(find.byKey(const ValueKey('website-icon-0'))), icon);
      expect(tester.widget<Text>(title).style!.color, scheme.primary);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
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
      sjtuLibraryUrl,
      sjtuMailUrl,
      sjtuCloudDriveUrl,
      sjtuMapUrl,
      shuiyuanUrl,
      courseCommunityUrl,
      heritageSjtuUrl,
      graduateSchoolUrl
    ];
    final hosts = [
      'oc.sjtu.edu.cn',
      'www.lib.sjtu.edu.cn',
      'mail.sjtu.edu.cn',
      'pan.sjtu.edu.cn',
      'map.sjtu.edu.cn',
      'shuiyuan.sjtu.edu.cn',
      'course.sjtu.plus',
      'share.dyweb.sjtu.cn',
      'yjs.sjtu.edu.cn'
    ];
    for (var i = 0; i < 8; i++) {
      final tile = find.byKey(ValueKey('website-grid-tile-$i'));
      expect(find.descendant(of: tile, matching: find.text(shortcutName(i))),
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
      expect(page.authenticationRequired, ![4, 6].contains(i));
      expect(page.preferSsoLogin, [2, 3, 5, 7, 8].contains(i));
      expect(page.canvasSite, i == 0);
      expect(page.ssoFallbackUrl, i == 0 ? canvasSsoUrl : '');
      expect(page.librarySite, i == 1);
      expect(page.mailSite, i == 2);
      expect(page.allowHttpTarget, [1, 2].contains(i));
      expect(page.enableGeolocation, i == 4);
      expect(tester.takeException(), isNull);
    }
    expect(navigator.currentState!.pages.length, 8);
    expect(find.text(names[8]), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('website-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('website-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('website-full-list')), findsOneWidget);
    final listNames = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(listNames, names);
    for (var i = 0; i < names.length; i++) {
      final row = find.ancestor(
          of: find.text(names[i]), matching: find.byType(ListTile));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      final page = navigator.currentState!.pages.last;
      expect(page.title, names[i]);
      expect(page.initialUrl, urls[i]);
      expect(page.targetHost, hosts[i]);
      expect(page.showCloseButton, true);
      expect(page.authenticationRequired, ![4, 6].contains(i));
      expect(page.preferSsoLogin, [2, 3, 5, 7, 8].contains(i));
      expect(page.canvasSite, i == 0);
      expect(page.librarySite, i == 1);
      expect(page.mailSite, i == 2);
      expect(page.allowHttpTarget, [1, 2].contains(i));
      expect(page.enableGeolocation, i == 4);
    }
    expect(navigator.currentState!.pages.length, 17);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets(
      'eight squares in four columns, normal labels, future entries excluded and all themes',
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
                    for (final name in [...names, '未来网站10', '未来网站11'])
                      ListTile(
                          leading: const Icon(Icons.language, size: 38),
                          title: Text(name),
                          onTap: () {}),
                  ]),
                )))),
          ));
          await tester.pumpAndSettle();
          expect(find.text(names[8]), findsNothing);
          expect(find.text('未来网站10'), findsNothing);
          expect(
              find.byKey(const ValueKey('website-grid-tile-8')), findsNothing);
          for (var i = 0; i < 8; i++) {
            final tile = find.byKey(ValueKey('website-grid-tile-$i'));
            final rect = tester.getRect(tile);
            expect(rect.width, closeTo(rect.height, .01));
            final labelFinder = find.text(shortcutName(i));
            final labelRect = tester.getRect(labelFinder);
            expect(rect.contains(labelRect.topLeft), true);
            expect(
                rect.contains(labelRect.bottomRight - const Offset(.01, .01)),
                true);
            final label = tester.widget<Text>(labelFinder);
            expect(label.maxLines, 1);
            expect(label.softWrap, false);
            final slot =
                tester.getRect(find.byKey(ValueKey('website-icon-slot-$i')));
            final glyph =
                tester.getRect(find.byKey(ValueKey('website-icon-$i')));
            expect((glyph.center - slot.center).distance, lessThan(.01));
            expect(glyph.width, closeTo(slot.width * 21 / 38 * 2, .01));
            expect(rect.deflate(3).contains(glyph.topLeft), true);
            expect(rect.deflate(3).contains(glyph.bottomRight), true);
            expect(
                tester
                    .widget<Icon>(find.byKey(ValueKey('website-icon-$i')))
                    .color,
                scheme.primary);
            expect(label.overflow, isNull);
            expect(label.style?.fontWeight, FontWeight.w400);
            expect(label.style?.fontSize,
                tester.widget<Text>(find.text('Canvas')).style?.fontSize);
            expect(tester.widget<Material>(tile).color,
                scheme.surfaceContainerLow);
            if (i % 4 > 0) {
              final previous = tester
                  .getRect(find.byKey(ValueKey('website-grid-tile-${i - 1}')));
              expect(rect.top, previous.top);
              expect(rect.height, previous.height);
              expect(rect.left, greaterThan(previous.right));
            } else if (i > 0) {
              final previousRow = tester
                  .getRect(find.byKey(ValueKey('website-grid-tile-${i - 4}')));
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
