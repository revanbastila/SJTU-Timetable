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
    unawaited(_open());
  }

  void _stateChanged() {
    if (!mounted) return;
    final state = widget.app.attendance;
    if (!state.enabled || (widget.execute && !state.executing)) {
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
    if (state == AppLifecycleState.paused && widget.execute && !_stopped) {
      unawaited(widget.app.attendance.cancel());
      unawaited(_stop());
    }
  }

  Future<void> _open() async {
    try {
      final tabs = await widget.app.attendanceBackend.tabs(
        widget.meeting.canvasId,
      );
      if (!_active) return;
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
        _failure('暂时无法读取课程入口，请检查网络与课程访问权限');
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
          ).hasMatch(uri.path)) {
        _failure(widget.execute ? '当前课程未提供“课堂视频新版”入口' : '当前课程未提供“点名签到”入口');
        return;
      }
      _sawCourse = true; // The authenticated tabs response binds this URL to the exact course ID.
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
            _generation++;
            _connected = false;
          },
          onPageFinished: (_) => unawaited(_inspect()),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) _failure('页面加载失败，请返回后重试');
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
      if (mounted) _failure('课程入口暂不可用，请先完成 Canvas 登录');
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
          () => _message = frame['message'] is String
              ? frame['message']
              : '等待直播开始或点击播放',
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
      widget.app.attendance.scanning();
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
          widget.app.attendance.acceptQr(qr);
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
    if (widget.execute) {
      widget.app.attendance.report(AttendancePhase.failed, message);
    }
    unawaited(_stop());
    setState(() => _message = message);
  }

  Future<void> _stop() async {
    if (_stopped) return;
    _stopped = true;
    _generation++;
    _sampling?.cancel();
    _limit?.cancel();
    try {
      if (_webId != null) {
        await widget.app.attendanceBackend.releaseWeb(_webId!);
      }
      await _web?.loadHtmlString('<html><body></body></html>');
    } catch (_) {}
  }

  Future<void> _cancel() async {
    if (widget.execute && widget.app.attendance.executing) {
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
    if (widget.execute && widget.app.attendance.executing) {
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
              ? Center(child: Text(_message))
              : WebViewWidget(controller: _web!),
        ),
      ],
    ),
  );
}

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
