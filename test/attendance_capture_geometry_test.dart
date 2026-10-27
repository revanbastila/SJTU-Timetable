import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/attendance_capture_geometry.dart';

void main() {
  test('JS viewport bounds include Flutter app bar and status panel offsets',
      () {
    final r = attendanceFlutterCaptureBounds(
        webView: const Rect.fromLTWH(0, 160, 360, 500),
        flutterView: const Size(360, 800),
        frame: {'x': 0.1, 'y': 0.2, 'width': 0.8, 'height': 0.5});
    expect(r['flutterX'], closeTo(.1, 1e-8));
    expect(r['flutterY'], closeTo(260 / 800, 1e-8));
    expect(r['flutterWidth'], closeTo(.8, 1e-8));
    expect(r['flutterHeight'], closeTo(250 / 800, 1e-8));
  });
  test('landscape and nonzero WebView left edge map to the same render surface',
      () {
    final r = attendanceFlutterCaptureBounds(
        webView: const Rect.fromLTWH(100, 50, 600, 300),
        flutterView: const Size(800, 400),
        frame: {'x': 0.0, 'y': 0.0, 'width': 1.0, 'height': 1.0});
    expect(r, {
      'flutterX': .125,
      'flutterY': .125,
      'flutterWidth': .75,
      'flutterHeight': .75
    });
  });
  test('stale bounds outside the Flutter view are rejected', () {
    expect(
        () => attendanceFlutterCaptureBounds(
            webView: const Rect.fromLTWH(0, 200, 360, 700),
            flutterView: const Size(360, 800),
            frame: {'x': 0, 'y': 0, 'width': 1, 'height': 1}),
        throwsFormatException);
  });
}
