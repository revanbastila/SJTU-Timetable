import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/services/canvas_dashboard_view.dart';

void main() {
  test('recognizes only the Canvas dashboard routes', () {
    expect(isCanvasDashboardUri(Uri.parse('https://oc.sjtu.edu.cn/')), isTrue);
    expect(
      isCanvasDashboardUri(Uri.parse('https://oc.sjtu.edu.cn/dashboard')),
      isTrue,
    );
    expect(
      isCanvasDashboardUri(
        Uri.parse('https://oc.sjtu.edu.cn/courses/123/announcements'),
      ),
      isFalse,
    );
  });

  test('dashboard repair never interacts with Today or scroll position', () {
    expect(canvasDashboardCardViewScript, contains('card view'));
    expect(canvasDashboardCardViewScript, contains('card.click()'));
    expect(canvasDashboardCardViewScript, isNot(contains('scrollIntoView')));
    expect(canvasDashboardCardViewScript, isNot(contains('scrollTo(')));
    expect(canvasDashboardCardViewScript, isNot(contains('Today')));
  });
}
