/// Public GitHub repository used by both manual and automatic update checks.
/// Edit these defaults, or provide --dart-define=GITHUB_OWNER=... and
/// --dart-define=GITHUB_REPO=... when building. No token is needed or stored.
class UpdateConfig {
  static const githubOwner = String.fromEnvironment(
    'GITHUB_OWNER',
    defaultValue: 'revanbastila',
  );
  static const githubRepo = String.fromEnvironment(
    'GITHUB_REPO',
    defaultValue: 'SJTU-Timetable',
  );

  static bool get configured => validRepository(githubOwner, githubRepo);

  static bool validRepository(String owner, String repo) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]*$').hasMatch(owner) &&
      RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(repo) &&
      repo != '.' &&
      repo != '..';

  static bool trustedAsset(Uri uri, String owner, String repo) {
    final parts = uri.pathSegments;
    return uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        !uri.hasPort &&
        uri.userInfo.isEmpty &&
        parts.length == 6 &&
        parts[0].toLowerCase() == owner.toLowerCase() &&
        parts[1].toLowerCase() == repo.toLowerCase() &&
        parts[2] == 'releases' &&
        parts[3] == 'download' &&
        parts[4].isNotEmpty &&
        parts[5].toLowerCase().endsWith('.apk');
  }

  static bool trustedReleasePage(Uri uri, String owner, String repo) =>
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      uri.pathSegments.length >= 4 &&
      uri.pathSegments[0].toLowerCase() == owner.toLowerCase() &&
      uri.pathSegments[1].toLowerCase() == repo.toLowerCase() &&
      uri.pathSegments[2] == 'releases';
}
