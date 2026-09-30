import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/canvas_data.dart';
import '../services/canvas_extractor.dart';
import '../services/school_web_auth.dart';
import '../state/app_controller.dart';

class SessionSyncAgent extends StatefulWidget {
  const SessionSyncAgent({super.key, required this.app});
  final AppController app;

  @override
  State<SessionSyncAgent> createState() => _SessionSyncAgentState();
}

class _SessionSyncAgentState extends State<SessionSyncAgent> {
  late final WebViewController _controller;
  late final SchoolWebAuthenticator _auth;
  late final SyncLoader _loader;
  Completer<SyncBundle?>? _pending;
  Future<void>? _catalogCommit;
  Timer? _timeout;
  bool _scriptStarted = false;
  bool _handlingReady = false;
  bool _readyQueued = false;
  int _loginAttempts = 0;
  int _ssoAttempts = 0;
  final CanvasSyncAccumulator _accumulator = CanvasSyncAccumulator();

  @override
  void initState() {
    super.initState();
    _loader = _refresh;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('SyncBridge', onMessageReceived: _message)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _ready(),
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) {
            // Never log redirect URLs: they may contain SSO tickets.
            debugPrint('[canvas-sync] main-frame error '
                'code=${error.errorCode}');
          }
        },
      ))
      ..loadHtmlString('<html><body></body></html>');
    _auth = SchoolWebAuthenticator(_controller);
    widget.app.registerLoader(_loader);
  }

  Future<SyncBundle?> _refresh() async {
    if (_pending != null) return _pending!.future;
    final completer = Completer<SyncBundle?>();
    _pending = completer;
    _catalogCommit = null;
    _scriptStarted = false;
    _loginAttempts = 0;
    _ssoAttempts = 0;
    _accumulator.reset();
    _timeout?.cancel();
    debugPrint('[canvas-sync] stage=connecting');
    widget.app.updateCanvasSyncProgress(
      CanvasSyncStage.connecting,
      '正在连接 Canvas',
    );
    _timeout = Timer(const Duration(seconds: 180), () {
      debugPrint('[canvas-sync] timed out before a complete snapshot');
      _finish(null);
    });
    try {
      await _controller.loadRequest(Uri.parse(canvasUrl));
    } catch (error, stack) {
      debugPrint('[canvas-sync] Canvas page load failed: $error\n$stack');
      _finish(null);
    }
    return completer.future;
  }

  Future<void> _ready() async {
    if (!mounted || _pending == null || _scriptStarted) return;
    // Redirects can finish while an earlier page inspection is still awaiting
    // a WebView JavaScript result. Never evaluate two pages concurrently.
    _readyQueued = true;
    if (_handlingReady) return;
    _handlingReady = true;
    try {
      while (_readyQueued && mounted && _pending != null && !_scriptStarted) {
        _readyQueued = false;
        await _handleReady();
      }
    } catch (error, stack) {
      debugPrint('[canvas-sync] page callback failed: $error\n$stack');
      _finish(null);
    } finally {
      _handlingReady = false;
    }
  }

  Future<void> _handleReady() async {
    final uri = Uri.tryParse(await _controller.currentUrl() ?? '');
    if (!mounted || _pending == null || _scriptStarted) return;
    if (uri == null) return;
    // The controller's bootstrap about:blank may finish after a Canvas refresh
    // has started. It is not an authentication failure and must not complete
    // the pending synchronization.
    if (uri.scheme != 'https') return;
    if (uri.host == 'oc.sjtu.edu.cn' && uri.path.contains('/login')) {
      // The chooser's jAccount action navigates away. Calling it through
      // evaluateJavascript can invalidate Chromium's pending result callback
      // during the redirect (observed as WebContentsImpl NPE / native SIGSEGV
      // on Android WebView). Navigate to the same official SSO endpoint
      // directly, without a JavaScript callback tied to the old page.
      if (uri.path == '/login/openid_connect') return;
      if (_ssoAttempts >= 2) {
        debugPrint('[canvas-auth] SSO redirect did not complete');
        _finish(null);
        return;
      }
      _ssoAttempts++;
      try {
        await _controller.loadRequest(Uri.parse(canvasSsoUrl));
      } catch (error, stack) {
        debugPrint('[canvas-auth] SSO navigation failed: $error\n$stack');
        _finish(null);
      }
      return;
    }
    if (uri.host != 'oc.sjtu.edu.cn') {
      try {
        final inspection = await _auth.inspect('oc.sjtu.edu.cn');
        if (inspection.kind == SchoolPageKind.login &&
            widget.app.sessionPassword.isNotEmpty &&
            _loginAttempts < 2) {
          _loginAttempts++;
          if (!await _auth.submit(
            widget.app.sessionUsername,
            widget.app.sessionPassword,
          )) {
            debugPrint('[canvas-auth] jAccount form submission failed');
            _finish(null);
          }
        } else if (inspection.kind == SchoolPageKind.challenge ||
            inspection.kind == SchoolPageKind.outside ||
            (inspection.kind == SchoolPageKind.login &&
                widget.app.sessionPassword.isEmpty)) {
          debugPrint(
            '[canvas-auth] cannot continue hidden authentication: '
            '${inspection.kind} '
            '${inspection.uri?.host ?? ''}${inspection.uri?.path ?? ''}',
          );
          _finish(null);
        }
      } catch (error, stack) {
        debugPrint('[canvas-auth] authentication inspection failed: '
            '$error\n$stack');
        _finish(null);
      }
      return;
    }
    _scriptStarted = true;
    try {
      // The extractor reports solely through SyncBridge; it never needs an
      // evaluateJavascript result. Android System WebView on this device has
      // crashed in WebContentsImpl's result callback during long Canvas runs.
      // A javascript: load executes the same script without registering that
      // native result callback, leaving the Canvas request/data flow intact.
      await _controller.loadRequest(canvasExtractionScriptUri);
    } catch (error, stack) {
      debugPrint('[canvas-sync] extraction script failed: $error\n$stack');
      _finish(null);
    }
  }

  void _message(JavaScriptMessage message) {
    if (!mounted || _pending == null) return;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is Map) {
        final data = Map<String, dynamic>.from(decoded);
        final kind = '${data['kind'] ?? ''}';
        if (kind == 'diagnostic') {
          final stage = '${data['stage'] ?? 'unknown'}';
          final courseName = '${data['courseName'] ?? ''}';
          final courseId = '${data['courseId'] ?? ''}';
          final endpoint = '${data['endpoint'] ?? ''}';
          final status = '${data['httpStatus'] ?? 0}';
          final returned = '${data['returnedCount'] ?? 0}';
          final parsed = '${data['parsedCount'] ?? 0}';
          final error =
              '${data['error'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ');
          debugPrint(
            '[canvas-announcement] stage=$stage '
            'course="$courseName" courseId=$courseId endpoint=$endpoint '
            'http=$status returned=$returned parsed=$parsed'
            '${error.isEmpty ? '' : ' error=$error'}',
          );
        }
        if (kind == 'progress') {
          final stage = _stage('${data['stage'] ?? ''}');
          if (stage != widget.app.canvasSyncStage) {
            debugPrint('[canvas-sync] stage=${stage.name}');
          }
          widget.app.updateCanvasSyncProgress(
            stage,
            '${data['message'] ?? '正在同步 Canvas'}',
            completed: int.tryParse('${data['completed'] ?? 0}') ?? 0,
            total: int.tryParse('${data['total'] ?? 0}') ?? 0,
          );
          return;
        }
        final snapshot = _accumulator.add(data);
        if (snapshot == null) return;
        if (kind == 'catalogComplete') {
          _catalogCommit ??= _saveCatalog(snapshot);
          return;
        }
        unawaited(_finishAfterCatalog(snapshot));
      } else {
        _finish(null);
      }
    } catch (error, stack) {
      debugPrint('[canvas-sync] bridge message failed: $error\n$stack');
      _finish(null);
    }
  }

  Future<void> _saveCatalog(CanvasSnapshot snapshot) async {
    try {
      await widget.app.applyCanvasCatalog(snapshot);
    } catch (error, stack) {
      // A cache write must not become an uncaught asynchronous exception.
      // The completed snapshot still gets its normal save attempt below.
      debugPrint('[canvas-sync] catalog cache save failed: $error\n$stack');
    }
  }

  Future<void> _finishAfterCatalog(CanvasSnapshot snapshot) async {
    final pending = _pending;
    try {
      await _catalogCommit;
      if (!mounted || !identical(_pending, pending)) return;
      _finish(SyncBundle(widget.app.courses, snapshot));
    } catch (error, stack) {
      debugPrint('[canvas-sync] completion failed: $error\n$stack');
      if (mounted && identical(_pending, pending)) _finish(null);
    }
  }

  CanvasSyncStage _stage(String value) => switch (value) {
        'matching' => CanvasSyncStage.matching,
        'details' => CanvasSyncStage.details,
        _ => CanvasSyncStage.connecting,
      };

  void _finish(SyncBundle? value) {
    _timeout?.cancel();
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      debugPrint(
          '[canvas-sync] stage=${value == null ? 'failed' : 'complete'}');
      pending.complete(value);
    }
  }

  @override
  void dispose() {
    widget.app.unregisterLoader(_loader);
    _finish(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Opacity(
          opacity: 0,
          child: SizedBox(
              width: 1,
              height: 1,
              child: WebViewWidget(controller: _controller)),
        ),
      );
}
