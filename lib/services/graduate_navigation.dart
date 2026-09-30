/// URL classification for the graduate school's jAccount OAuth round trip.
/// Query values are intentionally not inspected or logged because callbacks
/// can contain authorization codes and state tokens.
class GraduateNavigation {
  static const targetHost = 'yjs.sjtu.edu.cn';
  static const callbackPath = '/gsapp/sys/yjsrzfwapp/oauth_sjtu/callback.do';

  static bool isCallback(Uri? uri) =>
      uri?.scheme == 'https' &&
      uri?.host == targetHost &&
      uri?.path.toLowerCase() == callbackPath;

  static bool isSsoIntermediate(Uri? uri) {
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (host == targetHost) return isCallback(uri);
    if (host == 'jaccount.sjtu.edu.cn' ||
        host == 'id.sjtu.edu.cn' ||
        host == 'login.sjtu.edu.cn') {
      return path.contains('/oauth') ||
          path.contains('/login') ||
          path.contains('/auth');
    }
    return false;
  }

  static bool isGraduatePage(Uri? uri) =>
      uri?.scheme == 'https' && uri?.host == targetHost && !isCallback(uri);
}
