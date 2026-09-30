import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/android_web_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.sjtu.jiaotong_course/web_history');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'stopAndSnapshot') {
        return {
          'currentIndex': 2,
          'urls': [
            'about:blank',
            'https://oc.sjtu.edu.cn/courses/123',
            'https://oc.sjtu.edu.cn/courses/123/pages/video'
          ],
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('back sends stop-and-snapshot before native history jump', () async {
    final history = AndroidWebHistory.forTesting(27);
    final snapshot = await history.stopAndSnapshot();
    expect(snapshot.currentIndex, 2);
    expect(snapshot.urls[1]?.path, '/courses/123');
    await history.goBackTo(snapshot.urls[1]!, stepwise: true);
    expect(calls.map((call) => call.method), ['stopAndSnapshot', 'goBackTo']);
    expect(calls.first.arguments, {'webViewIdentifier': 27});
    expect(calls.last.arguments, {
      'webViewIdentifier': 27,
      'targetUrl': 'https://oc.sjtu.edu.cn/courses/123',
      'stepwise': true,
    });
  });

  test('close requests native stop without a history command', () async {
    await AndroidWebHistory.forTesting(27).stopLoading();
    expect(calls.single.method, 'stopLoading');
  });
}
