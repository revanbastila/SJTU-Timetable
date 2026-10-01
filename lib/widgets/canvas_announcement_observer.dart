import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/canvas_announcement_sync.dart';
import '../state/app_controller.dart';

class CanvasAnnouncementObserver extends StatefulWidget {
  const CanvasAnnouncementObserver({super.key, required this.app});
  final AppController app;
  @override
  State<CanvasAnnouncementObserver> createState() =>
      _CanvasAnnouncementObserverState();
}

class _CanvasAnnouncementObserverState extends State<CanvasAnnouncementObserver>
    with WidgetsBindingObserver {
  Timer? _timer;
  String _signature = '';
  bool _wasRefreshing = false;
  bool _busy = false;
  bool _foreground = true;

  String get _configuration => jsonEncode([
        widget.app.loggedIn,
        widget.app.username,
        for (final course in widget.app.canvas.courses) [course.id, course.name]
      ]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(_onChanged);
    _timer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_foreground) unawaited(_poll());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_poll());
    });
  }

  void _onChanged() {
    final finished = _wasRefreshing && !widget.app.refreshing;
    _wasRefreshing = widget.app.refreshing;
    if (_configuration != _signature || finished) unawaited(_poll());
  }

  Future<void> _poll() async {
    if (!mounted || _busy || !_foreground) return;
    _busy = true;
    final generation = widget.app.sessionGeneration;
    final signature = _configuration;
    try {
      await CanvasAnnouncementSync.configure(
          widget.app.loggedIn ? widget.app.username : '',
          widget.app.canvas.courses);
      _signature = signature;
      if (!mounted ||
          generation != widget.app.sessionGeneration ||
          !widget.app.loggedIn) {
        return;
      }
      await widget.app.applyAnnouncementUpdates(
          await CanvasAnnouncementSync.read(), generation);
      if (!mounted || widget.app.refreshing || !_foreground) return;
      await widget.app.applyAnnouncementUpdates(
          await CanvasAnnouncementSync.read(refresh: true), generation);
    } catch (error) {
      // Optional polling may not interrupt the timetable, login or current route.
      debugPrint('[canvas-announcements] deferred: ${error.runtimeType}');
    } finally {
      _busy = false;
      if (mounted && _foreground && _configuration != signature) {
        unawaited(_poll());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(widget.app.restoreReminders());
      unawaited(_poll());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.app.removeListener(_onChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
