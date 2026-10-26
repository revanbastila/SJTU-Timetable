import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/attendance.dart';
import '../services/school_web_auth.dart';
import '../state/app_controller.dart';
import '../services/canvas_extractor.dart';
import 'authenticated_web_page.dart';

/// A visible, cancellable browser session. It uses Canvas' discovered LTI tab,
/// not an assumed tool id or a guessed video URL. Login challenges remain here
/// for the user; capture/submission is impossible in connection-only mode.
class AttendanceWebPage extends StatefulWidget {
  const AttendanceWebPage({
    super.key,
    required this.app,
    required this.meeting,
    this.execute = false,
    this.keepOpen = false,
  });
  final AppController app;
  final AttendanceMeeting meeting;
  final bool execute;
  final bool keepOpen;
  @override
  State<AttendanceWebPage> createState() => _AttendanceWebPageState();
}

class _AttendanceWebPageState extends State<AttendanceWebPage>
    with WidgetsBindingObserver {
  WebViewController? _web;
  SchoolWebAuthenticator? _auth;
  Timer? _sampling, _limit;
  String _message = '正在读取课程入口…';
  AttendanceRecord? _executionRecord;
  int? _operation;
  int _openGeneration = 0;
  bool _retrying = false;
  Future<void>? _stopping;
  bool _captureBusy = false, _inspecting = false, _stopped = false;
  int _generation = 0,
      _loginAttempts = 0,
      _canvasAttempts = 0,
      _frameFailures = 0;
  double? _previousVideoTime;
  final Set<String> _visitedFrames = {};
  bool _sawCourse = false, _connected = false;
  bool _canvasSessionAttempted = false;
  int? get _webId => _web?.platform is AndroidWebViewController
      ? (_web!.platform as AndroidWebViewController).webViewIdentifier
      : null;
  bool get _active => mounted && !_stopped && widget.app.attendance.enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.attendance.addListener(_stateChanged);
    _executionRecord = widget.app.attendance.pendingRecord;
    _operation = widget.app.attendance.operation;
    unawaited(_open());
  }

  void _stateChanged() {
    if (!mounted) return;
    final state = widget.app.attendance;
    if (!state.enabled ||
        (widget.execute && !state.ownsOperation(_operation))) {
      unawaited(_stop());
      setState(
        () =>
            _message = state.detail.isEmpty ? state.phase.label : state.detail,
      );
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        widget.execute &&
        !_stopped &&
        widget.app.attendance.ownsOperation(_operation)) {
      unawaited(widget.app.attendance.cancel());
      unawaited(_stop());
    }
  }

  Future<void> _open({bool refresh = false}) async {
    final opening = ++_openGeneration;
    try {
      final tabs = await widget.app.attendanceBackend.tabs(
        widget.meeting.canvasId,
        refresh: refresh,
      );
      if (!_active || opening != _openGeneration) return;
      if (['login', 'canvas_login'].contains(tabs['status'])) {
        if (_canvasSessionAttempted) {
          _failure('Canvas 登录尚未完成，请返回后重试');
          return;
        }
        _canvasSessionAttempted = true;
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AuthenticatedWebPage(
              title: 'Canvas 登录',
              initialUrl: canvasSsoUrl,
              targetHost: 'oc.sjtu.edu.cn',
              app: widget.app,
              canvasSite: true,
              ssoFallbackUrl: canvasSsoUrl,
              showCloseButton: true,
            ),
          ),
        );
        if (_active) await _open();
        return;
      }
      if (tabs['status'] != 'ok') {
        _failure(attendanceEntryFailure('${tabs['status']}'));
        return;
      }
      final raw = tabs[widget.execute ? 'liveUrl' : 'attendanceUrl'];
      final uri = raw is String ? Uri.tryParse(raw) : null;
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'oc.sjtu.edu.cn' ||
          !RegExp(
            '^/courses/${widget.meeting.canvasId}/external_tools/'
            r'[0-9]+$',
          ).hasMatch(uri.path) ||
          uri.userInfo.isNotEmpty ||
          (uri.hasPort && uri.port != 443)) {
        _failure(widget.execute ? '当前课程未提供“课堂视频新版”入口' : '当前课程未提供“点名签到”入口');
        return;
      }
      _sawCourse =
          true; // The authenticated tabs response binds this URL to the exact course ID.
      final web = WebViewController();
      _web = web;
      _auth = SchoolWebAuthenticator(web);
      await web.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (web.platform is AndroidWebViewController) {
        await (web.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }
      await web.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (opening != _openGeneration) return NavigationDecision.prevent;
            final target = Uri.tryParse(request.url);
            if (_stopped && target?.scheme != 'about') {
              return NavigationDecision.prevent;
            }
            if (target?.scheme != 'https' && target?.scheme != 'about') {
              _failure('当前链接无法在安全连接中打开');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (opening != _openGeneration) return;
            _generation++;
            _connected = false;
          },
          onPageFinished: (_) {
            if (opening == _openGeneration) unawaited(_inspect());
          },
          onWebResourceError: (error) {
            if (opening == _openGeneration && error.isForMainFrame == true) {
              _failure('页面加载失败，请返回后重试');
            }
          },
        ),
      );
      if (!_active) return;
      if (_webId != null) {
        await widget.app.attendanceBackend.installLtiNavigation(_webId!);
      }
      if (!_active) return;
      setState(() => _message = widget.execute ? '正在进入课堂视频新版…' : '正在连接点名签到…');
      await web.loadRequest(uri);
      _limit = Timer(const Duration(minutes: 2), () {
        _failure(widget.execute ? '本次未能完成直播识别，请检查直播是否已开始' : '连接超时，请完成登录后重试');
      });
      _sampling = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_active && !_captureBusy) unawaited(_inspect());
      });
    } catch (_) {
      if (mounted && opening == _openGeneration && _active) {
        _failure('课程入口请求失败或超时，请检查网络后重试');
      }
    }
  }

  Map<String, dynamic> _decode(Object raw) {
    dynamic value = raw;
    for (var i = 0; i < 2 && value is String; i++) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        break;
      }
    }
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  Future<void> _inspect() async {
    if (!_active || _inspecting || _web == null || _connected) return;
    _inspecting = true;
    final epoch = _generation;
    try {
      final web = _web!;
      final uri = Uri.tryParse(await web.currentUrl() ?? '');
      if (!_active || epoch != _generation || uri == null) return;
      if (uri.host == 'oc.sjtu.edu.cn' &&
          uri.path.startsWith(
            '/courses/${widget.meeting.canvasId}/external_tools/',
          )) {
        _sawCourse = true;
      }
      if (uri.host == 'jaccount.sjtu.edu.cn') {
        final state = await _auth!.inspect('mlearning.sjtu.edu.cn');
        if (!_active || epoch != _generation) return;
        if (state.kind == SchoolPageKind.challenge ||
            widget.app.sessionPassword.isEmpty) {
          setState(() => _message = '请在页面中完成学校身份验证');
          return;
        }
        if (state.kind == SchoolPageKind.login && _loginAttempts < 2) {
          _loginAttempts++;
          await _auth!.submit(
            widget.app.sessionUsername,
            widget.app.sessionPassword,
            expectedUrl: state.uri?.toString(),
          );
        }
        return;
      }
      if (uri.host == 'oc.sjtu.edu.cn' && uri.path.startsWith('/login')) {
        if (_canvasAttempts++ < 2) {
          await _auth!.clickCanvasJaccount(
            expectedUrl: uri.toString(),
            attempts: 1,
            shouldContinue: () => _active && epoch == _generation,
          );
        }
        return;
      }
      if (!widget.execute) {
        if (!_sawCourse ||
            uri.host != 'mlearning.sjtu.edu.cn' ||
            !uri.path.startsWith('/lms/rollcall/')) {
          return;
        }
        final data = _decode(
          await web.runJavaScriptReturningResult(r'''
          (() => {
            const query = new URL(location.href).searchParams;
            const courseCode = query.get('courseCode') || '';
            const token = window.RollCall_Access_Token || '';
            return JSON.stringify({courseCode, token});
          })()
        '''),
        );
        if (!_active || epoch != _generation) return;
        if (data['courseCode'] is! String ||
            data['token'] is! String ||
            (data['token'] as String).isEmpty) {
          setState(() => _message = '请完成点名签到页面的登录');
          return;
        }
        await widget.app.attendanceBackend.saveConnection(
          widget.meeting.canvasId,
          data['courseCode'],
          data['token'],
        );
        if (!_active || epoch != _generation) return;
        if (widget.keepOpen) {
          _connected = true;
          _sampling?.cancel();
          _limit?.cancel();
          setState(() => _message = '已连接，请在学校页面核实并完成签到');
          unawaited(widget.app.attendance.inspectManually(widget.meeting));
        } else {
          await _stop();
          if (mounted) Navigator.of(context).pop(true);
          unawaited(widget.app.attendance.inspectManually(widget.meeting));
        }
        return;
      }
      if (!_sawCourse || !widget.app.attendance.executing) return;
      final frame = _decode(
        await web.runJavaScriptReturningResult(attendanceVideoProbe),
      );
      if (!_active || epoch != _generation) return;
      if (frame['playing'] != true) {
        final child = frame['frame'];
        if (child is String &&
            _visitedFrames.length < 3 &&
            _visitedFrames.add(child)) {
          final target = Uri.tryParse(child);
          if (target?.scheme == 'https' && target?.userInfo.isEmpty == true) {
            await web.loadRequest(target!);
          }
        }
        setState(
          () => _message =
              frame['message'] is String ? frame['message'] : '等待直播开始或点击播放',
        );
        return;
      }
      final currentTime = (frame['time'] as num?)?.toDouble();
      if (currentTime == null ||
          _previousVideoTime == null ||
          currentTime <= _previousVideoTime!) {
        _previousVideoTime = currentTime;
        return;
      }
      _previousVideoTime = currentTime;
      widget.app.attendance.scanning(operation: _operation);
      if (_webId == null) {
        _failure('当前设备不支持应用内视频识别');
        return;
      }
      _captureBusy = true;
      try {
        final qr = await widget.app.attendanceBackend.captureQr(_webId!, {
          for (final key in ['x', 'y', 'width', 'height']) key: frame[key],
        });
        if (_active && epoch == _generation && qr != null) {
          widget.app.attendance.acceptQr(qr, operation: _operation);
        }
        _frameFailures = 0;
      } catch (_) {
        if (++_frameFailures >= 5) _failure('未能取得有效视频画面，播放器可能受保护');
      } finally {
        _captureBusy = false;
      }
    } catch (_) {
      if (_active) setState(() => _message = '正在等待页面就绪…');
    } finally {
      _inspecting = false;
    }
  }

  void _failure(String message) {
    if (!mounted || _stopped) return;
    unawaited(_stop());
    if (widget.execute) {
      widget.app.attendance.report(
        AttendancePhase.failed,
        message,
        operation: _operation,
      );
    }
    setState(() => _message = message);
  }

  Future<void> _stop() {
    if (_stopping != null) return _stopping!;
    _stopped = true;
    _openGeneration++;
    _generation++;
    _sampling?.cancel();
    _limit?.cancel();
    final web = _web;
    final id = _webId;
    _web = null;
    return _stopping = _release(web, id);
  }

  Future<void> _release(WebViewController? web, int? id) async {
    try {
      if (id != null) {
        await widget.app.attendanceBackend.releaseWeb(id);
      }
      await web?.loadHtmlString('<html><body></body></html>');
    } catch (_) {}
  }

  Future<void> _retry() async {
    if (_retrying || !widget.app.attendance.enabled) return;
    setState(() => _retrying = true);
    try {
      await _stop();
      if (widget.execute) {
        final record = _executionRecord;
        if (record == null ||
            !await widget.app.attendance.retryExecution(
              record,
              widget.meeting,
            )) {
          if (mounted) {
            setState(
              () => _message = widget.app.attendance.detail.isEmpty
                  ? '当前签到已完成或检测窗口已结束，请返回检查记录'
                  : widget.app.attendance.detail,
            );
          }
          return;
        }
        _operation = widget.app.attendance.operation;
      }
      if (!mounted) return;
      setState(() {
        _stopped = false;
        _stopping = null;
        _web = null;
        _auth = null;
        _message = '正在重新读取课程入口…';
        _canvasSessionAttempted = false;
        _canvasAttempts = 0;
        _loginAttempts = 0;
        _frameFailures = 0;
        _previousVideoTime = null;
        _visitedFrames.clear();
        _sawCourse = false;
        _connected = false;
      });
      await _open(refresh: true);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _cancel() async {
    if (widget.execute && widget.app.attendance.ownsOperation(_operation)) {
      await widget.app.attendance.cancel();
    }
    await _stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.app.attendance.removeListener(_stateChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stop());
    if (widget.execute && widget.app.attendance.ownsOperation(_operation)) {
      unawaited(widget.app.attendance.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.execute ? '执行签到' : '连接点名签到'),
          leading: IconButton(
            onPressed: _cancel,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [TextButton(onPressed: _cancel, child: const Text('取消'))],
        ),
        body: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(widget.meeting.course.name),
              subtitle: Text(
                widget.execute && !_stopped
                    ? widget.app.attendance.phase.label
                    : _message,
              ),
            ),
            if (!_stopped && !_connected)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _web == null || _stopped
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_message, textAlign: TextAlign.center),
                            if (_stopped && widget.app.attendance.enabled) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _retrying ? null : _retry,
                                icon: const Icon(Icons.refresh),
                                label: Text(_retrying ? '正在重试…' : '重试当前课程'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : WebViewWidget(controller: _web!),
            ),
          ],
        ),
      );
}

String attendanceEntryFailure(String status) => switch (status) {
      'canvas_login' || 'login' => 'Canvas 登录已失效，请完成登录后重试',
      'permission' => '当前账号无权访问这门课程，请核对 Canvas 课程权限',
      'timeout' => '读取课程入口超时，请检查网络后重试',
      'network' => '读取课程入口时网络连接失败，请恢复网络后重试',
      'server' => 'Canvas 服务暂时异常，请稍后重试当前课程',
      'format' => '课程入口响应无法解析，请重试或在 Canvas 中检查课程',
      'no_entry' => '当前课程确实未提供所需入口',
      _ => '课程入口暂不可用，请重试当前课程',
    };

/// Reads the actual displayed player. It never selects a replay, pauses the
/// video to retain an old QR, or assumes a Canvas tool/player URL.
const attendanceVideoProbe = r'''
(() => {
  const visible = n => n && n.getBoundingClientRect().width > 32 && n.getBoundingClientRect().height > 32;
  const videos = [...document.querySelectorAll('video')].filter(visible);
  const video = videos.find(v => !v.paused && v.readyState >= 2 && v.videoWidth > 0 && v.videoHeight > 0);
  if (video) {
    const r=video.getBoundingClientRect();
    const left=Math.max(0,r.left), top=Math.max(0,r.top);
    const right=Math.min(innerWidth,r.right), bottom=Math.min(innerHeight,r.bottom);
    return JSON.stringify({playing:true,time:video.currentTime,x:left/innerWidth,y:top/innerHeight,
      width:(right-left)/innerWidth,height:(bottom-top)/innerHeight});
  }
  const live = [...document.querySelectorAll('a,button,[role=tab],[role=button]')]
    .find(n => visible(n) && (n.innerText || '').replace(/\s+/g,'') === '直播');
  if (live && !window.__attendanceLiveTabSelected) {
    window.__attendanceLiveTabSelected=true; live.click();
    return JSON.stringify({playing:false,message:'正在进入直播'});
  }
  const ongoing=[...document.querySelectorAll('a,button,[role=button]')].filter(n => {
    const text=(n.innerText || '').trim();
    return visible(n) && /直播中/.test(text) && !/回放|历史|未开始|已结束/.test(text);
  });
  if (ongoing.length === 1 && !window.__attendanceLiveSelected) {
    window.__attendanceLiveSelected=true; ongoing[0].click();
    return JSON.stringify({playing:false,message:'正在播放当前直播'});
  }
  if (videos.length === 1 && !window.__attendancePlayTried) {
    window.__attendancePlayTried=true; videos[0].play().catch(()=>{});
  }
  const frames=[...document.querySelectorAll('iframe')].filter(visible)
    .map(n=>n.src).filter(u=>/^https:\/\//.test(u));
  return JSON.stringify({playing:false,frame:frames.length===1 ? frames[0] : null,
    message:ongoing.length > 1 ? '存在多个直播，请在页面中选择当前课程' : '等待直播开始或点击播放'});
})()
''';
