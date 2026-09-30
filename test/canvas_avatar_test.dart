import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/canvas_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.sjtu.jiaotong_course/web_history');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'canvas_session=logged_in';
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses Canvas avatar URL and accepts root-relative image paths', () {
    expect(
        resolveCanvasAvatar('https://oc.sjtu.edu.cn/images/profiles/17.png')
            .toString(),
        'https://oc.sjtu.edu.cn/images/profiles/17.png');
    expect(resolveCanvasAvatar('/images/profiles/17.png').toString(),
        'https://oc.sjtu.edu.cn/images/profiles/17.png');
    expect(resolveCanvasAvatar('').toString(), canvasDefaultAvatarUrl);
  });

  test('supplies WebView Canvas cookies only to Canvas image host', () async {
    final headers = await canvasAvatarHeaders(
        Uri.parse('https://oc.sjtu.edu.cn/images/profiles/17.png'));
    expect(headers['Cookie'], 'canvas_session=logged_in');
    expect(headers['Referer'], 'https://oc.sjtu.edu.cn/');
    expect(calls.single.method, 'canvasCookies');

    final external = await canvasAvatarHeaders(
        Uri.parse('https://cdn.example.org/avatar/17.png'));
    expect(external, isEmpty);
    expect(calls, hasLength(1));
  });
}
