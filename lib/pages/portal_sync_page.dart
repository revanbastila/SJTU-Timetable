import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/app_theme.dart';
import '../models/course.dart';
import '../services/course_normalizer.dart';
import '../services/portal_extractor.dart';
import '../services/school_web_auth.dart';
import '../state/app_controller.dart';

const portalUrl = 'https://yjsxk.sjtu.edu.cn/yjsxkapp/sys/xsxkapp/index.html';
const portalLoginUrl =
    'https://yjsxk.sjtu.edu.cn/yjsxkapp/sys/xsxkapp/*default/index.do';

class PortalSyncPage extends StatefulWidget {
  const PortalSyncPage({
    super.key,
    required this.username,
    required this.password,
    required this.app,
    this.rememberMe = false,
  });

  final String username;
  final String password;
  final AppController app;
  final bool rememberMe;

  @override
  State<PortalSyncPage> createState() => _PortalSyncPageState();
}

class _PortalSyncPageState extends State<PortalSyncPage> {
  late final WebViewController _web;
  late final SchoolWebAuthenticator _auth;
  Timer? _deadline;
  String _status = '正在连接教务系统…';
  bool _showSchoolPage = false;
  bool _failed = false;
  bool _automationRunning = false;
  bool _sessionCheckRunning = false;
  bool _manualMode = false;
  bool _completed = false;
  bool _challengeCredentialsFilled = false;
  bool _profileReadRunning = false;
  Completer<Map<String, dynamic>>? _profilePending;
  String? _profileRequestId;
  int _loginAttempts = 0;
  int _portalAuthAttempts = 0;
  int _generation = 0;
  String _stage = 'auth';

  String get _username => widget.username.trim().isNotEmpty
      ? widget.username.trim()
      : widget.app.sessionUsername;
  String get _password =>
      widget.password.isNotEmpty ? widget.password : widget.app.sessionPassword;

  @override
  void initState() {
    super.initState();
    if (widget.password.isNotEmpty) {
      widget.app.retainSessionCredentials(widget.username, widget.password);
    }
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!_completed && !_showSchoolPage && !_profileReadRunning) {
              _setStatus('正在建立学校登录会话…');
            }
          },
          onPageFinished: (_) => _pageReady(),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              if (_profileReadRunning) return;
              _failStage(
                _stage,
                _stage == 'auth' ? '教务系统认证页面加载失败，请重试' : '课表接口请求失败，请重试',
                error: error.description,
              );
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'PortalProfile',
        onMessageReceived: (message) {
          try {
            final result = _decodeJsonMap(message.message);
            final pending = _profilePending;
            if (pending != null &&
                !pending.isCompleted &&
                result['requestId'] == _profileRequestId) {
              pending.complete(result);
            }
          } catch (error) {
            debugPrint('[portal-profile] response bridge parse failed: '
                '${error.runtimeType}');
          }
        },
      );
    _auth = SchoolWebAuthenticator(_web);
    _retry();
  }

  @override
  void dispose() {
    _deadline?.cancel();
    final pending = _profilePending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const <String, dynamic>{});
    }
    super.dispose();
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  void _startDeadline() {
    _deadline?.cancel();
    final generation = _generation;
    _deadline = Timer(const Duration(seconds: 50), () {
      if (generation == _generation && !_completed && !_showSchoolPage) {
        _failStage(_stage, _stage == 'auth' ? '教务系统认证超时，请重试' : '课表接口响应超时，请重试');
      }
    });
  }

  Future<void> _retry() async {
    _deadline?.cancel();
    _generation++;
    _loginAttempts = 0;
    _portalAuthAttempts = 0;
    _automationRunning = false;
    _sessionCheckRunning = false;
    _manualMode = false;
    _challengeCredentialsFilled = false;
    _stage = 'auth';
    if (mounted) {
      setState(() {
        _failed = false;
        _showSchoolPage = false;
        _status = '正在连接教务系统…';
      });
    }
    _startDeadline();
    await _web.loadRequest(Uri.parse(portalLoginUrl));
  }

  Future<void> _pageReady() async {
    if (_completed || _failed || _profileReadRunning) return;
    if (_manualMode) return;
    SchoolPageInspection inspection;
    try {
      inspection = await _auth.inspect('yjsxk.sjtu.edu.cn');
    } catch (error, stack) {
      debugPrint('School page inspection failed: $error\n$stack');
      _failStage('auth', '无法确认教务系统登录状态，请重试', error: error);
      return;
    }
    if (_completed || _failed) return;

    switch (inspection.kind) {
      case SchoolPageKind.target:
        // Extra verification is complete. Subsequent profile reads stay in
        // this hidden WebView and must never expose the selection page.
        if (_showSchoolPage && mounted) {
          setState(() => _showSchoolPage = false);
        }
        await _verifyPortalSession();
        return;
      case SchoolPageKind.login:
        await _submitLogin();
        return;
      case SchoolPageKind.challenge:
        if (!_challengeCredentialsFilled && _password.isNotEmpty) {
          _challengeCredentialsFilled = true;
          try {
            await _auth.fill(_username, _password);
          } catch (error, stack) {
            debugPrint(
              '[portal-auth] challenge credential fill failed: $error\n$stack',
            );
          }
        }
        _deadline?.cancel();
        if (mounted) {
          setState(() {
            _showSchoolPage = true;
            _status = '学校要求额外验证，完成后将自动继续';
          });
        }
        return;
      case SchoolPageKind.transition:
        _setStatus('学校正在完成登录跳转…');
        return;
      case SchoolPageKind.outside:
        _failStage('auth', '登录跳转异常，请重试');
        return;
    }
  }

  Future<void> _submitLogin() async {
    if (_password.isEmpty) {
      _failStage('auth', '登录状态已过期，请返回登录页重新验证');
      return;
    }
    if (_loginAttempts >= 2) {
      if (mounted) {
        setState(() {
          _showSchoolPage = true;
          _status = '学校未接受自动登录，请检查是否需要额外验证';
        });
      }
      _deadline?.cancel();
      return;
    }
    _loginAttempts++;
    _setStatus('正在使用 jAccount 自动登录…');
    try {
      final submitted = await _auth.submit(_username, _password);
      if (!submitted) {
        _failStage('auth', '无法提交学校登录页面，请重试');
      } else {
        _startDeadline();
      }
    } catch (error, stack) {
      debugPrint('Automatic jAccount submit failed: $error\n$stack');
      _failStage('auth', '自动登录失败，请重试', error: error);
    }
  }

  Future<void> _verifyPortalSession() async {
    if (_sessionCheckRunning || _automationRunning || _completed) return;
    _sessionCheckRunning = true;
    final generation = _generation;
    _setStatus('正在确认教务系统登录状态…');
    try {
      for (var attempt = 0; attempt < 36; attempt++) {
        if (generation != _generation || _completed) return;
        final raw = await _web.runJavaScriptReturningResult(
          portalSessionProbeScript,
        );
        final probe = _decodeJsonMap(raw);
        final state = '${probe['state'] ?? ''}';
        if (state == 'complete') {
          if (probe['authenticated'] == true) {
            _stage = 'request';
            _setStatus('登录状态已确认，正在自动获取课表…');
            await _startAutomaticImport();
            return;
          }
          if (_portalAuthAttempts >= 2) {
            _failStage('auth', '教务系统认证失败，请重试');
            return;
          }
          _portalAuthAttempts++;
          _setStatus('正在建立教务系统登录会话…');
          _sessionCheckRunning = false;
          await _web.loadRequest(Uri.parse(portalLoginUrl));
          return;
        }
        if (state == 'error') {
          _failStage('auth', '无法确认教务系统登录状态，请重试', error: probe['error']);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (generation == _generation) {
        _failStage('auth', '教务系统登录状态确认超时，请重试');
      }
    } catch (error, stack) {
      debugPrint('[portal-auth] session verification failed: $error\n$stack');
      if (generation == _generation) {
        _failStage('auth', '无法确认教务系统登录状态，请重试');
      }
    } finally {
      if (generation == _generation) _sessionCheckRunning = false;
    }
  }

  Future<void> _startAutomaticImport() async {
    if (_automationRunning || _completed) return;
    _automationRunning = true;
    final generation = _generation;
    try {
      await _web.runJavaScript(portalCaptureBootstrapScript);
      await _web.runJavaScript(portalStartTimetableFetchScript);
      Map<String, dynamic> request = const {'state': 'idle'};
      for (var attempt = 0; attempt < 40; attempt++) {
        if (generation != _generation || _completed) return;
        request = _decodeJsonMap(
          await _web.runJavaScriptReturningResult(
            portalTimetableFetchResultScript,
          ),
        );
        if (request['state'] == 'complete' ||
            request['state'] == 'error' ||
            request['state'] == 'auth-required') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      if (request['state'] == 'auth-required') {
        debugPrint(
          '[portal-auth] timetable endpoint requested authentication: '
          'url=${request['finalUrl']} error=${request['error']}',
        );
        if (_portalAuthAttempts >= 2) {
          _offerManualImport(
            'auth',
            '自动登录状态未能传递。请在下方完成登录并打开“我的课表”，然后点击“导入课表”。',
          );
          return;
        }
        _portalAuthAttempts++;
        _stage = 'auth';
        _automationRunning = false;
        final requested = Uri.tryParse('${request['loginUrl'] ?? ''}');
        final safeLoginUrl = requested != null &&
                (requested.host == 'jaccount.sjtu.edu.cn' ||
                    requested.host == 'yjsxk.sjtu.edu.cn')
            ? requested
            : Uri.parse(portalLoginUrl);
        _setStatus('课表接口要求重新验证，正在继续登录…');
        await _web.loadRequest(safeLoginUrl);
        return;
      }
      if (request['state'] == 'error') {
        debugPrint(
          '[portal-request] status=${request['status']} '
          'error=${request['error']} url=${request['finalUrl']} '
          'contentType=${request['contentType']} '
          'summary=${request['summary']}',
        );
        if (await _tryDomFallback(generation)) return;
        if (generation == _generation) {
          _offerManualImport('request', '自动请求课表失败。请在下方打开“我的课表”，然后点击“导入课表”。');
        }
        return;
      }
      if (request['state'] != 'complete') {
        debugPrint('[portal-request] timetable endpoint timed out');
        if (await _tryDomFallback(generation)) return;
        if (generation == _generation) {
          _offerManualImport('request', '课表接口响应超时。请在下方打开“我的课表”，然后点击“导入课表”。');
        }
        return;
      }

      Object? lastParseError;
      for (var attempt = 0; attempt < 8; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        try {
          final courses = await _extractCourses();
          if (generation != _generation) return;
          if (courses.any((course) => course.hasSchedule)) {
            await _saveAndFinish(courses);
            return;
          }
        } catch (error, stack) {
          lastParseError = error;
          debugPrint('[portal-parse] extraction failed: $error\n$stack');
        }
      }
      if (generation == _generation) {
        debugPrint(
          '[portal-parse] no scheduled course; keys=${request['keys']} '
          'arrays=${request['arrays']} error=$lastParseError',
        );
        _offerManualImport(
          'parse',
          '自动解析未得到有效课表。请在下方打开“我的课表”，然后点击“导入课表”。',
          error: lastParseError,
        );
      }
    } catch (error, stack) {
      debugPrint('[portal-request] automatic import failed: $error\n$stack');
      if (generation == _generation) {
        _offerManualImport(
          'request',
          '自动获取课表失败。请在下方打开“我的课表”，然后点击“导入课表”。',
          error: error,
        );
      }
    } finally {
      if (generation == _generation) _automationRunning = false;
    }
  }

  Future<bool> _tryDomFallback(int generation) async {
    try {
      await _web.runJavaScriptReturningResult(portalOpenTimetableScript);
      for (var attempt = 0; attempt < 6; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (generation != _generation || _completed) return false;
        final courses = await _extractCourses();
        if (courses.any((course) => course.hasSchedule)) {
          await _saveAndFinish(courses);
          return true;
        }
      }
    } catch (error, stack) {
      debugPrint('[portal-request] timetable fallback failed: $error\n$stack');
    }
    return false;
  }

  Future<List<Course>> _extractCourses() async {
    final raw = await _web.runJavaScriptReturningResult(portalExtractionScript);
    dynamic decoded = raw;
    for (var attempt = 0; attempt < 2 && decoded is String; attempt++) {
      decoded = jsonDecode(decoded);
    }
    if (decoded is! List) {
      throw const FormatException('portal extractor returned a non-list value');
    }
    if (decoded.isEmpty) return const [];
    final parsed = <Course>[
      for (var i = 0; i < decoded.length; i++)
        if (decoded[i] is Map)
          Course.fromMap(
            Map<String, dynamic>.from(decoded[i] as Map),
            index: i,
            totalWeeks: widget.app.totalWeeks,
          ),
    ];
    if (parsed.isEmpty) {
      throw const FormatException('portal extractor returned no valid rows');
    }
    return normalizePortalCourses(parsed, totalWeeks: widget.app.totalWeeks);
  }

  Future<void> _manualImport() async {
    if (_automationRunning || _completed) return;
    _automationRunning = true;
    _setStatus('正在读取当前打开的课表…');
    try {
      await _web.runJavaScript(portalCaptureBootstrapScript);
      final courses = await _extractCourses();
      if (courses.any((course) => course.hasSchedule)) {
        await _saveAndFinish(courses);
      } else {
        _setStatus('尚未检测到课表，请先打开“我的课表”，再点击“导入课表”');
      }
    } catch (error, stack) {
      debugPrint('[portal-parse] manual import failed: $error\n$stack');
      _setStatus('当前页面没有可导入的课表，请打开“我的课表”后重试');
    } finally {
      _automationRunning = false;
    }
  }

  Map<String, dynamic> _decodeJsonMap(dynamic raw) {
    dynamic decoded = raw;
    for (var attempt = 0; attempt < 2 && decoded is String; attempt++) {
      decoded = jsonDecode(decoded);
    }
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : const <String, dynamic>{};
  }

  Future<void> _saveAndFinish(List<Course> courses) async {
    _setStatus('课表已获取，正在保存…');
    try {
      // The plan view stays hidden; popping this route earlier destroys the
      // WebView before its profile fields can be read.
      final studentProfileRead = _readStudentProfileFromPlan();
      final result = await widget.app.saveSyncedData(
        _username,
        courses,
        widget.app.canvas,
        remember: widget.rememberMe,
      );
      final sessionGeneration = widget.app.sessionGeneration;
      try {
        final found = await studentProfileRead.timeout(
          const Duration(seconds: 6),
          onTimeout: () => const <String, dynamic>{},
        );
        final number = '${found['studentNumber'] ?? ''}';
        final name = '${found['studentName'] ?? ''}';
        final college = '${found['studentCollege'] ?? ''}';
        debugPrint(
          '[portal-profile] plan parse: '
          'number=${number.isNotEmpty}, name=${name.isNotEmpty}, '
          'college=${college.isNotEmpty}, '
          'diagnostics=${found['diagnostics']}',
        );
        await widget.app.saveStudentProfileForSession(
          _username,
          number,
          name,
          sessionGeneration,
          college: college,
        );
      } catch (error) {
        debugPrint(
          '[portal-profile] hidden profile read unavailable: '
          '${error.runtimeType}',
        );
      }
      if (result.notificationWarning != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('课表已导入，但课程提醒更新失败。')));
      }
      _completed = true;
      _deadline?.cancel();
      if (mounted) Navigator.of(context).pop();
    } catch (error, stack) {
      debugPrint('Automatic portal save failed: $error\n$stack');
      _failStage('save', '课表已读取，但保存失败，请重试', error: error);
    }
  }

  Future<Map<String, dynamic>> _readStudentProfileFromPlan() async {
    _profileReadRunning = true;
    final requestId = '${_generation}_${DateTime.now().microsecondsSinceEpoch}';
    final pending = Completer<Map<String, dynamic>>();
    _profilePending = pending;
    _profileRequestId = requestId;
    try {
      await _web.runJavaScript(
        portalStudentProfileRequestScript.replaceFirst(
          '__PROFILE_REQUEST_ID__',
          requestId,
        ),
      );
      return await pending.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => const <String, dynamic>{
          'diagnostics': {'stage': 'timeout'},
        },
      );
    } catch (error) {
      debugPrint(
        '[portal-profile] plan endpoint unavailable: '
        '${error.runtimeType}',
      );
      return const <String, dynamic>{
        'diagnostics': {'stage': 'bridge'},
      };
    } finally {
      if (identical(_profilePending, pending)) {
        _profilePending = null;
        _profileRequestId = null;
      }
      _profileReadRunning = false;
    }
  }

  void _failStage(String stage, String message, {Object? error}) {
    _stage = stage;
    debugPrint('[portal-$stage] $message${error == null ? '' : ': $error'}');
    _fail(message);
  }

  void _offerManualImport(String stage, String message, {Object? error}) {
    if (_completed || !mounted) return;
    _deadline?.cancel();
    _stage = stage;
    debugPrint('[portal-$stage] $message${error == null ? '' : ': $error'}');
    setState(() {
      _failed = false;
      _manualMode = true;
      _showSchoolPage = true;
      _status = message;
    });
  }

  void _fail(String message) {
    if (_completed || !mounted) return;
    _deadline?.cancel();
    setState(() {
      _failed = true;
      _showSchoolPage = false;
      _status = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final header =
        widget.app.themeChoice.headerFor(Theme.of(context).brightness);
    final soft = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : widget.app.themeChoice.soft;
    return Scaffold(
      appBar: AppBar(
        title: const Text('自动同步课表'),
        actions: [
          if (_manualMode)
            TextButton(onPressed: _manualImport, child: const Text('导入课表')),
          IconButton(
            tooltip: '重新尝试',
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: soft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: header),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_showSchoolPage,
                    child: Opacity(
                      opacity: _showSchoolPage ? 1 : 0,
                      child: WebViewWidget(controller: _web),
                    ),
                  ),
                ),
                if (!_showSchoolPage)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_failed)
                            const SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                              ),
                            )
                          else
                            Icon(
                              Icons.sync_problem_outlined,
                              size: 42,
                              color: accent,
                            ),
                          const SizedBox(height: 18),
                          Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: header),
                          ),
                          if (_failed) ...[
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重试'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
