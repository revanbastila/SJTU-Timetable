import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/canvas_extractor.dart';

void main() {
  test(
      'Canvas extractor URL preserves the bridge script without a result callback',
      () {
    final uri = canvasExtractionScriptUri;
    expect(uri.scheme, 'javascript');
    expect(Uri.decodeComponent(uri.path), canvasExtractionScript);
    expect(canvasExtractionScript, contains('SyncBridge.postMessage'));
  });
}
