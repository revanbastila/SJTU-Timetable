import 'dart:async';

import 'package:flutter/material.dart';

import '../models/attendance.dart';
import '../state/app_controller.dart';
import '../widgets/attendance_observer.dart' show AttendanceRecordConsentDialog;
import 'attendance_web_page.dart';

class AttendanceStatusPage extends StatefulWidget {
  const AttendanceStatusPage({super.key, required this.app});
  final AppController app;
  @override
  State<AttendanceStatusPage> createState() => _AttendanceStatusPageState();
}

class _AttendanceStatusPageState extends State<AttendanceStatusPage>
    with WidgetsBindingObserver {
  Map<String, dynamic> _monitor = {};
  Future<void> _monitorStatus() async {
    try {
      final value = await widget.app.attendanceBackend.monitorStatus();
      if (mounted) setState(() => _monitor = value);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_monitorStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  AttendanceMeeting? _selected;
  bool _manualBusy = false;
  List<AttendanceMeeting> _courses() {
    final now = widget.app.attendance.clock();
    final meetings = AttendanceSchedule.meetings(
      now,
      widget.app.getEffectiveCoursesForDate,
      days: 14,
    )..sort(
        (a, b) {
          if (a.contains(now) != b.contains(now)) {
            return a.contains(now) ? -1 : 1;
          }
          return a.start
              .difference(now)
              .abs()
              .compareTo(b.start.difference(now).abs());
        },
      );
    final byId = <String, AttendanceMeeting>{};
    for (final meeting in meetings) {
      byId.putIfAbsent(meeting.canvasId, () => meeting);
    }
    return byId.values.toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_monitorStatus());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final courses = _courses();
      if (mounted && courses.isNotEmpty) {
        unawaited(
          _inspect(widget.app.attendance.currentMeeting ?? courses.first),
        );
      }
    });
  }

  Future<void> _inspect(AttendanceMeeting meeting) async {
    if (_manualBusy) return;
    setState(() {
      _manualBusy = true;
      _selected = meeting;
    });
    try {
      await widget.app.attendance.inspectManually(meeting);
    } finally {
      if (mounted) setState(() => _manualBusy = false);
    }
  }

  Future<void> _open(AttendanceMeeting meeting) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AttendanceWebPage(
          app: widget.app,
          meeting: meeting,
          keepOpen: true,
        ),
      ),
    );
    if (mounted) await _inspect(meeting);
  }

  Future<void> _execute(
      AttendanceRecord record, AttendanceMeeting meeting) async {
    if (_manualBusy || widget.app.attendance.executing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AttendanceRecordConsentDialog(name: meeting.course.name),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _manualBusy = true);
    try {
      final attendance = widget.app.attendance;
      if (await attendance.retryExecution(record, meeting) && mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AttendanceWebPage(
              app: widget.app, meeting: meeting, execute: true),
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          attendance.detail.isEmpty
              ? '当前记录已完成或检测窗口已结束，请重新检测'
              : attendance.detail,
        )));
      }
    } finally {
      if (mounted) setState(() => _manualBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(title: const Text('自动签到')),
      body: AnimatedBuilder(
        animation: Listenable.merge([app, app.attendance]),
        builder: (context, _) {
          final courses = _courses();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: Text(app.attendance.phase.label),
                subtitle: Text(
                  app.attendance.detail.isEmpty
                      ? '发现未签到记录后提示，选择执行才打开直播并识别二维码。'
                      : app.attendance.detail,
                ),
              ),
              const SizedBox(height: 12),
              const Text('运行方式', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                '课前 5 分钟至课后 5 分钟，每 30 秒检查；可识别课前 30 分钟内创建的未签到记录。后台使用带常驻通知的原生服务；需允许准时启动，且受系统省电与网络限制。Android 15 及以上后台同步服务累计时限为 24 小时内 6 小时，达到时限或启动受限后降级为系统周期检查（最短 15 分钟）。后台发现签到通过通知进入执行弹窗。',
              ),
              const SizedBox(height: 8),
              Text(
                _monitor['running'] == true ? '课程检测服务已启动' : '检测服务等待课程窗口或系统允许',
              ),
              if (_monitor['error'] is String &&
                  (_monitor['error'] as String).isNotEmpty)
                Text(_monitor['error']),
              if (_monitor['notifications'] == false)
                const Text('当前应用消息通知关闭，后台新增签到不会弹出通知；请按需开启原有消息通知设置。'),
              if (_monitor['exact'] == false)
                OutlinedButton(
                  onPressed:
                      widget.app.attendanceBackend.openExactAlarmSettings,
                  child: const Text('允许在课程窗口准时启动'),
                ),
              const SizedBox(height: 16),
              if (courses.isEmpty)
                const Text('暂无已匹配 Canvas ID 的课程，请先同步或确认课程映射。')
              else ...[
                const Text(
                  '连接课程点名签到',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Text('点击课程检查真实记录；右侧入口打开学校页面并复用当前会话。若要求验证码，请自行完成。'),
                for (final meeting in courses) ...[
                  ListTile(
                    title: Text(meeting.course.name),
                    subtitle:
                        app.attendance.recordSnapshots[meeting.canvasId] == null
                            ? null
                            : Text(
                                '${app.attendance.recordStatus(meeting)}'
                                '${app.attendance.recordFailures[meeting.canvasId] == null || !app.attendance.recordSnapshots[meeting.canvasId]!.successful ? '' : '\n本次检测：${app.attendance.recordFailures[meeting.canvasId]!.summary}；保留上次记录'}',
                              ),
                    onTap: _manualBusy ? null : () => _inspect(meeting),
                    trailing: IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: '打开点名签到',
                      onPressed:
                          app.attendance.enabled ? () => _open(meeting) : null,
                    ),
                  ),
                  if (app.attendance.executableRecord(meeting)
                      case final record?)
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 16, right: 16, bottom: 12),
                      child: FilledButton.icon(
                        onPressed: _manualBusy
                            ? null
                            : () => _execute(record, meeting),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('执行签到／重新尝试'),
                      ),
                    ),
                ],
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: app.attendanceBackend.openNotificationSettings,
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('系统通知设置'),
              ),
              OutlinedButton.icon(
                onPressed: _manualBusy || _selected == null
                    ? null
                    : () => _inspect(_selected!),
                icon: const Icon(Icons.refresh),
                label: const Text('重新检测'),
              ),
            ],
          );
        },
      ),
    );
  }
}
