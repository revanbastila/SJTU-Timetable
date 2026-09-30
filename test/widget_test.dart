import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/course.dart';

void main() {
  test('course map retains required display fields', () {
    final course = Course.fromMap({
      'name': '高级计算机网络',
      'time': '星期一 08:00 - 09:40',
      'location': '东上院 101',
      'teacher': '李老师',
    });

    expect(course.name, '高级计算机网络');
    expect(course.location, '东上院 101');
    expect(course.teacher, '李老师');
  });
}
