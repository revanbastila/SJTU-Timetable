import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/main.dart';
import 'package:jiaotong_course/models/app_theme.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/pages/course_detail_page.dart';
import 'package:jiaotong_course/pages/home_page.dart';
import 'package:jiaotong_course/pages/home_shell.dart';
import 'package:jiaotong_course/pages/week_page.dart';
import 'package:jiaotong_course/pages/login_page.dart';
import 'package:jiaotong_course/pages/settings_page.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/state/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('cn.sjtu.jiaotong_course/updates'),
            (call) async {
      if (call.method == 'version') return {'name': '1.14.17', 'code': 57};
      return {'status': 'idle'};
    });
  });
  testWidgets('dark interface mode applies the layered dark theme', (
    tester,
  ) async {
    final app = AppController(NotificationService())
      ..interfaceMode = InterfaceMode.dark;
    await tester.pumpWidget(JiaotongCourseApp(app: app));
    final loginContext = tester.element(find.byType(LoginPage));
    final theme = Theme.of(loginContext);
    expect(Theme.of(loginContext).brightness, Brightness.dark);
    expect(
      theme.scaffoldBackgroundColor,
      AppThemeChoice.sjtuBlue.pageBackgroundFor(Brightness.dark),
    );
    expect(
      theme.colorScheme.surface,
      AppThemeChoice.sjtuBlue.surfaceFor(Brightness.dark),
    );
    expect(
      theme.colorScheme.primaryContainer,
      AppThemeChoice.sjtuBlue.primaryContainerFor(Brightness.dark),
    );
    expect(
      theme.colorScheme.surface.computeLuminance(),
      greaterThan(theme.scaffoldBackgroundColor.computeLuminance()),
    );
    app.dispose();
  });

  testWidgets('login title icon and input outline follow the selected theme', (
    tester,
  ) async {
    final app = AppController(NotificationService())
      ..themeChoice = AppThemeChoice.slateRose;
    await tester.pumpWidget(JiaotongCourseApp(app: app));

    expect(
      tester.widget<Icon>(find.byIcon(Icons.calendar_month_outlined)).color,
      AppThemeChoice.slateRose.primary,
    );
    expect(
      tester.widget<Text>(find.text('交大课表')).style?.color,
      AppThemeChoice.slateRose.header,
    );
    final inputTheme = Theme.of(
      tester.element(find.byType(TextFormField).first),
    ).inputDecorationTheme;
    final border = inputTheme.enabledBorder! as OutlineInputBorder;
    expect(border.borderSide.color, isNot(const Color(0xFFE0EAF3)));
    app.dispose();
  });

  testWidgets('light schedule header uses theme colors and jAccount username', (
    tester,
  ) async {
    final app = AppController(NotificationService())
      ..username = 'account-id'
      ..studentName = '杨惠泽';
    final primary = AppThemeChoice.sjtuBlue.primary;
    final primaryContainer = Color.alphaBlend(
      primary.withValues(alpha: .105),
      Colors.white,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      brightness: Brightness.light,
    ).copyWith(primaryContainer: primaryContainer);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: scheme,
          scaffoldBackgroundColor: Colors.white,
        ),
        home: Scaffold(body: HomePage(app: app)),
      ),
    );

    expect(find.text('交大课表'), findsNothing);
    expect(find.text('account-id，今天的课程安排'), findsOneWidget);
    expect(find.text('杨惠泽，今天的课程安排'), findsNothing);
    expect(find.text('交'), findsNothing);
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const Key('home-page-background')))
          .color,
      AppThemeChoice.sjtuBlue.primaryContainerFor(Brightness.light),
    );
    final glyph = tester.widget<Image>(
      find.byKey(const Key('home-jiao-glyph')),
    );
    expect(
      (glyph.image as AssetImage).assetName,
      'assets/jiao_glyph_white.png',
    );
    final date = find.byWidgetPredicate(
      (widget) => widget is Text && (widget.data ?? '').contains('星期'),
    );
    expect(date, findsOneWidget);
    expect(tester.widget<Text>(date).style?.color, primaryContainer);
    expect(
      tester.widget<Text>(find.text('account-id，今天的课程安排')).style?.color,
      Colors.white,
    );
    expect(
      tester
          .widget<IconButton>(
            find
                .ancestor(
                  of: find.byIcon(Icons.sync_rounded),
                  matching: find.byType(IconButton),
                )
                .first,
          )
          .color,
      Colors.white,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Container && widget.color == primary,
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());

    final darkChoice = AppThemeChoice.sjtuRed;
    final darkScheme = ColorScheme.fromSeed(
      seedColor: darkChoice.primaryFor(Brightness.dark),
      brightness: Brightness.dark,
      surface: darkChoice.surfaceFor(Brightness.dark),
    ).copyWith(
      primary: darkChoice.primaryFor(Brightness.dark),
      surfaceContainerLowest: darkChoice.pageBackgroundFor(Brightness.dark),
      surfaceContainerLow: darkChoice.surfaceLowFor(Brightness.dark),
      onSurfaceVariant: const Color(0xFFB0BBC6),
    );
    app.themeChoice = darkChoice;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, colorScheme: darkScheme),
        home: Scaffold(body: HomePage(app: app)),
      ),
    );
    expect(find.byKey(const Key('home-jiao-glyph')), findsOneWidget);
    expect(find.text('交大课表'), findsNothing);
    expect(
      tester.widget<Container>(find.byKey(const Key('home-header'))).color,
      darkChoice.brightThemeFor(Brightness.dark),
    );
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const Key('home-page-background')))
          .color,
      darkChoice.pageBackgroundFor(Brightness.dark),
    );
    final darkTabMaterial = tester.widget<Material>(
      find
          .ancestor(of: find.byType(TabBar), matching: find.byType(Material))
          .first,
    );
    expect(darkTabMaterial.color, darkChoice.surfaceFor(Brightness.dark));
    final darkDate = tester.widget<Text>(
      find.byKey(const Key('home-date-line')),
    );
    expect(darkDate.style?.fontSize, 14);
    expect(darkDate.style?.color, darkScheme.onSurfaceVariant);
    expect(
      tester.widget<Text>(find.text('account-id，今天的课程安排')).style?.color,
      Colors.white,
    );
    expect(
      tester
          .widget<IconButton>(
            find
                .ancestor(
                  of: find.byIcon(Icons.sync_rounded),
                  matching: find.byType(IconButton),
                )
                .first,
          )
          .color,
      Colors.white,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets('interface mode labels use a shared right-aligned width', (
    tester,
  ) async {
    final app = AppController(NotificationService());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(app: app, advanced: true)),
      ),
    );
    final dropdown = find.byType(DropdownButton<InterfaceMode>);
    await tester.ensureVisible(dropdown);
    final button = tester.widget<DropdownButton<InterfaceMode>>(dropdown);
    expect(
      button.items!.map((item) => (item.child as SizedBox).width),
      everyElement(76),
    );
    expect(button.alignment, AlignmentDirectional.centerEnd);
    expect(InterfaceMode.system.label, '跟随系统');
    expect(InterfaceMode.light.label, '浅色');
    expect(InterfaceMode.dark.label, '深色');
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    for (final label in ['浅色', '深色', '跟随系统']) {
      expect(find.text(label), findsWidgets);
    }
    final optionRects = [
      for (final label in ['浅色', '深色', '跟随系统'])
        tester.getRect(find.text(label).last),
    ];
    expect((optionRects[0].right - optionRects[1].right).abs(), lessThan(1));
    expect((optionRects[1].right - optionRects[2].right).abs(), lessThan(1));
    app.dispose();
  });

  testWidgets('featured card follows theme and dots cycle from none', (
    tester,
  ) async {
    final app = AppController(NotificationService());
    final now = DateTime.now();
    app.termStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    app.selectedWeek = app.currentAcademicWeekInTerm ?? 1;
    app.courses = [
      Course(
        id: 'current-course',
        name: '正在进行的课程',
        teacher: '教师',
        location: '教室',
        time: '00:00–24:00',
        weekday: now.weekday,
        startHour: 0,
        startMinute: 0,
        endHour: 23,
        endMinute: 59,
        activeWeeks: [app.selectedWeek],
        rawWeekText: '1-18周',
        courseIdentity: 'current-course',
      ),
    ];
    const featuredColor = Color(0xFF315F86);
    final lightScheme = ColorScheme.fromSeed(
      seedColor: featuredColor,
      primary: featuredColor,
      brightness: Brightness.light,
    ).copyWith(onPrimary: Colors.white);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: lightScheme),
        home: Scaffold(body: HomePage(app: app)),
      ),
    );
    final featuredCard = tester.widget<Material>(
      find.byKey(const Key('featured-course-card')),
    );
    expect(featuredCard.color, featuredColor);
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('featured-course-card')),
              matching: find.byIcon(Icons.school_outlined),
            ),
          )
          .color,
      Colors.white,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('featured-course-card')),
              matching: find.text('正在进行的课程'),
            ),
          )
          .style
          ?.color,
      Colors.white,
    );
    expect(find.text('正在上课'), findsOneWidget);
    final dots = find.byKey(const Key('current-class-dots'));
    expect(tester.widget<Text>(dots).data, '');
    final dotsSlot = find.byKey(const Key('current-class-dots-slot'));
    expect(tester.getSize(dotsSlot).width, 21);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<Text>(dots).data, '.');
    expect(tester.getSize(dotsSlot).width, 21);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<Text>(dots).data, '..');
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<Text>(dots).data, '...');
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<Text>(dots).data, '');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);

    final darkScheme = ColorScheme.fromSeed(
      seedColor: featuredColor,
      brightness: Brightness.dark,
    ).copyWith(
      primary: featuredColor,
      primaryContainer: const Color(0xFF1D2934),
      onPrimaryContainer: const Color(0xFFEAF0F5),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, colorScheme: darkScheme),
        home: Scaffold(body: HomePage(app: app)),
      ),
    );
    final darkFeaturedCard = tester.widget<Material>(
      find.byKey(const Key('featured-course-card')),
    );
    expect(darkFeaturedCard.color, darkScheme.primaryContainer);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('featured-course-card')),
              matching: find.text('正在进行的课程'),
            ),
          )
          .style
          ?.color,
      darkScheme.onPrimaryContainer,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets('week schedule icon exposes outlined and selected grid states', (
    tester,
  ) async {
    const key = Key('week-schedule-icon-state-test');
    const color = Color(0xFF315F86);
    Widget icon(bool selected) => SizedBox(
          width: 25,
          height: 25,
          child: CustomPaint(
            key: key,
            painter: WeekScheduleIconPainter(selected: selected, color: color),
          ),
        );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: icon(false))));
    expect(
      (tester.widget<CustomPaint>(find.byKey(key)).painter!
              as WeekScheduleIconPainter)
          .selected,
      isFalse,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: icon(true))));
    expect(
      (tester.widget<CustomPaint>(find.byKey(key)).painter!
              as WeekScheduleIconPainter)
          .selected,
      isTrue,
    );
  });

  testWidgets('course detail tab content area is white in light mode', (
    tester,
  ) async {
    final app = AppController(NotificationService());
    final course = Course.fromMap({'name': '测试课程'});
    app.courses = [course];
    await tester.pumpWidget(
      MaterialApp(
        home: CourseDetailPage(app: app, course: course),
      ),
    );
    final contentBackground = find.byKey(
      const Key('course-detail-content-background'),
    );
    expect(tester.widget<ColoredBox>(contentBackground).color, Colors.white);
    await tester.tap(find.text('大纲'));
    await tester.pumpAndSettle();
    expect(tester.widget<ColoredBox>(contentBackground).color, Colors.white);
    await tester.tap(find.text('班级成员'));
    await tester.pumpAndSettle();
    expect(tester.widget<ColoredBox>(contentBackground).color, Colors.white);
    expect(tester.takeException(), isNull);
    app.dispose();
  });

  testWidgets('dark course detail surfaces follow C, bright theme and B', (
    tester,
  ) async {
    final choice = AppThemeChoice.sjtuRed;
    final app = AppController(NotificationService())..themeChoice = choice;
    final course = Course.fromMap({
      'name': '测试课程',
      'weekday': 1,
      'startPeriod': 1,
      'endPeriod': 2,
      'activeWeeks': [1, 2],
      'rawWeekText': '1-2周',
    });
    app.courses = [course];
    final scheme = ColorScheme.fromSeed(
      seedColor: choice.primaryFor(Brightness.dark),
      brightness: Brightness.dark,
      surface: choice.surfaceFor(Brightness.dark),
    ).copyWith(
      primary: choice.primaryFor(Brightness.dark),
      surfaceContainerLowest: choice.pageBackgroundFor(Brightness.dark),
      surfaceContainerLow: choice.surfaceLowFor(Brightness.dark),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, colorScheme: scheme),
        home: CourseDetailPage(app: app, course: course),
      ),
    );

    expect(
      tester
          .widget<Container>(
            find.byKey(const Key('course-detail-header-background')),
          )
          .color,
      choice.pageBackgroundFor(Brightness.dark),
    );
    expect(
      tester
          .widget<Material>(
            find.byKey(const Key('course-detail-tabs-background')),
          )
          .color,
      choice.brightThemeFor(Brightness.dark),
    );
    final content = find.byKey(const Key('course-detail-content-background'));
    expect(
      tester.widget<ColoredBox>(content).color,
      choice.surfaceFor(Brightness.dark),
    );
    await tester.tap(find.text('大纲'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ColoredBox>(content).color,
      choice.surfaceFor(Brightness.dark),
    );
    expect(tester.takeException(), isNull);
    app.dispose();
  });

  testWidgets('course detail metadata follows the selected app theme', (
    tester,
  ) async {
    final app = AppController(NotificationService())
      ..themeChoice = AppThemeChoice.mutedViolet;
    final course = Course.fromMap({
      'name': '刑事程序法',
      'courseCode': 'LAW6548-19000-X01',
      'teacher': '孙长永',
      'location': '教一楼300',
      'weekday': 1,
      'startPeriod': 3,
      'endPeriod': 4,
      'rawWeekText': '1-16周',
    });
    app.courses = [course];
    await tester.pumpWidget(
      MaterialApp(
        home: CourseDetailPage(app: app, course: course),
      ),
    );

    final expected = AppThemeChoice.mutedViolet.header;
    for (final label in [
      '刑事程序法',
      '周一  10:00–11:40',
      '课程代码 LAW6548-19000-X01',
      '教一楼300',
      '孙长永',
      '1-16周',
    ]) {
      expect(tester.widget<Text>(find.text(label)).style?.color, expected);
    }
    app.dispose();
  });

  testWidgets('manual Canvas picker lists cached candidate courses', (
    tester,
  ) async {
    final app = AppController(NotificationService());
    final course = Course.fromMap({
      'name': '人工智能法学专题',
      'courseCode': 'LAW7001',
      'weekday': 3,
      'startPeriod': 3,
      'endPeriod': 5,
    });
    app.courses = [course];
    app.canvas = CanvasSnapshot(
      dashboardItems: const [],
      courses: const [
        CanvasCourseData(
          id: 'canvas-1',
          name: '人工智能法学专题',
          courseCode: 'LAW7001',
          syllabusHtml: '',
          announcements: [],
          people: [],
        ),
      ],
      syncedAt: DateTime(2026, 9, 20),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CourseDetailPage(app: app, course: course),
      ),
    );

    await tester.tap(find.text('选择课程'));
    await tester.pumpAndSettle();

    expect(find.text('关联 Canvas 课程'), findsOneWidget);
    expect(find.text('人工智能法学专题'), findsWidgets);
    expect(find.text('LAW7001'), findsWidgets);
    app.dispose();
  });

  testWidgets('week selector marks the current academic week', (tester) async {
    final app = AppController(NotificationService());
    final currentWeek = app.currentAcademicWeekInTerm;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WeekPage(app: app)),
      ),
    );

    expect(find.text('本周'), findsNothing);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();

    expect(currentWeek, isNotNull);
    expect(find.text('（本周）'), findsOneWidget);
    await tester.tap(find.text('（本周）'));
    await tester.pumpAndSettle();
    expect(find.text('本周'), findsOneWidget);
    expect(find.text('第 $currentWeek 周'), findsOneWidget);
    final otherWeek = currentWeek == 1 ? 2 : 1;
    app.selectWeek(otherWeek);
    await tester.pump();
    expect(find.text('本周'), findsNothing);
    expect(find.text('第 $otherWeek 周'), findsOneWidget);
    expect(tester.takeException(), isNull);
    app.dispose();
  });

  testWidgets('390px layout shows seven days and period start times', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController(NotificationService());
    app.courses = [
      Course.fromMap({
        'name': '算法课程(LAW6001-19000-X01)',
        'weekday': 2,
        'startPeriod': 1,
        'endPeriod': 2,
        'teacher': '朱军，庄加园',
        'location': '新上院 N100',
        'rawWeekText': '1-16周',
      }),
      Course.fromMap({
        'name': '周日课程',
        'weekday': 7,
        'startPeriod': 3,
        'endPeriod': 4,
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WeekPage(app: app)),
      ),
    );
    final syncButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.sync_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(syncButton.color, AppThemeChoice.sjtuBlue.primary);
    final weekPicker = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    final currentWeekText = find.text('第 ${app.selectedWeek} 周');
    final weekTheme = Theme.of(tester.element(currentWeekText));
    expect((weekPicker.icon as Icon).color, weekTheme.colorScheme.primary);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('week-date-range')))
          .style
          ?.color,
      weekTheme.colorScheme.primary,
    );
    expect(find.text('周一'), findsOneWidget);
    expect(find.text('周日'), findsOneWidget);
    final expectedCellColor = Theme.of(tester.element(find.text('节次')))
        .colorScheme
        .surfaceContainerLowest;
    Container headerCell(String label) => tester
        .widgetList<Container>(
          find.ancestor(of: find.text(label), matching: find.byType(Container)),
        )
        .first;
    expect(
      (headerCell('节次').decoration! as BoxDecoration).color,
      expectedCellColor,
    );
    expect(
      (headerCell('周一').decoration! as BoxDecoration).color,
      expectedCellColor,
    );
    expect(find.text('08:00\n08:45'), findsOneWidget);
    expect(find.text('08:55\n09:40'), findsOneWidget);
    expect(find.text('算法课程'), findsOneWidget);
    expect(find.textContaining('LAW6001'), findsNothing);
    expect(find.text('朱军\n庄加园'), findsOneWidget);
    expect(find.text('新上院\nN100'), findsOneWidget);
    expect(find.text('1-16周'), findsNothing);
    final nameTop = tester.getTopLeft(find.text('算法课程')).dy;
    final locationTop = tester.getTopLeft(find.text('新上院\nN100')).dy;
    final teacherTop = tester.getTopLeft(find.text('朱军\n庄加园')).dy;
    expect(nameTop, lessThan(locationTop));
    expect(locationTop, lessThan(teacherTop));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('算法课程'));
    await tester.pumpAndSettle();
    expect(find.textContaining('08:00–09:40'), findsOneWidget);
    expect(find.text('课程代码 LAW6001-19000-X01'), findsOneWidget);
    expect(find.text('朱军，庄加园'), findsOneWidget);
    expect(find.text('新上院 N100'), findsOneWidget);
    final tabBar = find.byType(TabBar);
    final tabView = find.byType(TabBarView);
    final controller = DefaultTabController.of(tester.element(tabBar));
    expect(controller.index, 0);
    await tester.drag(tabView, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(controller.index, 0);
    await tester.tap(find.text('大纲'));
    await tester.pumpAndSettle();
    expect(controller.index, 1);
    app.dispose();
  });
  testWidgets('360px large text keeps five-day grid free of overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController(NotificationService());
    app.courses = [
      Course.fromMap({
        'name': '高级人工智能系统设计',
        'weekday': 5,
        'startPeriod': 1,
        'endPeriod': 3,
        'teacher': '张老师',
        'location': '东上院101',
      }),
    ];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          home: Scaffold(body: WeekPage(app: app)),
        ),
      ),
    );
    expect(find.text('周一'), findsOneWidget);
    expect(find.text('周五'), findsOneWidget);
    expect(find.text('高级人工智能系统设计'), findsOneWidget);
    expect(tester.takeException(), isNull);
    app.dispose();
  });
  testWidgets('course title uses a four-line baseline without truncation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final courses = [
      Course.fromMap({
        'name': '算法',
        'weekday': 1,
        'startPeriod': 1,
        'endPeriod': 2,
        'teacher': '李老师',
        'location': '东上院101',
      }),
      Course.fromMap({
        'name': '高级人工智能系统设计与工程实践课程',
        'weekday': 2,
        'startPeriod': 1,
        'endPeriod': 3,
        'teacher': '王老师',
        'location': '新上院 N100',
      }, index: 1),
    ];
    final app = AppController(NotificationService())..courses = courses;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WeekPage(app: app)),
      ),
    );

    for (final course in courses) {
      final title = tester.widget<Text>(
        find.byKey(ValueKey('course-name-${course.id}')),
      );
      expect(title.maxLines, isNull);
      expect(title.data, course.name);
      final spacer = tester.widget<SizedBox>(
        find.byKey(ValueKey('course-title-space-${course.id}')),
      );
      expect(spacer.height, greaterThanOrEqualTo(0));
    }
    final shortSpacer = tester.widget<SizedBox>(
      find.byKey(ValueKey('course-title-space-${courses.first.id}')),
    );
    final longSpacer = tester.widget<SizedBox>(
      find.byKey(ValueKey('course-title-space-${courses.last.id}')),
    );
    expect(shortSpacer.height, greaterThan(longSpacer.height!));
    expect(find.text(courses.last.name), findsOneWidget);
    expect(tester.takeException(), isNull);
    app.dispose();
  });
  testWidgets('login exposes jAccount and remember choice', (tester) async {
    final app = AppController(NotificationService());
    await tester.pumpWidget(MaterialApp(home: LoginPage(app: app)));
    expect(find.text('jAccount账号'), findsOneWidget);
    expect(find.text('记住本人'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      true,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    app.dispose();
  });
  testWidgets('my page keeps websites and moves settings behind the gear', (
    tester,
  ) async {
    final app = AppController(NotificationService())..username = 'student';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(app: app)),
      ),
    );
    expect(
      graduateSchoolUrl,
      'https://yjs.sjtu.edu.cn/gsapp/sys/emaphome/portal/index.do',
    );
    expect(find.text('研究生应用管理平台'), findsOneWidget);
    expect(find.text('Canvas教学平台'), findsOneWidget);
    expect(find.textContaining('学号：'), findsNothing);
    expect(find.text('student'), findsOneWidget);
    expect(find.text('账号：student'), findsNothing);
    expect(find.text('我的信息'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);
    final gearButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('设置'),
        matching: find.byType(IconButton),
      ),
    );
    expect(gearButton.color, app.themeChoice.primary);
    app.studentNumber = '123456789012';
    app.notifyListeners();
    await tester.pump();
    expect(find.text('123456789012'), findsOneWidget);
    expect(find.text('杨惠泽'), findsNothing);
    final dividerCount = find.byType(Divider).evaluate().length;
    app.studentName = '杨惠泽';
    app.studentCollege = '凯原法学院';
    app.notifyListeners();
    await tester.pump();
    expect(find.text('杨惠泽'), findsOneWidget);
    expect(find.text('123456789012'), findsOneWidget);
    expect(find.text('凯原法学院'), findsOneWidget);
    expect(find.byType(Divider).evaluate().length, dividerCount);
    expect(find.textContaining('学号：'), findsNothing);
    expect(find.byTooltip('复制学号'), findsOneWidget);
    final informationCard = find.byKey(const Key('my-information-card'));
    final cardRect = tester.getRect(informationCard);
    final dividerRect = tester.getRect(
      find.descendant(of: informationCard, matching: find.byType(Divider)),
    );
    final nameRect = tester.getRect(find.text('杨惠泽'));
    final numberRect = tester.getRect(find.text('123456789012'));
    final collegeRect = tester.getRect(find.text('凯原法学院'));
    final numberRowRect = tester.getRect(
      find.byKey(const Key('student-number-row')),
    );
    final copyRect = tester.getRect(
      find.ancestor(
        of: find.byTooltip('复制学号'),
        matching: find.byType(IconButton),
      ),
    );
    expect(nameRect.top - dividerRect.bottom, inInclusiveRange(14, 18));
    expect((nameRect.center.dy - numberRect.center.dy).abs(), lessThan(8));
    expect(collegeRect.top, greaterThanOrEqualTo(numberRowRect.bottom));
    expect(collegeRect.top - numberRowRect.bottom, inInclusiveRange(0, 5));
    expect(cardRect.bottom - collegeRect.bottom, greaterThan(8));
    expect(numberRect.left - nameRect.right, inInclusiveRange(7, 10));
    expect(copyRect.left - numberRect.right, inInclusiveRange(3, 6));
    expect(cardRect.right - copyRect.right, greaterThan(6));
    final accountRect = tester.getRect(find.text('student'));
    expect(accountRect.left - nameRect.left, inInclusiveRange(3, 5));
    expect(accountRect.left - dividerRect.left, inInclusiveRange(2, 6));
    expect(
      find.descendant(
        of: find.byKey(const Key('student-number-row')),
        matching: find.byTooltip('复制学号'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('复制学号'),
              matching: find.byType(IconButton),
            ),
          )
          .iconSize,
      16,
    );
    final nameStyle = tester.widget<Text>(find.text('杨惠泽')).style!;
    final numberStyle =
        tester.widget<SelectableText>(find.byType(SelectableText)).style!;
    final collegeStyle = tester.widget<Text>(find.text('凯原法学院')).style!;
    expect(nameStyle.fontSize, 16);
    expect(numberStyle.fontSize, 16);
    expect(collegeStyle.fontSize, 16);
    expect(nameStyle.fontWeight, FontWeight.w700);
    expect(numberStyle.fontWeight, FontWeight.w700);
    expect(collegeStyle.fontWeight, FontWeight.w700);
    expect(nameStyle.height, 1.0);
    expect(numberStyle.height, 1.0);
    expect(collegeStyle.height, 1.0);
    Object? clipboardData;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardData = call.arguments;
        return null;
      },
    );
    await tester.tap(find.byTooltip('复制学号'));
    await tester.pump();
    expect(clipboardData, {'text': '123456789012'});
    expect(find.text('学号已复制'), findsOneWidget);
    clipboardData = null;
    await tester.longPress(find.text('123456789012'));
    await tester.pump();
    expect(clipboardData, isNull);
    expect(
      tester
          .widget<SelectableText>(find.byType(SelectableText))
          .onSelectionChanged,
      isNull,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    expect(find.text('复用当前 jAccount 登录状态'), findsNothing);
    expect(find.text('复用当前 Canvas 与 jAccount 会话'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('水源社区'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('水源社区'), findsOneWidget);
    expect(find.text('传承·交大'), findsOneWidget);
    expect(find.text('选课社区'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('图书馆'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('图书馆'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('交大云盘'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('交大云盘'), findsOneWidget);
    expect(sjtuCloudDriveUrl, 'https://pan.sjtu.edu.cn/');
    await tester.scrollUntilVisible(
      find.text('交大邮箱'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('交大邮箱'), findsOneWidget);
    expect(sjtuMailUrl, 'https://mail.sjtu.edu.cn/modern/');
    await tester.scrollUntilVisible(
      find.text('Stay Young, Stay Simple ▣-▣'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    final myPageEgg = tester.widget<Text>(
      find.text('Stay Young, Stay Simple ▣-▣'),
    );
    expect(myPageEgg.style?.color, const Color(0xFF8C9CAD));
    expect(
      find.ancestor(
        of: find.text('Stay Young, Stay Simple ▣-▣'),
        matching: find.byType(Center),
      ),
      findsOneWidget,
    );
    expect(find.text('主题颜色'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, 1800));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('设置'));
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('主题颜色'), findsOneWidget);
    expect(find.text('图书馆'), findsNothing);
    expect(find.text('我的账号'), findsOneWidget);
    expect(find.text('student'), findsOneWidget);
    expect(find.text('账号：student'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('交大课表  ·  v1.14.17'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('你们给我搞的这个课表啊，Excited！'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('退出登录'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('退出登录'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('退出登录')).dy,
      lessThan(tester.getTopLeft(find.text('交大课表  ·  v1.14.17')).dy),
    );
    final signOut = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '退出登录'),
    );
    expect(
      signOut.style?.foregroundColor?.resolve({}),
      const Color(0xFFB42330),
    );
    expect(signOut.style?.textStyle?.resolve({})?.fontSize, 16);
    expect(tester.takeException(), isNull);
    app.dispose();
  });
}
