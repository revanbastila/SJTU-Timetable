import 'package:flutter/services.dart';

const canvasDefaultAvatarUrl =
    'https://oc.sjtu.edu.cn/images/messages/avatar-50.png';

const _canvasHost = 'oc.sjtu.edu.cn';
const _canvasOrigin = 'https://oc.sjtu.edu.cn/';
const _avatarChannel = MethodChannel('cn.sjtu.jiaotong_course/web_history');

/// Canvas can return absolute, protocol-relative, or root-relative avatar URLs.
Uri resolveCanvasAvatar(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return Uri.parse(canvasDefaultAvatarUrl);
  final parsed = Uri.tryParse(value);
  if (parsed == null) return Uri.parse(canvasDefaultAvatarUrl);
  final resolved = Uri.parse(_canvasOrigin).resolveUri(parsed);
  if (resolved.scheme != 'https' && resolved.scheme != 'http') {
    return Uri.parse(canvasDefaultAvatarUrl);
  }
  if (resolved.scheme == 'http' && resolved.host == _canvasHost) {
    return resolved.replace(scheme: 'https');
  }
  return resolved;
}

/// Flutter's image loader does not share Android WebView's cookie jar.
/// Only pass Canvas cookies to requests addressed to Canvas itself.
Future<Map<String, String>> canvasAvatarHeaders(Uri uri) async {
  if (uri.scheme != 'https' || uri.host != _canvasHost) return const {};
  try {
    final cookies = await _avatarChannel.invokeMethod<String>(
      'canvasCookies',
      {'url': uri.toString()},
    );
    return {
      'Referer': _canvasOrigin,
      if (cookies != null && cookies.isNotEmpty) 'Cookie': cookies,
    };
  } on PlatformException {
    return const {'Referer': _canvasOrigin};
  } on MissingPluginException {
    return const {'Referer': _canvasOrigin};
  }
}
