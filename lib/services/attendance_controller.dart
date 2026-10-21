import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance.dart';

class AttendanceFailure implements Exception {
  const AttendanceFailure(this.phase, this.message);
  final AttendancePhase phase;
  final String message;
}

abstract interface class AttendanceBackend {
  Future<List<AttendanceTask>> poll(AttendanceMeeting meeting);
  Future<AttendanceSubmitResult> submit(AttendanceTask task, AttendanceQr qr);
  Future<bool> verify(AttendanceTask task);
  Future<void> configure(
    bool enabled,
    String account,
    List<AttendanceMeeting> meetings,
  );
  Future<void> cancel();
  Future<void> notifyTask(AttendanceTask task, AttendanceMeeting meeting);
  Future<void> acknowledge(String taskKey, DateTime until);
}

abstract interface class AttendanceRecordBackend {
  Future<AttendanceSnapshot> inspectRecords(AttendanceMeeting meeting,
      {bool manual = false});
  Future<bool> claimRecord(
    AttendanceRecord record,
    AttendanceMeeting meeting, {
    required bool foreground,
  });
  Future<void> notifyRecord(AttendanceRecord record, AttendanceMeeting meeting);
  Future<void> acknowledgeRecord(AttendanceRecord record);
  Future<void> setRecordForeground(bool value);
}

abstract interface class AttendanceRecordExecutionBackend {
  Future<AttendanceSubmitResult> submitRecord(
      AttendanceRecord record, AttendanceMeeting meeting, AttendanceQr qr);
}

class AttendanceController extends ChangeNotifier {
  AttendanceController({required this.backend, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;
  final AttendanceBackend backend;
  final DateTime Function() clock;
  bool enabled = false, foreground = true;
  AttendancePhase phase = AttendancePhase.off;
  String detail = '';
  AttendanceTask? pending;
  AttendanceMeeting? pendingMeeting;
  List<AttendanceMeeting> _meetings = [];
  final Map<String, int> _seen = {};
  final Set<String> _submitted = {};
  final Map<String, AttendanceQr> _latestQr = {};
  final Map<String, int> _attemptCounts = {};
  final Map<String, Set<String>> _attemptedQr = {};
  Timer? _wake;
  int _epoch = 0, _failures = 0;
  bool _polling = false, _submitting = false, _disposed = false;
  String _account = '', _configuration = '';
  SharedPreferences? _prefs;
  final Map<String, AttendanceSnapshot> recordSnapshots = {};
  final Map<String, Future<AttendanceSnapshot>> _recordReads = {};
  AttendanceRecord? pendingRecord;
  AttendanceMeeting? recordMeeting;
  bool get recordMode => backend is AttendanceRecordBackend;

  Future<AttendanceSnapshot> _readRecords(AttendanceMeeting meeting,
      {bool manual = false}) {
    final existing = _recordReads[meeting.canvasId];
    if (existing != null) return existing;
    final future = (backend as AttendanceRecordBackend)
        .inspectRecords(meeting, manual: manual);
    _recordReads[meeting.canvasId] = future;
    return future.whenComplete(() {
      if (identical(_recordReads[meeting.canvasId], future)) {
        _recordReads.remove(meeting.canvasId);
      }
    });
  }

  Future<void> inspectManually(AttendanceMeeting meeting) async {
    if (!recordMode || _disposed) return;
    final generation = _epoch;
    if (pendingRecord == null) _set(AttendancePhase.checking);
    final snapshot = await _readRecords(meeting, manual: true);
    if (_disposed || generation != _epoch) return;
    recordSnapshots[meeting.canvasId] = snapshot;
    if (pendingRecord == null) _set(snapshot.phase, snapshot.summary);
    notifyListeners();
  }

  void dismissRecord() {
    final record = pendingRecord;
    if (record != null && recordMode) {
      unawaited((backend as AttendanceRecordBackend).acknowledgeRecord(record));
    }
    pendingRecord = null;
    recordMeeting = null;
    if (!_disposed) {
      _set(enabled ? AttendancePhase.waiting : AttendancePhase.off);
    }
  }

  Future<void> _checkRecords(
    List<AttendanceMeeting> meetings,
    int generation,
  ) async {
    var failed = false;
    final round = <String, AttendanceSnapshot>{};
    for (final meeting in meetings) {
      final snapshot = round[meeting.canvasId] ?? await _readRecords(meeting);
      round[meeting.canvasId] = snapshot;
      if (!valid(generation)) return;
      recordSnapshots[meeting.canvasId] = snapshot;
      failed = failed || !snapshot.successful;
      if (pendingRecord?.canvasId == meeting.canvasId &&
          !snapshot.records.any(
            (r) => r.key == pendingRecord!.key && r.unsigned,
          )) {
        if (snapshot.successful) dismissRecord();
      }
      if (pendingRecord == null) _set(snapshot.phase, snapshot.summary);
      if (!snapshot.successful || !meeting.contains(clock())) continue;
      for (final row in snapshot.records) {
        if (pendingRecord != null || !row.relevant(meeting, clock())) continue;
        if (!await (backend as AttendanceRecordBackend).claimRecord(
          row,
          meeting,
          foreground: foreground,
        )) {
          continue;
        }
        if (!valid(generation) || !row.relevant(meeting, clock())) return;
        pendingRecord = row;
        recordMeeting = meeting;
        _set(AttendancePhase.pending, '本人尚未签到，开放状态未确认，请进入页面核实');
        if (!foreground) {
          await (backend as AttendanceRecordBackend).notifyRecord(row, meeting);
        }
      }
    }
    _failures = failed ? _failures + 1 : 0;
    notifyListeners();
  }

  int get epoch => _epoch;
  bool get executing => [
        AttendancePhase.openingLive,
        AttendancePhase.scanning,
        AttendancePhase.submitting,
      ].contains(phase);
  bool valid(int generation) => !_disposed && enabled && generation == _epoch;
  AttendanceMeeting? get currentMeeting {
    for (final item in _meetings) {
      if (item.contains(clock())) return item;
    }
    return null;
  }

  Future<void> restore() async {
    _prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    enabled = _prefs!.getBool('autoAttendanceEnabled') ?? false;
    phase = enabled ? AttendancePhase.waiting : AttendancePhase.off;
    final raw = _prefs!.getString('autoAttendanceSeen');
    if (raw != null) {
      try {
        final values = jsonDecode(raw);
        if (values is Map) {
          for (final item in values.entries) {
            if (item.value is int) _seen['${item.key}'] = item.value;
          }
        }
      } catch (_) {
        /* Old/corrupt dedup data never creates an actionable task. */
      }
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    enabled = value;
    _epoch++;
    final generation = _epoch;
    _wake?.cancel();
    pending = null;
    pendingMeeting = null;
    pendingRecord = null;
    recordMeeting = null;
    _latestQr.clear();
    _attemptCounts.clear();
    _attemptedQr.clear();
    _submitting = false;
    await _prefs!.setBool('autoAttendanceEnabled', value);
    await backend.cancel();
    if (_disposed || generation != _epoch) return;
    _set(value ? AttendancePhase.waiting : AttendancePhase.off);
    _configuration = '';
    await _configure();
    if (value) unawaited(check());
  }

  Future<void> updateSchedule(
    String account,
    List<AttendanceMeeting> meetings,
  ) async {
    final hashed =
        account.isEmpty ? '' : sha256.convert(utf8.encode(account)).toString();
    final signature = jsonEncode([
      hashed,
      enabled,
      meetings.map((m) => m.toMap()).toList(),
    ]);
    if (signature == _configuration) return;
    if (_account != hashed) {
      _epoch++;
      pending = null;
      pendingMeeting = null;
      _latestQr.clear();
      _submitted.clear();
      _attemptCounts.clear();
      _attemptedQr.clear();
      _submitting = false;
      _failures = 0;
      recordSnapshots.clear();
      _recordReads.clear();
      pendingRecord = null;
      recordMeeting = null;
      await backend.cancel();
    }
    _account = hashed;
    _meetings = meetings;
    await _configure();
    if (enabled) unawaited(check());
  }

  Future<void> _configure() async {
    _configuration = jsonEncode([
      _account,
      enabled,
      _meetings.map((m) => m.toMap()).toList(),
    ]);
    try {
      await backend.configure(
        enabled && _account.isNotEmpty,
        _account,
        _meetings,
      );
    } catch (_) {
      if (enabled) _set(AttendancePhase.limited, '后台检测暂不可用，打开应用后重试');
    }
  }

  void setForeground(bool value) {
    foreground = value;
    if (recordMode) {
      unawaited(
          (backend as AttendanceRecordBackend).setRecordForeground(value));
    }
    if (value && enabled) unawaited(check());
    if (!value) _wake?.cancel(); // Native JobScheduler is the background owner.
  }

  Future<void> _remember(String key, AttendanceMeeting meeting) async {
    final now = clock().millisecondsSinceEpoch;
    _seen.removeWhere((_, end) => end <= now);
    _seen['$_account:$key'] = meeting.detectionEnd.millisecondsSinceEpoch;
    while (_seen.length > 500) {
      _seen.remove(_seen.keys.first);
    }
    await _prefs?.setString('autoAttendanceSeen', jsonEncode(_seen));
    try {
      await backend.acknowledge(key, meeting.detectionEnd);
    } catch (_) {}
  }

  Future<void> check() async {
    if (!enabled || _disposed || _polling || !foreground) return;
    _wake?.cancel();
    final now = clock();
    final meetings = _meetings.where((m) => m.contains(now)).toList();
    if (pendingMeeting != null && !pendingMeeting!.contains(now)) {
      await cancel(AttendancePhase.expired);
    }
    if (recordMeeting != null && !recordMeeting!.contains(now)) dismissRecord();
    if (meetings.isEmpty) {
      _set(AttendancePhase.waiting);
      _scheduleWake();
      return;
    }
    if (executing) {
      _scheduleWake();
      return;
    }
    _polling = true;
    final generation = _epoch;
    if (pending == null) _set(AttendancePhase.checking);
    try {
      if (recordMode) {
        await _checkRecords(meetings, generation);
        return;
      }
      for (final meeting in meetings) {
        final tasks =
            await backend.poll(meeting).timeout(const Duration(seconds: 25));
        if (!valid(generation)) return;
        for (final task in tasks) {
          if (!task.eligible(meeting, clock())) continue;
          if (pending?.key == task.key) continue;
          if (_seen.containsKey('$_account:${task.key}') ||
              _submitted.contains(task.key)) {
            continue;
          }
          if (pending != null) continue;
          await _remember(task.key, meeting);
          if (!valid(generation)) return;
          pending = task;
          pendingMeeting = meeting;
          _set(AttendancePhase.pending);
          if (!foreground) await backend.notifyTask(task, meeting);
        }
      }
      _failures = 0;
    } on AttendanceFailure catch (error) {
      if (valid(generation) && pending == null) {
        _set(error.phase, error.message);
      }
      _failures++;
    } catch (_) {
      if (valid(generation) && pending == null) {
        _set(AttendancePhase.failed, '网络暂不可用，将稍后重试');
      }
      _failures++;
    } finally {
      _polling = false;
      if (!_disposed && enabled && foreground) {
        if (generation != _epoch) {
          unawaited(check());
        } else {
          _scheduleWake(pollStarted: now);
        }
      }
    }
  }

  void _scheduleWake({DateTime? pollStarted}) {
    _wake?.cancel();
    if (!enabled || !foreground || _disposed) return;
    var delay = Duration(
      seconds:
          _failures == 0 ? 30 : [30, 60, 120, 300][_failures.clamp(1, 4) - 1],
    );
    final now = clock();
    // Successful rounds run 30 seconds start-to-start; slow rounds never
    // overlap or accumulate catch-up requests. Failures use bounded backoff.
    if (_failures == 0 && pollStarted != null) {
      final remaining = delay - now.difference(pollStarted);
      delay =
          remaining > Duration.zero ? remaining : const Duration(seconds: 1);
    }
    for (final m in _meetings) {
      for (final boundary in [m.detectionStart, m.detectionEnd]) {
        final remaining = boundary.difference(now);
        if (remaining > Duration.zero && remaining < delay) delay = remaining;
      }
    }
    _wake = Timer(delay, () => unawaited(check()));
  }

  /// The only entry into execution. Discovery/polling never opens live video
  /// or invokes a sign endpoint. A dialog/notification must lead here first.
  Future<bool> authorizeExecution() async {
    if (recordMode) {
      final record = pendingRecord, meeting = recordMeeting;
      if (!enabled ||
          executing ||
          record == null ||
          meeting == null ||
          backend is! AttendanceRecordExecutionBackend ||
          !record.relevant(meeting, clock())) {
        return false;
      }
      final generation = _epoch;
      final latest = await _readRecords(meeting, manual: true);
      if (!valid(generation)) return false;
      recordSnapshots[meeting.canvasId] = latest;
      if (!latest.successful) {
        dismissRecord();
        _set(latest.phase, latest.summary);
        return false;
      }
      if (!latest.records
          .any((r) => r.key == record.key && r.relevant(meeting, clock()))) {
        dismissRecord();
        return false;
      }
      pendingMeeting = meeting;
      _set(AttendancePhase.openingLive);
      return true;
    }
    final task = pending, meeting = pendingMeeting;
    if (!enabled || task == null || meeting == null || executing) return false;
    if (!task.eligible(meeting, clock())) {
      await cancel(AttendancePhase.expired);
      return false;
    }
    final generation = _epoch;
    final latest =
        await backend.poll(meeting).timeout(const Duration(seconds: 25));
    if (!valid(generation)) return false;
    if (!latest.any((t) => t.key == task.key && t.eligible(meeting, clock()))) {
      await cancel(AttendancePhase.expired);
      return false;
    }
    _set(AttendancePhase.openingLive);
    return true;
  }

  void scanning() {
    if (enabled && executing) _set(AttendancePhase.scanning);
  }

  void report(AttendancePhase value, String message) {
    if (!enabled) return;
    if (executing &&
        [
          AttendancePhase.failed,
          AttendancePhase.limited,
          AttendancePhase.needsLogin,
          AttendancePhase.expired
        ].contains(value)) {
      _epoch++;
      unawaited(_finish(value, message));
    } else {
      _set(value, message);
    }
  }

  void acceptQr(String raw) {
    if (recordMode && pendingRecord != null && enabled && executing) {
      try {
        final qr = AttendanceQr.parse(raw);
        _latestQr[pendingRecord!.key] = qr;
        if (!_submitting) unawaited(_submitRecord());
      } on FormatException {/* Unrelated frame QR. */}
      return;
    }
    if (!enabled || !executing || pending == null) return;
    try {
      final qr = AttendanceQr.parse(raw);
      if (!qr.matches(pending!)) return;
      _latestQr[pending!.key] =
          qr; // Capture continues during a pending submit.
      if (!_submitting) unawaited(_submitLatest());
    } on FormatException {
      /* A frame can contain an unrelated QR; ignore it. */
    }
  }

  Future<void> _submitRecord() async {
    final record = pendingRecord, meeting = recordMeeting;
    if (_submitting || record == null || meeting == null) return;
    _submitting = true;
    final generation = _epoch;
    final attempted = _attemptedQr.putIfAbsent(record.key, () => <String>{});
    try {
      while (valid(generation) && (_attemptCounts[record.key] ?? 0) < 3) {
        if (!record.relevant(meeting, clock())) {
          await cancel(AttendancePhase.expired);
          return;
        }
        final qr = _latestQr[record.key];
        if (qr == null || !attempted.add(qr.fingerprint)) {
          _set(AttendancePhase.scanning, '等待最新二维码');
          return;
        }
        _attemptCounts[record.key] = (_attemptCounts[record.key] ?? 0) + 1;
        _set(AttendancePhase.submitting);
        // Native layer independently verifies the bound course, own record and
        // server task metadata before sending any sign request.
        final result = await (backend as AttendanceRecordExecutionBackend)
            .submitRecord(record, meeting, qr)
            .timeout(const Duration(seconds: 45));
        if (!valid(generation)) return;
        if (result == AttendanceSubmitResult.success) {
          final latest = await _readRecords(meeting, manual: true);
          if (!valid(generation)) return;
          recordSnapshots[meeting.canvasId] = latest;
          final confirmed = latest.successful &&
              latest.records.any((r) => r.key == record.key && r.completed);
          await _finish(
              confirmed ? AttendancePhase.succeeded : AttendancePhase.failed,
              confirmed ? '' : '提交结果尚未确认，请查看本人签到记录');
          return;
        }
        if (result == AttendanceSubmitResult.needsLogin) {
          await _finish(AttendancePhase.needsLogin, '请在签到系统中完成学校身份验证后重试');
          return;
        }
        if (result != AttendanceSubmitResult.expired) {
          await _finish(AttendancePhase.failed, '签到系统未确认成功，请查看学校页面');
          return;
        }
        if (_latestQr[record.key]?.fingerprint == qr.fingerprint) {
          _set(AttendancePhase.scanning, '二维码已过期，等待新画面');
          return;
        }
      }
      if (valid(generation)) await _finish(AttendancePhase.failed, '已达到本次重试上限');
    } on AttendanceFailure catch (error) {
      if (valid(generation)) await _finish(error.phase, error.message);
    } catch (_) {
      if (valid(generation)) {
        await _finish(AttendancePhase.failed, '签到请求失败，请检查网络');
      }
    } finally {
      if (generation == _epoch) _submitting = false;
    }
  }

  Future<void> _submitLatest() async {
    if (_submitting || pending == null || pendingMeeting == null) return;
    _submitting = true;
    final generation = _epoch;
    final task = pending!, meeting = pendingMeeting!;
    final attempted = _attemptedQr.putIfAbsent(task.key, () => <String>{});
    try {
      while ((_attemptCounts[task.key] ?? 0) < 3 && valid(generation)) {
        if (!meeting.contains(clock())) {
          await cancel(AttendancePhase.expired);
          return;
        }
        final qr = _latestQr[task.key];
        if (qr == null || !attempted.add(qr.fingerprint)) {
          _set(AttendancePhase.scanning, '等待最新二维码');
          return;
        }
        _attemptCounts[task.key] = (_attemptCounts[task.key] ?? 0) + 1;
        _set(AttendancePhase.submitting);
        final result =
            await backend.submit(task, qr).timeout(const Duration(seconds: 15));
        if (!valid(generation)) return;
        if (result == AttendanceSubmitResult.success) {
          final confirmed =
              await backend.verify(task).timeout(const Duration(seconds: 15));
          if (!valid(generation)) return;
          if (!confirmed) {
            await _finish(AttendancePhase.failed, '提交结果尚未确认，请查看本人签到状态');
            return;
          }
          _submitted.add(task.key);
          await _finish(AttendancePhase.succeeded);
          return;
        }
        if (result == AttendanceSubmitResult.needsLogin) {
          await _finish(AttendancePhase.needsLogin, '请完成签到系统登录后再试');
          return;
        }
        if (result != AttendanceSubmitResult.expired) {
          await _finish(AttendancePhase.failed, '签到系统未确认成功，请查看签到记录');
          return;
        }
        if ((_attemptCounts[task.key] ?? 0) >= 3) {
          await _finish(AttendancePhase.failed, '已达到本次重试上限');
          return;
        }
        // Never retry the same stale token. A newly captured frame may already
        // have updated the candidate while the HTTP request was in flight.
        if (_latestQr[task.key]?.fingerprint == qr.fingerprint) {
          _set(AttendancePhase.scanning, '二维码已更新，正在重新识别');
          return;
        }
      }
      if (valid(generation)) await _finish(AttendancePhase.failed, '已达到本次重试上限');
    } on AttendanceFailure catch (error) {
      if (valid(generation)) await _finish(error.phase, error.message);
    } catch (_) {
      if (valid(generation)) {
        await _finish(AttendancePhase.failed, '签到请求失败，请检查网络');
      }
    } finally {
      if (generation == _epoch) _submitting = false;
    }
  }

  Future<void> cancel([
    AttendancePhase reason = AttendancePhase.cancelled,
  ]) async {
    _epoch++;
    await _finish(reason);
  }

  Future<void> _finish(AttendancePhase value, [String message = '']) async {
    final key = pending?.key ?? pendingRecord?.key;
    if (key != null) {
      _attemptCounts.remove(key);
      _attemptedQr.remove(key);
    }
    _latestQr.clear();
    pending = null;
    pendingMeeting = null;
    pendingRecord = null;
    recordMeeting = null;
    _submitting = false;
    _set(enabled ? value : AttendancePhase.off, message);
    await backend.cancel();
  }

  void _set(AttendancePhase value, [String message = '']) {
    if (_disposed) return;
    if (phase == value && detail == message) return;
    phase = value;
    detail = message;
    notifyListeners();
  }

  @override
  void dispose() {
    final hadWork = enabled || _polling || _submitting || pending != null;
    _disposed = true;
    _epoch++;
    _wake?.cancel();
    _latestQr.clear();
    _attemptCounts.clear();
    _attemptedQr.clear();
    if (hadWork) unawaited(backend.cancel());
    super.dispose();
  }
}
