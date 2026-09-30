import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/canvas_data.dart';
import '../models/course.dart';

class AppDatabase {
  Database? _database;
  bool get available => _database != null;

  Future<bool> initialize() async {
    try {
      final root = await getDatabasesPath();
      _database = await openDatabase(
        p.join(root, 'jiaotong_course_1_1.db'),
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
              'CREATE TABLE cache (cache_key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)');
          await db.execute(
              'CREATE TABLE course_mapping (course_identity TEXT PRIMARY KEY, canvas_course_id TEXT NOT NULL)');
        },
      );
      return true;
    } catch (_) {
      _database = null;
      return false;
    }
  }

  Future<List<Course>?> loadCourses({int totalWeeks = 18}) async {
    final value = await _read('courses');
    if (value == null) return null;
    final decoded = jsonDecode(value);
    if (decoded is! List) return null;
    return [
      for (var i = 0; i < decoded.length; i++)
        if (decoded[i] is Map)
          Course.fromMap(Map<String, dynamic>.from(decoded[i] as Map),
              index: i, totalWeeks: totalWeeks),
    ];
  }

  Future<CanvasSnapshot?> loadCanvas() async {
    final value = await _read('canvas');
    if (value == null) return null;
    final decoded = jsonDecode(value);
    return decoded is Map
        ? CanvasSnapshot.fromMap(Map<String, dynamic>.from(decoded))
        : null;
  }

  Future<Map<String, int>> loadCourseColors() async {
    final value = await _read('course_colors');
    if (value == null) return {};
    final decoded = jsonDecode(value);
    if (decoded is! Map) return {};
    return {
      for (final entry in decoded.entries)
        if (int.tryParse('${entry.value}') != null)
          '${entry.key}': int.parse('${entry.value}'),
    };
  }

  Future<Map<String, String>> loadMappings() async {
    final db = _database;
    if (db == null) return {};
    final rows = await db.query('course_mapping');
    return {
      for (final row in rows)
        '${row['course_identity']}': '${row['canvas_course_id']}',
    };
  }

  Future<void> replaceAll(
    List<Course> courses,
    CanvasSnapshot canvas,
    Map<String, String> mappings,
  ) async {
    final db = _database;
    if (db == null) return;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert(
        'cache',
        {
          'cache_key': 'courses',
          'value': jsonEncode(courses.map((course) => course.toMap()).toList()),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'cache',
        {
          'cache_key': 'canvas',
          'value': jsonEncode(canvas.toMap()),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('course_mapping');
      for (final entry in mappings.entries) {
        await txn.insert('course_mapping', {
          'course_identity': entry.key,
          'canvas_course_id': entry.value,
        });
      }
    });
  }

  Future<void> saveCourses(List<Course> courses) async {
    final db = _database;
    if (db == null) return;
    await db.insert(
      'cache',
      {
        'cache_key': 'courses',
        'value': jsonEncode(courses.map((course) => course.toMap()).toList()),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveCourseColors(Map<String, int> colors) async {
    final db = _database;
    if (db == null) return;
    await db.insert(
      'cache',
      {
        'cache_key': 'course_colors',
        'value': jsonEncode(colors),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveMapping(String identity, String canvasCourseId) async {
    final db = _database;
    if (db == null) return;
    await db.insert(
      'course_mapping',
      {'course_identity': identity, 'canvas_course_id': canvasCourseId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clear() async {
    final db = _database;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete('cache');
      await txn.delete('course_mapping');
    });
  }

  Future<String?> _read(String key) async {
    final db = _database;
    if (db == null) return null;
    final rows = await db.query(
      'cache',
      columns: ['value'],
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : '${rows.first['value']}';
  }
}
