import 'library_navigation.dart';

/// Only user-facing pages count as a stop when unwinding WebView history.
class WebHistoryPolicy {
  const WebHistoryPolicy({
    required this.homeHost,
    required this.librarySite,
    this.mailSite = false,
    this.canvasSite = false,
  });

  final String homeHost;
  final bool librarySite;
  final bool mailSite;
  final bool canvasSite;

  bool isHomePage(Uri? uri) {
    if (uri == null || uri.host != homeHost) return false;
    // Query/fragment routes are often an SPA's actual content page (notably
    // Zimbra's modern client). The initially observed exact home URL is still
    // recognized by samePage() in the caller.
    if (uri.hasFragment) return false;
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '').toLowerCase();
    if (mailSite) {
      if (uri.hasQuery) return false;
      return path.isEmpty || path == '/modern' || path == '/zimbra';
    }
    if (librarySite) {
      return path.isEmpty ||
          path == '/f/main/index.shtml' ||
          path == '/sjtu/f/main/index.shtml';
    }
    if (uri.hasQuery) return false;
    return path.isEmpty;
  }

  bool isVisiblePage(Uri? uri) {
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final host = uri.host;
    if (host == 'jaccount.sjtu.edu.cn' ||
        host == 'id.sjtu.edu.cn' ||
        host == 'login.sjtu.edu.cn') {
      return false;
    }
    if (librarySite) {
      if (host != homeHost &&
          !host.endsWith('.lib.sjtu.edu.cn') &&
          !LibraryNavigation.isPrimoHost(host)) {
        return false;
      }
      if (LibraryNavigation.isAuthenticationIntermediate(uri) ||
          (LibraryNavigation.isPrimoHost(host) &&
              uri.path.toLowerCase().contains('/account'))) {
        return false;
      }
    } else if (canvasSite && host != homeHost) {
      // LTI players can open several temporary documents (including popups)
      // before returning to Canvas. None is a useful stop on the way back to
      // the course that launched the player.
      return false;
    } else if (!canvasSite && host != homeHost) {
      return false;
    }
    final path = uri.path.toLowerCase();
    if (canvasSite &&
        (path.startsWith('/api/lti/') ||
            path.startsWith('/lti/') ||
            path.contains('/external_tools/'))) {
      return false;
    }
    if (path.contains('/login') ||
        path.contains('/signin') ||
        path.endsWith('/redirect') ||
        path.startsWith('/oauth') ||
        path.startsWith('/auth/') ||
        path.startsWith('/saml') ||
        path.contains('pds_login') ||
        path.contains('/callback') ||
        path.contains('/shibboleth.sso') ||
        uri.queryParameters.containsKey('ticket') ||
        uri.queryParameters.containsKey('code')) {
      return false;
    }
    return true;
  }

  /// Finds a real browser-history entry; no URL is loaded to emulate back.
  int? previousVisibleIndex({
    required List<Uri?> urls,
    required int currentIndex,
    required Uri? currentPage,
    required Uri? rootPage,
  }) {
    if (currentIndex < 0 || currentIndex >= urls.length) return null;
    final current = currentPage ?? urls[currentIndex];
    if (samePage(current, rootPage) || (!canvasSite && isHomePage(current))) {
      return null;
    }
    var rootIndex = 0;
    for (var index = currentIndex; index >= 0; index--) {
      if (samePage(urls[index], rootPage) ||
          (rootPage == null && isHomePage(urls[index]))) {
        rootIndex = index;
        break;
      }
    }
    for (var index = currentIndex - 1; index >= rootIndex; index--) {
      final candidate = urls[index];
      if (isVisiblePage(candidate) && !samePage(candidate, current)) {
        return index;
      }
    }
    return null;
  }

  bool samePage(Uri? first, Uri? second) =>
      first != null &&
      second != null &&
      first.scheme == second.scheme &&
      first.host == second.host &&
      first.path.replaceFirst(RegExp(r'/+$'), '') ==
          second.path.replaceFirst(RegExp(r'/+$'), '') &&
      first.query == second.query &&
      first.fragment == second.fragment;
}
