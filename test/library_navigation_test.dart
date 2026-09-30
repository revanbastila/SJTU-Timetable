import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/library_navigation.dart';

void main() {
  const home = 'libcms.lib.sjtu.edu.cn';

  test('Primo account callback remains in the library login chain', () {
    expect(
      LibraryNavigation.classify(
        Uri.parse('https://${LibraryNavigation.primoHost}'
            '/primo-explore/account?vid=book&section=loans'),
        home,
      ),
      LibraryDestination.primo,
    );
    expect(
      LibraryNavigation.classify(
        Uri.parse('https://jaccount.sjtu.edu.cn/jaccount/login'),
        home,
      ),
      LibraryDestination.schoolLogin,
    );
    expect(
      LibraryNavigation.classify(
        Uri.parse('https://auth.exlibrisgroup.com/saml/callback'),
        home,
      ),
      LibraryDestination.web,
    );
  });

  test('existing library pages and search remain reachable', () {
    expect(
      LibraryNavigation.classify(Uri.parse('http://$home/'), home),
      LibraryDestination.library,
    );
    expect(
      LibraryNavigation.classify(
        Uri.parse('https://www.lib.sjtu.edu.cn/f/main/index.shtml'),
        home,
      ),
      LibraryDestination.library,
    );
    expect(
      LibraryNavigation.classify(
        Uri.parse('https://example.org/search'),
        home,
      ),
      LibraryDestination.web,
    );
    expect(
      LibraryNavigation.classify(Uri.parse('about:blank'), home),
      LibraryDestination.transient,
    );
  });

  test('library authentication uses HTTPS before scoped HTTP fallback', () {
    final primoHttp = Uri.parse('http://${LibraryNavigation.primoHost}'
        '/primo-explore/account?vid=book');
    expect(LibraryNavigation.shouldUpgradeToHttps(primoHttp, home), isTrue);
    expect(LibraryNavigation.permitsHttp(primoHttp, home), isTrue);
    expect(
        LibraryNavigation.classify(primoHttp, home), LibraryDestination.primo);
    expect(
        LibraryNavigation.shouldUpgradeToHttps(
            Uri.parse('http://$home/'), home),
        isTrue);
    expect(
        LibraryNavigation.permitsHttp(
            Uri.parse('http://jaccount.sjtu.edu.cn/login'), home),
        isFalse);
    expect(
        LibraryNavigation.permitsHttp(
            Uri.parse('http://unrelated.example/login'), home),
        isFalse);
    expect(
        LibraryNavigation.permitsHttp(
            Uri.parse('http://lib.sjtu.edu.cn/'), home),
        isTrue);
    expect(
      LibraryNavigation.permitsHttp(
        Uri.parse('http://${LibraryNavigation.accountHost}/primo/pds_login'),
        home,
      ),
      isTrue,
    );
    expect(
      LibraryNavigation.permitsHttp(
        Uri.parse(
            'http://${LibraryNavigation.currentPrimoHost}/primo-explore/account'),
        home,
      ),
      isTrue,
    );
  });

  test('current Primo and account login redirects stay in the SSO flow', () {
    expect(
      LibraryNavigation.classify(
        Uri.parse('https://${LibraryNavigation.accountHost}/primo/pds_login'),
        'www.lib.sjtu.edu.cn',
      ),
      LibraryDestination.schoolLogin,
    );
    expect(
      LibraryNavigation.classify(
        Uri.parse('https://${LibraryNavigation.currentPrimoHost}'
            '/primo-explore/login?vid=main'),
        'www.lib.sjtu.edu.cn',
      ),
      LibraryDestination.schoolLogin,
    );
    expect(
      LibraryNavigation.classify(
        Uri.parse('https://${LibraryNavigation.currentPrimoHost}'
            '/primo-explore/account?vid=main'),
        'www.lib.sjtu.edu.cn',
      ),
      LibraryDestination.primo,
    );
  });
}
