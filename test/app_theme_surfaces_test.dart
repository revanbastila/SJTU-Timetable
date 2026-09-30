import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/app_theme.dart';

void main() {
  test('shared surfaces remain subtle and layered in both modes', () {
    for (final choice in AppThemeChoice.values) {
      final lightBackground = choice.pageBackgroundFor(Brightness.light);
      final darkBackground = choice.pageBackgroundFor(Brightness.dark);
      final darkSurface = choice.surfaceFor(Brightness.dark);
      final darkIconTile = choice.primaryContainerFor(Brightness.dark);
      final darkBrightTheme = choice.brightThemeFor(Brightness.dark);
      final darkScheduleChrome = choice.scheduleChromeFor(Brightness.dark);
      final darkScheduleContent = choice.scheduleContentFor(Brightness.dark);
      final iconTileBackground = Color.alphaBlend(
        choice.primary.withValues(alpha: .105),
        Colors.white,
      );

      expect(lightBackground, iconTileBackground);
      expect(lightBackground.computeLuminance(), greaterThan(.80));
      expect(lightBackground, isNot(Colors.white));
      expect(darkBackground.computeLuminance(), lessThan(.025));
      expect(darkBackground, isNot(Colors.black));
      expect(darkIconTile.computeLuminance(), greaterThan(.006));
      expect(darkIconTile.computeLuminance(), lessThan(.05));
      expect(darkIconTile.computeLuminance(),
          greaterThan(darkBackground.computeLuminance()));
      expect(
        HSLColor.fromColor(darkIconTile).saturation,
        lessThanOrEqualTo(.241),
      );
      expect(darkSurface.computeLuminance(),
          greaterThan(darkBackground.computeLuminance()));
      expect(darkScheduleContent, darkBackground);
      expect(darkScheduleChrome, darkSurface);
      expect(
        darkScheduleChrome.computeLuminance(),
        greaterThan(darkScheduleContent.computeLuminance()),
      );
      expect(
        darkBrightTheme.computeLuminance(),
        greaterThan(darkScheduleChrome.computeLuminance()),
      );
      expect(darkBrightTheme.computeLuminance(), lessThan(.08));
      expect(
        HSLColor.fromColor(darkBrightTheme).saturation,
        lessThanOrEqualTo(.241),
      );
      expect(choice.scheduleChromeFor(Brightness.light), Colors.white);
      expect(
        choice.scheduleContentFor(Brightness.light),
        choice.primaryContainerFor(Brightness.light),
      );
      expect(choice.surfaceFor(Brightness.light), Colors.white);
      expect(choice.gridLineFor(Brightness.light), isNot(Colors.grey));
      expect(choice.gridLineFor(Brightness.dark), isNot(Colors.grey));
      expect(
        choice.gridLineFor(Brightness.light).computeLuminance(),
        greaterThan(lightBackground.computeLuminance() * .72),
      );
      expect(
        choice.gridLineFor(Brightness.dark).computeLuminance(),
        greaterThan(darkBackground.computeLuminance()),
      );
      expect(
        choice.surfaceFor(Brightness.dark).computeLuminance(),
        lessThan(.06),
      );
    }

    expect(
      AppThemeChoice.sjtuBlue.gridLineFor(Brightness.light),
      isNot(AppThemeChoice.sjtuRed.gridLineFor(Brightness.light)),
    );
    expect(
      AppThemeChoice.sjtuBlue.gridLineFor(Brightness.dark),
      isNot(AppThemeChoice.sjtuRed.gridLineFor(Brightness.dark)),
    );
    expect(
      AppThemeChoice.sjtuBlue.primaryContainerFor(Brightness.dark),
      isNot(AppThemeChoice.sjtuRed.primaryContainerFor(Brightness.dark)),
    );
    expect(
      AppThemeChoice.sjtuBlue.brightThemeFor(Brightness.dark),
      isNot(AppThemeChoice.sjtuRed.brightThemeFor(Brightness.dark)),
    );
  });
}
