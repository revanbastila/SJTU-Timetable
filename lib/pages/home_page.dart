import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_theme.dart';
import '../models/course.dart';
import '../models/teaching_calendar.dart';
import '../services/message_feed.dart';
import '../state/app_controller.dart';
import '../widgets/course_tile.dart';
import '../widgets/draggable_unread_badge.dart';
import 'course_detail_page.dart';
import 'portal_sync_page.dart';

({Course? course, bool isInClass}) featuredCourseAt(
  List<Course> courses,
  DateTime now,
) {
  final nowMinutes = now.hour * 60 + now.minute;
  for (final course in courses) {
    if (course.startMinutes <= nowMinutes && nowMinutes < course.endMinutes) {
      return (course: course, isInClass: true);
    }
    if (course.startMinutes > nowMinutes) {
      return (course: course, isInClass: false);
    }
  }
  return (course: null, isInClass: false);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.app, this.isActive = true});
  final AppController app;
  final bool isActive;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _clockTimer;

  AppController get app => widget.app;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String _weekday(int day) =>
      const ['一', '二', '三', '四', '五', '六', '日'][day - 1];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: app,
        builder: (context, _) {
          final now = shanghaiNow();
          final week = app.currentAcademicWeekInTerm;
          final todayCourses = app.getEffectiveCoursesForDate(now);
          final featured = featuredCourseAt(todayCourses, now);
          final makeupMessage =
              app.teachingCalendar.ruleFor(now)?.makeupMessage;
          final isExamWeek = week != null && app.examWeeks.contains(week);
          final brightness = Theme.of(context).brightness;
          return ColoredBox(
            key: const Key('home-page-background'),
            color: app.themeChoice.scheduleContentFor(brightness),
            child: DefaultTabController(
              length: 2,
              child: SafeArea(
                child: Column(
                  children: [
                    _Header(
                      app: app,
                      today: now,
                      weekday: _weekday(now.weekday),
                      weekLabel:
                          week == null ? app.currentTermStatus : '第 $week 周',
                    ),
                    Material(
                      color: app.themeChoice.scheduleChromeFor(brightness),
                      child: TabBar(
                        tabs: [
                          const Tab(text: '今日课程'),
                          Tab(
                            child: Center(
                              child: DraggableUnreadBadge(
                                count: app.unreadMessageCount,
                                onDismiss: app.markAllMessagesRead,
                                // Keep the badge inside the TabBar paint and hit-test
                                // bounds; the default floating position is clipped.
                                badgeTop: 2,
                                badgeRight: 0,
                                child: const SizedBox(
                                  width: 76,
                                  height: 40,
                                  child: Padding(
                                    padding: EdgeInsets.only(right: 36),
                                    child: Center(child: Text('消息')),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _TodayList(
                            app: app,
                            courses: todayCourses,
                            featured: featured.course,
                            isInClass: featured.isInClass,
                            isActive: widget.isActive,
                            onCurrentClassEnded: () {
                              if (mounted) setState(() {});
                            },
                          ),
                          _DashboardAnnouncements(app: app),
                        ],
                      ),
                    ),
                    if (makeupMessage != null || isExamWeek)
                      _CalendarNoticeBanner(
                          makeupMessage: makeupMessage, isExamWeek: isExamWeek),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.app,
    required this.today,
    required this.weekday,
    required this.weekLabel,
  });
  final AppController app;
  final DateTime today;
  final String weekday;
  final String weekLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('home-header'),
      color: light
          ? scheme.primary
          : app.themeChoice.brightThemeFor(theme.brightness),
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 23),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Image.asset(
                  'assets/jiao_glyph_white.png',
                  key: const Key('home-jiao-glyph'),
                  width: 38,
                  height: 40,
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.contain,
                ),
              ),
              IconButton(
                tooltip: '同步教务与 Canvas',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PortalSyncPage(
                      username: app.username,
                      password: '',
                      app: app,
                      rememberMe: app.rememberMe,
                    ),
                  ),
                ),
                color: Colors.white,
                icon: const Icon(Icons.sync_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${today.month}月${today.day}日  星期$weekday  ·  $weekLabel',
            key: const Key('home-date-line'),
            style: TextStyle(
              color: light ? scheme.primaryContainer : scheme.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            app.username.isEmpty ? '今天的课程安排' : '${app.username}，今天的课程安排',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Occupies its own space below the scrolling tabs, above the shell navigation.
class _CalendarNoticeBanner extends StatelessWidget {
  const _CalendarNoticeBanner({this.makeupMessage, required this.isExamWeek});
  final String? makeupMessage;
  final bool isExamWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Retain the former makeup note's tab-label typography and primary color.
    final style = (theme.useMaterial3
            ? theme.textTheme.titleSmall!
            : theme.primaryTextTheme.bodyLarge!)
        .merge(theme.tabBarTheme.labelStyle)
        .copyWith(color: scheme.primary);
    return Padding(
      key: const Key('calendar-notice-banner'),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (makeupMessage != null)
              Text(makeupMessage!,
                  key: const Key('today-makeup-message'), style: style),
            if (makeupMessage != null && isExamWeek) const SizedBox(height: 4),
            if (isExamWeek)
              Text('本周为考试周，请按安排准时参加考试，加油！',
                  key: const Key('today-exam-message'), style: style),
          ],
        ),
      ),
    );
  }
}

class _TodayList extends StatelessWidget {
  const _TodayList({
    required this.app,
    required this.courses,
    required this.featured,
    required this.isInClass,
    required this.isActive,
    required this.onCurrentClassEnded,
  });
  final AppController app;
  final List<Course> courses;
  final Course? featured;
  final bool isInClass;
  final bool isActive;
  final VoidCallback onCurrentClassEnded;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: app.refreshNow,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text(
                  '今天',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color:
                        app.themeChoice.headerFor(Theme.of(context).brightness),
                  ),
                )),
                Text(
                  '${courses.length} 门课',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (featured != null)
              _NextClass(
                course: featured!,
                isInClass: isInClass,
                isActive: isActive,
                onCurrentClassEnded: onCurrentClassEnded,
                onTap: () => _openCourse(context, featured!),
              )
            else
              _EmptyState(
                  hasCourses: courses.isNotEmpty,
                  message: app.teachingCalendar
                      .ruleFor(shanghaiNow())
                      ?.emptyMessage),
            const SizedBox(height: 18),
            for (final course in courses)
              CourseTile(
                course: course,
                highlight: course.id == featured?.id,
                onTap: () => _openCourse(context, course),
              ),
            if (courses.isEmpty) const SizedBox(height: 120),
          ],
        ),
      );

  void _openCourse(BuildContext context, Course course) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CourseDetailPage(app: app, course: course),
        ),
      );
}

class _DashboardAnnouncements extends StatelessWidget {
  const _DashboardAnnouncements({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final items = buildMessageFeed(app.canvas, app.courses);
    return RefreshIndicator(
      onRefresh: app.refreshNow,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 150),
                Icon(
                  Icons.notifications_none_rounded,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                const Center(child: Text('暂无消息')),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => Dismissible(
                key: ValueKey(items[index].key),
                direction: DismissDirection.horizontal,
                confirmDismiss: (_) async {
                  await app.markMessageRead(items[index].key);
                  return false;
                },
                background: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('已读'),
                ),
                secondaryBackground: const Align(
                  alignment: Alignment.centerRight,
                  child: Text('已读'),
                ),
                child: _MessageTile(app: app, entry: items[index]),
              ),
            ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.app, required this.entry});
  final AppController app;
  final MessageFeedEntry entry;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.campaign_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          entry.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            entry.sourceLabel,
            _date(entry.createdAt),
          ].where((s) => s.isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await app.markMessageRead(entry.key);
          if (!context.mounted) return;
          final item = entry.canvasItem!;
          final course = entry.timetableCourse;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => item.messageHtml.trim().isNotEmpty ||
                      course == null
                  ? CanvasHtmlPage(title: item.title, html: item.messageHtml)
                  : CourseDetailPage(app: app, course: course),
            ),
          );
        },
      );

  static String _date(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    return date == null ? '' : DateFormat('M.d HH:mm').format(date);
  }
}

class _NextClass extends StatefulWidget {
  const _NextClass({
    required this.course,
    required this.isInClass,
    required this.isActive,
    required this.onCurrentClassEnded,
    required this.onTap,
  });
  final Course course;
  final bool isInClass;
  final bool isActive;
  final VoidCallback onCurrentClassEnded;
  final VoidCallback onTap;
  @override
  State<_NextClass> createState() => _NextClassState();
}

class _NextClassState extends State<_NextClass> {
  Timer? _statusTimer;
  int _dotCount = 0;
  bool _endNotified = false;

  @override
  void initState() {
    super.initState();
    _syncStatusTimer();
  }

  @override
  void didUpdateWidget(covariant _NextClass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isInClass != widget.isInClass ||
        oldWidget.isActive != widget.isActive ||
        oldWidget.course.id != widget.course.id ||
        oldWidget.course.endMinutes != widget.course.endMinutes) {
      _dotCount = 0;
      _endNotified = false;
      _syncStatusTimer();
    }
  }

  void _syncStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = null;
    if (!widget.isInClass || !widget.isActive) return;
    _statusTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final now = shanghaiNow();
      final nowMinutes = now.hour * 60 + now.minute;
      if (nowMinutes >= widget.course.endMinutes) {
        _statusTimer?.cancel();
        _statusTimer = null;
        if (!_endNotified) {
          _endNotified = true;
          widget.onCurrentClassEnded();
        }
        return;
      }
      setState(() => _dotCount = (_dotCount + 1) % 4);
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The highlighted card echoes the schedule header in light mode. Keep
    // the existing dark-mode surface treatment unchanged.
    final cardColor = theme.brightness == Brightness.light
        ? scheme.primary
        : scheme.primaryContainer;
    final foreground = theme.brightness == Brightness.light
        ? scheme.onPrimary
        : scheme.onPrimaryContainer;
    return Material(
      key: const Key('featured-course-card'),
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Icon(Icons.school_outlined, color: foreground, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isInClass)
                      Row(
                        key: const Key('current-class-status'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '正在上课',
                            style: TextStyle(
                              color: foreground.withValues(alpha: .86),
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(
                            key: const Key('current-class-dots-slot'),
                            width: 21,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '.' * _dotCount,
                                key: const Key('current-class-dots'),
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: foreground.withValues(alpha: .86),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        '下一节课',
                        style: TextStyle(
                          color: foreground.withValues(alpha: .78),
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      widget.course.name,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${widget.course.time}  ${widget.course.location}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground.withValues(alpha: .88),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasCourses, this.message});
  final String? message;
  final bool hasCourses;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(
          color: dark
              ? scheme.outlineVariant
              : _softHomeThemeColor(scheme.primary, lightness: .91),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.free_breakfast_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Text(message ?? (hasCourses ? '今天的课程已经结束。' : '本周今天没有课程。'))),
        ],
      ),
    );
  }
}

Color _softHomeThemeColor(Color primary, {required double lightness}) {
  final hsl = HSLColor.fromColor(primary);
  return hsl
      .withSaturation((hsl.saturation * .38).clamp(0.10, 0.30))
      .withLightness(lightness)
      .toColor();
}
