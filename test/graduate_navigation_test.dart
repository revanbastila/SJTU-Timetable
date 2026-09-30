import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/graduate_navigation.dart';

void main() {
  test('graduate OAuth callback is treated as an intermediate page', () {
    final callback = Uri.parse(
      'https://yjs.sjtu.edu.cn${GraduateNavigation.callbackPath}?code=redacted&state=redacted',
    );
    expect(GraduateNavigation.isCallback(callback), isTrue);
    expect(GraduateNavigation.isSsoIntermediate(callback), isTrue);
    expect(GraduateNavigation.isGraduatePage(callback), isFalse);
  });

  test('jAccount authorization URLs remain inside the expected SSO flow', () {
    expect(
      GraduateNavigation.isSsoIntermediate(
        Uri.parse('https://jaccount.sjtu.edu.cn/oauth2/authorize'),
      ),
      isTrue,
    );
    expect(
      GraduateNavigation.isSsoIntermediate(
        Uri.parse('https://unrelated.example/login'),
      ),
      isFalse,
    );
  });

  test('graduate home and child pages count as authenticated destination', () {
    expect(
      GraduateNavigation.isGraduatePage(
        Uri.parse('https://yjs.sjtu.edu.cn/'),
      ),
      isTrue,
    );
    expect(
      GraduateNavigation.isGraduatePage(
        Uri.parse('https://yjs.sjtu.edu.cn/gsapp/sys/yjsrzfwapp/index.do'),
      ),
      isTrue,
    );
    expect(
      GraduateNavigation.isGraduatePage(
        Uri.parse(
          'https://yjs.sjtu.edu.cn/gsapp/sys/emaphome/portal/index.do',
        ),
      ),
      isTrue,
    );
  });
}
