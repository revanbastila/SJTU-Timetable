import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps the existing unread action, but commits it only after the drag burst.
class DraggableUnreadBadge extends StatefulWidget {
  const DraggableUnreadBadge({
    super.key,
    required this.count,
    required this.onDismiss,
    required this.child,
    this.badgeTop = -16,
    this.badgeRight = -16,
  });

  final int count;
  final Future<void> Function() onDismiss;
  final Widget child;
  final double badgeTop;
  final double badgeRight;

  @override
  State<DraggableUnreadBadge> createState() => _DraggableUnreadBadgeState();
}

class _DraggableUnreadBadgeState extends State<DraggableUnreadBadge>
    with SingleTickerProviderStateMixin {
  static const _dismissDistance = 18.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..addStatusListener(_onAnimationStatus);

  Offset _offset = Offset.zero;
  Offset _returnFrom = Offset.zero;
  Offset? _pointerDown;
  Offset _dragBaseOffset = Offset.zero;
  bool _dragging = false;
  bool _returning = false;
  bool _bursting = false;
  bool _dismissed = false;

  @override
  void didUpdateWidget(covariant DraggableUnreadBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count <= 0 || oldWidget.count <= 0) {
      _controller.stop();
      _offset = Offset.zero;
      _pointerDown = null;
      _dragging = false;
      _returning = false;
      _bursting = false;
      _dismissed = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (_bursting) {
      setState(() => _dismissed = true);
      unawaited(_commitDismiss());
    } else if (_returning) {
      setState(() {
        _offset = Offset.zero;
        _returning = false;
      });
    }
  }

  Future<void> _commitDismiss() async {
    try {
      await widget.onDismiss();
    } catch (error, stack) {
      debugPrint('Unread badge dismissal failed: $error\n$stack');
      if (mounted && widget.count > 0) {
        setState(() {
          _dismissed = false;
          _bursting = false;
          _offset = Offset.zero;
        });
      }
    }
  }

  void _start(DragStartDetails details) {
    if (widget.count <= 0 || _dismissed || _bursting) return;
    final currentOffset = _returning
        ? Offset.lerp(
            _returnFrom,
            Offset.zero,
            Curves.easeOutBack.transform(_controller.value),
          )!
        : _offset;
    _controller.stop();
    _dragBaseOffset = currentOffset;
    setState(() {
      _dragging = true;
      _returning = false;
      _offset = currentOffset +
          (details.globalPosition - (_pointerDown ?? details.globalPosition));
    });
  }

  void _update(DragUpdateDetails details) {
    if (!_dragging) return;
    setState(
      () => _offset = _pointerDown == null
          ? _offset + details.delta
          : _dragBaseOffset + details.globalPosition - _pointerDown!,
    );
  }

  void _end(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    _pointerDown = null;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_offset.distance >= _dismissDistance) {
      if (reduceMotion) {
        setState(() => _dismissed = true);
        unawaited(_commitDismiss());
      } else {
        setState(() => _bursting = true);
        _controller.forward(from: 0);
      }
    } else {
      _returnBadge(reduceMotion);
    }
  }

  void _cancel() {
    if (!_dragging) return;
    _dragging = false;
    _pointerDown = null;
    _returnBadge(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  void _returnBadge(bool reduceMotion) {
    if (reduceMotion) {
      setState(() => _offset = Offset.zero);
    } else {
      _returnFrom = _offset;
      setState(() => _returning = true);
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (widget.count > 0 && !_dismissed)
          Positioned(
            top: widget.badgeTop,
            right: widget.badgeRight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanDown: (details) => _pointerDown = details.globalPosition,
              onPanStart: _start,
              onPanUpdate: _update,
              onPanEnd: _end,
              onPanCancel: _cancel,
              child: SizedBox(
                width: 36,
                height: 36,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final progress = _controller.value;
                    final offset = _returning
                        ? Offset.lerp(
                            _returnFrom,
                            Offset.zero,
                            Curves.easeOutBack.transform(progress),
                          )!
                        : _offset;
                    return Transform.translate(
                      offset: offset,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          if (_bursting)
                            Positioned(
                              left: -18,
                              top: -18,
                              child: IgnorePointer(
                                child: CustomPaint(
                                  size: const Size(72, 72),
                                  painter: _BurstPainter(
                                    color: colors.error,
                                    progress: progress,
                                  ),
                                ),
                              ),
                            ),
                          Opacity(
                            opacity: _bursting ? 1 - progress : 1,
                            child: Transform.scale(
                              scale: _bursting ? 1 - .75 * progress : 1,
                              child: SizedBox.square(
                                dimension: widget.count > 9 ? 21 : 18,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.error,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      widget.count > 99
                                          ? '99+'
                                          : '${widget.count}',
                                      style: TextStyle(
                                        color: colors.onError,
                                        fontSize: widget.count > 99 ? 8 : 9,
                                        height: 1,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 1 - progress);
    final radius = 8 + progress * 24;
    for (var index = 0; index < 7; index++) {
      final angle = index * 2 * math.pi / 7;
      final center = Offset(
        size.width / 2 + math.cos(angle) * radius,
        size.height / 2 + math.sin(angle) * radius,
      );
      canvas.drawCircle(center, 2.5 * (1 - progress), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
