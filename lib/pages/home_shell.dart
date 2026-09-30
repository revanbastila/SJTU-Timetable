import 'package:flutter/material.dart';

import '../models/app_theme.dart';
import '../state/app_controller.dart';
import '../widgets/session_sync_agent.dart';
import '../widgets/draggable_unread_badge.dart';
import '../widgets/app_update_ui.dart';
import 'home_page.dart';
import 'settings_page.dart';
import 'week_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.app,
    this.initializeCanvas = true,
    this.showInitialCanvasHint = false,
  });

  final AppController app;
  final bool initializeCanvas;
  final bool showInitialCanvasHint;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final GlobalKey<SettingsPageState> _settingsPageKey =
      GlobalKey<SettingsPageState>();
  late bool _firstCanvasSyncPending;
  bool _firstCanvasSyncStarted = false;

  @override
  void initState() {
    super.initState();
    _firstCanvasSyncPending = widget.showInitialCanvasHint &&
        widget.initializeCanvas &&
        widget.app.canvas.courses.isEmpty;
    widget.app.addListener(_checkFirstCanvasSync);
    if (widget.initializeCanvas) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initializeCanvas());
    }
  }

  void _checkFirstCanvasSync() {
    if (!_firstCanvasSyncPending) return;
    if (widget.app.refreshing) _firstCanvasSyncStarted = true;
    if (_firstCanvasSyncStarted && !widget.app.refreshing) {
      _firstCanvasSyncPending = false;
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_checkFirstCanvasSync);
    super.dispose();
  }

  Future<void> _initializeCanvas() async {
    if (!mounted) return;
    final success = await widget.app.initializeCanvasAfterLogin();
    if (!mounted) return;
    if (!success) _firstCanvasSyncPending = false;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Canvas 暂未完成同步，课表仍可正常使用。')),
      );
    }
  }

  void _select(int value) {
    _settingsPageKey.currentState?.clearStudentNumberSelection();
    if (value == 1 && _index != 1) widget.app.selectWeekForToday();
    setState(() => _index = value);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(app: widget.app, isActive: _index == 0),
      WeekPage(app: widget.app),
      SettingsPage(key: _settingsPageKey, app: widget.app),
    ];
    return Scaffold(
      // Background listeners must not determine the visible tab area's size.
      // UpdateObserver builds a zero-size widget; loose Stack sizing otherwise
      // collapses every Positioned tab to zero width and height.
      body: Stack(fit: StackFit.expand, children: [
        const UpdateObserver(),
        Positioned.fill(child: IndexedStack(index: _index, children: pages)),
        Positioned(
            right: 0, bottom: 0, child: SessionSyncAgent(app: widget.app)),
        Positioned(
          left: 12,
          right: 12,
          bottom: 8,
          child: AnimatedBuilder(
            animation: widget.app,
            builder: (context, _) {
              if (!_firstCanvasSyncPending ||
                  widget.app.canvasSyncStage == CanvasSyncStage.idle ||
                  widget.app.canvasSyncStage == CanvasSyncStage.complete ||
                  widget.app.canvasSyncStage == CanvasSyncStage.failed ||
                  !widget.app.refreshing) {
                return const SizedBox.shrink();
              }
              return Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 2,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.app.canvasSyncStage == CanvasSyncStage.details
                            ? '课程 Canvas 信息仍在后台自动加载，课程表功能已可以正常使用'
                            : '${widget.app.canvasSyncMessage}，课程表功能已可以正常使用',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
      bottomNavigationBar: AnimatedBuilder(
        animation: widget.app,
        builder: (context, _) {
          return Material(
            key: const Key('home-bottom-navigation'),
            color: widget.app.themeChoice
                .scheduleChromeFor(Theme.of(context).brightness),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 76,
                child: Row(children: [
                  Expanded(
                    child: _SideDestination(
                      label: '日程',
                      icon: Icons.today_outlined,
                      selectedIcon: Icons.today,
                      selected: _index == 0,
                      count: widget.app.unreadMessageCount,
                      onBadgeSwipe: widget.app.markAllMessagesRead,
                      onTap: () => _select(0),
                    ),
                  ),
                  Expanded(
                    child: _SideDestination(
                      label: '周课表',
                      icon: Icons.calendar_view_week_outlined,
                      selectedIcon: Icons.calendar_view_week,
                      selected: _index == 1,
                      weekGrid: true,
                      onTap: () => _select(1),
                    ),
                  ),
                  Expanded(
                    child: _SideDestination(
                      label: '我的',
                      icon: Icons.person_outline_rounded,
                      selectedIcon: Icons.person_rounded,
                      selected: _index == 2,
                      onTap: () => _select(2),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SideDestination extends StatelessWidget {
  const _SideDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
    this.weekGrid = false,
    this.count = 0,
    this.onBadgeSwipe,
  });
  final String label;
  final IconData icon, selectedIcon;
  final bool selected;
  final bool weekGrid;
  final int count;
  final Future<void> Function()? onBadgeSwipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final color = selected ? primary : Theme.of(context).colorScheme.onSurface;
    final Widget iconChild = weekGrid
        ? SizedBox(
            key: ValueKey(selected),
            width: 25,
            height: 25,
            child: CustomPaint(
              key: const Key('week-schedule-nav-icon'),
              painter: WeekScheduleIconPainter(
                selected: selected,
                color: color,
              ),
            ),
          )
        : Icon(
            selected ? selectedIcon : icon,
            key: ValueKey(selected),
            color: color,
            size: 25,
          );
    final animatedIcon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .90, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: iconChild,
    );
    return InkWell(
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (onBadgeSwipe != null)
          DraggableUnreadBadge(
            count: count,
            onDismiss: onBadgeSwipe!,
            child: animatedIcon,
          )
        else
          animatedIcon,
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
  }
}

class WeekScheduleIconPainter extends CustomPainter {
  const WeekScheduleIconPainter({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(3, 4, size.width - 6, size.height - 8);
    final cellWidth = frame.width / 4;
    final fill = Paint()..color = color;
    if (selected) {
      for (final column in const [1, 3]) {
        canvas.drawRect(
          Rect.fromLTWH(
            frame.left + column * cellWidth + .8,
            frame.top + .8,
            cellWidth - 1.6,
            frame.height - 1.6,
          ),
          fill,
        );
      }
    }

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(2)),
      line,
    );
    for (var column = 1; column < 4; column++) {
      final x = frame.left + column * cellWidth;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), line);
    }
  }

  @override
  bool shouldRepaint(covariant WeekScheduleIconPainter oldDelegate) =>
      oldDelegate.selected != selected || oldDelegate.color != color;
}
