import 'package:flutter/material.dart';

enum AppThemeChoice {
  sjtuBlue,
  sjtuRed,
  mistTeal,
  sage,
  mutedViolet,
  slateRose,
}

// Enum order is also the order displayed by the appearance selector.
enum InterfaceMode { system, light, dark }

extension InterfaceModeStyle on InterfaceMode {
  String get storageKey => name;

  String get label => switch (this) {
        InterfaceMode.light => '浅色',
        InterfaceMode.dark => '深色',
        InterfaceMode.system => '跟随系统',
      };

  ThemeMode get themeMode => switch (this) {
        InterfaceMode.light => ThemeMode.light,
        InterfaceMode.dark => ThemeMode.dark,
        InterfaceMode.system => ThemeMode.system,
      };

  static InterfaceMode fromStorage(String? value) =>
      InterfaceMode.values.firstWhere(
        (item) => item.storageKey == value,
        orElse: () => InterfaceMode.system,
      );
}

extension AppThemeChoiceStyle on AppThemeChoice {
  String get storageKey => name;

  String get label => switch (this) {
        AppThemeChoice.sjtuBlue => '经典蓝',
        AppThemeChoice.mistTeal => '雾青',
        AppThemeChoice.sage => '鼠尾草',
        AppThemeChoice.mutedViolet => '灰紫',
        AppThemeChoice.slateRose => '岩蔷薇',
        AppThemeChoice.sjtuRed => '交大红',
      };

  Color get primary => switch (this) {
        AppThemeChoice.sjtuBlue => const Color(0xFF315F86),
        AppThemeChoice.mistTeal => const Color(0xFF39736E),
        AppThemeChoice.sage => const Color(0xFF66775A),
        AppThemeChoice.mutedViolet => const Color(0xFF6D6382),
        AppThemeChoice.slateRose => const Color(0xFF865F69),
        AppThemeChoice.sjtuRed => const Color(0xFFA22D3F),
      };

  Color get header => switch (this) {
        AppThemeChoice.sjtuBlue => const Color(0xFF254B6D),
        AppThemeChoice.mistTeal => const Color(0xFF2E5D59),
        AppThemeChoice.sage => const Color(0xFF536149),
        AppThemeChoice.mutedViolet => const Color(0xFF574F69),
        AppThemeChoice.slateRose => const Color(0xFF6E4C56),
        AppThemeChoice.sjtuRed => const Color(0xFF842536),
      };

  Color get soft =>
      Color.alphaBlend(primary.withValues(alpha: .13), Colors.white);

  Color _deepThemeTone(double lightness) {
    final hsl = HSLColor.fromColor(primary);
    return hsl
        .withSaturation((hsl.saturation * .45).clamp(.07, .24).toDouble())
        .withLightness(lightness)
        .toColor();
  }

  /// The dark counterpart of the pale theme tile used in light mode.
  Color primaryContainerFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return Color.alphaBlend(primary.withValues(alpha: .105), Colors.white);
    }
    return _deepThemeTone(.155);
  }

  Color _surfaceTint(Brightness brightness) {
    final hsl = HSLColor.fromColor(primary);
    return hsl
        .withSaturation((hsl.saturation * .24).clamp(.035, .12).toDouble())
        .withLightness(brightness == Brightness.dark ? .72 : .52)
        .toColor();
  }

  /// A near-neutral page canvas with a barely visible reflection of the
  /// selected theme. In light mode it intentionally matches the icon tile
  /// surface (`primaryContainer`) used throughout the app.
  Color pageBackgroundFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return primaryContainerFor(brightness);
    }
    return _deepThemeTone(.085);
  }

  Color surfaceFor(Brightness brightness) {
    if (brightness == Brightness.light) return Colors.white;
    return Color.alphaBlend(
      _surfaceTint(brightness).withValues(alpha: .06),
      const Color(0xFF23272D),
    );
  }

  Color surfaceLowFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return Color.alphaBlend(
        _surfaceTint(brightness).withValues(alpha: .035),
        const Color(0xFFF9FAFC),
      );
    }
    return Color.alphaBlend(
      _surfaceTint(brightness).withValues(alpha: .045),
      const Color(0xFF191D22),
    );
  }

  Color surfaceHighFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return Color.alphaBlend(
        _surfaceTint(brightness).withValues(alpha: .035),
        const Color(0xFFF4F7FA),
      );
    }
    return Color.alphaBlend(
      _surfaceTint(brightness).withValues(alpha: .065),
      const Color(0xFF292E35),
    );
  }

  /// Theme-derived illuminated surface used for prominent dark-mode headers
  /// and tab strips. The subdued saturation keeps it readable without looking
  /// like a large block of vivid color.
  Color brightThemeFor(Brightness brightness) {
    if (brightness == Brightness.light) return primary;
    return _deepThemeTone(.235);
  }

  /// Shared neutral-gray chrome for the schedule tabs and bottom navigation.
  /// Light mode deliberately preserves its existing surface color.
  Color scheduleChromeFor(Brightness brightness) {
    if (brightness == Brightness.light) return surfaceFor(brightness);
    return surfaceFor(brightness);
  }

  /// Background behind the schedule page's actual content. It matches the
  /// ordinary timetable cell color in light mode and deep theme color C in
  /// dark mode.
  Color scheduleContentFor(Brightness brightness) {
    return pageBackgroundFor(brightness);
  }

  Color gridLineFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = dark ? const Color(0xFF292D33) : const Color(0xFFE9EDF1);
    final hsl = HSLColor.fromColor(primary);
    final gridTint = hsl
        .withSaturation((hsl.saturation * .32).clamp(.04, .16).toDouble())
        .withLightness(dark ? .62 : .72)
        .toColor();
    return Color.alphaBlend(
      gridTint.withValues(alpha: dark ? .34 : .24),
      base,
    );
  }

  Color primaryFor(Brightness brightness) {
    if (brightness == Brightness.light) return primary;
    final hsl = HSLColor.fromColor(primary);
    return hsl
        .withSaturation((hsl.saturation * .78).clamp(.18, .62))
        .withLightness(.70)
        .toColor();
  }

  Color headerFor(Brightness brightness) =>
      brightness == Brightness.light ? header : primaryFor(brightness);

  static AppThemeChoice fromStorage(String? value) =>
      AppThemeChoice.values.firstWhere(
        (item) => item.storageKey == value,
        orElse: () => AppThemeChoice.sjtuBlue,
      );
}
