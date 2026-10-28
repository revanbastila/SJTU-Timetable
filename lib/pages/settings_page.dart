import '../widgets/settings_dropdown.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_theme.dart';
import '../services/notification_service.dart';
import '../models/common_website.dart';
import '../state/app_controller.dart';
import '../widgets/app_update_ui.dart';
import '../widgets/common_website_grid.dart';
import 'authenticated_web_page.dart';
import 'login_page.dart';
import 'attendance_status_page.dart';
import '../models/attendance.dart';

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

  Future<void> _openWebsite(BuildContext context, CommonWebsite site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AuthenticatedWebPage(
          title: site.name,
          initialUrl: site.url,
          targetHost: Uri.parse(site.url).host,
          app: app,
          preferSsoLogin: site.preferSsoLogin,
          allowHttpTarget: site.allowHttpTarget,
          canvasSite: site.canvasSite,
          librarySite: site.librarySite,
          mailSite: site.mailSite,
          authenticationRequired: site.authenticationRequired,
          enableGeolocation: site.enableGeolocation,
          ssoFallbackUrl: site.canvasSite ? site.url : '',
          showCloseButton: true,
        ),
      ),
    );
    if (site.canvasSite) await app.refreshNow();
  }

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
      animation: Listenable.merge([app, app.attendance]),
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
                  color: app.themeChoice.headerFor(
                    Theme.of(context).brightness,
                  ),
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
                      color: app.themeChoice.headerFor(
                        Theme.of(context).brightness,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_outlined),
                    color: app.themeChoice.primaryFor(
                      Theme.of(context).brightness,
                    ),
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
                    trailing: SettingsDropdown<int>(
                      key: const Key('settings-refresh-menu'),
                      value: app.refreshMinutes,
                      options: {
                        for (final value in [15, 30, 60, 120])
                          value: '$value 分钟',
                      },
                      onChanged: app.setRefreshMinutes,
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
                // Move title/account/details 12px left. Keep the divider's
                // right inset so its line extends to the original endpoint.
                contentPadding: const EdgeInsets.fromLTRB(4, 14, 8, 14),
                titleInset: 8,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 8, right: 12),
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
                      padding: const EdgeInsets.only(
                        left: 58,
                        right: 12,
                        bottom: 4,
                      ),
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
                contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                onMore: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('常用网站')),
                      body: SafeArea(
                        child: ListView(
                          key: const Key('website-full-list'),
                          padding: const EdgeInsets.all(20),
                          children: [
                            _SettingCard(
                              children: [
                                for (var index = 0;
                                    index < commonWebsites.length;
                                    index++) ...[
                                  if (index > 0) const Divider(height: 1),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: _SettingIcon(
                                      icon: commonWebsites[index].icon,
                                    ),
                                    title: Text(
                                      commonWebsites[index].name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openWebsite(
                                      context,
                                      commonWebsites[index],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                children: [
                  CommonWebsiteGrid(
                    entries: commonWebsites,
                    topPadding: 0,
                    onOpen: (site) => _openWebsite(context, site),
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
                    trailing: SettingsDropdown<InterfaceMode>(
                      key: const Key('settings-interface-menu'),
                      value: app.interfaceMode,
                      options: {
                        for (final mode in InterfaceMode.values)
                          mode: mode.label,
                      },
                      onChanged: app.setInterfaceMode,
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
                    onSelectionChanged: (value) async {
                      final warning = await app.setReminderMode(value.first);
                      if (context.mounted && warning != null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(warning)));
                      }
                    },
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
                    trailing: SettingsDropdown<int>(
                      key: const Key('settings-reminder-menu'),
                      value: app.reminderMinutes,
                      options: {
                        for (final value in [5, 10, 15, 30]) value: '$value 分钟',
                      },
                      onChanged: app.setReminderMinutes,
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
            if (advanced) ...[
              _SettingCard(
                key: const Key('auto-attendance-settings'),
                title: '自动签到',
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIcon(icon: Icons.qr_code_scanner),
                    title: const Text(
                      '自动签到',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      '课前后检测 Canvas 签到，发现后提示；选择执行后打开直播，识别二维码并核实提交。后台检测需显示常驻通知。',
                    ),
                    trailing: Switch(
                      value: app.attendance.enabled,
                      onChanged: (value) async {
                        await app.attendance.setEnabled(value);
                        if (value) {
                          try {
                            final allowed = await app.attendanceBackend
                                .notificationPermission();
                            if (!allowed) {
                              app.attendance.report(
                                app.attendance.phase,
                                '通知未开启，后台提示受限',
                              );
                            }
                          } catch (_) {
                            app.attendance.report(
                              AttendancePhase.limited,
                              '当前设备暂不支持后台提示',
                            );
                          }
                        }
                      },
                    ),
                  ),
                  if (app.attendance.enabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const _SettingIcon(icon: Icons.info_outline),
                      title: Text(app.attendance.phase.label),
                      subtitle: Text(
                        app.attendance.detail.isEmpty
                            ? '课前后各 5 分钟内检查；点此连接课程及查看运行状态'
                            : app.attendance.detail,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AttendanceStatusPage(app: app),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              _SettingCard(
                title: '关于',
                children: const [UpdateSettingsEntry()],
              ),
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
                    const CurrentAppVersionLabel(),
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
    this.contentPadding,
    this.titleInset = 0,
    this.onMore,
  });
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry? contentPadding;
  final double titleInset;
  final VoidCallback? onMore;
  @override
  Widget build(BuildContext context) => Material(
        key: ValueKey('setting-surface-$title'),
        color: Theme.of(context).colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          // Keep the current left alignment while letting trailing controls
          // and dividers reach the matching right inset.
          padding: contentPadding ??
              (title == null
                  ? const EdgeInsets.fromLTRB(24, 14, 24, 14)
                  : const EdgeInsets.fromLTRB(12, 14, 12, 14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Padding(
                  padding: EdgeInsets.only(
                    left: titleInset,
                    bottom: onMore != null ? 16 : 5,
                  ),
                  child: Row(
                    crossAxisAlignment: onMore != null
                        ? CrossAxisAlignment.baseline
                        : CrossAxisAlignment.center,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          key: ValueKey('setting-heading-$title'),
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
                      ),
                      if (onMore != null)
                        TextButton(
                          key: const Key('website-more'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: onMore,
                          child: const Text('更多 >'),
                        ),
                    ],
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
