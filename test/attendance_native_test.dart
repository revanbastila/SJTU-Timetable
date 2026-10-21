import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/services/attendance_native.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';
import 'attendance_test.dart' show fixtureCourse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final task = AttendanceTask(
      id: 'task',
      canvasId: '91',
      courseCode: 'bound',
      createdAt: DateTime.utc(2030),
      state: 'UNNORMAL',
      serverActive: true);
  final qr = AttendanceQr.parse(
      'https://mlearning.sjtu.edu.cn/lms/mobile2/forscan/?courseCode=bound&rollCallToken=fixture&signHistoryId=task&fromType=scanRollCall');
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(NativeAttendanceBackend.channel, null));
  test(
      'native authentication loss during submit reports re-login instead of success',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeAttendanceBackend.channel,
            (call) async => {'status': 'login'});
    final backend = NativeAttendanceBackend();
    expect(await backend.submit(task, qr), AttendanceSubmitResult.needsLogin);
    await expectLater(
        backend.verify(task),
        throwsA(isA<AttendanceFailure>()
            .having((e) => e.phase, 'phase', AttendancePhase.needsLogin)));
  });
  test('unverified student task link never manufactures a pending task',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeAttendanceBackend.channel,
            (call) async => {'status': 'unverified_student_task_link'});
    final backend = NativeAttendanceBackend();
    final meeting = AttendanceMeeting(
        course: fixtureCourse(),
        start: DateTime.utc(2030),
        end: DateTime.utc(2030, 1, 1, 1));
    await expectLater(
        backend.poll(meeting),
        throwsA(isA<AttendanceFailure>()
            .having((e) => e.phase, 'phase', AttendancePhase.limited)));
  });
}
