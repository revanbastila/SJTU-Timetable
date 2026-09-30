import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/web_navigation_guard.dart';

void main() {
  test('back invalidates an in-flight login callback', () {
    final guard = WebNavigationGuard();
    final loginGeneration = guard.generation;
    expect(guard.permits(loginGeneration, returning: false), isTrue);
    guard.invalidate();
    expect(guard.permits(loginGeneration, returning: false), isFalse);
    expect(guard.permits(guard.generation, returning: true), isFalse);
    expect(guard.permits(guard.generation, returning: false), isTrue);
  });
}
