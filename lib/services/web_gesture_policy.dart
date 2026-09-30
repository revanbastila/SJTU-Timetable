/// Gesture rules for browser routes that expose app-level edge navigation.
class WebGesturePolicy {
  const WebGesturePolicy._();

  static const double edgeWidth = 28;

  static bool startsAtHorizontalEdge({
    required double x,
    required double viewportWidth,
  }) =>
      x >= 0 &&
      x <= viewportWidth &&
      (x <= edgeWidth || x >= viewportWidth - edgeWidth);
}
