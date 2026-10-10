import 'dart:convert';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/services/app_database.dart';

/// Test storage implements the real persistence boundary. Tests no longer
/// mistake writes to a redundant preferences mirror for successful SQL writes.
class MemoryDatabase extends AppDatabase {
  List<Course>? savedCourses;
  CanvasSnapshot? savedCanvas;
  Map<String, String> mappings = {};
  Map<String, int> colors = {};
  int fullWrites = 0, canvasWrites = 0;
  @override
  bool get available => true;
  @override
  Future<bool> initialize() async => true;
  @override
  Future<List<Course>?> loadCourses({int totalWeeks = 18}) async =>
      savedCourses;
  @override
  Future<CanvasSnapshot?> loadCanvas() async => savedCanvas;
  @override
  Future<Map<String, String>> loadMappings() async => Map.of(mappings);
  @override
  Future<Map<String, int>> loadCourseColors() async => Map.of(colors);
  @override
  Future<void> replaceAll(List<Course> courses, CanvasSnapshot canvas,
      Map<String, String> mappings, Map<String, int> colors) async {
    fullWrites++;
    await saveCourses(courses);
    await saveCanvas(canvas);
    this.mappings = Map.of(mappings);
    this.colors = Map.of(colors);
  }

  @override
  Future<void> saveCourses(List<Course> courses) async {
    final values =
        jsonDecode(jsonEncode(courses.map((c) => c.toMap()).toList())) as List;
    savedCourses = [
      for (var i = 0; i < values.length; i++)
        Course.fromMap(Map<String, dynamic>.from(values[i] as Map), index: i)
    ];
  }

  @override
  Future<void> saveCanvas(CanvasSnapshot canvas) async {
    canvasWrites++;
    savedCanvas = CanvasSnapshot.fromMap(
        jsonDecode(jsonEncode(canvas.toMap())) as Map<String, dynamic>);
  }

  @override
  Future<void> saveCourseColors(Map<String, int> colors) async =>
      this.colors = Map.of(colors);
  @override
  Future<void> saveMapping(String identity, String canvasCourseId) async {
    mappings[identity] = canvasCourseId;
  }

  @override
  Future<void> clear() async {
    savedCourses = null;
    savedCanvas = null;
    mappings = {};
    colors = {};
  }
}
