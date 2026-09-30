import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/canvas_extractor.dart';

void main() {
  test('Canvas sync reads the full catalog and each course announcement feed',
      () {
    expect(canvasExtractionScript, contains('/api/v1/courses?'));
    expect(canvasExtractionScript,
        contains('/users?include[]=enrollments&include[]=avatar_url'));
    expect(canvasExtractionScript, contains('person?.avatar_image_url'));
    expect(
        canvasExtractionScript, isNot(contains('enrollment_state=available')));
    expect(canvasExtractionScript,
        contains('/discussion_topics?only_announcements=true&per_page=100'));
    expect(canvasExtractionScript, contains('/api/v1/announcements?'));
    expect(canvasExtractionScript,
        contains("'start_date', '1970-01-01T00:00:00Z'"));
    expect(
        canvasExtractionScript, contains("'end_date', '2100-01-01T00:00:00Z'"));
    expect(canvasExtractionScript, contains("'announcement_read'"));
    expect(canvasExtractionScript, contains("'announcement_request'"));
    expect(canvasExtractionScript, contains('returnedCount'));
    expect(canvasExtractionScript, contains('parsedCount'));
    expect(canvasExtractionScript, isNot(contains('请选课同学加入课程群')));
    expect(canvasExtractionScript, isNot(contains('上课提醒')));
  });
}
