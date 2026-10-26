import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/attendance_video_probe.dart';
import 'package:jiaotong_course/widgets/attendance_video_status.dart';

Map<String, dynamic> frame(String key, double time) => {
      'playing': true,
      'frameKey': key,
      'time': time,
      'x': 0.0,
      'y': 0.1,
      'width': 1.0,
      'height': 0.6,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'PreviewChinese': 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons':
          '../../work/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(entry.value);
      if (await file.exists()) {
        await (FontLoader(entry.key)
              ..addFont(file
                  .readAsBytes()
                  .then((bytes) => ByteData.view(bytes.buffer))))
            .load();
      }
    }
  });
  test('view, stream and geometry changes need fresh advancing frames', () {
    final sampling = AttendanceVideoSampling();
    expect(sampling.accept(frame('camera', 250)), false);
    expect(sampling.accept(frame('camera', 251)), true);
    expect(sampling.accept(frame('ppt', 2)), false);
    expect(sampling.accept(frame('ppt', 3)), true);
    expect(sampling.accept(frame('ppt-new-bounds', 4)), false);
    expect(sampling.accept(frame('ppt-new-bounds', 5)), true);
    sampling.reset();
    expect(sampling.accept(frame('ppt-new-bounds', 6)), false);
  });

  test('switching, buffering, frozen clocks and invalid crops cannot capture',
      () {
    final sampling = AttendanceVideoSampling();
    sampling.accept(frame('ppt', 1));
    expect(sampling.accept(frame('ppt', 1)), false);
    expect(
        sampling.accept({'playing': false, 'viewState': 'switching'}), false);
    expect(sampling.accept(frame('ppt', 50)), false);
    for (final bad in [
      {...frame('ppt', 51), 'width': 0.0},
      {...frame('ppt', 51), 'x': -0.1},
      {...frame('ppt', 51), 'height': 1.0},
      {...frame('ppt', 51), 'time': double.nan},
      {...frame('ppt', 51), 'frameKey': ''},
    ]) {
      expect(sampling.accept(bad), false);
      expect(sampling.accept(frame('ppt', 52)), false);
    }
  });

  testWidgets(
      'status and manual override stay above video across theme changes',
      (t) async {
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var manual = false;
    var taps = 0;
    Widget page(Brightness brightness) => MaterialApp(
          theme: ThemeData(
              fontFamily: 'PreviewChinese',
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue, brightness: brightness)),
          home: RepaintBoundary(
            key: const Key('video-preview'),
            child: Scaffold(
                body: Column(children: [
              AttendanceVideoStatus(
                message: manual
                    ? '使用手动选择的直播画面识别'
                    : '未找到可用的 PPT／电脑画面入口，继续识别当前直播，可手动切换',
                manual: manual,
                onUseCurrentView: () {
                  taps++;
                  manual = true;
                },
              ),
              const Expanded(
                  child: ColoredBox(
                      key: Key('video'),
                      color: Colors.black,
                      child: Center(
                          child: Text('直播画面',
                              style: TextStyle(color: Colors.white))))),
            ])),
          ),
        );
    for (final brightness in [
      Brightness.light,
      Brightness.dark,
      Brightness.light
    ]) {
      await t.pumpWidget(page(brightness));
      await t.pumpAndSettle();
      expect(t.getBottomLeft(find.byType(AttendanceVideoStatus)).dy,
          lessThanOrEqualTo(t.getTopLeft(find.byKey(const Key('video'))).dy));
      expect(Theme.of(t.element(find.byType(AttendanceVideoStatus))).brightness,
          brightness);
      expect(find.text('手动选择').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
      final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('video-preview')));
      await t.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/attendance-video-previews');
        await dir.create(recursive: true);
        await File('${dir.path}/status-${brightness.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }
    await t.tap(find.text('手动选择'));
    await t.pumpWidget(page(Brightness.dark));
    await t.pumpAndSettle();
    expect(taps, 1);
    expect(find.text('手动选择'), findsNothing);
    expect(find.text('使用手动选择的直播画面识别'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
