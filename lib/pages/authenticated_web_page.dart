import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/app_theme.dart';
import '../services/location_permission_service.dart';
import '../services/android_web_history.dart';
import '../services/graduate_navigation.dart';
import '../services/canvas_dashboard_view.dart';
import '../services/library_navigation.dart';
import '../services/school_web_auth.dart';
import '../services/web_history_policy.dart';
import '../services/web_gesture_policy.dart';
import '../services/web_navigation_guard.dart';
import '../state/app_controller.dart';

class AuthenticatedWebPage extends StatefulWidget {
  const AuthenticatedWebPage({
    super.key,
    required this.title,
    required this.initialUrl,
    required this.targetHost,
    required this.app,
    this.canvasSite = false,
    this.preferSsoLogin = false,
    this.ssoFallbackUrl = '',
    this.authenticationRequired = true,
    this.webHistory = true,
    this.enableGeolocation = false,
    this.locationQuery = '',
    this.allowHttpTarget = false,
    this.librarySite = false,
    this.mailSite = false,
    this.showCloseButton = false,
  });

  final String title;
  final String initialUrl;
  final String targetHost;
  final AppController app;
  final bool canvasSite;
  final bool preferSsoLogin;
  final String ssoFallbackUrl;
  final bool authenticationRequired;
  final bool webHistory;
  final bool enableGeolocation;
  final String locationQuery;
  final bool allowHttpTarget;
  final bool librarySite;
  final bool mailSite;
  final bool showCloseButton;

  @override
  State<AuthenticatedWebPage> createState() => _AuthenticatedWebPageState();
}

class _AuthenticatedWebPageState extends State<AuthenticatedWebPage> {
  late final WebViewController _web;
  late final AndroidWebHistory _history;
  late final SchoolWebAuthenticator _auth;
  Timer? _deadline;
  Timer? _libraryErrorGrace;
  String? _libraryFailedUrl;
  bool _ready = false;
  bool _verification = false;
  bool _failed = false;
  bool _allowCanvasExit = false;
  bool _handlingBack = false;
  bool _backStepFailed = false;
  bool _closingWebPage = false;
  final WebNavigationGuard _navigationGuard = WebNavigationGuard();
  Uri? _backOrigin;
  Uri? _backTarget;
  bool _backTargetFinished = false;
  DateTime? _backHoldUntil;
  Offset? _swipeStart;
  int? _swipePointer;
  DateTime? _lastBackAction;
  int _loginAttempts = 0;
  bool _locationApplied = false;
  bool _ssoAttempted = false;
  bool _ssoSelecting = false;
  bool _libraryOpened = false;
  bool _libraryAuthenticating = false;
  bool _libraryPersonalLoginRequested = false;
  int _librarySsoAttempts = 0;
  Uri? _libraryHttpFallback;
  final Set<String> _libraryHttpsRetries = {};
  final Set<String> _libraryScopedHttpFallbacksTried = {};
  final Set<String> _mailHttpsRetries = {};
  final Set<String> _mailHttpAllowed = {};
  Uri? _mailPendingHttpFallback;
  Uri? _canvasHomeUri;
  bool _canvasDashboardViewCheckInstalled = false;
  String _status = '';

  static const _primoHost = LibraryNavigation.primoHost;
  bool get _compactHistorySite =>
      widget.canvasSite ||
      widget.librarySite ||
      widget.mailSite ||
      widget.targetHost == 'yjs.sjtu.edu.cn' ||
      widget.targetHost == 'shuiyuan.sjtu.edu.cn';
  bool get _graduatePlatform =>
      widget.targetHost == GraduateNavigation.targetHost;
  WebHistoryPolicy get _historyPolicy => WebHistoryPolicy(
        homeHost: widget.targetHost,
        canvasSite: widget.canvasSite,
        librarySite: widget.librarySite,
        mailSite: widget.mailSite,
      );
  bool get _returningFromWeb =>
      _closingWebPage ||
      _handlingBack ||
      (_backHoldUntil != null && DateTime.now().isBefore(_backHoldUntil!));

  bool _mayAutoNavigate(int epoch) =>
      mounted && _navigationGuard.permits(epoch, returning: _returningFromWeb);

  String get _loadingStatus =>
      widget.authenticationRequired ? '正在复用当前登录状态…' : '正在加载…';

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final requested = Uri.tryParse(request.url);
            if (_closingWebPage) return NavigationDecision.prevent;
            if (_returningFromWeb) {
              if (!_handlingBack ||
                  !_historyPolicy.isVisiblePage(requested) ||
                  _historyPolicy.samePage(requested, _backOrigin) ||
                  !_historyPolicy.samePage(requested, _backTarget)) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            }
            if (widget.mailSite) {
              final uri = Uri.tryParse(request.url);
              if (uri?.host == widget.targetHost && uri?.scheme == 'http') {
                final key = uri.toString();
                if (_mailHttpAllowed.contains(key)) {
                  if (_mailPendingHttpFallback?.toString() == key) {
                    _mailPendingHttpFallback = null;
                  }
                  return NavigationDecision.navigate;
                }
                if (_mailHttpsRetries.add(key)) {
                  _mailPendingHttpFallback = uri;
                  _mailLog('https_upgrade', uri);
                  unawaited(_web.loadRequest(uri!.replace(scheme: 'https')));
                  return NavigationDecision.prevent;
                }
                // Some legacy Zimbra callbacks are hard-coded to HTTP. Let
                // only the exact callback through after its HTTPS attempt;
                // Android's network policy separately scopes cleartext to
                // mail.sjtu.edu.cn.
                _mailHttpAllowed.add(key);
                _mailLog('scoped_http_callback', uri);
                return NavigationDecision.navigate;
              }
            }
            if (widget.librarySite) {
              final uri = Uri.tryParse(request.url);
              if (uri?.scheme == 'http') {
                _libraryLog('http_navigation', uri);
              }
              if (uri != null && uri == _libraryHttpFallback) {
                _libraryHttpFallback = null;
                return NavigationDecision.navigate;
              }
              if (LibraryNavigation.shouldUpgradeToHttps(
                      uri, widget.targetHost) &&
                  uri != _libraryHttpFallback) {
                final key = uri.toString();
                if (!_libraryHttpsRetries.add(key)) {
                  // HTTPS was already attempted for this exact redirect. Use
                  // HTTP only for the explicitly allow-listed library hosts.
                  if (LibraryNavigation.permitsHttp(uri, widget.targetHost)) {
                    _libraryHttpFallback = uri;
                    _libraryLog('scoped_http_fallback', uri);
                    return NavigationDecision.navigate;
                  }
                  return NavigationDecision.prevent;
                }
                _libraryLog('https_upgrade', uri);
                if (LibraryNavigation.permitsHttp(uri, widget.targetHost)) {
                  _libraryHttpFallback = uri;
                }
                unawaited(_web.loadRequest(uri!.replace(scheme: 'https')));
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            if (_returningFromWeb) return;
            final uri = Uri.tryParse(url);
            _graduateLog('redirect', uri);
            if (widget.targetHost == GraduateNavigation.targetHost &&
                _failed &&
                mounted) {
              setState(() {
                _failed = false;
                _status = _loadingStatus;
              });
            }
            if (widget.targetHost == 'yjs.sjtu.edu.cn' &&
                uri?.host.endsWith('.sjtu.edu.cn') == true &&
                uri?.host != widget.targetHost &&
                mounted) {
              setState(() => _status = '正在通过 jAccount 登录…');
            }
            if (widget.librarySite) {
              _libraryErrorGrace?.cancel();
              _libraryFailedUrl = null;
              if (_failed && mounted) {
                setState(() {
                  _failed = false;
                  _status = _loadingStatus;
                });
              }
              final destination =
                  LibraryNavigation.classify(uri, widget.targetHost);
              _libraryLog('redirect', uri);
              if (destination == LibraryDestination.schoolLogin ||
                  LibraryNavigation.isAuthenticationIntermediate(uri) ||
                  (destination == LibraryDestination.primo &&
                      (uri?.path.contains('/account') ?? false))) {
                _libraryPersonalLoginRequested = true;
              }
              if (_libraryOpened &&
                  destination == LibraryDestination.schoolLogin) {
                _libraryAuthenticating = true;
                _startDeadline();
                if (mounted) {
                  setState(() {
                    _ready = false;
                    _status = '正在通过 jAccount 进入我的图书馆…';
                  });
                }
              }
              if (_libraryOpened &&
                  LibraryNavigation.isAuthenticationIntermediate(uri)) {
                if (!_libraryAuthenticating) _startDeadline();
                _libraryAuthenticating = true;
                if (mounted) {
                  setState(() {
                    _ready = false;
                    _failed = false;
                    _status = '正在通过 jAccount 进入我的图书馆…';
                  });
                }
              }
            }
            if (mounted &&
                !_ready &&
                !_verification &&
                !_failed &&
                !(widget.librarySite && _libraryAuthenticating)) {
              setState(() => _status = _loadingStatus);
            }
          },
          onPageFinished: (url) async {
            if (_returningFromWeb) {
              final uri = Uri.tryParse(url);
              if (_handlingBack &&
                  _historyPolicy.isVisiblePage(uri) &&
                  !_historyPolicy.samePage(uri, _backOrigin) &&
                  _historyPolicy.samePage(uri, _backTarget)) {
                _backTargetFinished = true;
              }
              return;
            }
            final epoch = _navigationGuard.generation;
            if (widget.targetHost == GraduateNavigation.targetHost &&
                _failed &&
                mounted) {
              setState(() {
                _failed = false;
                _status = _loadingStatus;
              });
            }
            if (widget.librarySite) {
              // A failed main-frame callback can precede the next SSO
              // redirect. Its onPageFinished is not a successful page.
              if (_libraryFailedUrl == url) return;
              _libraryErrorGrace?.cancel();
            }
            final uri = Uri.tryParse(url);
            if (widget.mailSite &&
                uri?.host == widget.targetHost &&
                uri?.scheme == 'https') {
              _mailPendingHttpFallback = null;
            }
            if (widget.librarySite &&
                uri?.scheme == 'https' &&
                uri?.host == _libraryHttpFallback?.host) {
              _libraryHttpFallback = null;
            }
            final destination =
                LibraryNavigation.classify(uri, widget.targetHost);
            if (widget.librarySite &&
                (destination == LibraryDestination.library ||
                    destination == LibraryDestination.primo)) {
              await _keepLibraryLinksInWebView();
            }
            if (!_mayAutoNavigate(epoch)) return;
            await _pageReady();
            if (!_mayAutoNavigate(epoch)) return;
            if (widget.canvasSite &&
                !_canvasDashboardViewCheckInstalled &&
                isCanvasDashboardUri(uri)) {
              _canvasDashboardViewCheckInstalled = true;
              unawaited(_applyCanvasDashboardDefaultView());
            }
          },
          onWebResourceError: (error) {
            if (_returningFromWeb) {
              if (_handlingBack &&
                  _backTarget != null &&
                  error.isForMainFrame == true &&
                  error.errorCode != -3 &&
                  _historyPolicy.samePage(
                      Uri.tryParse(error.url ?? ''), _backTarget)) {
                _backStepFailed = true;
              }
              return;
            }
            if (widget.librarySite &&
                error.description.contains('ERR_CLEARTEXT_NOT_PERMITTED') &&
                error.isForMainFrame != true) {
              final blockedUri = Uri.tryParse(error.url ?? '');
              _libraryLog('cleartext_subresource_blocked', blockedUri,
                  'code=${error.errorCode}');
              return;
            }
            if (error.isForMainFrame == true) {
              if (widget.librarySite) {
                final uri = Uri.tryParse(error.url ?? '');
                final cleartext =
                    error.description.contains('ERR_CLEARTEXT_NOT_PERMITTED');
                final authIntermediate =
                    LibraryNavigation.isAuthenticationIntermediate(uri);
                final connectionRefused =
                    error.description.contains('ERR_CONNECTION_REFUSED');
                final failureStage = cleartext
                    ? 'http_blocked'
                    : authIntermediate
                        ? 'auth_intermediate_unavailable'
                        : connectionRefused
                            ? 'connection_refused'
                            : 'page_load_failed';
                _libraryLog(failureStage, uri, 'code=${error.errorCode}');
                if (cleartext && uri?.scheme == 'http') {
                  if (uri != null && _libraryHttpsRetries.add(uri.toString())) {
                    if (LibraryNavigation.permitsHttp(uri, widget.targetHost)) {
                      _libraryHttpFallback = uri;
                    }
                    _libraryLog('https_retry', uri);
                    unawaited(_web.loadRequest(uri.replace(scheme: 'https')));
                  } else {
                    // The navigation delegate may already have started the
                    // HTTPS replacement. Do not turn the canceled cleartext
                    // leg into a user-visible terminal error.
                    _libraryLog('https_retry_pending', uri);
                  }
                  return;
                }
                if (error.errorCode != -3 &&
                    uri?.scheme == 'https' &&
                    uri != null) {
                  final fallback = uri.replace(scheme: 'http');
                  if (LibraryNavigation.permitsHttp(
                          fallback, widget.targetHost) &&
                      _libraryScopedHttpFallbacksTried
                          .add(fallback.toString())) {
                    _libraryHttpFallback = fallback;
                    _libraryLog('https_failed_scoped_http_fallback', fallback,
                        'code=${error.errorCode}');
                    unawaited(_web.loadRequest(fallback));
                    return;
                  }
                }
                if (authIntermediate) {
                  _libraryFailedUrl = error.url;
                  if (!_libraryAuthenticating) _startDeadline();
                  _libraryAuthenticating = true;
                  _libraryLog('redirect_pending', uri,
                      'webview_code=${error.errorCode}');
                  if (mounted) {
                    setState(() {
                      _ready = false;
                      _failed = false;
                      _status = '正在通过 jAccount 进入我的图书馆…';
                    });
                  }
                  return;
                }
                final fallback = _libraryHttpFallback;
                if (error.errorCode != -3 &&
                    fallback != null &&
                    uri?.scheme == 'https' &&
                    uri?.host == fallback.host &&
                    uri?.path == fallback.path &&
                    LibraryNavigation.permitsHttp(
                        fallback, widget.targetHost)) {
                  _libraryLog('http_fallback', fallback);
                  unawaited(_web.loadRequest(fallback));
                  return;
                }
                if (_libraryPersonalLoginRequested) {
                  _libraryLog('redirect_failed', uri,
                      'webview_code=${error.errorCode}');
                }
                if (error.errorCode != -3) {
                  _libraryFailedUrl = error.url;
                  // Intermediate SSO callbacks may fail while the redirect
                  // chain continues. During authentication, the existing
                  // deadline decides whether the final page truly failed.
                  if (!_libraryAuthenticating) {
                    _libraryErrorGrace?.cancel();
                    final failedUrl = error.url;
                    _libraryErrorGrace =
                        Timer(const Duration(seconds: 3), () async {
                      if (mounted &&
                          !_returningFromWeb &&
                          failedUrl != null &&
                          _libraryFailedUrl == failedUrl &&
                          await _web.currentUrl() == failedUrl) {
                        _fail('页面加载失败，请检查网络后重试');
                      }
                    });
                  }
                }
                return;
              } else if (widget.mailSite) {
                final uri = Uri.tryParse(error.url ?? '');
                final cleartext =
                    error.description.contains('ERR_CLEARTEXT_NOT_PERMITTED');
                _mailLog(cleartext ? 'cleartext_blocked' : 'page_load_failed',
                    uri, 'code=${error.errorCode}');
                if (cleartext &&
                    uri?.scheme == 'http' &&
                    uri?.host == widget.targetHost &&
                    _mailHttpsRetries.add(uri.toString())) {
                  _mailLog('https_retry', uri);
                  unawaited(_web.loadRequest(uri!.replace(scheme: 'https')));
                  return;
                }
                final fallback = _mailPendingHttpFallback;
                if (error.errorCode != -3 &&
                    fallback != null &&
                    uri?.scheme == 'https' &&
                    uri?.host == fallback.host &&
                    uri?.path == fallback.path) {
                  _mailPendingHttpFallback = null;
                  _mailHttpAllowed.add(fallback.toString());
                  _mailLog('https_unavailable_scoped_http_fallback', fallback,
                      'code=${error.errorCode}');
                  unawaited(_web.loadRequest(fallback));
                  return;
                }
              } else if (widget.targetHost == 'yjs.sjtu.edu.cn') {
                final uri = Uri.tryParse(error.url ?? '');
                if (error.errorCode == -3) return;
                if (GraduateNavigation.isSsoIntermediate(uri)) {
                  _graduateLog('sso_intermediate_unavailable', uri,
                      'code=${error.errorCode}');
                  // A known OAuth bridge can be replaced by the next server
                  // redirect. The bounded authentication deadline handles a
                  // bridge that never recovers.
                  return;
                }
                _graduateLog('graduate_page_load_failed', uri,
                    'code=${error.errorCode}');
                _fail('研究生应用管理平台页面加载失败，请重试');
                return;
              } else {
                debugPrint('School web main-frame error: ${error.errorCode} '
                    '${error.description} ${_safeLocation(error.url)}');
              }
              // Android WebView reports ERR_ABORTED while a redirect is being
              // replaced. The new page will invoke onPageFinished.
              if (error.errorCode != -3 &&
                  !(widget.librarySite &&
                      _ready &&
                      !_libraryPersonalLoginRequested)) {
                _fail('页面加载失败，请检查网络后重试');
              }
            }
          },
        ),
      );
    _auth = SchoolWebAuthenticator(_web);
    _history = AndroidWebHistory(_web);
    _status = _loadingStatus;
    unawaited(_initialize());
  }

  String _safeLocation(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri == null ? '' : '${uri.host}${uri.path}';
  }

  void _libraryLog(String stage, Uri? uri, [String detail = '']) {
    if (!widget.librarySite) return;
    // Never log URL queries, fragments, cookies, form values or page bodies.
    final destination = uri == null ? 'unknown' : '${uri.host}${uri.path}';
    debugPrint('[library-auth][$stage] $destination $detail');
  }

  void _mailLog(String stage, Uri? uri, [String detail = '']) {
    if (!widget.mailSite) return;
    final destination = uri == null ? 'unknown' : '${uri.host}${uri.path}';
    // Deliberately omit query, fragment, request headers and page contents.
    debugPrint('[mail-auth][$stage] $destination $detail');
  }

  void _graduateLog(String stage, Uri? uri, [String detail = '']) {
    if (widget.targetHost != 'yjs.sjtu.edu.cn') return;
    final destination = uri == null ? 'unknown' : '${uri.host}${uri.path}';
    debugPrint('[graduate-sso][$stage] $destination $detail');
  }

  Future<void> _logLibraryCookieStatus(String stage,
      {bool expectPrimoSession = false}) async {
    try {
      final cookies = WebViewCookieManager();
      final school = await cookies.getCookies(
          domain: Uri.parse('https://jaccount.sjtu.edu.cn/'));
      final primo =
          await cookies.getCookies(domain: Uri.parse('https://$_primoHost/'));
      final currentPrimo = await cookies.getCookies(
          domain: Uri.parse('https://${LibraryNavigation.currentPrimoHost}/'));
      final hasPrimoCookie = primo.isNotEmpty || currentPrimo.isNotEmpty;
      debugPrint('[library-auth][$stage] jAccountCookie=${school.isNotEmpty} '
          'primoCookie=$hasPrimoCookie');
      if (expectPrimoSession && !hasPrimoCookie) {
        debugPrint('[library-auth][cookie_not_saved] '
            'Primo session cookie is not yet visible');
      }
    } catch (error) {
      debugPrint('[library-auth][cookie_check_failed] ${error.runtimeType}');
    }
  }

  Future<void> _keepLibraryLinksInWebView() async {
    try {
      await _web.runJavaScript(r'''
        (() => {
          if (window.__librarySameWindowLinks) return;
          window.__librarySameWindowLinks = true;
          document.addEventListener('click', event => {
            const link = event.target?.closest?.('a[target]');
            if (link && link.target.toLowerCase() === '_blank')
              link.target = '_self';
          }, true);
          document.querySelectorAll('form[target="_blank"]')
            .forEach(form => form.target = '_self');
          const originalOpen = window.open.bind(window);
          window.open = (url, target, features) => {
            if (url) {
              try {
                const destination = new URL(url, location.href);
                if (destination.hostname ===
                    '86sjt-primo.hosted.exlibrisgroup.com.cn' ||
                    destination.hostname ===
                    'primo.hosted.exlibrisgroup.com.cn' ||
                    destination.hostname.endsWith('.sjtu.edu.cn')) {
                  location.assign(destination.href);
                  return window;
                }
              } catch (_) {}
            }
            return originalOpen(url, target, features);
          };
        })();
      ''');
    } catch (error) {
      debugPrint('Library navigation preparation failed: $error');
    }
  }

  Future<void> _prepareLibraryPersonalLogin() async {
    final epoch = _navigationGuard.generation;
    if (!_mayAutoNavigate(epoch)) return;
    if (_librarySsoAttempts >= 3) {
      _libraryLog('jaccount_login_failed',
          Uri.tryParse(await _web.currentUrl() ?? ''), 'selection_limit');
      return;
    }
    _librarySsoAttempts++;
    try {
      await _web.runJavaScript(r'''
        (() => {
          if (window.__sjtuLibrarySignInObserver) return;
          window.__sjtuLibrarySignInObserver = true;
          const clicked = new WeakSet();
          let attempts = 0;
          const visible = element => !!element &&
            (element.offsetWidth || element.offsetHeight ||
             element.getClientRects().length);
          const label = element => [element.innerText, element.title,
            element.getAttribute?.('aria-label'), element.href]
            .filter(Boolean).join(' ').toLowerCase();
          const context = element => [label(element),
            element.parentElement?.innerText?.slice(0, 120)]
            .filter(Boolean).join(' ').toLowerCase();
          const choose = () => {
            if (!/(pds_login|\/(account|login)(\/|$))/i
                .test(location.pathname)) return;
            const options = [...document.querySelectorAll(
              'a,button,[role=button],input[type=button]')]
              .filter(element => visible(element) && !clicked.has(element));
            const allowed = element =>
              !/校外|guest|external|非jaccount/.test(label(element));
            const candidate = options.find(element => allowed(element) &&
              /jaccount|统一身份认证/.test(label(element))) ||
              options.find(element => allowed(element) &&
              /上海交通大学/.test(label(element)) &&
              /登录|认证|选择|机构|sign|login/.test(context(element))) ||
              options.find(element => allowed(element) &&
              /机构登录|institutional (sign.?in|login)/.test(label(element))) ||
              options.find(element => allowed(element) &&
              /^(登录|sign in|log in)$/i.test(
                String(element.innerText || element.value || '').trim()));
            if (!candidate || attempts >= 2) return;
            clicked.add(candidate);
            attempts++;
            candidate.click();
          };
          const observer = new MutationObserver(choose);
          observer.observe(document.documentElement,
            {childList: true, subtree: true});
          choose();
          setTimeout(() => observer.disconnect(), 10000);
        })();
      ''');
      if (!_mayAutoNavigate(epoch)) return;
      _libraryLog(
          'sso_selection_ready', Uri.tryParse(await _web.currentUrl() ?? ''));
      unawaited(_inspectLibrarySessionAfterLoad());
    } catch (error) {
      _libraryLog(
          'jaccount_login_failed',
          Uri.tryParse(await _web.currentUrl() ?? ''),
          'selection=${error.runtimeType}');
    }
  }

  Future<void> _inspectLibrarySessionAfterLoad() async {
    final epoch = _navigationGuard.generation;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!_mayAutoNavigate(epoch) || !_libraryPersonalLoginRequested) return;
    final uri = Uri.tryParse(await _web.currentUrl() ?? '');
    if (!_mayAutoNavigate(epoch)) return;
    if (!LibraryNavigation.isPrimoHost(uri?.host)) return;
    try {
      final rejected = await _web.runJavaScriptReturningResult(r'''
        (() => /session expired|session invalid|access denied|登录失败|会话过期|认证失败/i
          .test((document.body?.innerText || '').slice(0, 6000)))()
      ''');
      if (rejected == true || '$rejected' == 'true') {
        _libraryLog('library_session_rejected', uri);
      }
    } catch (error) {
      _libraryLog('session_check_failed', uri, '${error.runtimeType}');
    }
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _libraryErrorGrace?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _configureAndroidWebView();
    await _reloadFromStart();
  }

  void _startDeadline() {
    _deadline?.cancel();
    _deadline = Timer(const Duration(seconds: 30), () {
      if (_returningFromWeb) return;
      if (!_ready && !_verification) {
        if (widget.targetHost == GraduateNavigation.targetHost) {
          unawaited(_logGraduateTimeout());
        }
        if (widget.librarySite) {
          _libraryLog(
              _libraryAuthenticating
                  ? 'jaccount_login_failed'
                  : 'redirect_failed',
              null,
              'timeout');
        }
        _fail(widget.authenticationRequired ? '连接学校系统超时，请重试' : '页面加载超时，请重试');
      }
    });
  }

  Future<void> _logGraduateTimeout() async {
    Uri? uri;
    try {
      uri = Uri.tryParse(await _web.currentUrl() ?? '');
    } catch (_) {}
    _graduateLog('timeout', uri, 'authentication_or_callback');
  }

  Future<void> _configureAndroidWebView() async {
    final platform = _web.platform;
    if (platform is! AndroidWebViewController) return;
    if (widget.librarySite) {
      try {
        final cookieManager = WebViewCookieManager().platform;
        if (cookieManager is AndroidWebViewCookieManager) {
          await cookieManager.setAcceptThirdPartyCookies(platform, true);
        }
      } catch (error) {
        _libraryLog('cookie_setup_failed', null, '${error.runtimeType}');
      }
    }
    if (widget.enableGeolocation) {
      await platform.setGeolocationEnabled(true);
      await platform.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          final uri = Uri.tryParse(request.origin);
          final trusted =
              uri?.scheme == 'https' && uri?.host == widget.targetHost;
          final allowed =
              trusted && await const LocationPermissionService().request();
          return GeolocationPermissionsResponse(
              allow: allowed, retain: allowed);
        },
      );
    }
  }

  Future<void> _reloadFromStart() async {
    if (_handlingBack || _closingWebPage) return;
    _backHoldUntil = null;
    _deadline?.cancel();
    _loginAttempts = 0;
    _locationApplied = false;
    _ssoAttempted = false;
    _libraryOpened = false;
    _libraryAuthenticating = false;
    _libraryPersonalLoginRequested = false;
    _librarySsoAttempts = 0;
    _libraryHttpFallback = null;
    _libraryHttpsRetries.clear();
    _libraryScopedHttpFallbacksTried.clear();
    if (mounted) {
      setState(() {
        _ready = false;
        _verification = false;
        _failed = false;
        _status = _loadingStatus;
      });
    }
    _startDeadline();
    await _web.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _applyCanvasDashboardDefaultView() async {
    final epoch = _navigationGuard.generation;
    if (!_mayAutoNavigate(epoch)) return;
    try {
      await _web.runJavaScript(canvasDashboardCardViewScript);
    } catch (error, stack) {
      debugPrint('[canvas-dashboard] default card view check failed: '
          '$error\n$stack');
      // This is a dashboard presentation preference only; keep the web page
      // usable even if Canvas changes its view-switcher markup.
    }
  }

  Future<void> _pageReady() async {
    final epoch = _navigationGuard.generation;
    if (!_mayAutoNavigate(epoch)) return;
    if (_failed && !widget.librarySite) return;
    final uri = Uri.tryParse(await _web.currentUrl() ?? '');
    if (uri == null) return;
    if (!_mayAutoNavigate(epoch)) return;
    if (widget.targetHost == GraduateNavigation.targetHost &&
        GraduateNavigation.isCallback(uri)) {
      _graduateLog('oauth_callback_received', uri);
      if (mounted) setState(() => _status = '正在等待 jAccount 登录回跳…');
      return;
    }
    final libraryDestination =
        LibraryNavigation.classify(uri, widget.targetHost);

    // The current official library portal may canonicalize between its
    // www/non-www hostnames before the webview reaches a stable page. Treat a
    // library/Primo destination as the ready site instead of misclassifying
    // that harmless canonical redirect as an SSO failure.
    if (widget.librarySite &&
        !_libraryOpened &&
        (libraryDestination == LibraryDestination.library ||
            libraryDestination == LibraryDestination.primo)) {
      _libraryOpened = true;
      _canvasHomeUri ??= uri;
      _deadline?.cancel();
      if (mounted) {
        setState(() {
          _ready = true;
          _verification = false;
          _failed = false;
          _status = '';
        });
      }
      unawaited(_keepLibraryLinksInWebView());
      unawaited(_logLibraryCookieStatus('library_home'));
      return;
    }

    if (widget.librarySite &&
        _libraryOpened &&
        (libraryDestination == LibraryDestination.schoolLogin ||
            LibraryNavigation.isAuthenticationIntermediate(uri))) {
      if (!_libraryAuthenticating) _startDeadline();
      _libraryAuthenticating = true;
      _libraryLog('redirect_pending', uri);
      if (mounted) {
        setState(() {
          _ready = false;
          _failed = false;
          _status = '正在通过 jAccount 进入我的图书馆…';
        });
      }
      if (LibraryNavigation.isPrimoHost(uri.host) &&
          _libraryPersonalLoginRequested) {
        unawaited(_prepareLibraryPersonalLogin());
      }
      return;
    }

    if (widget.librarySite &&
        _libraryOpened &&
        libraryDestination != LibraryDestination.schoolLogin) {
      if (libraryDestination == LibraryDestination.transient) return;
      if (libraryDestination == LibraryDestination.unsupported) {
        _libraryLog('redirect_failed', uri, 'unsupported_scheme');
        _fail('图书馆页面跳转失败，请重试');
        return;
      }
      if (_libraryAuthenticating &&
          libraryDestination == LibraryDestination.web) {
        _libraryLog('redirect_pending', uri);
        return;
      }
      _libraryLog(
          _libraryAuthenticating ? 'callback_accepted' : 'page_ready', uri);
      if (_libraryAuthenticating) {
        unawaited(_logLibraryCookieStatus('callback',
            expectPrimoSession:
                libraryDestination == LibraryDestination.primo));
      }
      _libraryAuthenticating = false;
      _deadline?.cancel();
      if (mounted) {
        setState(() {
          _ready = true;
          _verification = false;
          _failed = false;
          _status = '';
        });
      }
      if (libraryDestination == LibraryDestination.primo &&
          _libraryPersonalLoginRequested) {
        await _prepareLibraryPersonalLogin();
      }
      return;
    }

    if (!widget.authenticationRequired) {
      if (uri.scheme == 'https' && uri.host == widget.targetHost) {
        _canvasHomeUri ??= uri;
        _deadline?.cancel();
        if (mounted) {
          setState(() {
            _ready = true;
            _verification = false;
            _failed = false;
            _status = '';
          });
        }
        await _applyLocationQuery();
      }
      return;
    }

    final canvasChooser = widget.canvasSite &&
        uri.host == widget.targetHost &&
        uri.path.startsWith('/login/canvas');
    if (!_ssoAttempted &&
        !_ssoSelecting &&
        (widget.canvasSite || widget.preferSsoLogin) &&
        uri.host == widget.targetHost &&
        (widget.preferSsoLogin || uri.path.contains('/login'))) {
      try {
        _ssoSelecting = true;
        final clicked = canvasChooser
            ? await _auth.clickCanvasJaccount(
                shouldContinue: () => _mayAutoNavigate(epoch))
            : await _auth.clickSsoButton(
                attempts: 6,
                shouldContinue: () => _mayAutoNavigate(epoch),
              );
        if (!_mayAutoNavigate(epoch)) return;
        if (clicked) {
          _ssoAttempted = true;
          if (mounted) setState(() => _status = '正在通过 jAccount 登录…');
          return;
        }
        if (widget.canvasSite) {
          final fallback = Uri.tryParse(widget.ssoFallbackUrl);
          if (fallback != null && fallback.scheme == 'https') {
            _ssoAttempted = true;
            if (mounted) setState(() => _status = '正在进入 jAccount 登录…');
            await _web.loadRequest(fallback);
            return;
          }
          _fail('未找到 Canvas 的 jAccount 登录入口，请重试');
          return;
        }
      } catch (error, stack) {
        if (!_mayAutoNavigate(epoch)) return;
        debugPrint('School SSO selection failed: $error\n$stack');
        if (widget.canvasSite) {
          _fail('Canvas 登录跳转失败，请重试');
          return;
        }
      } finally {
        _ssoSelecting = false;
      }
    }

    SchoolPageInspection inspection;
    try {
      inspection = await _auth.inspect(widget.targetHost,
          allowHttpTarget: widget.allowHttpTarget);
      if (!_mayAutoNavigate(epoch)) return;
    } catch (error, stack) {
      if (!_mayAutoNavigate(epoch)) return;
      if (widget.librarySite && _libraryOpened) {
        _libraryLog('redirect_pending', uri, 'inspection=${error.runtimeType}');
        return;
      }
      if (widget.targetHost == GraduateNavigation.targetHost &&
          GraduateNavigation.isSsoIntermediate(uri)) {
        _graduateLog('sso_inspection_pending', uri, '${error.runtimeType}');
        if (mounted) setState(() => _status = '正在等待 jAccount 登录回跳…');
        return;
      }
      debugPrint('Authenticated page inspection failed: $error\n$stack');
      _fail('无法确认学校登录状态，请重试');
      return;
    }

    _graduateLog('inspection', inspection.uri, 'kind=${inspection.kind.name}');

    switch (inspection.kind) {
      case SchoolPageKind.target:
        if (widget.librarySite) {
          _libraryOpened = true;
          _libraryLog('library_home', inspection.uri);
          unawaited(_logLibraryCookieStatus('library_home'));
        }
        _canvasHomeUri ??= inspection.uri;
        _deadline?.cancel();
        if (mounted) {
          setState(() {
            _ready = true;
            _verification = false;
            _failed = false;
            _status = '';
          });
        }
        await _applyLocationQuery();
        return;
      case SchoolPageKind.login:
        _libraryLog('jaccount_login_required', inspection.uri);
        await _submitLogin(epoch);
        return;
      case SchoolPageKind.challenge:
        _libraryLog('jaccount_verification_required', inspection.uri);
        if (widget.app.sessionPassword.isNotEmpty) {
          await _auth.fill(
            widget.app.sessionUsername,
            widget.app.sessionPassword,
          );
          if (!_mayAutoNavigate(epoch)) return;
        }
        _deadline?.cancel();
        if (mounted) {
          setState(() {
            _ready = false;
            _verification = true;
            _status = '学校要求额外验证，完成后将自动继续';
          });
        }
        return;
      case SchoolPageKind.transition:
        _libraryLog('redirect_pending', inspection.uri);
        if (mounted) setState(() => _status = '学校正在完成登录跳转…');
        return;
      case SchoolPageKind.outside:
        if (widget.librarySite) {
          _libraryLog('redirect_failed', inspection.uri, 'inspection_outside');
        }
        if (widget.targetHost == GraduateNavigation.targetHost &&
            GraduateNavigation.isSsoIntermediate(inspection.uri)) {
          _graduateLog('sso_transition', inspection.uri);
          if (mounted) setState(() => _status = '正在等待 jAccount 登录回跳…');
          return;
        }
        debugPrint(
          'School authentication left the allowed redirect chain: '
          '${_safeLocation(inspection.uri?.toString())}',
        );
        _fail('登录跳转异常，请重试');
        return;
    }
  }

  Future<void> _applyLocationQuery() async {
    final epoch = _navigationGuard.generation;
    if (!_mayAutoNavigate(epoch)) return;
    final query = widget.locationQuery.trim();
    if (_locationApplied || query.isEmpty) return;
    _locationApplied = true;
    final encoded = jsonEncode(query);
    try {
      await _web.runJavaScript('''
        (() => {
          const input = document.querySelector('#searchKey');
          if (!input) return false;
          const value = $encoded;
          const setter = Object.getOwnPropertyDescriptor(
            HTMLInputElement.prototype, 'value')?.set;
          if (setter) setter.call(input, value); else input.value = value;
          input.dispatchEvent(new Event('input', {bubbles: true}));
          input.dispatchEvent(new KeyboardEvent('keyup', {
            key: value.slice(-1) || 'Enter', bubbles: true
          }));
          input.focus();
          setTimeout(() => {
            const normalized = text => String(text || '').replace(/\\s+/g, '');
            const wanted = normalized(value);
            const candidates = [...document.querySelectorAll(
              '.bigautocomplete-layout tr, .search_list li, .autocomplete-suggestion')];
            const matched = candidates.find(node =>
              normalized(node.innerText).includes(wanted) ||
              wanted.includes(normalized(node.innerText)));
            if (matched) matched.click();
            else input.dispatchEvent(new KeyboardEvent('keydown', {
              key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true
            }));
          }, 900);
          return true;
        })()
      ''');
      if (!_mayAutoNavigate(epoch)) return;
    } catch (error, stack) {
      debugPrint('Map location search was not applied: $error\n$stack');
    }
  }

  Future<void> _submitLogin(int epoch) async {
    if (!_mayAutoNavigate(epoch)) return;
    if (widget.app.sessionPassword.isEmpty) {
      _libraryLog('jaccount_login_failed',
          Uri.tryParse(await _web.currentUrl() ?? ''), 'no_saved_session');
      if (!_mayAutoNavigate(epoch)) return;
      _fail('登录状态已过期，请返回登录页重新验证');
      return;
    }
    if (_loginAttempts >= 2) {
      _libraryLog('jaccount_login_failed',
          Uri.tryParse(await _web.currentUrl() ?? ''), 'attempt_limit');
      if (!_mayAutoNavigate(epoch)) return;
      _fail(widget.canvasSite ? 'Canvas 登录未完成，请重试' : '学校登录未完成，请重试');
      return;
    }
    _loginAttempts++;
    if (mounted) setState(() => _status = '正在自动重新登录…');
    try {
      final submitted = await _auth.submit(
        widget.app.sessionUsername,
        widget.app.sessionPassword,
      );
      if (!_mayAutoNavigate(epoch)) return;
      if (!submitted) {
        _libraryLog('jaccount_login_failed',
            Uri.tryParse(await _web.currentUrl() ?? ''), 'form_not_submitted');
        _fail('无法提交学校登录页面，请重试');
      } else {
        _startDeadline();
      }
    } catch (error, stack) {
      if (!_mayAutoNavigate(epoch)) return;
      if (widget.librarySite) {
        _libraryLog(
            'jaccount_login_failed',
            Uri.tryParse(await _web.currentUrl() ?? ''),
            'submission=${error.runtimeType}');
      } else {
        debugPrint('Authenticated page login failed: $error\n$stack');
      }
      _fail('自动登录失败，请重试');
    }
  }

  void _fail(String message) {
    if (!mounted || _returningFromWeb) return;
    _deadline?.cancel();
    setState(() {
      _ready = false;
      _verification = false;
      _failed = true;
      _status = message;
    });
  }

  Future<void> _handleCanvasBack(bool didPop, Object? result) async {
    if (didPop || _handlingBack || _closingWebPage) return;
    final now = DateTime.now();
    if (_compactHistorySite &&
        _lastBackAction != null &&
        now.difference(_lastBackAction!) < const Duration(milliseconds: 650)) {
      return;
    }
    _lastBackAction = now;
    _handlingBack = true;
    _navigationGuard.invalidate();
    _deadline?.cancel();
    _libraryErrorGrace?.cancel();
    try {
      // The native command stops the in-flight request before reading history.
      // This also works when JavaScript cannot run on a blank/error page.
      var snapshot = await _history.stopAndSnapshot();
      final live = Uri.tryParse(await _web.currentUrl() ?? '');
      final historyCurrent =
          snapshot.urls.elementAtOrNull(snapshot.currentIndex);
      final origin =
          _historyPolicy.isVisiblePage(live) ? live : historyCurrent ?? live;
      _backOrigin = origin;
      debugPrint('[web-back] stopped index=${snapshot.currentIndex} '
          'page=${_safeLocation(origin?.toString())}');
      final root = widget.canvasSite &&
              Uri.tryParse(widget.initialUrl)?.path.startsWith('/courses/') ==
                  true
          ? Uri.tryParse(widget.initialUrl)
          : _canvasHomeUri;
      var searchBefore = snapshot.currentIndex;
      var invalidHistoryRetries = 0;
      for (var attempt = 0; attempt < snapshot.urls.length; attempt++) {
        final targetIndex = _historyPolicy.previousVisibleIndex(
          urls: snapshot.urls,
          currentIndex: searchBefore,
          currentPage: origin,
          rootPage: root,
        );
        if (targetIndex == null) break;
        final target = snapshot.urls[targetIndex];
        _backTarget = target;
        _backStepFailed = false;
        _backTargetFinished = false;
        debugPrint('[web-back] history jump '
            'offset=${targetIndex - snapshot.currentIndex} '
            'target=${_safeLocation(target?.toString())}');
        try {
          await _history.goBackTo(target!, stepwise: widget.canvasSite);
        } on PlatformException catch (error) {
          if (error.code != 'invalid_history') rethrow;
          debugPrint('[web-back] history changed: ${error.message}');
          if (++invalidHistoryRetries >= 5) break;
          // A redirect may have changed the native index after the snapshot.
          // Re-read it without loading a URL, then choose the previous page.
          await Future<void>.delayed(const Duration(milliseconds: 60));
          snapshot = await _history.stopAndSnapshot();
          searchBefore = snapshot.currentIndex;
          continue;
        }
        var stableChecks = 0;
        for (var poll = 0; poll < 40; poll++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (!mounted || _closingWebPage) return;
          if (_backStepFailed) break;
          final current = Uri.tryParse(await _web.currentUrl() ?? '');
          if (_historyPolicy.samePage(current, target) &&
              !_historyPolicy.samePage(current, origin)) {
            stableChecks++;
            if ((_backTargetFinished && stableChecks >= 4) ||
                stableChecks >= 8) {
              debugPrint('[web-back] settled '
                  'page=${_safeLocation(current?.toString())}');
              _libraryAuthenticating = false;
              _libraryPersonalLoginRequested = false;
              _libraryFailedUrl = null;
              setState(() {
                _ready = true;
                _verification = false;
                _failed = false;
                _status = '';
              });
              return;
            }
          } else {
            stableChecks = 0;
          }
        }
        // A failed or redirected history entry is not a stopping point.
        snapshot = await _history.stopAndSnapshot();
        searchBefore = targetIndex < snapshot.currentIndex
            ? targetIndex
            : snapshot.currentIndex;
      }
      debugPrint('[web-back] no earlier visible entry; closing route');
      await _exitWebPage(result);
    } catch (error, stack) {
      debugPrint('WebView back navigation failed: $error\n$stack');
      await _exitWebPage(result);
    } finally {
      _backHoldUntil = DateTime.now().add(const Duration(milliseconds: 900));
      _handlingBack = false;
    }
  }

  void _onWebPointerDown(PointerDownEvent event) {
    if (!_compactHistorySite || _handlingBack) return;
    if (_graduatePlatform &&
        !WebGesturePolicy.startsAtHorizontalEdge(
          x: event.position.dx,
          viewportWidth: MediaQuery.sizeOf(context).width,
        )) {
      _swipePointer = null;
      _swipeStart = null;
      return;
    }
    _swipePointer = event.pointer;
    _swipeStart = event.position;
  }

  void _onWebPointerUp(PointerUpEvent event) {
    if (event.pointer != _swipePointer || _swipeStart == null) return;
    final delta = event.position - _swipeStart!;
    _swipePointer = null;
    _swipeStart = null;
    if (delta.dx.abs() < 88 || delta.dx.abs() < delta.dy.abs() * 1.5) {
      return;
    }
    unawaited(_handleCanvasBack(false, null));
  }

  Future<void> _exitWebPage(Object? result) async {
    if (!mounted || _closingWebPage) return;
    _closingWebPage = true;
    _navigationGuard.invalidate();
    _deadline?.cancel();
    _libraryErrorGrace?.cancel();
    _allowCanvasExit = true;
    try {
      await _history.stopLoading().timeout(const Duration(milliseconds: 300));
    } catch (_) {
      // Closing the route is still safer than reloading a broken WebView.
    }
    if (!mounted) return;
    // Removing this route leaves the preceding APP page and cookies intact.
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route != null) {
      navigator.removeRoute(route, result);
    } else {
      navigator.pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final header =
        widget.app.themeChoice.headerFor(Theme.of(context).brightness);
    final soft = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : widget.app.themeChoice.soft;
    final page = Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: _compactHistorySite
            ? IconButton(
                tooltip: '返回上一页',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _handleCanvasBack(false, null),
              )
            : null,
        actions: [
          if (_compactHistorySite || widget.showCloseButton)
            IconButton(
              tooltip: '关闭网页',
              onPressed: () => _exitWebPage(null),
              icon: const Icon(Icons.close),
            ),
          IconButton(
            tooltip: '重新加载',
            onPressed: _reloadFromStart,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Listener(
        onPointerDown: _onWebPointerDown,
        onPointerUp: _onWebPointerUp,
        onPointerCancel: (_) {
          _swipePointer = null;
          _swipeStart = null;
        },
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_ready && !_verification,
                child: Opacity(
                  opacity: _ready || _verification ? 1 : 0,
                  child: WebViewWidget(controller: _web),
                ),
              ),
            ),
            if (!_ready && !_verification)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_failed)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      else
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 40,
                          color: accent,
                        ),
                      const SizedBox(height: 16),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: header),
                      ),
                      if (_failed) ...[
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _reloadFromStart,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (_verification)
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: double.infinity,
                  color: soft,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: header,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (!widget.webHistory) return page;
    return PopScope<Object?>(
      canPop: _allowCanvasExit,
      onPopInvokedWithResult: _handleCanvasBack,
      child: page,
    );
  }
}
