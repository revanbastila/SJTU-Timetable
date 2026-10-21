import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:jiaotong_course/models/common_website.dart';
import 'package:jiaotong_course/pages/authenticated_web_page.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'package:jiaotong_course/services/school_web_auth.dart';
import 'package:webview_flutter/webview_flutter.dart' as web;
import 'package:shared_preferences/shared_preferences.dart';
import 'support/memory_database.dart';
import 'week_display_mode_test.dart' show QuietNotifications;

class BrowserPlatform extends WebViewPlatform {
  final controllers = <BrowserController>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    final c = BrowserController(params, controllers.length + 1);
    controllers.add(c);
    return c;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      BrowserDelegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      BrowserWidget(params);
}

class BrowserController extends PlatformWebViewController
    implements AndroidWebViewController {
  BrowserController(super.params, this.webViewIdentifier)
      : super.implementation();
  @override
  final int webViewIdentifier;
  late BrowserDelegate delegate;
  String url = '';
  final loads = <String>[];
  final history = <String>[];
  final failedUrls = <String>{};
  int index = -1;
  int ssoChecks = 0;
  final scripts = <String>[];
  bool clickSsoOnContent = false;
  bool loginForm = false;
  String? nativeUrlOverride;
  Completer<Object>? inspectionGate;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {
    delegate = handler as BrowserDelegate;
  }

  @override
  Future<void> setGeolocationEnabled(bool enabled) async {}
  @override
  Future<void> setGeolocationPermissionsPromptCallbacks(
      {Future<GeolocationPermissionsResponse> Function(
              GeolocationPermissionsRequestParams)?
          onShowPrompt,
      void Function()? onHidePrompt}) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loads.add(params.uri.toString());
    debugPrint(
        '[fixture-web] app.loadRequest ${params.uri.host}${params.uri.path}');
    await navigate(params.uri.toString());
  }

  Future<void> navigate(String target,
      {bool finish = false, bool spa = false}) async {
    final decision = await delegate.request
        ?.call(NavigationRequest(url: target, isMainFrame: true));
    if (decision == NavigationDecision.prevent) return;
    url = target;
    if (index + 1 < history.length) {
      history.removeRange(index + 1, history.length);
    }
    history.add(target);
    index++;
    if (!spa) delegate.started?.call(url);
    delegate.changed?.call(UrlChange(url: url));
    if (finish) delegate.finished?.call(url);
  }

  @override
  Future<String?> currentUrl() async => nativeUrlOverride ?? url;
  @override
  Future<void> runJavaScript(String script) async {}
  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    scripts.add(script);
    if (script.contains('hasPassword:')) {
      final gate = inspectionGate;
      if (gate != null) {
        inspectionGate = null;
        return gate.future;
      }
      return jsonEncode(
          {'href': url, 'hasPassword': loginForm, 'hasChallenge': false});
    }
    if (script.contains('const positive') || script.contains('const scored')) {
      ssoChecks++;
      debugPrint(
          '[fixture-web] auto-sso-check ${Uri.parse(url).path} #$ssoChecks');
      if (clickSsoOnContent && Uri.parse(url).path.contains('/t/')) {
        debugPrint('[fixture-web] unexpected SSO click on content -> home');
        unawaited(navigate('${Uri.parse(url).origin}/', finish: true));
        return true;
      }
      return false;
    }
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BrowserDelegate extends PlatformNavigationDelegate {
  BrowserDelegate(super.params) : super.implementation();
  PageEventCallback? started, finished;
  NavigationRequestCallback? request;
  UrlChangeCallback? changed;
  WebResourceErrorCallback? error;
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    started = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback callback) async {
    request = callback;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback callback) async {
    changed = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    error = callback;
  }
}

class BrowserWidget extends PlatformWebViewWidget {
  BrowserWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Colors.transparent, child: SizedBox.expand());
}

void main() {
  late BrowserPlatform platform;
  late AppController app;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platform = BrowserPlatform();
    WebViewPlatform.instance = platform;
    app = AppController(QuietNotifications(), database: MemoryDatabase());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('cn.sjtu.jiaotong_course/web_history'),
            (call) async {
      final args = call.arguments as Map;
      final c = platform.controllers
          .firstWhere((c) => c.webViewIdentifier == args['webViewIdentifier']);
      if (call.method == 'stopAndSnapshot') {
        return {'currentIndex': c.index, 'urls': c.history};
      }
      if (call.method == 'goBackTo') {
        c.index = c.history.lastIndexOf(args['targetUrl'], c.index - 1);
        c.url = c.history[c.index];
        c.delegate.started?.call(c.url);
        c.delegate.changed?.call(UrlChange(url: c.url));
        if (c.failedUrls.contains(c.url)) {
          c.delegate.error?.call(WebResourceError(
              errorCode: -2,
              description: 'fixture failed history entry',
              isForMainFrame: true,
              url: c.url));
        } else {
          c.delegate.finished?.call(c.url);
        }
      }
      return null;
    });
  });
  tearDown(() => app.dispose());

  Future<BrowserController> open(WidgetTester tester, CommonWebsite site,
      {Brightness brightness = Brightness.light}) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: AuthenticatedWebPage(
            key: ValueKey(site.name),
            title: site.name,
            initialUrl: site.url,
            targetHost: Uri.parse(site.url).host,
            app: app,
            canvasSite: site.canvasSite,
            ssoFallbackUrl: site.canvasSite ? site.url : '',
            preferSsoLogin: site.preferSsoLogin,
            authenticationRequired: site.authenticationRequired,
            librarySite: site.librarySite,
            mailSite: site.mailSite,
            allowHttpTarget: site.allowHttpTarget)));
    await tester.pump();
    return platform.controllers.last;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  void fail(BrowserController c, String url) =>
      c.delegate.error?.call(WebResourceError(
          errorCode: -2,
          description: 'fixture network offline',
          isForMainFrame: true,
          url: url));

  testWidgets(
      'SSO inspection uses document URL instead of transient native blank',
      (tester) async {
    final c =
        await open(tester, commonWebsites.firstWhere((s) => s.name == '水源社区'));
    c.nativeUrlOverride = 'about:blank';
    await c.navigate('https://shuiyuan.sjtu.edu.cn/t/fixture/100',
        finish: true);
    await settle(tester);
    expect(find.text('登录跳转异常，请重试'), findsNothing);
    expect(find.text('重试'), findsNothing);
    final opacity = tester.widget<Opacity>(find
        .ancestor(
            of: find.byType(web.WebViewWidget), matching: find.byType(Opacity))
        .first);
    expect(opacity.opacity, 1);
    expect(c.loads.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Shuiyuan HTTP callback upgrades exact destination before inspection',
      (tester) async {
    final c =
        await open(tester, commonWebsites.firstWhere((s) => s.name == '水源社区'));
    const callback =
        'http://shuiyuan.sjtu.edu.cn/auth/oauth2_basic/callback?code=fixture&state=fixture';
    await c.navigate(callback, finish: true);
    await tester.pump();
    expect(c.url, callback.replaceFirst('http:', 'https:'));
    expect(c.loads.last, callback.replaceFirst('http:', 'https:'));
    c.delegate.finished?.call(c.url);
    await settle(tester);
    expect(find.text('重试'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'SSO snapshots preserve auth boundaries and real blank transitions',
      (tester) async {
    final c =
        await open(tester, commonWebsites.firstWhere((s) => s.name == '水源社区'));
    final auth = SchoolWebAuthenticator(web.WebViewController.fromPlatform(c));
    c.nativeUrlOverride = 'https://shuiyuan.sjtu.edu.cn/';
    c.url = 'https://outside.example/login';
    c.loginForm = true;
    var result = await auth.inspect('shuiyuan.sjtu.edu.cn');
    expect(result.kind, SchoolPageKind.outside);
    expect(result.uri!.host, 'outside.example');
    c.nativeUrlOverride = 'about:blank';
    c.url = 'https://jaccount.sjtu.edu.cn/oauth2/login';
    result = await auth.inspect('shuiyuan.sjtu.edu.cn');
    expect(result.kind, SchoolPageKind.login);
    expect(result.uri!.host, 'jaccount.sjtu.edu.cn');
    c.url = 'about:blank';
    result = await auth.inspect('shuiyuan.sjtu.edu.cn');
    expect(result.kind, SchoolPageKind.transition);
    c.loginForm = false;
    c.url = 'http://shuiyuan.sjtu.edu.cn/t/123';
    expect((await auth.inspect('shuiyuan.sjtu.edu.cn')).kind,
        SchoolPageKind.outside);
    c.url = 'http://mail.sjtu.edu.cn/modern/';
    expect((await auth.inspect('mail.sjtu.edu.cn', allowHttpTarget: true)).kind,
        SchoolPageKind.target);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'repro: Shuiyuan content never re-enters automatic SSO after initial session ready',
      (tester) async {
    final c =
        await open(tester, commonWebsites.firstWhere((s) => s.name == '水源社区'));
    await c.navigate('https://shuiyuan.sjtu.edu.cn/', finish: true);
    await settle(tester);
    final checks = c.ssoChecks;
    c.clickSsoOnContent = true;
    await c.navigate('https://shuiyuan.sjtu.edu.cn/t/topic/123', finish: true);
    await settle(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(c.url, 'https://shuiyuan.sjtu.edu.cn/t/topic/123');
    expect(c.ssoChecks, checks);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'repro: failed post retries that post instead of configured login/home',
      (tester) async {
    final c =
        await open(tester, commonWebsites.firstWhere((s) => s.name == '水源社区'));
    await c.navigate('https://shuiyuan.sjtu.edu.cn/', finish: true);
    await settle(tester);
    const topic = 'https://shuiyuan.sjtu.edu.cn/t/topic/456';
    await c.navigate(topic);
    fail(c, topic);
    await tester.pump();
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(c.loads.last, topic);
    c.delegate.finished?.call(topic);
    await settle(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(c.url, topic);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final site in commonWebsites) {
    for (final brightness in Brightness.values) {
      testWidgets(
          '${site.name} ${brightness.name}: retry/history/rebuild/resume/late callbacks',
          (tester) async {
        final c = await open(tester, site, brightness: brightness);
        final origin = Uri.parse(site.url).origin;
        await c.navigate('$origin/', finish: true);
        await settle(tester);
        final beforeLoads = c.loads.length;
        await c.navigate('$origin/t/fixture/1', finish: true);
        await settle(tester);
        await c.navigate('$origin/t/fixture/2', finish: true);
        await settle(tester);
        c.delegate.finished?.call('$origin/');
        fail(c, '$origin/');
        await tester.pump(const Duration(seconds: 10));
        expect(c.url, '$origin/t/fixture/2');
        expect(c.loads.length, beforeLoads);
        expect(find.text('重试'), findsNothing);

        // Theme/widget rebuilds, another APP route and lifecycle signals must
        // leave this same WebView instance, current URL and native history intact.
        final page = tester
            .widget<AuthenticatedWebPage>(find.byType(AuthenticatedWebPage));
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark),
            home: page));
        await tester.pump();
        final context = tester.element(find.byType(AuthenticatedWebPage));
        final route = Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('other app page'))));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.text('other app page'))).pop();
        await route;
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 3));
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(platform.controllers.length, 1);
        expect(c.loads.length, beforeLoads);
        expect(c.url, '$origin/t/fixture/2');

        fail(c, c.url); // A late error after success must not hide the page.
        await tester.pump();
        expect(find.text('重试'), findsNothing);
        await c.navigate(c.url); // A new main-frame load genuinely fails.
        c.failedUrls.add(c.url);
        fail(c, c.url);
        await tester.pump();
        if (site.librarySite) {
          // Preserve the existing scoped HTTPS -> HTTP fallback. Its network
          // failure must still offer retry of that exact destination.
          c.failedUrls.add(c.url);
          fail(c, c.url);
        }
        final retryTarget = c.url;
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(find.text('重试'), findsOneWidget);
        await tester.tap(find.text('重试'));
        await tester.pump();
        expect(c.loads.last, retryTarget);
        c.failedUrls.remove(c.url);
        c.delegate.finished?.call(c.url);
        await settle(tester);
        await tester.pump(const Duration(seconds: 10));
        expect(find.text('重试'), findsNothing);
        expect(c.url, retryTarget);

        final loadsAfterRetry = c.loads.length;
        // The existing PopScope routes Android back into native WebView history.
        final pop = tester.binding.handlePopRoute();
        await tester.pump();
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await pop;
        await tester.pump();
        expect(c.url, '$origin/t/fixture/1');
        expect(c.loads.length, loadsAfterRetry);
        // No timed URL lock after settling: a legitimate redirect is allowed.
        await c.navigate('$origin/t/fixture/3', finish: true);
        await settle(tester);
        expect(c.url, '$origin/t/fixture/3');
        if (find.byTooltip('返回上一页').evaluate().isNotEmpty) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 700)));
          await tester.dragFrom(
              tester.getTopLeft(find.byType(web.WebViewWidget)) +
                  const Offset(4, 140),
              const Offset(130, 0));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(c.url, '$origin/t/fixture/1');
        }
        expect(c.loads.length, loadsAfterRetry);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
      'in-flight SSO, SPA navigation and stale inspection are superseded',
      (tester) async {
    final c =
        await open(tester, commonWebsites.firstWhere((s) => s.name == '水源社区'));
    await c.navigate('https://shuiyuan.sjtu.edu.cn/', finish: true);
    await tester.pump();
    c.clickSsoOnContent = true;
    await c.navigate('https://shuiyuan.sjtu.edu.cn/t/topic/1',
        spa: true, finish: true);
    await settle(tester);
    expect(c.url, 'https://shuiyuan.sjtu.edu.cn/t/topic/1');
    final gate = Completer<Object>();
    c.inspectionGate = gate;
    await c.navigate('https://shuiyuan.sjtu.edu.cn/t/topic/2', finish: true);
    await tester.pump();
    await c.navigate('https://shuiyuan.sjtu.edu.cn/t/topic/3', finish: true);
    await tester.pump();
    gate.complete(jsonEncode({'hasPassword': true, 'hasChallenge': false}));
    await settle(tester);
    expect(c.url, 'https://shuiyuan.sjtu.edu.cn/t/topic/3');
    expect(find.text('重试'), findsNothing);
    expect(c.loads.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'export actual document-bound authentication scripts for JS execution',
      (tester) async {
    final c =
        await open(tester, commonWebsites.firstWhere((s) => s.name == '水源社区'));
    c.scripts.clear();
    final auth = SchoolWebAuthenticator(web.WebViewController.fromPlatform(c));
    const expected = 'https://shuiyuan.sjtu.edu.cn/login';
    await auth.clickSsoButton(expectedUrl: expected);
    await auth.clickCanvasJaccount(expectedUrl: expected, attempts: 1);
    await auth.submit('fixture-user', 'fixture-password',
        expectedUrl: expected);
    await auth.fill('fixture-user', 'fixture-password', expectedUrl: expected);
    File('../../work/web-auth-scripts-1.14.26.json')
        .writeAsStringSync(jsonEncode(c.scripts));
    expect(c.scripts.length, 4);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'central horizontal content swipe is not back: ${brightness.name}',
        (tester) async {
      final c = await open(
          tester, commonWebsites.firstWhere((s) => s.name == '水源社区'),
          brightness: brightness);
      await c.navigate('https://shuiyuan.sjtu.edu.cn/t/topic/1', finish: true);
      await settle(tester);
      await c.navigate('https://shuiyuan.sjtu.edu.cn/t/topic/2', finish: true);
      await settle(tester);
      await tester.dragFrom(
          tester.getTopLeft(find.byType(web.WebViewWidget)) +
              const Offset(200, 200),
          const Offset(150, 0));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.url, 'https://shuiyuan.sjtu.edu.cn/t/topic/2');
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets(
        'external links stay visible and retry exactly: ${brightness.name}',
        (tester) async {
      final c = await open(
          tester, commonWebsites.firstWhere((s) => s.name == '水源社区'),
          brightness: brightness);
      await c.navigate('https://shuiyuan.sjtu.edu.cn/t/topic/123',
          finish: true);
      await settle(tester);
      const external = 'https://external.example/article?id=123';
      await c.navigate(external);
      fail(c, external);
      await tester.pump();
      await tester.tap(find.text('重试'));
      await tester.pump();
      c.loginForm =
          true; // An external password form must not receive school credentials.
      c.delegate.finished?.call(external);
      await settle(tester);
      await tester.pump(const Duration(seconds: 11));
      expect(c.url, external);
      expect(c.loads.last, external);
      expect(find.text('重试'), findsNothing);
      final opacity = tester.widget<Opacity>(find
          .ancestor(
              of: find.byType(web.WebViewWidget),
              matching: find.byType(Opacity))
          .first);
      expect(opacity.opacity, 1);
      expect(c.scripts.any((s) => s.contains('setValue(u,')), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('explicit account and SPA login routes still select existing SSO',
      (tester) async {
    final c =
        await open(tester, commonWebsites.firstWhere((s) => s.name == '交大云盘'));
    await c.navigate('https://pan.sjtu.edu.cn/', finish: true);
    await settle(tester);
    for (final target in [
      'https://pan.sjtu.edu.cn/accounts/login/?next=/library',
      'https://pan.sjtu.edu.cn/#/login'
    ]) {
      final previousChecks = c.ssoChecks;
      await c.navigate(target, finish: true);
      await settle(tester);
      expect(c.ssoChecks, greaterThan(previousChecks));
      expect(c.url, target);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'website routes retain separate controllers; frames cannot reload top-level pages',
      (tester) async {
    final first =
        await open(tester, commonWebsites.firstWhere((s) => s.name == '水源社区'));
    await first.navigate('https://shuiyuan.sjtu.edu.cn/', finish: true);
    await settle(tester);
    await first.navigate('https://shuiyuan.sjtu.edu.cn/t/topic/999',
        finish: true);
    await settle(tester);
    final before = first.loads.length;
    final context = tester.element(find.byType(AuthenticatedWebPage));
    final route = Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AuthenticatedWebPage(
            title: '交大邮箱',
            initialUrl: sjtuMailUrl,
            targetHost: 'mail.sjtu.edu.cn',
            app: app,
            preferSsoLogin: true,
            mailSite: true,
            allowHttpTarget: true,
            showCloseButton: true)));
    await tester.pumpAndSettle();
    final second = platform.controllers.last;
    await second.navigate(sjtuMailUrl, finish: true);
    await settle(tester);
    final mailLoads = second.loads.length;
    final frameDecision = await second.delegate.request!.call(NavigationRequest(
        url: 'http://mail.sjtu.edu.cn/modern/frame', isMainFrame: false));
    expect(frameDecision, NavigationDecision.navigate);
    expect(second.loads.length, mailLoads);
    await second.navigate('https://mail.sjtu.edu.cn/modern/#/mail/77',
        spa: true, finish: true);
    await settle(tester);
    expect(first.url, 'https://shuiyuan.sjtu.edu.cn/t/topic/999');
    expect(first.loads.length, before);
    await tester.tap(find.byTooltip('关闭网页'));
    await tester.pumpAndSettle();
    await route;
    expect(find.text('水源社区'), findsOneWidget);
    expect(first.url, 'https://shuiyuan.sjtu.edu.cn/t/topic/999');
    expect(first.loads.length, before);
    expect(platform.controllers.length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
