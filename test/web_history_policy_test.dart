import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/web_history_policy.dart';

void main() {
  test('library authentication hops are not visible back stops', () {
    const policy =
        WebHistoryPolicy(homeHost: 'libcms.lib.sjtu.edu.cn', librarySite: true);
    expect(policy.isVisiblePage(Uri.parse('about:blank')), isFalse);
    expect(
        policy.isVisiblePage(
            Uri.parse('https://jaccount.sjtu.edu.cn/jaccount/login')),
        isFalse);
    expect(
        policy.isVisiblePage(Uri.parse(
            'https://86sjt-primo.hosted.exlibrisgroup.com.cn/saml/callback')),
        isFalse);
    expect(policy.isVisiblePage(Uri.parse('http://libcms.lib.sjtu.edu.cn/')),
        isTrue);
    expect(
        policy.isVisiblePage(
            Uri.parse('https://86sjt-primo.hosted.exlibrisgroup.com.cn/'
                'primo-explore/account?section=loans')),
        isFalse);
  });

  test('Shuiyuan topics count but login and redirects do not', () {
    const policy =
        WebHistoryPolicy(homeHost: 'shuiyuan.sjtu.edu.cn', librarySite: false);
    expect(
        policy.isVisiblePage(Uri.parse('https://shuiyuan.sjtu.edu.cn/login')),
        isFalse);
    expect(
        policy.isVisiblePage(
            Uri.parse('https://shuiyuan.sjtu.edu.cn/t/topic/123')),
        isTrue);
    expect(
        policy.samePage(Uri.parse('https://shuiyuan.sjtu.edu.cn/#/topic/1'),
            Uri.parse('https://shuiyuan.sjtu.edu.cn/#/topic/2')),
        isFalse);
  });

  test('mail pages count as history except their authentication hops', () {
    const policy = WebHistoryPolicy(
      homeHost: 'mail.sjtu.edu.cn',
      librarySite: false,
      mailSite: true,
    );
    expect(policy.isHomePage(Uri.parse('https://mail.sjtu.edu.cn/modern/')),
        isTrue);
    expect(policy.isHomePage(Uri.parse('https://mail.sjtu.edu.cn/zimbra/')),
        isTrue);
    expect(
        policy.isHomePage(
            Uri.parse('https://mail.sjtu.edu.cn/modern/#/mail/inbox')),
        isFalse);
    expect(
        policy
            .isHomePage(Uri.parse('https://mail.sjtu.edu.cn/modern/mail/123')),
        isFalse);
    expect(
      policy.isVisiblePage(Uri.parse('https://mail.sjtu.edu.cn/modern/')),
      isTrue,
    );
    expect(
      policy.isVisiblePage(Uri.parse(
        'http://mail.sjtu.edu.cn/zimbra/jaccount/login?service=mail',
      )),
      isFalse,
    );
    expect(
      policy.isVisiblePage(Uri.parse('https://jaccount.sjtu.edu.cn/login')),
      isFalse,
    );
  });

  test('official library homepage is the root for back navigation', () {
    const policy = WebHistoryPolicy(
      homeHost: 'www.lib.sjtu.edu.cn',
      librarySite: true,
    );
    expect(
        policy.isHomePage(Uri.parse('https://www.lib.sjtu.edu.cn/')), isTrue);
    expect(
        policy.isHomePage(Uri.parse(
            'https://www.lib.sjtu.edu.cn/f/main/index.shtml?lang=zh-cn')),
        isTrue);
    expect(
        policy.isVisiblePage(Uri.parse(
            'https://account.lib.sjtu.edu.cn/primo/pds_login?service=x')),
        isFalse);
    expect(
        policy.isVisiblePage(Uri.parse(
            'https://primo.hosted.exlibrisgroup.com.cn/primo-explore/account')),
        isFalse);
  });

  test('identical redirects are not an earlier visible page', () {
    const policy =
        WebHistoryPolicy(homeHost: 'shuiyuan.sjtu.edu.cn', librarySite: false);
    final topic = Uri.parse('https://shuiyuan.sjtu.edu.cn/t/topic/123');
    final earlier = Uri.parse('https://shuiyuan.sjtu.edu.cn/t/topic/122');
    expect(policy.samePage(topic, topic), isTrue);
    expect(policy.samePage(topic, earlier), isFalse);
    expect(policy.isVisiblePage(Uri.parse('about:blank')), isFalse);
    expect(
        policy.isVisiblePage(
            Uri.parse('https://shuiyuan.sjtu.edu.cn/auth/callback')),
        isFalse);
    expect(
        policy.isVisiblePage(Uri.parse(
            'https://shuiyuan.sjtu.edu.cn/?code=temporary-auth-code')),
        isFalse);
  });

  test('Canvas video returns to the course across duplicate and auth entries',
      () {
    const policy = WebHistoryPolicy(
      homeHost: 'oc.sjtu.edu.cn',
      librarySite: false,
      canvasSite: true,
    );
    final course = Uri.parse('https://oc.sjtu.edu.cn/courses/123');
    final video = Uri.parse('https://video.example.edu/watch/456');
    final urls = <Uri?>[
      Uri.parse('about:blank'),
      Uri.parse('https://jaccount.sjtu.edu.cn/jaccount/login'),
      course,
      Uri.parse('https://oc.sjtu.edu.cn/login/canvas'),
      Uri.parse('https://oc.sjtu.edu.cn/courses/123/external_tools/8329'),
      Uri.parse('https://oc.sjtu.edu.cn/api/lti/authorize'),
      video,
      video,
    ];
    expect(
      policy.isVisiblePage(video),
      isFalse,
    );
    expect(
      policy.previousVisibleIndex(
        urls: urls,
        currentIndex: 7,
        currentPage: video,
        rootPage: course,
      ),
      2,
    );
    expect(
      policy.previousVisibleIndex(
        urls: [
          course,
          Uri.parse('https://video.example.edu/player/bootstrap'),
          Uri.parse('about:blank'),
          Uri.parse('https://video.example.edu/player/watch'),
        ],
        currentIndex: 3,
        currentPage: Uri.parse('https://video.example.edu/player/watch'),
        rootPage: course,
      ),
      0,
    );
    expect(
      policy.previousVisibleIndex(
        urls: urls,
        currentIndex: 2,
        currentPage: course,
        rootPage: course,
      ),
      isNull,
    );
    final dashboard = Uri.parse('https://oc.sjtu.edu.cn/');
    expect(
      policy.previousVisibleIndex(
        urls: [course, dashboard, video],
        currentIndex: 1,
        currentPage: dashboard,
        rootPage: course,
      ),
      0,
    );
  });

  test('library account returns to its last real library page', () {
    const policy = WebHistoryPolicy(
      homeHost: 'www.lib.sjtu.edu.cn',
      librarySite: true,
    );
    final home = Uri.parse('https://www.lib.sjtu.edu.cn/');
    final account = Uri.parse(
        'https://primo.hosted.exlibrisgroup.com.cn/primo-explore/account');
    expect(
      policy.previousVisibleIndex(
        urls: [
          home,
          Uri.parse('https://www.lib.sjtu.edu.cn/engine2/mh-params/redirect'),
          Uri.parse('https://account.lib.sjtu.edu.cn/primo/pds_login'),
          Uri.parse('https://jaccount.sjtu.edu.cn/login'),
          account,
          Uri.parse('https://primo-pmtch01.hosted.exlibrisgroup.com.cn/pds'),
        ],
        currentIndex: 5,
        currentPage:
            Uri.parse('https://primo-pmtch01.hosted.exlibrisgroup.com.cn/pds'),
        rootPage: home,
      ),
      0,
    );
  });
}
