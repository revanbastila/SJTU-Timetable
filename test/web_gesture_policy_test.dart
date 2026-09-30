import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/web_gesture_policy.dart';

void main() {
  test('back swipe starts only at either horizontal screen edge', () {
    expect(
      WebGesturePolicy.startsAtHorizontalEdge(x: 12, viewportWidth: 400),
      isTrue,
    );
    expect(
      WebGesturePolicy.startsAtHorizontalEdge(x: 388, viewportWidth: 400),
      isTrue,
    );
    expect(
      WebGesturePolicy.startsAtHorizontalEdge(x: 60, viewportWidth: 400),
      isFalse,
    );
    expect(
      WebGesturePolicy.startsAtHorizontalEdge(x: 400, viewportWidth: 400),
      isTrue,
    );
    expect(
      WebGesturePolicy.startsAtHorizontalEdge(x: -1, viewportWidth: 400),
      isFalse,
    );
  });
}
