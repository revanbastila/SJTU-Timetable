import 'dart:ui';

/// Video bounds from JS are relative to the WebView viewport. PixelCopy of the
/// Flutter rendering surface needs bounds relative to the entire Flutter view.
Map<String, Object?> attendanceFlutterCaptureBounds({
  required Rect webView,
  required Size flutterView,
  required Map<String, dynamic> frame,
}) {
  final x = (frame['x'] as num).toDouble();
  final y = (frame['y'] as num).toDouble();
  final width = (frame['width'] as num).toDouble();
  final height = (frame['height'] as num).toDouble();
  final crop = Rect.fromLTWH(
      webView.left + x * webView.width,
      webView.top + y * webView.height,
      width * webView.width,
      height * webView.height);
  if (flutterView.isEmpty ||
      crop.isEmpty ||
      [crop.left, crop.top, crop.right, crop.bottom].any((v) => !v.isFinite) ||
      crop.left < 0 ||
      crop.top < 0 ||
      crop.right > flutterView.width + 0.5 ||
      crop.bottom > flutterView.height + 0.5) {
    throw const FormatException('直播截图范围尚未稳定');
  }
  return {
    'flutterX': crop.left / flutterView.width,
    'flutterY': crop.top / flutterView.height,
    'flutterWidth': crop.width / flutterView.width,
    'flutterHeight': crop.height / flutterView.height,
  };
}
