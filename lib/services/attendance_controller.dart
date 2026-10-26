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
  Future<AttendanceSnapshot> inspectRecords(
    AttendanceMeeting meeting, {
    bool manual = false,
  });
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
    AttendanceRecord record,
    AttendanceMeeting meeting,
    AttendanceQr qr,
  );
}

abstract interface class AttendancePresentationBackend {
  Future<void> recordDisplayed(AttendanceRecord record);
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
  int _epoch = 0, _failures = 0, _operation = 0;
  int? _activeOperation;
  int? get operation => _activeOperation;
  bool ownsOperation(int? value) =>
      value != null && value == _activeOperation && enabled && !_disposed;
  final Map<String, AttendanceSnapshot> recordFailures = {};
  final Map<String, DateTime> _recordDue = {};
  final Map<String, Object> _checkingRecords = {};
  final Map<String, int> _recordFailures = {};
  final Set<String> _displayedRecords = {};

  Future<void> recordDisplayed(String key) async {
    final record = pendingRecord;
    if (!foreground ||
        record?.key != key ||
        _disposed ||
        _displayedRecords.contains(key)) {
      return;
    }
    _displayedRecords.add(key);
    try {
      if (backend is AttendancePresentationBackend) {
        await (backend as AttendancePresentationBackend)
            .recordDisplayed(record!);
      }
    } catch (_) {
      _displayedRecords.remove(key);
    }
  }

  void _queryState(AttendancePhase value, [String message = '']) {
    if (!executing && pendingRecord == null && pending == null) {
      _set(value, message);
    }
  }

  void _storeSnapshot(AttendanceSnapshot snapshot) {
    if (snapshot.successful) {
      recordSnapshots[snapshot.canvasId] = snapshot;
      recordFailures.remove(snapshot.canvasId);
    } else {
      recordFailures[snapshot.canvasId] = snapshot;
      recordSnapshots.putIfAbsent(snapshot.canvasId, () => snapshot);
    }
  }

  bool _polling = false, _submitting = false, _disposed = false;
  String _account = '', _configuration = '';
  SharedPreferences? _prefs;
  final Map<String, AttendanceSnapshot> recordSnapshots = {};
  final Map<String, Future<AttendanceSnapshot>> _recordReads = {};
  AttendanceRecord? pendingRecord;
  AttendanceMeeting? recordMeeting;
  bool get recordMode => backend is AttendanceRecordBackend;

  Future<AttendanceSnapshot> _readRecords(
    AttendanceMeeting meeting, {
    bool manual = false,
  }) {
    final existing = _recordReads[meeting.canvasId];
    if (existing != null) return existing;
    final future = (backend as AttendanceRecordBackend).inspectRecords(
      meeting,
      manual: manual,
    );
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
    _queryState(AttendancePhase.checking);
    final snapshot = await _readRecords(meeting, manual: true);
    if (_disposed || generation != _epoch) return;
    _storeSnapshot(snapshot);
    if (snapshot.nextCheckDelay != null) {
      _recordDue[meeting.canvasId] = clock().add(snapshot.nextCheckDelay!);
      _scheduleWake();
    }
    _queryState(snapshot.phase, snapshot.summary);
    notifyListeners();
  }

  void dismissRecord() {
    final record = pendingRecord;
    if (record != null && recordMode) {
      unawaited((backend as AttendanceRecordBackend).acknowledgeRecord(record));
    }
    _activeOperation = null;
    _operation++;
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
    // Each course owns its due time and failure count. One slow or broken
    // course cannot delay requests for another course.
    final byId = {for (final m in meetings) m.canvasId: m};
    await Future.wait(
      byId.values.map((meeting) async {
        if (_checkingRecords.containsKey(meeting.canvasId)) return;
        final due = _recordDue[meeting.canvasId];
        if (due != null && clock().isBefore(due)) {
          final previous = recordSnapshots[meeting.canvasId];
          if (previous != null &&
              previous.successful &&
              pendingRecord == null &&
              !executing) {
            for (final row in previous.records) {
              if (!row.relevant(meeting, clock()) ||
                  _displayedRecords.contains(row.key)) {
                continue;
              }
              if (await (backend as AttendanceRecordBackend)
                  .claimRecord(row, meeting, foreground: foreground)) {
                if (!valid(generation) || pendingRecord != null || executing) {
                  return;
                }
                pendingRecord = row;
                recordMeeting = meeting;
                _set(AttendancePhase.pending, '本人尚未签到，开放状态未确认，请进入页面核实');
                break;
              }
            }
          }
          return;
        }
        final token = Object();
        _checkingRecords[meeting.canvasId] = token;
        try {
          final started = clock();
          _recordDue[meeting.canvasId] =
              started.add(const Duration(seconds: 30));
          AttendanceSnapshot snapshot;
          try {
            snapshot = await _readRecords(meeting);
          } catch (_) {
            snapshot = AttendanceSnapshot(
              canvasId: meeting.canvasId,
              checkedAt: clock(),
              records: [],
              failure: 'network',
            );
          }
          if (!valid(generation)) return;
          if (snapshot.failure == 'cancelled') {
            _recordDue[meeting.canvasId] =
                clock().add(const Duration(seconds: 1));
            return;
          }
          final failures = snapshot.successful
              ? 0
              : (_recordFailures[meeting.canvasId] ?? 0) + 1;
          _recordFailures[meeting.canvasId] = failures;
          final seconds =
              failures == 0 ? 30 : [30, 60, 120, 300][failures.clamp(1, 4) - 1];
          final next = (failures == 0 ? started : clock()).add(
            Duration(seconds: seconds),
          );
          _recordDue[meeting.canvasId] = next.isAfter(clock())
              ? next
              : clock().add(const Duration(seconds: 1));
          if (snapshot.nextCheckDelay != null) {
            _recordDue[meeting.canvasId] =
                clock().add(snapshot.nextCheckDelay!);
          }
          _storeSnapshot(snapshot);
          if (pendingRecord?.canvasId == meeting.canvasId &&
              snapshot.successful &&
              !snapshot.records.any(
                (r) => r.key == pendingRecord!.key && r.unsigned,
              )) {
            // A completed own record may stop execution; a read failure may not.
            if (executing) {
              await cancel(AttendancePhase.completed);
            } else {
              dismissRecord();
            }
          }
          _queryState(snapshot.phase, snapshot.summary);
          if (!snapshot.successful || !meeting.contains(clock()) || executing) {
            return;
          }
          for (final row in snapshot.records) {
            if (pendingRecord != null ||
                !row.relevant(meeting, clock()) ||
                _displayedRecords.contains(row.key)) {
              continue;
            }
            final claimed = await (backend as AttendanceRecordBackend)
                .claimRecord(row, meeting, foreground: foreground);
            if (!valid(generation)) return;
            if (!claimed ||
                !row.relevant(meeting, clock()) ||
                pendingRecord != null ||
                executing) {
              continue;
            }
            pendingRecord = row;
            recordMeeting = meeting;
            _set(AttendancePhase.pending, '本人尚未签到，开放状态未确认，请进入页面核实');
            if (!foreground) {
              await (backend as AttendanceRecordBackend).notifyRecord(
                row,
                meeting,
              );
            }
          }
          if (!_disposed) notifyListeners();
        } finally {
          if (identical(_checkingRecords[meeting.canvasId], token)) {
            _checkingRecords.remove(meeting.canvasId);
          }
          if (valid(generation)) _scheduleWake();
        }
      }),
    );
  }

  int get epoch => _epoch;
  bool get executing => _activeOperation != null;
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
    _activeOperation = null;
    _operation++;
    _recordDue.clear();
    _checkingRecords.clear();
    _recordReads.clear();
    _recordFailures.clear();
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
      _activeOperation = null;
      _operation++;
      _recordDue.clear();
      _checkingRecords.clear();
      _recordFailures.clear();
      recordFailures.clear();
      _displayedRecords.clear();
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
      if (enabled) _queryState(AttendancePhase.limited, '后台检测暂不可用，打开应用后重试');
    }
  }

  void setForeground(bool value) {
    foreground = value;
    if (recordMode) {
      unawaited(
        (backend as AttendanceRecordBackend).setRecordForeground(value),
      );
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
    if (!enabled || _disposed || (_polling && !recordMode) || !foreground) {
      return;
    }
    _wake?.cancel();
    final now = clock();
    final meetings = _meetings.where((m) => m.contains(now)).toList();
    if (pendingMeeting != null && !pendingMeeting!.contains(now)) {
      await cancel(AttendancePhase.expired);
    }
    if (recordMeeting != null && !recordMeeting!.contains(now)) {
      if (executing) {
        await cancel(AttendancePhase.expired);
      } else {
        dismissRecord();
      }
    }
    if (meetings.isEmpty) {
      _queryState(AttendancePhase.waiting);
      _scheduleWake();
      return;
    }
    if (executing && !recordMode) {
      _scheduleWake();
      return;
    }
    _polling = true;
    final generation = _epoch;
    if (pending == null) _queryState(AttendancePhase.checking);
    try {
      if (recordMode) {
        final reads = _checkRecords(meetings, generation);
        _scheduleWake();
        await reads;
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
    if (recordMode) {
      final active = _meetings.where(
          (m) => m.contains(now) && !_checkingRecords.containsKey(m.canvasId));
      final dues = active.map((m) => _recordDue[m.canvasId] ?? now);
      if (dues.isNotEmpty) {
        delay =
            dues.map((d) => d.difference(now)).reduce((a, b) => a < b ? a : b);
        if (delay <= Duration.zero) delay = const Duration(seconds: 1);
      }
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
      final operation = ++_operation;
      _activeOperation = operation;
      _set(AttendancePhase.openingLive, '正在重新确认本人签到记录…');
      final latest = await _readRecords(meeting, manual: true);
      if (!valid(generation) ||
          !ownsOperation(operation) ||
          pendingRecord?.key != record.key) {
        return false;
      }
      _storeSnapshot(latest);
      if (!latest.successful) {
        await _finish(latest.phase, latest.summary);
        return false;
      }
      if (!record.relevant(meeting, clock()) ||
          !latest.records.any(
            (r) => r.key == record.key && r.relevant(meeting, clock()),
          )) {
        await _finish(AttendancePhase.expired, '当前记录已完成或检测窗口已结束');
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
    _activeOperation = ++_operation;
    _set(AttendancePhase.openingLive);
    return true;
  }

  Future<bool> retryExecution(
    AttendanceRecord record,
    AttendanceMeeting meeting,
  ) async {
    if (!enabled || executing || !record.relevant(meeting, clock())) {
      return false;
    }
    pendingRecord = record;
    recordMeeting = meeting;
    return authorizeExecution();
  }

  void scanning({int? operation}) {
    if (operation != null && !ownsOperation(operation)) return;
    if (enabled && executing) _set(AttendancePhase.scanning);
  }

  void report(AttendancePhase value, String message, {int? operation}) {
    if (!enabled || (operation != null && !ownsOperation(operation))) return;
    if (executing &&
        [
          AttendancePhase.failed,
          AttendancePhase.limited,
          AttendancePhase.needsLogin,
          AttendancePhase.expired,
        ].contains(value)) {
      unawaited(_finish(value, message));
    } else {
      _set(value, message);
    }
  }

  void acceptQr(String raw, {int? operation}) {
    if (operation != null && !ownsOperation(operation)) return;
    if (recordMode && pendingRecord != null && enabled && executing) {
      try {
        final qr = AttendanceQr.parse(raw);
        _latestQr[pendingRecord!.key] = qr;
        if (!_submitting) unawaited(_submitRecord());
      } on FormatException {
        /* Unrelated frame QR. */
      }
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
    final operation = _activeOperation;
    final attempted = _attemptedQr.putIfAbsent(record.key, () => <String>{});
    try {
      while ((valid(generation) && ownsOperation(operation)) &&
          (_attemptCounts[record.key] ?? 0) < 3) {
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
        if (!(valid(generation) && ownsOperation(operation))) return;
        if (result == AttendanceSubmitResult.success) {
          final latest = await _readRecords(meeting, manual: true);
          if (!(valid(generation) && ownsOperation(operation))) return;
          recordSnapshots[meeting.canvasId] = latest;
          final confirmed = latest.successful &&
              latest.records.any((r) => r.key == record.key && r.completed);
          await _finish(
            confirmed ? AttendancePhase.succeeded : AttendancePhase.failed,
            confirmed ? '' : '提交结果尚未确认，请查看本人签到记录',
          );
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
      if ((valid(generation) && ownsOperation(operation))) {
        await _finish(AttendancePhase.failed, '已达到本次重试上限');
      }
    } on AttendanceFailure catch (error) {
      if ((valid(generation) && ownsOperation(operation))) {
        await _finish(error.phase, error.message);
      }
    } catch (_) {
      if ((valid(generation) && ownsOperation(operation))) {
        await _finish(AttendancePhase.failed, '签到请求失败，请检查网络');
      }
    } finally {
      if (generation == _epoch && ownsOperation(operation)) _submitting = false;
    }
  }

  Future<void> _submitLatest() async {
    if (_submitting || pending == null || pendingMeeting == null) return;
    _submitting = true;
    final generation = _epoch;
    final operation = _activeOperation;
    final task = pending!, meeting = pendingMeeting!;
    final attempted = _attemptedQr.putIfAbsent(task.key, () => <String>{});
    try {
      while ((_attemptCounts[task.key] ?? 0) < 3 &&
          (valid(generation) && ownsOperation(operation))) {
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
        if (!(valid(generation) && ownsOperation(operation))) return;
        if (result == AttendanceSubmitResult.success) {
          final confirmed =
              await backend.verify(task).timeout(const Duration(seconds: 15));
          if (!(valid(generation) && ownsOperation(operation))) return;
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
      if ((valid(generation) && ownsOperation(operation))) {
        await _finish(AttendancePhase.failed, '已达到本次重试上限');
      }
    } on AttendanceFailure catch (error) {
      if ((valid(generation) && ownsOperation(operation))) {
        await _finish(error.phase, error.message);
      }
    } catch (_) {
      if ((valid(generation) && ownsOperation(operation))) {
        await _finish(AttendancePhase.failed, '签到请求失败，请检查网络');
      }
    } finally {
      if (generation == _epoch && ownsOperation(operation)) _submitting = false;
    }
  }

  Future<void> cancel([
    AttendancePhase reason = AttendancePhase.cancelled,
  ]) async {
    await _finish(reason);
  }

  Future<void> _finish(AttendancePhase value, [String message = '']) async {
    _activeOperation = null;
    _operation++;
    final record = pendingRecord;
    if (record != null &&
        [
          AttendancePhase.succeeded,
          AttendancePhase.cancelled,
          AttendancePhase.expired,
          AttendancePhase.completed,
        ].contains(value)) {
      unawaited((backend as AttendanceRecordBackend).acknowledgeRecord(record));
    }
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
