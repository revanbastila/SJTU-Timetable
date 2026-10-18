import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/pages/week_page.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_database.dart';
import 'week_display_mode_test.dart' show meeting, QuietNotifications;

void main() {
  testWidgets('preview floating control in both themes and timetable modes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final fonts = {
        'PreviewChinese': File('C:/Windows/Fonts/msyh.ttc'),
        'MaterialIcons': File(
            '../../work/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
      };
      for (final entry in fonts.entries) {
        if (await entry.value.exists()) {
          await (FontLoader(entry.key)
                ..addFont(entry.value
                    .readAsBytes()
                    .then((bytes) => ByteData.view(bytes.buffer))))
              .load();
        }
      }
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppController(QuietNotifications(),
        database: MemoryDatabase(), calendarClock: () => DateTime(2030, 1, 9))
      ..termStart = DateTime(2030, 1, 7)
      ..selectedWeek = 1
      ..courses = [
        meeting('law', [1, 2, 3, 4, 7, 8, 9], first: 1, last: 4),
        meeting('thought', [2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13],
            name: '习近平法治思想', day: 3, first: 5, last: 7),
        meeting('procedure', [1, 2, 3, 4],
            name: '民事程序法', day: 2, first: 3, last: 4),
      ];
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            fontFamily: 'PreviewChinese',
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue, brightness: brightness)),
        home: RepaintBoundary(
            key: const Key('preview'),
            child: Scaffold(body: WeekPage(app: app))),
      ));
      for (final dynamicDisplay in [true, false]) {
        await app.setDynamicWeekDisplay(dynamicDisplay);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('preview')));
        await tester.runAsync(() async {
          final picture = await boundary.toImage(pixelRatio: 2);
          final bytes =
              await picture.toByteData(format: ui.ImageByteFormat.png);
          final output = Directory('../../work/previews-1.14.24a');
          await output.create(recursive: true);
          await File(
                  '${output.path}/${brightness.name}-${dynamicDisplay ? 'dynamic' : 'static'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}
