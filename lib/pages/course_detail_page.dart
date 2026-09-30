import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/canvas_data.dart';
import '../models/course.dart';
import '../models/periods.dart';
import '../models/app_theme.dart';
import '../services/canvas_extractor.dart';
import '../services/canvas_avatar.dart';
import '../services/canvas_avatar_cache.dart';
import '../state/app_controller.dart';
import 'authenticated_web_page.dart';

class CourseDetailPage extends StatelessWidget {
  const CourseDetailPage({super.key, required this.app, required this.course});

  final AppController app;
  final Course course;
  static const _days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: app,
        builder: (context, _) {
          final current = app.courses.firstWhere(
            (item) => item.id == course.id,
            orElse: () => course,
          );
          final canvasCourse = app.canvasCourseFor(current);
          return DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('课程详情'),
                actions: [
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 17),
                    label: const Text('Canvas'),
                    onPressed: () {
                      final id = canvasCourse?.id.trim() ?? '';
                      if (id.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('暂未匹配 Canvas 课程')),
                        );
                        return;
                      }
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AuthenticatedWebPage(
                          title: canvasCourse!.name,
                          initialUrl:
                              'https://oc.sjtu.edu.cn/courses/${Uri.encodeComponent(id)}',
                          targetHost: 'oc.sjtu.edu.cn',
                          app: app,
                          canvasSite: true,
                          ssoFallbackUrl: canvasSsoUrl,
                          showCloseButton: true,
                        ),
                      ));
                    },
                  ),
                ],
              ),
              body: Column(children: [
                _CourseHeader(app: app, course: current, days: _days),
                if (canvasCourse == null)
                  _LinkCanvasPanel(app: app, course: current),
                Material(
                  key: const Key('course-detail-tabs-background'),
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.transparent
                      : app.themeChoice.brightThemeFor(
                          Theme.of(context).brightness,
                        ),
                  child: const TabBar(
                    tabs: [
                      Tab(text: '公告'),
                      Tab(text: '大纲'),
                      Tab(text: '班级成员'),
                    ],
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    key: const Key('course-detail-content-background'),
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.white
                        : app.themeChoice.surfaceFor(
                            Theme.of(context).brightness,
                          ),
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _Announcements(app: app, course: canvasCourse),
                        _Syllabus(course: canvasCourse),
                        _People(course: canvasCourse),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}

class _CourseHeader extends StatelessWidget {
  const _CourseHeader(
      {required this.app, required this.course, required this.days});
  final AppController app;
  final Course course;
  final List<String> days;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = app.themeChoice.headerFor(brightness);
    return Container(
      key: const Key('course-detail-header-background'),
      width: double.infinity,
      color: brightness == Brightness.light
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : app.themeChoice.pageBackgroundFor(brightness),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          course.name,
          style: TextStyle(
            fontSize: 24,
            height: 1.25,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
        const SizedBox(height: 12),
        _MetaLine(
          icon: Icons.schedule_outlined,
          color: accent,
          text: course.hasSchedule
              ? '${days[course.weekday - 1]}  ${clockLabel(course.startMinutes)}–${clockLabel(course.endMinutes)}'
              : '时间待确认',
        ),
        if (course.courseCode.isNotEmpty)
          _MetaLine(
            icon: Icons.tag_outlined,
            color: accent,
            text: '课程代码 ${course.courseCode}',
          ),
        _MetaLine(
          icon: Icons.location_on_outlined,
          color: accent,
          text: course.location.isEmpty ? '地点待确认' : course.location,
          action: course.location.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AuthenticatedWebPage(
                        title: '交大地图',
                        initialUrl: 'https://map.sjtu.edu.cn/',
                        targetHost: 'map.sjtu.edu.cn',
                        app: app,
                        authenticationRequired: false,
                        enableGeolocation: true,
                        locationQuery: course.location,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('地图'),
                ),
        ),
        _MetaLine(
          icon: Icons.person_outline,
          color: accent,
          text: course.teacher.isEmpty ? '教师待确认' : course.teacher,
        ),
        _MetaLine(
          icon: Icons.date_range_outlined,
          color: accent,
          text: course.rawWeekText.isEmpty
              ? '第 ${course.activeWeeks.first}–${course.activeWeeks.last} 周（待确认）'
              : course.rawWeekText,
        ),
      ]),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine(
      {required this.icon,
      required this.text,
      required this.color,
      this.action});
  final IconData icon;
  final String text;
  final Color color;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
          if (action != null) action!,
        ]),
      );
}

class _LinkCanvasPanel extends StatelessWidget {
  const _LinkCanvasPanel({required this.app, required this.course});
  final AppController app;
  final Course course;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: ListTile(
          dense: true,
          leading:
              Icon(Icons.link, color: Theme.of(context).colorScheme.primary),
          title: Text(app.refreshing ? '正在同步 Canvas 课程' : 'Canvas 暂无匹配课程'),
          subtitle:
              Text(app.refreshing ? '同步完成后将自动匹配并显示课程内容' : '下次同步会自动重试，也可手动选择'),
          trailing: TextButton(
            onPressed: () => _pick(context),
            child: const Text('选择课程'),
          ),
        ),
      );

  Future<void> _pick(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _CanvasCoursePicker(app: app),
    );
    if (selected != null) await app.mapCourseToCanvas(course, selected);
  }
}

class _CanvasCoursePicker extends StatefulWidget {
  const _CanvasCoursePicker({required this.app});
  final AppController app;

  @override
  State<_CanvasCoursePicker> createState() => _CanvasCoursePickerState();
}

class _CanvasCoursePickerState extends State<_CanvasCoursePicker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.app.canvas.courses.isEmpty) {
        unawaited(widget.app.refreshNow());
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.app,
        builder: (context, _) {
          final courses = widget.app.canvas.courses;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .68,
              child: Column(children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '关联 Canvas 课程',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                Expanded(
                  child: courses.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.app.refreshing)
                                const CircularProgressIndicator(
                                    strokeWidth: 2.4)
                              else
                                Icon(Icons.cloud_off_outlined,
                                    size: 38,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              const SizedBox(height: 14),
                              Text(widget.app.refreshing
                                  ? '正在读取 Canvas 课程…'
                                  : '尚未读取到 Canvas 课程'),
                              if (!widget.app.refreshing) ...[
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: widget.app.refreshNow,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('重新同步'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: courses.length,
                          itemBuilder: (context, index) {
                            final item = courses[index];
                            return ListTile(
                              title: Text(item.name),
                              subtitle: item.courseCode.isEmpty
                                  ? null
                                  : Text(item.courseCode),
                              onTap: () => Navigator.pop(context, item.id),
                            );
                          },
                        ),
                ),
              ]),
            ),
          );
        },
      );
}

class _Announcements extends StatelessWidget {
  const _Announcements({required this.app, required this.course});
  final AppController app;
  final CanvasCourseData? course;

  @override
  Widget build(BuildContext context) {
    if (course == null) return const _EmptyCanvas(text: 'Canvas 暂无匹配课程');
    if (course!.announcementsError.isNotEmpty &&
        course!.announcements.isEmpty) {
      return const _EmptyCanvas(text: '这门课程的公告暂时无法读取，请稍后重试');
    }
    if (course!.announcements.isEmpty) {
      return const _EmptyCanvas(text: '这门课程暂无公告');
    }
    final items = [...course!.announcements]..sort((a, b) {
        final first = DateTime.tryParse(a.createdAt);
        final second = DateTime.tryParse(b.createdAt);
        if (first != null && second != null) return second.compareTo(first);
        if (first != null) return -1;
        if (second != null) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          title: Text(item.title,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(_plainText(item.messageHtml),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await app.markCanvasItemRead(item);
            if (!context.mounted) return;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  CanvasHtmlPage(title: item.title, html: item.messageHtml),
            ));
          },
        );
      },
    );
  }
}

class _Syllabus extends StatelessWidget {
  const _Syllabus({required this.course});
  final CanvasCourseData? course;
  @override
  Widget build(BuildContext context) {
    if (course == null) return const _EmptyCanvas(text: 'Canvas 暂无匹配课程');
    if (course!.syllabusHtml.trim().isEmpty) {
      return const _EmptyCanvas(text: 'Canvas 中未提供课程大纲');
    }
    return CanvasHtmlView(html: course!.syllabusHtml);
  }
}

class _People extends StatelessWidget {
  const _People({required this.course});
  final CanvasCourseData? course;

  Widget _avatar(BuildContext context, CanvasPerson person) {
    return _CanvasPersonAvatar(
      key: ValueKey('canvas-avatar:${person.id}'),
      avatarUrl: person.avatarUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (course == null) return const _EmptyCanvas(text: 'Canvas 暂无匹配课程');
    if (course!.peopleError.isNotEmpty && course!.people.isEmpty) {
      return const _EmptyCanvas(text: 'Canvas 权限不允许读取班级成员');
    }
    if (course!.people.isEmpty) return const _EmptyCanvas(text: '暂无可见成员');
    final people = canvasPeopleInRoleOrder(course!.people);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: people.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final person = people[index];
        return ListTile(
          key: ValueKey('canvas-person:${person.id}'),
          leading: _avatar(context, person),
          title: Text(person.name.isEmpty ? '未命名成员' : person.name),
          subtitle: Text(_roleLabel(person.role) +
              (person.email.isEmpty ? '' : '  ${person.email}')),
        );
      },
    );
  }
}

class _CanvasPersonAvatar extends StatefulWidget {
  const _CanvasPersonAvatar({super.key, required this.avatarUrl});

  final String avatarUrl;

  @override
  State<_CanvasPersonAvatar> createState() => _CanvasPersonAvatarState();
}

class _CanvasPersonAvatarState extends State<_CanvasPersonAvatar> {
  static final _defaultUrl = Uri.parse(canvasDefaultAvatarUrl);

  late Uri _source;
  File? _imageFile;
  Uri? _imageSource;
  int _requestGeneration = 0;
  final Set<String> _failedFiles = {};

  @override
  void initState() {
    super.initState();
    _source = resolveCanvasAvatar(widget.avatarUrl);
    unawaited(_load(_source, ++_requestGeneration));
  }

  @override
  void didUpdateWidget(covariant _CanvasPersonAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = resolveCanvasAvatar(widget.avatarUrl);
    if (next == _source) return;
    _source = next;
    unawaited(_load(next, ++_requestGeneration));
  }

  bool _isCurrent(int generation) =>
      mounted && generation == _requestGeneration;

  Future<void> _load(Uri uri, int generation) async {
    final cache = CanvasAvatarCache.instance;
    final cached = await cache.read(uri);
    if (!_isCurrent(generation)) return;
    if (cached != null) {
      _show(cached.file, uri);
      if (cache.isStale(cached)) {
        unawaited(_refresh(uri, cached, generation));
      }
      return;
    }

    final downloaded = await cache.download(uri);
    if (!_isCurrent(generation)) return;
    if (downloaded != null) {
      _show(downloaded.file, uri);
      return;
    }

    if (uri != _defaultUrl) {
      await _loadFallback(generation);
    }
  }

  Future<void> _loadFallback(int generation) async {
    final fallback = await CanvasAvatarCache.instance.read(_defaultUrl);
    if (!_isCurrent(generation)) return;
    if (fallback != null) {
      _show(fallback.file, _defaultUrl);
      if (CanvasAvatarCache.instance.isStale(fallback)) {
        unawaited(_refresh(_defaultUrl, fallback, generation));
      }
      return;
    }
    final downloaded = await CanvasAvatarCache.instance.download(_defaultUrl);
    if (!_isCurrent(generation) || downloaded == null) return;
    _show(downloaded.file, _defaultUrl);
  }

  Future<void> _refresh(
    Uri uri,
    CanvasAvatarCacheEntry previous,
    int generation,
  ) async {
    final updated = await CanvasAvatarCache.instance.download(uri);
    if (!_isCurrent(generation) ||
        updated == null ||
        updated.file.path == previous.file.path) {
      return;
    }
    _show(updated.file, uri);
  }

  void _show(File file, Uri source) {
    if (!mounted || (_imageFile?.path == file.path && _imageSource == source)) {
      return;
    }
    setState(() {
      _imageFile = file;
      _imageSource = source;
    });
  }

  void _handleImageError(File file, Uri source, int generation) {
    if (!_isCurrent(generation) ||
        _imageFile?.path != file.path ||
        !_failedFiles.add(file.path)) {
      return;
    }
    unawaited(CanvasAvatarCache.instance.evict(source, expectedFile: file));
    if (source == _defaultUrl) {
      setState(() {
        _imageFile = null;
        _imageSource = null;
      });
    } else {
      unawaited(_loadFallback(generation));
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _imageFile;
    final imageSource = _imageSource;
    final generation = _requestGeneration;
    final colors = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: colors.primaryContainer,
      child: ClipOval(
        child: SizedBox(
          width: 40,
          height: 40,
          child: file == null || imageSource == null
              ? Center(
                  child: Icon(
                    Icons.person_outline,
                    size: 27,
                    color: colors.onPrimaryContainer,
                  ),
                )
              : Image.file(
                  file,
                  key: ValueKey(file.path),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  cacheWidth: 120,
                  cacheHeight: 120,
                  errorBuilder: (_, __, ___) {
                    _handleImageError(file, imageSource, generation);
                    return Center(
                      child: Icon(
                        Icons.person_outline,
                        size: 27,
                        color: colors.onPrimaryContainer,
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inbox_outlined,
                size: 38,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      );
}

class CanvasHtmlPage extends StatelessWidget {
  const CanvasHtmlPage({super.key, required this.title, required this.html});
  final String title, html;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: CanvasHtmlView(html: html),
      );
}

class CanvasHtmlView extends StatefulWidget {
  const CanvasHtmlView({super.key, required this.html});
  final String html;
  @override
  State<CanvasHtmlView> createState() => _CanvasHtmlViewState();
}

class _CanvasHtmlViewState extends State<CanvasHtmlView> {
  late final WebViewController controller;
  Brightness? _loadedBrightness;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_loadedBrightness == brightness) return;
    _loadedBrightness = brightness;
    unawaited(controller
        .setBackgroundColor(Theme.of(context).colorScheme.surface)
        .then((_) => controller.loadHtmlString(
              _document(widget.html, brightness),
              baseUrl: 'https://oc.sjtu.edu.cn',
            )));
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: controller);

  static String _document(String body, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? '#252D36' : '#FFFFFF';
    final foreground = dark ? '#E1E7ED' : '#203247';
    final border = dark ? '#46515D' : '#DFE7EF';
    final link = dark ? '#9BBEE0' : '#005BAC';
    return '''<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{background:$background}body{font-family:-apple-system,BlinkMacSystemFont,"Noto Sans CJK SC",sans-serif;color:$foreground;line-height:1.7;padding:14px 18px;margin:0}img,video{max-width:100%;height:auto}table{width:100%;border-collapse:collapse}td,th{border:1px solid $border;padding:6px}a{color:$link}pre{white-space:pre-wrap}</style>
</head><body>$body</body></html>''';
  }
}

String _plainText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _roleLabel(String role) {
  final lower = role.toLowerCase();
  if (lower.contains('teacher')) return '教师';
  if (lower.contains('ta')) return '助教';
  if (lower.contains('student')) return '学生';
  return role.isEmpty ? '成员' : role;
}
