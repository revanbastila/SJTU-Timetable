import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/attendance.dart';
import '../pages/attendance_web_page.dart';
import '../state/app_controller.dart';

class AttendanceObserver extends StatefulWidget {
  const AttendanceObserver({super.key, required this.app});
  final AppController app;
  @override
  State<AttendanceObserver> createState() => _AttendanceObserverState();
}

class _AttendanceObserverState extends State<AttendanceObserver>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _events;
  String _scheduleSignature = '';
  bool _dialogOpen = false, _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(_schedule);
    widget.app.attendance.addListener(_changed);
    _events = widget.app.attendanceBackend.events.listen((_) {
      _scheduleSignature = '';
      _schedule();
      unawaited(widget.app.attendance.refreshMessages());
      unawaited(widget.app.attendance.check());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
  }

  void _schedule() {
    if (!mounted) return;
    final app = widget.app;
    final signature = jsonEncode([
      app.loggedIn,
      app.username,
      app.teachingCalendar.fingerprint,
      app.termStart.toIso8601String(),
      app.totalWeeks,
      app.courses.map((c) => c.toMap()).toList(),
      DateTime.now().timeZoneOffset.inMinutes,
    ]);
    if (signature == _scheduleSignature) return;
    _scheduleSignature = signature;
    unawaited(
      app.attendance.updateSchedule(
        app.loggedIn ? app.username : '',
        app.loggedIn
            ? AttendanceSchedule.meetings(
                DateTime.now(),
                app.getEffectiveCoursesForDate,
                days: 120,
              )
            : [],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    widget.app.attendance.setForeground(_foreground);
    if (_foreground) {
      _scheduleSignature = '';
      _schedule();
      if (_dialogOpen && widget.app.attendance.pendingRecord != null) {
        unawaited(
          widget.app.attendance.recordDisplayed(
            widget.app.attendance.pendingRecord!.key,
          ),
        );
      }
      _changed();
    }
  }

  void _changed() {
    if (!mounted ||
        !_foreground ||
        _dialogOpen ||
        widget.app.attendance.phase != AttendancePhase.pending) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_prompt()));
  }

  Future<void> _prompt() async {
    if (!mounted ||
        !_foreground ||
        _dialogOpen ||
        widget.app.attendance.phase != AttendancePhase.pending) {
      return;
    }
    final attendance = widget.app.attendance;
    if (attendance.recordMode) {
      final record = attendance.pendingRecord,
          meeting = attendance.recordMeeting;
      if (record == null || meeting == null) return;
      _dialogOpen = true;
      try {
        final open = await showDialog<bool>(
          context: context,
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  _foreground &&
                  _dialogOpen &&
                  attendance.pendingRecord?.key == record.key) {
                unawaited(attendance.recordDisplayed(record.key));
              }
            });
            return AttendanceRecordConsentDialog(
              name: meeting.course.name,
              body: _RecordReminderBody(
                app: widget.app,
                recordKey: record.key,
                name: meeting.course.name,
              ),
            );
          },
        );
        if (!mounted ||
            !_foreground ||
            attendance.pendingRecord?.key != record.key) {
          return;
        }
        if (open != true) {
          attendance.dismissRecord();
          return;
        }
        if (!mounted ||
            !attendance.enabled ||
            attendance.pendingRecord?.key != record.key) {
          return;
        }
        final authorized = await attendance.authorizeExecution();
        if (authorized && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AttendanceWebPage(
                app: widget.app,
                meeting: meeting,
                execute: true,
              ),
            ),
          );
          if (mounted) await attendance.inspectManually(meeting);
        }
      } finally {
        _dialogOpen = false;
        if (mounted) _changed();
      }
      return;
    }
    final task = attendance.pending, meeting = attendance.pendingMeeting;
    if (!mounted ||
        !_foreground ||
        _dialogOpen ||
        task == null ||
        meeting == null ||
        attendance.phase != AttendancePhase.pending) {
      return;
    }
    _dialogOpen = true;
    try {
      final execute = await showDialog<bool>(
        context: context,
        builder: (context) => AttendanceConsentDialog(app: widget.app),
      );
      if (!mounted ||
          !attendance.enabled ||
          attendance.pending?.key != task.key) {
        return;
      }
      if (execute != true) {
        await attendance.cancel();
        return;
      }
      bool authorized;
      try {
        authorized = await attendance.authorizeExecution();
      } catch (_) {
        attendance.report(AttendancePhase.failed, '无法重新确认签到状态，请稍后再试');
        return;
      }
      if (authorized && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AttendanceWebPage(
              app: widget.app,
              meeting: meeting,
              execute: true,
            ),
          ),
        );
      }
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_schedule);
    widget.app.attendance.removeListener(_changed);
    _events?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class AttendanceConsentDialog extends StatefulWidget {
  const AttendanceConsentDialog({super.key, required this.app});
  final AppController app;
  @override
  State<AttendanceConsentDialog> createState() =>
      _AttendanceConsentDialogState();
}

class _AttendanceConsentDialogState extends State<AttendanceConsentDialog> {
  Timer? _countdown;
  @override
  void initState() {
    super.initState();
    widget.app.attendance.addListener(_changed);
    if (widget.app.attendance.pending?.expiresAt != null) {
      _countdown = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _changed(),
      );
    }
  }

  void _changed() {
    if (!mounted) return;
    final a = widget.app.attendance;
    final end = a.pending?.expiresAt;
    if (!a.enabled ||
        a.phase != AttendancePhase.pending ||
        (end != null && !DateTime.now().isBefore(end))) {
      scheduleMicrotask(() {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop(false);
        }
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    widget.app.attendance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.app.attendance;
    final remaining =
        a.pending?.expiresAt?.difference(DateTime.now()).inSeconds;
    return AlertDialog(
      title: const Text('发现课程签到'),
      content: Text(
        '${a.pendingMeeting?.course.name ?? '课程'}\n正在进行，本人尚未签到${remaining != null ? '\n剩余 ${remaining.clamp(0, 86400)} 秒' : ''}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('暂不执行'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('执行签到'),
        ),
      ],
    );
  }
}

class _RecordReminderBody extends StatefulWidget {
  const _RecordReminderBody({
    required this.app,
    required this.recordKey,
    required this.name,
  });
  final AppController app;
  final String recordKey, name;
  @override
  State<_RecordReminderBody> createState() => _RecordReminderBodyState();
}

class _RecordReminderBodyState extends State<_RecordReminderBody> {
  @override
  void initState() {
    super.initState();
    widget.app.attendance.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (!widget.app.attendance.enabled ||
        widget.app.attendance.pendingRecord?.key != widget.recordKey) {
      scheduleMicrotask(() {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pop(context, false);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.app.attendance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(attendanceRecordConsentText(widget.name));
}

String attendanceRecordConsentText(String name) =>
    '$name\n本人尚未签到，接口未提供开放状态。执行后进入当前课程直播；未开播时等待，可手动刷新或取消。识别二维码并核对课程与任务后提交。';

class AttendanceRecordConsentDialog extends StatelessWidget {
  const AttendanceRecordConsentDialog(
      {super.key, required this.name, this.body});
  final String name;
  final Widget? body;
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('发现课程签到'),
        content: body ?? Text(attendanceRecordConsentText(name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不执行')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('执行签到')),
        ],
      );
}
