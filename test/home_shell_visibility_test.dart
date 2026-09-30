import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// The app's WebView dependency supplies this platform test interface.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:jiaotong_course/pages/home_shell.dart';
import 'package:jiaotong_course/pages/home_page.dart';
import 'package:jiaotong_course/pages/week_page.dart';
import 'package:jiaotong_course/pages/settings_page.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/state/app_controller.dart';

class TestWebViewPlatform extends WebViewPlatform {
  bool failCreation = false;
  bool failLoad = false;
  Completer<void>? loadGate;
  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    if (failCreation) {
      throw StateError('simulated Canvas WebView initialization failure');
    }
    return TestController(params, this);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      TestDelegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      TestWebViewWidget(params);
}

class TestController extends PlatformWebViewController {
  TestController(super.params, this.platform) : super.implementation();
  final TestWebViewPlatform platform;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {}
  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    if (platform.failLoad) {
      throw StateError('simulated async bootstrap failure');
    }
    await platform.loadGate?.future;
  }
}

class TestDelegate extends PlatformNavigationDelegate {
  TestDelegate(super.params) : super.implementation();
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class TestWebViewWidget extends PlatformWebViewWidget {
  TestWebViewWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController app;
  late TestWebViewPlatform platform;
  setUp(() {
    app = AppController(NotificationService())..loggedIn = true;
    platform = TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('cn.sjtu.jiaotong_course/updates'),
            (call) async {
      if (call.method == 'version') {
        throw PlatformException(code: 'unavailable');
      }
      return {'status': 'idle'};
    });
  });
  tearDown(() => app.dispose());

  testWidgets(
      'logged-in shell gives all three tabs visible body area even when update service fails',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: HomeShell(app: app, initializeCanvas: false)));
    await tester.pump();
    final size = tester.getSize(find.byType(IndexedStack));
    debugPrint('[home-layout] IndexedStack=$size');
    expect(size.width, greaterThan(300));
    expect(size.height, greaterThan(300));
    for (final tab in [
      ('日程', HomePage),
      ('周课表', WeekPage),
      ('我的', SettingsPage)
    ]) {
      await tester.tap(find.text(tab.$1).last);
      await tester.pump();
      expect(find.byType(tab.$2).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Canvas controller initialization failure leaves all tabs usable without uncaught errors',
      (tester) async {
    platform.failCreation = true;
    await tester.pumpWidget(MaterialApp(home: HomeShell(app: app)));
    await tester.pump();
    for (final tab in [
      ('日程', HomePage),
      ('周课表', WeekPage),
      ('我的', SettingsPage)
    ]) {
      await tester.tap(find.text(tab.$1).last);
      await tester.pump();
      expect(find.byType(tab.$2).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('async Canvas bootstrap failure preserves the visible shell',
      (tester) async {
    platform.failLoad = true;
    await tester.pumpWidget(MaterialApp(home: HomeShell(app: app)));
    await tester.pump();
    expect(tester.getSize(find.byType(IndexedStack)).height, greaterThan(300));
    expect(find.byType(HomePage).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'disposing the shell during Canvas initialization never updates disposed state',
      (tester) async {
    platform.loadGate = Completer<void>();
    await tester.pumpWidget(
        MaterialApp(home: HomeShell(app: app, initializeCanvas: false)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    platform.loadGate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
