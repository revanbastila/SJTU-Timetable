import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class AndroidWebHistorySnapshot {
  const AndroidWebHistorySnapshot(this.currentIndex, this.urls);

  final int currentIndex;
  final List<Uri?> urls;
}

/// Accesses the WebView's native history and stopLoading() on Android.
class AndroidWebHistory {
  AndroidWebHistory(WebViewController controller)
      : _identifier =
            (controller.platform as AndroidWebViewController).webViewIdentifier;

  AndroidWebHistory.forTesting(this._identifier);

  static const _channel = MethodChannel('cn.sjtu.jiaotong_course/web_history');
  final int _identifier;

  Future<AndroidWebHistorySnapshot> stopAndSnapshot() async {
    final data = await _channel.invokeMapMethod<String, Object?>(
      'stopAndSnapshot',
      {'webViewIdentifier': _identifier},
    );
    if (data == null) throw StateError('Native WebView history unavailable');
    final urls = (data['urls'] as List<Object?>)
        .map((value) => Uri.tryParse(value?.toString() ?? ''))
        .toList(growable: false);
    return AndroidWebHistorySnapshot(data['currentIndex'] as int, urls);
  }

  Future<void> stopLoading() => _channel.invokeMethod<void>(
        'stopLoading',
        {'webViewIdentifier': _identifier},
      );

  Future<void> goBackOrForward(int offset) => _channel.invokeMethod<void>(
        'goBackOrForward',
        {'webViewIdentifier': _identifier, 'offset': offset},
      );

  Future<void> goBackTo(Uri target, {bool stepwise = false}) =>
      _channel.invokeMethod<void>(
        'goBackTo',
        {
          'webViewIdentifier': _identifier,
          'targetUrl': target.toString(),
          'stepwise': stepwise
        },
      );
}
