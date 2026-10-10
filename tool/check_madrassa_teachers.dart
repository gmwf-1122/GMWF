import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final srcDir = 'C:\\Users\\win\\AppData\\Roaming\\com.example\\gmwf\\gmwf_hive';
  final tempDir = Directory.systemTemp.createTempSync('hive_inspect_');
  for (final name in ['local_users.hive', 'local_madrassa_students.hive', 'local_madrassa_logs.hive']) {
    final f = File('$srcDir\\$name');
    if (f.existsSync()) {
      f.copySync('${tempDir.path}\\$name');
    }
  }
  Hive.init(tempDir.path);
  final appBoxFile = File('$srcDir\\app_settings.hive');
  if (appBoxFile.existsSync()) {
    appBoxFile.copySync('${tempDir.path}\\app_settings.hive');
    final appBox = await Hive.openBox('app_settings');
    print('=== APP SETTINGS ===');
    print('currentUser: ${appBox.get('currentUser')}');
    print('user_data: ${appBox.get('user_data')}');
  }
  final userBox = await Hive.openBox('local_users');
  final stdBox = await Hive.openBox('local_madrassa_students');
  final logBox = await Hive.openBox('local_madrassa_logs');

  print('=== TEACHERS IN local_users ===');
  for (final k in userBox.keys) {
    final v = userBox.get(k);
    if (v is Map) {
      final role = (v['role'] ?? '').toString().toLowerCase();
      if (role.contains('madrassa') || role.contains('teacher') || role.contains('qari') || role.contains('nazim') || role.contains('principal')) {
        print('Key: $k | Name: ${v['name'] ?? v['displayName']} | Username: ${v['username']} | Role: ${v['role']} | Branch: ${v['branchId']} | email: ${v['email']}');
      }
    }
  }

  print('\n=== KARACHI STUDENTS ===');
  for (final k in stdBox.keys) {
    final v = stdBox.get(k);
    if (v is Map) {
      final b = (v['branchId'] ?? '').toString();
      if (b.toLowerCase().contains('karachi') || b.isEmpty || b == 'none') {
        print('Student ID: ${v['id'] ?? k} | Name: ${v['name']} | Branch: $b | Teacher: ${v['teacherName'] ?? v['teacherId'] ?? v['teacher'] ?? v['assignedTeacher']} | Program: ${v['program']} | Creator: ${v['createdBy'] ?? v['creatorUid']}');
      }
    }
  }

  print('\n=== LOG DETAILS ===');
  for (final k in logBox.keys) {
    if (k.toString().startsWith('karachi') || k.toString().startsWith('all')) {
      final v = logBox.get(k);
      if (v is Map) {
        print('Log Key: $k | Entries count: ${v.length} | Keys: ${v.keys.take(5).toList()}');
        for (final entryKey in v.keys.take(3)) {
          final entry = v[entryKey];
          if (entry is Map) {
            print('  -> Entry $entryKey: teacher=${entry['teacherName'] ?? entry['teacherId'] ?? entry['editorName']}, status=${entry['status']}, sabq=${entry['sabq']}');
          }
        }
      }
    }
  }
  print('=== DETAILED TEACHER PROFILES ===');
  for (final k in userBox.keys) {
    final v = userBox.get(k);
    if (v is Map) {
      final role = (v['role'] ?? '').toString().toLowerCase();
      if (role.contains('teacher') || role.contains('madrassa')) {
        print('KEY: $k -> DATA: $v\n');
      }
    }
  }
  exit(0);
}
