import 'package:flutter/material.dart';
import '../services/canvas_extractor.dart';

const sjtuMapUrl = 'https://map.sjtu.edu.cn/';
const shuiyuanUrl = 'https://shuiyuan.sjtu.edu.cn/login';
const heritageSjtuUrl = 'https://share.dyweb.sjtu.cn/';
const courseCommunityUrl = 'https://course.sjtu.plus/';
const graduateSchoolUrl =
    'https://yjs.sjtu.edu.cn/gsapp/sys/emaphome/portal/index.do';
const sjtuLibraryUrl = 'https://www.lib.sjtu.edu.cn/f/main/index.shtml';
const sjtuCloudDriveUrl = 'https://pan.sjtu.edu.cn/';
const sjtuMailUrl = 'https://mail.sjtu.edu.cn/modern/';

/// One catalog for the shortcut grid and complete list. Both use the same
/// navigation handler and existing authenticated WebView implementation.
class CommonWebsite {
  const CommonWebsite(
      {required this.name,
      required this.icon,
      required this.url,
      String? shortcutName,
      this.preferSsoLogin = false,
      this.allowHttpTarget = false,
      this.canvasSite = false,
      this.librarySite = false,
      this.mailSite = false,
      this.authenticationRequired = true,
      this.enableGeolocation = false})
      : shortcutName = shortcutName ?? name;

  final String name, shortcutName, url;
  final IconData icon;
  final bool preferSsoLogin,
      allowHttpTarget,
      canvasSite,
      librarySite,
      mailSite,
      authenticationRequired,
      enableGeolocation;
}

const commonWebsites = [
  CommonWebsite(
      name: 'Canvas教学平台',
      shortcutName: 'Canvas',
      icon: Icons.language_outlined,
      url: canvasSsoUrl,
      canvasSite: true),
  CommonWebsite(
      name: '图书馆',
      icon: Icons.local_library_outlined,
      url: sjtuLibraryUrl,
      allowHttpTarget: true,
      librarySite: true),
  CommonWebsite(
      name: '交大邮箱',
      icon: Icons.mail_outline,
      url: sjtuMailUrl,
      preferSsoLogin: true,
      mailSite: true,
      allowHttpTarget: true),
  CommonWebsite(
      name: '交大云盘',
      icon: Icons.cloud_outlined,
      url: sjtuCloudDriveUrl,
      preferSsoLogin: true),
  CommonWebsite(
      name: '校园地图',
      icon: Icons.map_outlined,
      url: sjtuMapUrl,
      authenticationRequired: false,
      enableGeolocation: true),
  CommonWebsite(
      name: '水源社区',
      icon: Icons.forum_outlined,
      url: shuiyuanUrl,
      preferSsoLogin: true),
  CommonWebsite(
      name: '选课社区',
      icon: Icons.groups_outlined,
      url: courseCommunityUrl,
      authenticationRequired: false),
  CommonWebsite(
      name: '传承·交大',
      shortcutName: '传承交大',
      icon: Icons.auto_stories_outlined,
      url: heritageSjtuUrl,
      preferSsoLogin: true),
  CommonWebsite(
      name: '研究生应用管理平台',
      icon: Icons.school_outlined,
      url: graduateSchoolUrl,
      preferSsoLogin: true),
];
