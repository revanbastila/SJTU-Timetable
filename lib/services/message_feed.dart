import '../models/canvas_data.dart';
import '../models/attendance.dart';
import '../models/course.dart';
import 'announcement_feed.dart';

class MessageFeedEntry {
  const MessageFeedEntry({
    required this.key,
    required this.title,
    required this.sourceLabel,
    required this.createdAt,
    this.canvasItem,
    this.timetableCourse,
    this.attendanceMessage,
  });

  final String key;
  final String title;
  final String sourceLabel;
  final String createdAt;
  final CanvasItem? canvasItem;
  final Course? timetableCourse;
  final AttendanceMessage? attendanceMessage;

  // The previous release used only Canvas's numeric ID. Keep this for a
  // one-time migration of already-read cached items.
  String get legacyKey {
    final id = canvasItem?.id.trim() ?? '';
    return id.isEmpty ? key : 'canvas:$id';
  }

  // Key format used by 1.14.11 and earlier. The next migration maps existing
  // read flags to course-scoped keys without marking older messages unread.
  String get legacyV2Key {
    final item = canvasItem;
    if (item == null) return key;
    return item.id.trim().isNotEmpty
        ? 'canvas:${item.id.trim()}|${item.title.trim()}|${item.createdAt.trim()}'
        : 'canvas:$sourceLabel|${item.title}|${item.createdAt}|${item.messageHtml}'
            .toLowerCase();
  }
}

List<MessageFeedEntry> buildMessageFeed(
    CanvasSnapshot canvas, List<Course> courses,
    {List<AttendanceMessage> attendanceMessages = const []}) {
  final entries = <String, MessageFeedEntry>{};
  for (final value in buildAnnouncementFeed(canvas, courses)) {
    final item = value.item;
    final courseId = value.canvasCourseId.trim().isNotEmpty
        ? value.canvasCourseId.trim()
        : item.courseId.trim();
    final announcementId =
        item.assetId.trim().isNotEmpty ? item.assetId.trim() : item.id.trim();
    final url = Uri.tryParse(item.htmlUrl.trim());
    final topicId = url == null
        ? null
        : RegExp(r'/(?:discussion_topics|announcements)/(\d+)(?:/|$)',
                caseSensitive: false)
            .firstMatch(url.path)
            ?.group(1);
    final stableId = announcementId.isNotEmpty ? announcementId : topicId;
    final key = courseId.isNotEmpty && stableId != null && stableId.isNotEmpty
        ? 'canvas:course:$courseId:announcement:$stableId'
        : item.id.trim().isNotEmpty
            ? 'canvas:${courseId.isEmpty ? 'activity' : 'course:$courseId'}:'
                '${item.id.trim()}|${item.title.trim()}|${item.createdAt.trim()}'
            : 'canvas:${courseId.isEmpty ? value.courseName : 'course:$courseId'}:'
                    '${item.title}|${item.createdAt}|${item.messageHtml}'
                .toLowerCase();
    entries.putIfAbsent(
      key,
      () => MessageFeedEntry(
        key: key,
        title: item.title,
        sourceLabel: value.courseName,
        createdAt: item.createdAt,
        canvasItem: item,
        timetableCourse: value.timetableCourse,
      ),
    );
  }
  for (final message in attendanceMessages) {
    entries[message.key] = MessageFeedEntry(
        key: message.key,
        title: '发现课程签到',
        sourceLabel: message.courseName,
        createdAt: message.record.createdAt.toUtc().toIso8601String(),
        attendanceMessage: message);
  }
  if (attendanceMessages.isNotEmpty) {
    final result = entries.values.toList();
    result.sort((a, b) {
      final x = DateTime.tryParse(a.createdAt),
          y = DateTime.tryParse(b.createdAt);
      final order = x == null
          ? (y == null ? 0 : 1)
          : y == null
              ? -1
              : y.compareTo(x);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
    return result;
  }
  // AnnouncementFeed already owns chronological ordering; filtering stable
  // message IDs preserves that order without a second date parse and sort.
  return entries.values.toList();
}
