import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/school_web_auth.dart';

void main() {
  test('configured sjtu.cn target participates in its own SSO redirect chain',
      () {
    expect(
      SchoolWebAuthenticator.isAllowedHost(
        'share.dyweb.sjtu.cn',
        'share.dyweb.sjtu.cn',
      ),
      isTrue,
    );
    expect(
      SchoolWebAuthenticator.isAllowedHost(
        'jaccount.sjtu.edu.cn',
        'share.dyweb.sjtu.cn',
      ),
      isTrue,
    );
    expect(
      SchoolWebAuthenticator.isAllowedHost(
        'jaccount.sjtu.edu.cn',
        'yjs.sjtu.edu.cn',
      ),
      isTrue,
    );
    expect(
      SchoolWebAuthenticator.isAllowedHost(
        'yjs.sjtu.edu.cn',
        'yjs.sjtu.edu.cn',
      ),
      isTrue,
    );
    expect(
      SchoolWebAuthenticator.isAllowedHost(
        'example.com',
        'share.dyweb.sjtu.cn',
      ),
      isFalse,
    );
  });
}
