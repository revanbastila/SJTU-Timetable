> 本文是上一版 1.14.23+76 精简结构测试版的审查快照。本轮 1.14.23.1+77 的新增接口、文件变化与构建结果见 apk-packaging.md 和 delivery-verification.md；此前结构精简记录继续保留。
# 精简测试版：源文件与公开接口索引

本索引覆盖 lib 全部 Dart 源文件和项目 Android 原生 Kotlin 文件。按实际声明记录接口名和行号，不列方法体、不输出凭据。具体功能到实现的对应关系、HTTP 接口和 MethodChannel 契约见 architecture-audit.md。字段数据模型与私有实现通过所在类型和源码位置查阅。

## lib/main.dart

源文件行数：231。

- `main`：第 18 行。
- 类型 `JiaotongCourseApp`：第 48 行。
- `JiaotongCourseApp`：第 49 行。
- `createState`：第 54 行。
- `app`：第 58 行。
- `initState`：第 64 行。
- `didUpdateWidget`：第 76 行。
- `dispose`：第 86 行。
- `build`：第 92 行。

## lib/models/app_theme.dart

源文件行数：191。

- 类型 `AppThemeChoice`：第 3 行。
- 类型 `InterfaceMode`：第 13 行。
- 类型 `InterfaceModeStyle`：第 15 行。
- `storageKey`：第 16 行。
- `label`：第 18 行。
- `themeMode`：第 24 行。
- `fromStorage`：第 30 行。
- 类型 `AppThemeChoiceStyle`：第 37 行。
- `storageKey`：第 38 行。
- `label`：第 40 行。
- `primary`：第 49 行。
- `header`：第 58 行。
- `soft`：第 67 行。
- `primaryContainerFor`：第 79 行。
- `pageBackgroundFor`：第 97 行。
- `surfaceFor`：第 104 行。
- `surfaceLowFor`：第 112 行。
- `surfaceHighFor`：第 125 行。
- `brightThemeFor`：第 141 行。
- `scheduleChromeFor`：第 148 行。
- `scheduleContentFor`：第 156 行。
- `gridLineFor`：第 160 行。
- `primaryFor`：第 174 行。
- `headerFor`：第 183 行。
- `fromStorage`：第 186 行。

## lib/models/app_update.dart

源文件行数：106。

- 类型 `AppVersion`：第 3 行。
- `AppVersion`：第 4 行。
- 类型 `ReleaseVersion`：第 9 行。
- `ReleaseVersion`：第 10 行。
- `parse`：第 13 行。
- `compareTo`：第 20 行。
- 类型 `UpdateException`：第 33 行。
- `UpdateException`：第 34 行。
- `toString`：第 37 行。
- 类型 `UpdateInfo`：第 40 行。
- `UpdateInfo`：第 41 行。
- `hasApk`：第 55 行。
- `displayVersion`：第 56 行。

## lib/models/canvas_data.dart

源文件行数：469。

- `Function`：第 21 行。
- 类型 `CanvasItem`：第 36 行。
- `CanvasItem`：第 37 行。
- `toMap`：第 86 行。
- 类型 `CanvasPerson`：第 101 行。
- `CanvasPerson`：第 102 行。
- `toMap`：第 134 行。
- `canvasPeopleInRoleOrder`：第 145 行。
- `group`：第 146 行。
- 类型 `CanvasCourseData`：第 161 行。
- `CanvasCourseData`：第 162 行。
- `toMap`：第 215 行。
- `withAnnouncements`：第 231 行。
- `mergeDetails`：第 245 行。
- `withCachedDetails`：第 261 行。
- 类型 `CanvasSnapshot`：第 279 行。
- `CanvasSnapshot`：第 280 行。
- `toMap`：第 309 行。
- `courseById`：第 316 行。
- `mergeCatalog`：第 324 行。
- `mergeRefresh`：第 334 行。
- 类型 `CanvasSyncException`：第 349 行。
- `CanvasSyncException`：第 350 行。
- `toString`：第 353 行。
- 类型 `CanvasSyncAccumulator`：第 358 行。
- `reset`：第 365 行。
- `add`：第 373 行。

## lib/models/common_website.dart

源文件行数：94。

- 配置/脚本 `sjtuMapUrl`：第 4 行。
- 配置/脚本 `shuiyuanUrl`：第 5 行。
- 配置/脚本 `heritageSjtuUrl`：第 6 行。
- 配置/脚本 `courseCommunityUrl`：第 7 行。
- 配置/脚本 `graduateSchoolUrl`：第 8 行。
- 配置/脚本 `sjtuLibraryUrl`：第 10 行。
- 配置/脚本 `sjtuCloudDriveUrl`：第 11 行。
- 配置/脚本 `sjtuMailUrl`：第 12 行。
- 类型 `CommonWebsite`：第 16 行。
- `CommonWebsite`：第 17 行。
- 配置/脚本 `commonWebsites`：第 42 行。

## lib/models/course.dart

源文件行数：361。

- 类型 `Course`：第 4 行。
- `Course`：第 5 行。
- `startMinutes`：第 32 行。
- `endMinutes`：第 33 行。
- `hasSchedule`：第 34 行。
- `firstPeriod`：第 46 行。
- `lastPeriod`：第 47 行。
- `isActiveInWeek`：第 49 行。
- `copyWith`：第 51 行。
- `toMap`：第 338 行。

## lib/models/periods.dart

源文件行数：34。

- 配置/脚本 `periodStarts`：第 2 行。
- 配置/脚本 `periodEnds`：第 17 行。
- `clockLabel`：第 33 行。

## lib/models/teaching_calendar.dart

源文件行数：277。

- `shanghaiNow`：第 18 行。
- `calendarCivilDate`：第 19 行。
- `DateTime`：第 24 行。
- `nextShanghaiMidnight`：第 27 行。
- `calendarDateKey`：第 29 行。
- 类型 `TeachingDateRule`：第 34 行。
- `TeachingDateRule`：第 35 行。
- `label`：第 40 行。
- `emptyMessage`：第 45 行。
- `makeupMessage`：第 50 行。
- 类型 `TeachingSemester`：第 61 行。
- `contains`：第 70 行。
- `weekFor`：第 75 行。
- 类型 `TeachingCalendar`：第 124 行。
- `semesterFor`：第 219 行。
- `semesterForTerm`：第 226 行。
- `weekForDate`：第 235 行。
- `datesForTerm`：第 243 行。
- `ruleFor`：第 254 行。
- `getEffectiveCoursesForDate`：第 256 行。

## lib/models/week_rules.dart

源文件行数：91。

- 类型 `WeekRule`：第 1 行。
- `WeekRule`：第 2 行。
- `parseWeekRule`：第 13 行。
- `WeekRule`：第 64 行。
- `academicWeekFor`：第 71 行。
- `academicWeekInTerm`：第 79 行。
- `mondayForAcademicWeek`：第 87 行。

## lib/pages/authenticated_web_page.dart

源文件行数：1409。

- 类型 `AuthenticatedWebPage`：第 21 行。
- `AuthenticatedWebPage`：第 22 行。
- `createState`：第 58 行。
- `initState`：第 128 行。
- `dispose`：第 681 行。
- `build`：第 1293 行。

## lib/pages/course_detail_page.dart

源文件行数：693。

- 类型 `CourseDetailPage`：第 17 行。
- `CourseDetailPage`：第 18 行。
- `build`：第 25 行。
- `build`：第 118 行。
- `build`：第 204 行。
- `build`：第 221 行。
- `createState`：第 253 行。
- `initState`：第 258 行。
- `build`：第 268 行。
- `build`：第 344 行。
- `build`：第 393 行。
- `build`：第 414 行。
- `createState`：第 445 行。
- `initState`：第 458 行。
- `didUpdateWidget`：第 465 行。
- `build`：第 557 行。
- `build`：第 605 行。
- 类型 `CanvasHtmlPage`：第 622 行。
- `CanvasHtmlPage`：第 623 行。
- `build`：第 626 行。
- 类型 `CanvasHtmlView`：第 632 行。
- `CanvasHtmlView`：第 633 行。
- `createState`：第 636 行。
- `initState`：第 643 行。
- `didChangeDependencies`：第 650 行。
- `build`：第 664 行。

## lib/pages/home_page.dart

源文件行数：663。

- 类型 `HomePage`：第 32 行。
- `HomePage`：第 33 行。
- `createState`：第 38 行。
- `app`：第 44 行。
- `initState`：第 47 行。
- `dispose`：第 55 行。
- `build`：第 64 行。
- `build`：第 160 行。
- `build`：第 235 行。
- `build`：第 290 行。
- `build`：第 358 行。
- `build`：第 409 行。
- `createState`：第 469 行。
- `initState`：第 478 行。
- `didUpdateWidget`：第 484 行。
- `dispose`：第 518 行。
- `build`：第 524 行。
- `build`：第 627 行。

## lib/pages/home_shell.dart

源文件行数：311。

- 类型 `HomeShell`：第 12 行。
- `HomeShell`：第 13 行。
- `createState`：第 25 行。
- `initState`：第 36 行。
- `dispose`：第 56 行。
- `build`：第 80 行。
- `build`：第 212 行。
- 类型 `WeekScheduleIconPainter`：第 269 行。
- `WeekScheduleIconPainter`：第 270 行。
- `paint`：第 276 行。
- `shouldRepaint`：第 309 行。

## lib/pages/login_page.dart

源文件行数：166。

- 类型 `LoginPage`：第 8 行。
- `LoginPage`：第 9 行。
- `createState`：第 12 行。
- `initState`：第 23 行。
- `dispose`：第 29 行。
- `build`：第 69 行。

## lib/pages/portal_sync_page.dart

源文件行数：682。

- 配置/脚本 `portalUrl`：第 14 行。
- 配置/脚本 `portalLoginUrl`：第 15 行。
- 类型 `PortalSyncPage`：第 18 行。
- `PortalSyncPage`：第 19 行。
- `createState`：第 33 行。
- `initState`：第 63 行。
- `dispose`：第 112 行。
- `build`：第 592 行。

## lib/pages/settings_page.dart

源文件行数：659。

- 类型 `SettingsPage`：第 13 行。
- `SettingsPage`：第 14 行。
- `createState`：第 20 行。
- 类型 `SettingsPageState`：第 23 行。
- `app`：第 24 行。
- `advanced`：第 25 行。
- `clearStudentNumberSelection`：第 29 行。
- `dispose`：第 41 行。
- `build`：第 135 行。
- `build`：第 583 行。
- `build`：第 649 行。

## lib/pages/week_page.dart

源文件行数：580。

- `weekdayInDisplayedWeek`：第 14 行。
- 类型 `WeekPage`：第 20 行。
- `WeekPage`：第 21 行。
- `build`：第 26 行。
- `createState`：第 223 行。
- `courses`：第 228 行。
- `viewportWidth`：第 229 行。
- `Function`：第 230 行。
- `onCourseTap`：第 231 行。
- `dispose`：第 234 行。
- `build`：第 244 行。

## lib/services/android_update_bridge.dart

源文件行数：50。

- 类型 `UpdatePlatform`：第 5 行。
- `version`：第 6 行。
- `download`：第 7 行。
- `state`：第 8 行。
- `install`：第 9 行。
- `allowInstall`：第 10 行。
- `openRelease`：第 11 行。
- 类型 `AndroidUpdateBridge`：第 14 行。
- `version`：第 17 行。
- `download`：第 24 行。
- `state`：第 36 行。
- `install`：第 39 行。
- `allowInstall`：第 42 行。
- `openRelease`：第 44 行。

## lib/services/android_web_history.dart

源文件行数：49。

- 类型 `AndroidWebHistorySnapshot`：第 5 行。
- `AndroidWebHistorySnapshot`：第 6 行。
- 类型 `AndroidWebHistory`：第 13 行。
- `stopAndSnapshot`：第 23 行。
- `stopLoading`：第 35 行。
- `goBackTo`：第 40 行。

## lib/services/announcement_feed.dart

源文件行数：242。

- 类型 `AnnouncementFeedEntry`：第 4 行。
- `AnnouncementFeedEntry`：第 5 行。
- `buildAnnouncementFeed`：第 23 行。
- `uniqueTimetableMatch`：第 42 行。

## lib/services/app_database.dart

源文件行数：190。

- 类型 `AppDatabase`：第 9 行。
- `available`：第 11 行。
- `initialize`：第 14 行。
- `loadCourses`：第 34 行。
- `loadCanvas`：第 47 行。
- `loadCourseColors`：第 56 行。
- `loadMappings`：第 68 行。
- `replaceAll`：第 78 行。
- `saveCourses`：第 123 行。
- `saveCourseColors`：第 136 行。
- `saveMapping`：第 149 行。
- `saveCanvas`：第 158 行。
- `clear`：第 169 行。

## lib/services/canvas_announcement_sync.dart

源文件行数：98。

- 类型 `CanvasAnnouncementSync`：第 8 行。
- `configure`：第 12 行。
- `disable`：第 23 行。
- `read`：第 29 行。
- `merge`：第 39 行。

## lib/services/canvas_avatar_cache.dart

源文件行数：225。

- 类型 `CanvasAvatarHeadersProvider`：第 12 行。
- 类型 `CanvasAvatarBytesLoader`：第 14 行。
- 类型 `CanvasAvatarCacheEntry`：第 17 行。
- `CanvasAvatarCacheEntry`：第 18 行。
- 类型 `CanvasAvatarCache`：第 26 行。
- `read`：第 82 行。
- `isStale`：第 96 行。
- `download`：第 99 行。
- `evict`：第 119 行。

## lib/services/canvas_avatar.dart

源文件行数：44。

- 配置/脚本 `canvasDefaultAvatarUrl`：第 3 行。
- `resolveCanvasAvatar`：第 11 行。
- `canvasAvatarHeaders`：第 28 行。

## lib/services/canvas_dashboard_view.dart

源文件行数：42。

- `isCanvasDashboardUri`：第 2 行。
- 配置/脚本 `canvasDashboardCardViewScript`：第 13 行。

## lib/services/canvas_extractor.dart

源文件行数：303。

- 配置/脚本 `canvasUrl`：第 1 行。
- 配置/脚本 `canvasSsoUrl`：第 2 行。
- `canvasExtractionScriptUri`：第 4 行。
- 配置/脚本 `canvasExtractionScript`：第 9 行。

## lib/services/course_matcher.dart

源文件行数：114。

- 类型 `CourseMatcher`：第 4 行。
- `apply`：第 5 行。

## lib/services/course_normalizer.dart

源文件行数：161。

- `normalizePortalCourses`：第 6 行。
- `normalized`：第 7 行。
- `stableCode`：第 10 行。
- `sameCourse`：第 15 行。
- `useful`：第 33 行。
- `sameWeeks`：第 101 行。
- `canJoin`：第 107 行。

## lib/services/credential_store.dart

源文件行数：48。

- 类型 `StoredCredentials`：第 3 行。
- `StoredCredentials`：第 4 行。
- 类型 `CredentialStore`：第 10 行。
- `read`：第 11 行。
- `write`：第 12 行。
- `clear`：第 13 行。
- 类型 `SecureCredentialStore`：第 16 行。
- `read`：第 29 行。
- `write`：第 37 行。
- `clear`：第 44 行。

## lib/services/github_release_api.dart

源文件行数：73。

- 类型 `ReleaseRepository`：第 8 行。
- `latest`：第 9 行。
- 类型 `GitHubReleaseApi`：第 12 行。
- `latest`：第 22 行。

## lib/services/graduate_navigation.dart

源文件行数：30。

- 类型 `GraduateNavigation`：第 4 行。
- `isCallback`：第 8 行。
- `isSsoIntermediate`：第 13 行。
- `isGraduatePage`：第 28 行。

## lib/services/library_navigation.dart

源文件行数：78。

- 类型 `LibraryDestination`：第 1 行。
- 类型 `LibraryNavigation`：第 10 行。
- `isPrimoHost`：第 16 行。
- `isAuthenticationIntermediate`：第 25 行。
- `permitsHttp`：第 38 行。
- `shouldUpgradeToHttps`：第 44 行。
- `classify`：第 48 行。

## lib/services/location_permission_service.dart

源文件行数：16。

- 类型 `LocationPermissionService`：第 3 行。
- `LocationPermissionService`：第 4 行。
- `request`：第 8 行。

## lib/services/message_feed.dart

源文件行数：84。

- 类型 `MessageFeedEntry`：第 5 行。
- `MessageFeedEntry`：第 6 行。
- `legacyKey`：第 24 行。
- `legacyV2Key`：第 31 行。
- `buildMessageFeed`：第 41 行。

## lib/services/notification_service.dart

源文件行数：237。

- 类型 `ReminderMode`：第 9 行。
- 类型 `NotificationSyncReport`：第 11 行。
- `NotificationSyncReport`：第 12 行。
- `succeeded`：第 14 行。
- 类型 `NotificationService`：第 17 行。
- `initialize`：第 24 行。
- `requestPermissions`：第 39 行。
- `sync`：第 54 行。
- `reminderDetails`：第 195 行。
- `scheduleProbe`：第 222 行。

## lib/services/portal_extractor.dart

源文件行数：675。

- 配置/脚本 `portalCaptureBootstrapScript`：第 3 行。
- 配置/脚本 `portalSessionProbeScript`：第 61 行。
- 配置/脚本 `portalStartTimetableFetchScript`：第 143 行。
- 配置/脚本 `portalTimetableFetchResultScript`：第 206 行。
- 配置/脚本 `portalOpenTimetableScript`：第 213 行。
- 配置/脚本 `portalStudentProfileRequestScript`：第 245 行。
- 配置/脚本 `portalExtractionScript`：第 317 行。

## lib/services/school_web_auth.dart

源文件行数：270。

- 类型 `SchoolPageKind`：第 5 行。
- 类型 `SchoolPageInspection`：第 7 行。
- `SchoolPageInspection`：第 8 行。
- 类型 `SchoolWebAuthenticator`：第 14 行。
- `SchoolWebAuthenticator`：第 15 行。
- `isAllowedHost`：第 19 行。
- `inspect`：第 24 行。
- `submit`：第 79 行。
- `fill`：第 121 行。
- `clickSsoButton`：第 153 行。
- `clickCanvasJaccount`：第 196 行。

## lib/services/teaching_calendar_repository.dart

源文件行数：101。

- 类型 `TeachingCalendarRepository`：第 9 行。
- `readCache`：第 19 行。
- `refresh`：第 34 行。

## lib/services/timetable_widget_bridge.dart

源文件行数：186。

- 类型 `TimetableWidgetBridge`：第 14 行。
- `attach`：第 29 行。
- `detach`：第 41 行。
- `syncNow`：第 58 行。
- `consumePendingCourse`：第 175 行。

## lib/services/update_config.dart

源文件行数：46。

- 类型 `UpdateConfig`：第 4 行。
- `configured`：第 14 行。
- `validRepository`：第 16 行。
- `trustedAsset`：第 22 行。
- `trustedReleasePage`：第 37 行。

## lib/services/update_manager.dart

源文件行数：250。

- 类型 `UpdateCheckResult`：第 10 行。
- `UpdateCheckResult`：第 11 行。
- 类型 `UpdateManager`：第 18 行。
- `downloading`：第 52 行。
- `progress`：第 53 行。
- `initialize`：第 57 行。
- `check`：第 67 行。
- `deferUpdate`：第 128 行。
- `download`：第 138 行。
- `refreshDownload`：第 158 行。
- `install`：第 189 行。
- `allowInstall`：第 208 行。
- `openRelease`：第 216 行。
- `messageFor`：第 230 行。
- `didChangeAppLifecycleState`：第 237 行。
- `dispose`：第 245 行。

## lib/services/web_gesture_policy.dart

源文件行数：14。

- 类型 `WebGesturePolicy`：第 2 行。
- `startsAtHorizontalEdge`：第 7 行。

## lib/services/web_history_policy.dart

源文件行数：127。

- 类型 `WebHistoryPolicy`：第 4 行。
- `WebHistoryPolicy`：第 5 行。
- `isHomePage`：第 17 行。
- `isVisiblePage`：第 37 行。
- `previousVisibleIndex`：第 90 行。
- `samePage`：第 118 行。

## lib/services/web_navigation_guard.dart

源文件行数：11。

- 类型 `WebNavigationGuard`：第 2 行。
- `generation`：第 5 行。
- `invalidate`：第 7 行。
- `permits`：第 9 行。

## lib/state/app_controller.dart

源文件行数：1114。

- 类型 `SyncBundle`：第 21 行。
- `SyncBundle`：第 22 行。
- 类型 `SyncSaveResult`：第 27 行。
- `SyncSaveResult`：第 28 行。
- 类型 `SyncLoader`：第 33 行。
- 类型 `CanvasSyncStage`：第 35 行。
- 类型 `AppController`：第 37 行。
- `currentSemester`：第 89 行。
- `termStart`：第 91 行。
- `termStart`：第 93 行。
- `totalWeeks`：第 95 行。
- `totalWeeks`：第 96 行。
- `examWeeks`：第 97 行。
- `sessionGeneration`：第 107 行。
- `saveStudentProfileForSession`：第 109 行。
- `messageFeed`：第 173 行。
- `unreadMessageCount`：第 182 行。
- `isMessageRead`：第 186 行。
- `markMessageRead`：第 209 行。
- `markAllMessagesRead`：第 216 行。
- `markCanvasItemRead`：第 228 行。
- `currentAcademicWeek`：第 281 行。
- `currentAcademicWeekInTerm`：第 284 行。
- `currentTermStatus`：第 286 行。
- `getEffectiveCoursesForDate`：第 290 行。
- `effectiveCoursesForWeek`：第 292 行。
- `startTeachingCalendarSync`：第 302 行。
- `refreshTeachingCalendar`：第 327 行。
- `canvasCourseFor`：第 379 行。
- `sessionUsername`：第 405 行。
- `sessionPassword`：第 407 行。
- `awaitSessionCleanup`：第 409 行。
- `retainSessionCredentials`：第 411 行。
- `courseColorValue`：第 416 行。
- `bootstrap`：第 423 行。
- `saveSyncedData`：第 584 行。
- `registerLoader`：第 656 行。
- `unregisterLoader`：第 663 行。
- `initializeCanvasAfterLogin`：第 667 行。
- `updateCanvasSyncProgress`：第 699 行。
- `applyCanvasCatalog`：第 713 行。
- `applyAnnouncementUpdates`：第 740 行。
- `refreshNow`：第 755 行。
- `mapCourseToCanvas`：第 819 行。
- `selectWeek`：第 840 行。
- `selectWeekForToday`：第 845 行。
- `setRefreshMinutes`：第 854 行。
- `setThemeChoice`：第 862 行。
- `setInterfaceMode`：第 870 行。
- `setReminderMode`：第 878 行。
- `restoreReminders`：第 899 行。
- `setReminderMinutes`：第 912 行。
- `logout`：第 935 行。
- `dispose`：第 1106 行。

## lib/widgets/app_update_ui.dart

源文件行数：285。

- `readableReleaseNotes`：第 6 行。
- `showUpdateDialog`：第 12 行。
- `showInstallPermissionDialog`：第 87 行。
- 类型 `UpdateObserver`：第 108 行。
- `UpdateObserver`：第 109 行。
- `createState`：第 113 行。
- `initState`：第 121 行。
- `dispose`：第 173 行。
- `build`：第 179 行。
- 类型 `UpdateSettingsEntry`：第 182 行。
- `UpdateSettingsEntry`：第 183 行。
- `createState`：第 185 行。
- `initState`：第 191 行。
- `build`：第 226 行。
- 类型 `CurrentAppVersionLabel`：第 276 行。
- `CurrentAppVersionLabel`：第 277 行。
- `build`：第 279 行。

## lib/widgets/canvas_announcement_observer.dart

源文件行数：100。

- 类型 `CanvasAnnouncementObserver`：第 9 行。
- `CanvasAnnouncementObserver`：第 10 行。
- `createState`：第 13 行。
- `initState`：第 32 行。
- `didChangeAppLifecycleState`：第 82 行。
- `dispose`：第 91 行。
- `build`：第 99 行。

## lib/widgets/common_website_grid.dart

源文件行数：128。

- 类型 `CommonWebsiteGrid`：第 5 行。
- `CommonWebsiteGrid`：第 6 行。
- `build`：第 16 行。

## lib/widgets/course_tile.dart

源文件行数：124。

- 类型 `CourseTile`：第 6 行。
- `CourseTile`：第 7 行。
- `build`：第 15 行。
- `build`：第 118 行。

## lib/widgets/draggable_unread_badge.dart

源文件行数：273。

- 类型 `DraggableUnreadBadge`：第 7 行。
- `DraggableUnreadBadge`：第 8 行。
- `createState`：第 24 行。
- `didUpdateWidget`：第 46 行。
- `dispose`：第 60 行。
- `build`：第 158 行。
- `paint`：第 257 行。
- `shouldRepaint`：第 271 行。

## lib/widgets/jt_logo.dart

源文件行数：31。

- 类型 `JtLogo`：第 3 行。
- `JtLogo`：第 4 行。
- `build`：第 9 行。

## lib/widgets/session_sync_agent.dart

源文件行数：310。

- 类型 `SessionSyncAgent`：第 12 行。
- `SessionSyncAgent`：第 13 行。
- `createState`：第 17 行。
- `initState`：第 36 行。
- `dispose`：第 292 行。
- `build`：第 299 行。

## android/app/src/main/kotlin/cn/sjtu/jiaotong_course/AppUpdateBridge.kt

- `AppUpdateBridge`：第 28 行（原生实现/生命周期，通道对照见主文档）。
- `onResume`：第 38 行（原生实现/生命周期，通道对照见主文档）。
- `onPause`：第 43 行（原生实现/生命周期，通道对照见主文档）。
- `dispose`：第 44 行（原生实现/生命周期，通道对照见主文档）。
- `handle`：第 46 行（原生实现/生命周期，通道对照见主文档）。
- `safely`：第 84 行（原生实现/生命周期，通道对照见主文档）。
- `async`：第 90 行（原生实现/生命周期，通道对照见主文档）。
- `trustedHttps`：第 98 行（原生实现/生命周期，通道对照见主文档）。
- `trustedAsset`：第 101 行（原生实现/生命周期，通道对照见主文档）。
- `download`：第 111 行（原生实现/生命周期，通道对照见主文档）。
- `state`：第 148 行（原生实现/生命周期，通道对照见主文档）。
- `apkFile`：第 180 行（原生实现/生命周期，通道对照见主文档）。
- `installedInfo`：第 191 行（原生实现/生命周期，通道对照见主文档）。
- `versionCode`：第 195 行（原生实现/生命周期，通道对照见主文档）。
- `signatures`：第 199 行（原生实现/生命周期，通道对照见主文档）。
- `hex`：第 204 行（原生实现/生命周期，通道对照见主文档）。
- `canInstall`：第 205 行（原生实现/生命周期，通道对照见主文档）。
- `validateApk`：第 207 行（原生实现/生命周期，通道对照见主文档）。
- `install`：第 234 行（原生实现/生命周期，通道对照见主文档）。

## android/app/src/main/kotlin/cn/sjtu/jiaotong_course/CanvasAnnouncementSync.kt

- `CanvasAnnouncementSync`：第 25 行（原生实现/生命周期，通道对照见主文档）。
- `bind`：第 34 行（原生实现/生命周期，通道对照见主文档）。
- `configure`：第 58 行（原生实现/生命周期，通道对照见主文档）。
- `cached`：第 90 行（原生实现/生命周期，通道对照见主文档）。
- `poll`：第 93 行（原生实现/生命周期，通道对照见主文档）。
- `HttpFailure`：第 181 行（原生实现/生命周期，通道对照见主文档）。
- `readPages`：第 183 行（原生实现/生命周期，通道对照见主文档）。
- `CanvasAnnouncementJobService`：第 220 行（原生实现/生命周期，通道对照见主文档）。
- `onStartJob`：第 222 行（原生实现/生命周期，通道对照见主文档）。
- `onStopJob`：第 232 行（原生实现/生命周期，通道对照见主文档）。

## android/app/src/main/kotlin/cn/sjtu/jiaotong_course/MainActivity.kt

- `MainActivity`：第 19 行（原生实现/生命周期，通道对照见主文档）。
- `onCreate`：第 27 行（原生实现/生命周期，通道对照见主文档）。
- `onNewIntent`：第 32 行（原生实现/生命周期，通道对照见主文档）。
- `persistWidgetCourseIntent`：第 45 行（原生实现/生命周期，通道对照见主文档）。
- `sameHistoryPage`：第 55 行（原生实现/生命周期，通道对照见主文档）。
- `goBackToTarget`：第 66 行（原生实现/生命周期，通道对照见主文档）。
- `run`：第 78 行（原生实现/生命周期，通道对照见主文档）。
- `onPause`：第 129 行（原生实现/生命周期，通道对照见主文档）。
- `onResume`：第 135 行（原生实现/生命周期，通道对照见主文档）。
- `onDestroy`：第 140 行（原生实现/生命周期，通道对照见主文档）。
- `configureFlutterEngine`：第 145 行（原生实现/生命周期，通道对照见主文档）。
- `onRequestPermissionsResult`：第 268 行（原生实现/生命周期，通道对照见主文档）。

## android/app/src/main/kotlin/cn/sjtu/jiaotong_course/TimetableWidgetProvider.kt

- `TimetableWidgetProvider`：第 28 行（原生实现/生命周期，通道对照见主文档）。
- `onUpdate`：第 29 行（原生实现/生命周期，通道对照见主文档）。
- `onAppWidgetOptionsChanged`：第 38 行（原生实现/生命周期，通道对照见主文档）。
- `onReceive`：第 47 行（原生实现/生命周期，通道对照见主文档）。
- `onEnabled`：第 62 行（原生实现/生命周期，通道对照见主文档）。
- `onDeleted`：第 68 行（原生实现/生命周期，通道对照见主文档）。
- `safelyUpdate`：第 76 行（原生实现/生命周期，通道对照见主文档）。
- `buildViews`：第 100 行（原生实现/生命周期，通道对照见主文档）。
- `populateCourse`：第 168 行（原生实现/生命周期，通道对照见主文档）。
- `coursesForToday`：第 181 行（原生实现/生命周期，通道对照见主文档）。
- `prioritizeCurrentAndUpcoming`：第 211 行（原生实现/生命周期，通道对照见主文档）。
- `showPlaceholder`：第 226 行（原生实现/生命周期，通道对照见主文档）。
- `placeholderViews`：第 234 行（原生实现/生命周期，通道对照见主文档）。
- `bindScheduleClick`：第 244 行（原生实现/生命周期，通道对照见主文档）。
- `bindCourseClick`：第 262 行（原生实现/生命周期，通道对照见主文档）。
- `scheduleMidnightRefresh`：第 284 行（原生实现/生命周期，通道对照见主文档）。
- `cancelMidnightRefresh`：第 311 行（原生实现/生命周期，通道对照见主文档）。
- `colorDot`：第 322 行（原生实现/生命周期，通道对照见主文档）。
- `weekdayLabel`：第 331 行（原生实现/生命周期，通道对照见主文档）。
- `formatTime`：第 341 行（原生实现/生命周期，通道对照见主文档）。
- `immutableFlag`：第 346 行（原生实现/生命周期，通道对照见主文档）。
- `courseTimeId`：第 349 行（原生实现/生命周期，通道对照见主文档）。
- `courseLocationId`：第 354 行（原生实现/生命周期，通道对照见主文档）。
- `courseNameId`：第 359 行（原生实现/生命周期，通道对照见主文档）。
- `courseTeacherId`：第 364 行（原生实现/生命周期，通道对照见主文档）。
- `courseColorId`：第 369 行（原生实现/生命周期，通道对照见主文档）。
- `updateAll`：第 410 行（原生实现/生命周期，通道对照见主文档）。


