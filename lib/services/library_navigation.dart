enum LibraryDestination {
  schoolLogin,
  library,
  primo,
  web,
  transient,
  unsupported
}

class LibraryNavigation {
  static const primoHost = '86sjt-primo.hosted.exlibrisgroup.com.cn';
  static const currentPrimoHost = 'primo.hosted.exlibrisgroup.com.cn';
  static const accountHost = 'account.lib.sjtu.edu.cn';
  static const primoHosts = {primoHost, currentPrimoHost};

  static bool isPrimoHost(String? host) => primoHosts.contains(host);

  static bool _isLibraryHost(String? host, String homeHost) =>
      host == homeHost ||
      host == 'lib.sjtu.edu.cn' ||
      (host?.endsWith('.lib.sjtu.edu.cn') ?? false);

  /// Some Primo releases route JAccount through this intermediate endpoint.
  /// It is not a user-facing page and should not become a back-stack stop.
  static bool isAuthenticationIntermediate(Uri? uri) {
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    return uri.host == accountHost ||
        ((uri.host == 'jaccount.sjtu.edu.cn' ||
                uri.host == 'id.sjtu.edu.cn' ||
                uri.host == 'login.sjtu.edu.cn') &&
            (path.contains('/login') || path.contains('/auth'))) ||
        path.contains('pds_login') ||
        (isPrimoHost(uri.host) &&
            (path.contains('/saml/') || path.contains('/login')));
  }

  static bool permitsHttp(Uri? uri, String homeHost) =>
      uri?.scheme == 'http' &&
      (_isLibraryHost(uri?.host, homeHost) || isPrimoHost(uri?.host));

  // Upgrade every known library/Primo HTTP hop, including canonical home
  // redirects, before relying on the narrowly-scoped Android fallback.
  static bool shouldUpgradeToHttps(Uri? uri, String homeHost) =>
      uri?.scheme == 'http' &&
      (_isLibraryHost(uri?.host, homeHost) || isPrimoHost(uri?.host));

  static LibraryDestination classify(Uri? uri, String homeHost) {
    if (uri == null || uri.scheme == 'about') {
      return LibraryDestination.transient;
    }
    if (isAuthenticationIntermediate(uri)) {
      return LibraryDestination.schoolLogin;
    }
    final libraryHost =
        uri.host == homeHost || uri.host.endsWith('.lib.sjtu.edu.cn');
    if (isPrimoHost(uri.host)) {
      return LibraryDestination.primo;
    }
    if (uri.scheme == 'http' && uri.host == primoHost) {
      return LibraryDestination.primo;
    }
    if (uri.scheme == 'http' && libraryHost) {
      return LibraryDestination.library;
    }
    if (uri.scheme != 'https') {
      return LibraryDestination.unsupported;
    }
    if (uri.host == 'jaccount.sjtu.edu.cn' ||
        uri.host == 'id.sjtu.edu.cn' ||
        uri.host == 'login.sjtu.edu.cn') {
      return LibraryDestination.schoolLogin;
    }
    if (libraryHost) return LibraryDestination.library;
    if (isPrimoHost(uri.host)) return LibraryDestination.primo;
    return LibraryDestination.web;
  }
}
