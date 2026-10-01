import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_theme.dart';
import 'models/course.dart';
import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'pages/course_detail_page.dart';
import 'services/notification_service.dart';
import 'services/timetable_widget_bridge.dart';
import 'state/app_controller.dart';

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppController(NotificationService());
  await app.bootstrap();
  final widgetBridge = TimetableWidgetBridge();
  widgetBridge.onOpenCourse = (id) => _openWidgetCourse(app, id);
  widgetBridge.attach(app);
  runApp(JiaotongCourseApp(app: app));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    app.startTeachingCalendarSync();
    unawaited(widgetBridge.consumePendingCourse());
  });
}

void _openWidgetCourse(AppController app, String id) {
  if (!app.loggedIn) return;
  Course? course;
  for (final candidate in app.courses) {
    if (candidate.id == id) {
      course = candidate;
      break;
    }
  }
  final navigator = _navigatorKey.currentState;
  if (course == null || navigator == null) return;
  navigator.push(MaterialPageRoute<void>(
    builder: (_) => CourseDetailPage(app: app, course: course!),
  ));
}

class JiaotongCourseApp extends StatelessWidget {
  const JiaotongCourseApp({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return AppScope(
        app: app,
        child: AnimatedBuilder(
          animation: app,
          builder: (context, _) => MaterialApp(
            title: '交大课表',
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigatorKey,
            theme: _theme(app.themeChoice, Brightness.light),
            darkTheme: _theme(app.themeChoice, Brightness.dark),
            themeMode: app.interfaceMode.themeMode,
            home: app.loggedIn ? HomeShell(app: app) : LoginPage(app: app),
            builder: (context, child) {
              final theme = Theme.of(context);
              final followsDark = theme.brightness == Brightness.dark;
              final scheme = theme.colorScheme;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: theme.scaffoldBackgroundColor,
                  statusBarIconBrightness:
                      followsDark ? Brightness.light : Brightness.dark,
                  systemNavigationBarColor: scheme.surface,
                  systemNavigationBarIconBrightness:
                      followsDark ? Brightness.light : Brightness.dark,
                  systemNavigationBarDividerColor: scheme.outlineVariant,
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
          ),
        ));
  }

  ThemeData _theme(AppThemeChoice choice, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primary = choice.primaryFor(brightness);
    final background = choice.pageBackgroundFor(brightness);
    final surface = choice.surfaceFor(brightness);
    final surfaceLow = choice.surfaceLowFor(brightness);
    final surfaceHigh = choice.surfaceHighFor(brightness);
    const darkText = Color(0xFFE1E7ED);
    const darkSubtleText = Color(0xFFB0BBC6);
    final gridLine = choice.gridLineFor(brightness);
    final scheme = dark
        ? ColorScheme.fromSeed(
            seedColor: primary,
            brightness: Brightness.dark,
            surface: surface,
          ).copyWith(
            primary: primary,
            onPrimary: const Color(0xFF16212A),
            surface: surface,
            onSurface: darkText,
            surfaceContainerLowest: background,
            surfaceContainerLow: surfaceLow,
            surfaceContainer: surface,
            surfaceContainerHigh: surfaceHigh,
            surfaceContainerHighest: Color.alphaBlend(
              choice.primary.withValues(alpha: .035),
              const Color(0xFF30363D),
            ),
            onSurfaceVariant: darkSubtleText,
            outline: Color.alphaBlend(gridLine.withValues(alpha: .38), surface),
            outlineVariant: gridLine,
            primaryContainer: choice.primaryContainerFor(brightness),
            onPrimaryContainer: const Color(0xFFEAF0F5),
            secondary: const Color(0xFF9AABB9),
            onSecondary: const Color(0xFF17212A),
          )
        : ColorScheme.fromSeed(
            seedColor: primary,
            primary: primary,
            surface: Colors.white,
            brightness: Brightness.light,
          ).copyWith(
            surfaceContainerLowest: background,
            surfaceContainerLow: surfaceLow,
            surfaceContainer: surface,
            surfaceContainerHigh: surfaceHigh,
            surfaceContainerHighest: surfaceHigh,
            outlineVariant: gridLine,
            outline: gridLine,
            primaryContainer: choice.primaryContainerFor(brightness),
            onPrimaryContainer: const Color(0xFF25313B),
          );
    final inputOutline = scheme.outline;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceLow,
        foregroundColor: dark ? scheme.onSurface : choice.header,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: inputOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: inputOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: dark
            ? scheme.primaryContainer
            : Color.alphaBlend(primary.withValues(alpha: .13), Colors.white),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? primary : null,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: states.contains(WidgetState.selected) ? primary : null,
            )),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: dark ? scheme.onPrimary : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required super.child, required AppController app})
      : super(notifier: app);
  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
