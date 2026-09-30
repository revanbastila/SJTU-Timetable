import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_theme.dart';
import '../services/notification_service.dart';
import '../services/canvas_extractor.dart';
import '../state/app_controller.dart';
import 'authenticated_web_page.dart';
import 'login_page.dart';

const sjtuMapUrl = 'https://map.sjtu.edu.cn/';
const shuiyuanUrl = 'https://shuiyuan.sjtu.edu.cn/login';
const heritageSjtuUrl = 'https://share.dyweb.sjtu.cn/';
const courseCommunityUrl = 'https://course.sjtu.plus/';
const graduateSchoolUrl =
    'https://yjs.sjtu.edu.cn/gsapp/sys/emaphome/portal/index.do';
const sjtuLibraryUrl = 'https://www.lib.sjtu.edu.cn/f/main/index.shtml';
const sjtuCloudDriveUrl = 'https://pan.sjtu.edu.cn/';
const sjtuMailUrl = 'https://mail.sjtu.edu.cn/modern/';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.app, this.advanced = false});

  final AppController app;
  final bool advanced;

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  AppController get app => widget.app;
  bool get advanced => widget.advanced;

  final FocusNode _studentNumberFocusNode = FocusNode();

  void clearStudentNumberSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _studentNumberFocusNode.context == null ||
          !_studentNumberFocusNode.hasFocus) {
        return;
      }
      _studentNumberFocusNode.unfocus();
    });
  }

  @override
  void dispose() {
    _studentNumberFocusNode.dispose();
    super.dispose();
  }

  void _openAdvancedSettings(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('设置')),
            body: SettingsPage(app: app, advanced: true),
          ),
        ),
      );

  String _modeLabel(ReminderMode mode) => switch (mode) {
        ReminderMode.off => '关闭提醒',
        ReminderMode.push => '推送消息',
        ReminderMode.alarm => '闹钟提醒',
      };

  Future<void> _copyStudentNumber(BuildContext context) async {
    if (app.studentNumber.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: app.studentNumber));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('学号已复制')));
  }

  Future<void> _showThemePicker(BuildContext context) async {
    final selected = await showModalBottomSheet<AppThemeChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 2, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '主题颜色',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              for (final choice in AppThemeChoice.values)
                ListTile(
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: choice.primary,
                  ),
                  title: Text(choice.label),
                  trailing: app.themeChoice == choice
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(choice),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) await app.setThemeChoice(selected);
  }

  @override
  Widget build(BuildContext context) {
    final informationTextStyle =
        (Theme.of(context).listTileTheme.titleTextStyle ??
                Theme.of(context).textTheme.titleMedium ??
                const TextStyle(fontSize: 16))
            .copyWith(fontWeight: FontWeight.w700, height: 1.0);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          children: [
            if (advanced)
              Text(
                '设置',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color:
                      app.themeChoice.headerFor(Theme.of(context).brightness),
                ),
              )
            else
              Row(
                children: [
                  Text(
                    '我的',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: app.themeChoice
                          .headerFor(Theme.of(context).brightness),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_outlined),
                    color: app.themeChoice
                        .primaryFor(Theme.of(context).brightness),
                    onPressed: () => _openAdvancedSettings(context),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            if (advanced) ...[
              _SettingCard(
                title: '我的账号',
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(
                      icon: Icons.account_circle_outlined,
                    ),
                    title: Text(
                      app.username,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _SettingCard(
                title: '数据同步',
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.sync_rounded),
                    title: const Text(
                      '自动更新频率',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('每 ${app.refreshMinutes} 分钟检查一次课表'),
                    trailing: DropdownButton<int>(
                      value: app.refreshMinutes,
                      underline: const SizedBox(),
                      items: const [15, 30, 60, 120]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value分'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) app.setRefreshMinutes(value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
            ],
            if (!advanced) ...[
              _SettingCard(
                key: const Key('my-information-card'),
                title: '我的信息',
                contentPadding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                titleInset: 8,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 8),
                    minLeadingWidth: 38,
                    horizontalTitleGap: 16,
                    leading: const _SettingIcon(
                      icon: Icons.account_circle_outlined,
                    ),
                    title: Text(
                      app.username,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (app.studentName.isNotEmpty ||
                      app.studentNumber.isNotEmpty ||
                      app.studentCollege.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(left: 58),
                      child: Divider(height: 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 58, bottom: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (app.studentName.isNotEmpty ||
                              app.studentNumber.isNotEmpty)
                            Wrap(
                              key: const Key('student-number-row'),
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 0,
                              children: [
                                if (app.studentName.isNotEmpty)
                                  Text(
                                    app.studentName,
                                    softWrap: true,
                                    style: informationTextStyle,
                                  ),
                                if (app.studentNumber.isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TapRegion(
                                        onTapOutside: (_) =>
                                            clearStudentNumberSelection(),
                                        child: SelectableText(
                                          app.studentNumber,
                                          focusNode: _studentNumberFocusNode,
                                          maxLines: 1,
                                          style: informationTextStyle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        tooltip: '复制学号',
                                        icon: const Icon(Icons.copy_outlined),
                                        iconSize: 16,
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                          width: 20,
                                          height: 24,
                                        ),
                                        onPressed: () =>
                                            _copyStudentNumber(context),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          if (app.studentCollege.isNotEmpty)
                            Text(
                              app.studentCollege,
                              softWrap: true,
                              style: informationTextStyle,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              _SettingCard(
                title: '常用网站',
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.school_outlined),
                    title: const Text(
                      '研究生应用管理平台',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuthenticatedWebPage(
                          title: '研究生应用管理平台',
                          initialUrl: graduateSchoolUrl,
                          targetHost: 'yjs.sjtu.edu.cn',
                          app: app,
                          preferSsoLogin: true,
                          showCloseButton: true,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.language_outlined),
                    title: const Text(
                      '交大 Canvas',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AuthenticatedWebPage(
                            title: '交大 Canvas',
                            // This is the same endpoint used by Canvas' jAccount
                            // card. Starting here avoids mistaking the adjacent
                            // external-account form for a jAccount login page.
                            initialUrl: canvasSsoUrl,
                            targetHost: 'oc.sjtu.edu.cn',
                            app: app,
                            canvasSite: true,
                            ssoFallbackUrl: canvasSsoUrl,
                            showCloseButton: true,
                          ),
                        ),
                      );
                      await app.refreshNow();
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.map_outlined),
                    title: const Text(
                      '交大地图',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuthenticatedWebPage(
                          title: '交大地图',
                          initialUrl: sjtuMapUrl,
                          targetHost: 'map.sjtu.edu.cn',
                          app: app,
                          authenticationRequired: false,
                          enableGeolocation: true,
                          showCloseButton: true,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.forum_outlined),
                    title: const Text(
                      '水源社区',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuthenticatedWebPage(
                          title: '水源社区',
                          initialUrl: shuiyuanUrl,
                          targetHost: 'shuiyuan.sjtu.edu.cn',
                          app: app,
                          preferSsoLogin: true,
                          showCloseButton: true,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(
                      icon: Icons.auto_stories_outlined,
                    ),
                    title: const Text(
                      '传承·交大',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuthenticatedWebPage(
                          title: '传承·交大',
                          initialUrl: heritageSjtuUrl,
                          targetHost: 'share.dyweb.sjtu.cn',
                          app: app,
                          preferSsoLogin: true,
                          showCloseButton: true,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.groups_outlined),
                    title: const Text(
                      '选课社区',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuthenticatedWebPage(
                          title: '选课社区',
                          initialUrl: courseCommunityUrl,
                          targetHost: 'course.sjtu.plus',
                          app: app,
                          authenticationRequired: false,
                          showCloseButton: true,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(
                      icon: Icons.local_library_outlined,
                    ),
                    title: const Text(
                      '图书馆',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuthenticatedWebPage(
                          title: '图书馆',
                          initialUrl: sjtuLibraryUrl,
                          targetHost: 'www.lib.sjtu.edu.cn',
                          app: app,
                          allowHttpTarget: true,
                          librarySite: true,
                          showCloseButton: true,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.cloud_outlined),
                    title: const Text(
                      '交大云盘',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuthenticatedWebPage(
                          title: '交大云盘',
                          initialUrl: sjtuCloudDriveUrl,
                          targetHost: 'pan.sjtu.edu.cn',
                          app: app,
                          preferSsoLogin: true,
                          showCloseButton: true,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.mail_outline),
                    title: const Text(
                      '交大邮箱',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuthenticatedWebPage(
                          title: '交大邮箱',
                          initialUrl: sjtuMailUrl,
                          targetHost: 'mail.sjtu.edu.cn',
                          app: app,
                          preferSsoLogin: true,
                          mailSite: true,
                          allowHttpTarget: true,
                          showCloseButton: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
            ],
            if (advanced) ...[
              _SettingCard(
                title: '应用外观',
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.contrast_rounded),
                    title: const Text(
                      '界面模式',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: DropdownButton<InterfaceMode>(
                      value: app.interfaceMode,
                      underline: const SizedBox(),
                      alignment: AlignmentDirectional.centerEnd,
                      items: [
                        for (final mode in InterfaceMode.values)
                          DropdownMenuItem(
                            value: mode,
                            child: SizedBox(
                              width: 76,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(mode.label),
                              ),
                            ),
                          ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) app.setInterfaceMode(mode);
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.palette_outlined),
                    title: const Text(
                      '主题颜色',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 7,
                          backgroundColor: app.themeChoice.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(app.themeChoice.label),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => _showThemePicker(context),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _SettingCard(
                title: '学期设置',
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(
                      icon: Icons.date_range_outlined,
                    ),
                    title: const Text(
                      '第 1 周周一',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${app.termStart.year}.${app.termStart.month.toString().padLeft(2, '0')}.${app.termStart.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: app.termStart,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2032),
                        helpText: '选择第 1 周周一',
                      );
                      if (picked != null) {
                        await app.setTerm(picked, app.totalWeeks);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.view_week_outlined),
                    title: const Text(
                      '学期总周数',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: DropdownButton<int>(
                      value: app.totalWeeks,
                      underline: const SizedBox(),
                      items: [
                        for (var weeks = 16; weeks <= 22; weeks++)
                          DropdownMenuItem(
                            value: weeks,
                            child: Text('$weeks 周'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) app.setTerm(app.termStart, value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _SettingCard(
                title: '上课提醒',
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _SettingIcon(
                      icon: Icons.notifications_none_rounded,
                    ),
                    title: Text(
                      '提醒方式',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SegmentedButton<ReminderMode>(
                    segments: const [
                      ButtonSegment(value: ReminderMode.off, label: Text('关闭')),
                      ButtonSegment(
                        value: ReminderMode.push,
                        label: Text('推送'),
                      ),
                      ButtonSegment(
                        value: ReminderMode.alarm,
                        label: Text('闹钟'),
                      ),
                    ],
                    selected: {app.reminderMode},
                    onSelectionChanged: (value) =>
                        app.setReminderMode(value.first),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '当前：${_modeLabel(app.reminderMode)}。闹钟提醒会使用声音和震动。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Divider(height: 22),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.schedule_outlined),
                    title: const Text(
                      '提前时间',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: DropdownButton<int>(
                      value: app.reminderMinutes,
                      underline: const SizedBox(),
                      items: const [5, 10, 15, 30]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value 分钟'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) app.setReminderMinutes(value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
            ],
            if (!advanced) ...[
              _SettingCard(
                title: '设置',
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.settings_outlined),
                    title: const Text(
                      '设置',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openAdvancedSettings(context),
                  ),
                ],
              ),
            ],
            if (!advanced) ...[
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'Stay Young, Stay Simple ▣-▣',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF8C9CAD)),
                ),
              ),
            ],
            if (advanced) ...[
              const SizedBox(height: 26),
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB42330),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    final cleanup = app.logout();
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => LoginPage(app: app)),
                      (_) => false,
                    );
                    await cleanup;
                  },
                  child: const Text('退出登录'),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Column(
                  children: [
                    Text(
                      '交大课表  ·  v1.14.16.1',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: const Color(0xFF9AAABC)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '你们给我搞的这个课表啊，Excited！',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: const Color(0xFF8C9CAD)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    super.key,
    this.title,
    required this.children,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 14, 24, 14),
    this.titleInset = 0,
  });
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry contentPadding;
  final double titleInset;
  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Padding(
                  padding: EdgeInsets.only(left: titleInset, bottom: 5),
                  child: Text(
                    title!,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
              ...children,
            ],
          ),
        ),
      );
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child:
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 21),
      );
}
