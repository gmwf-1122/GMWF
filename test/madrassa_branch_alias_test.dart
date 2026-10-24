import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/pages/madrassa/utils/madrassa_local_storage.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/services/local_storage_service.dart';

/// Madrassa folded only Karachi's aliases, so a Gujrat teacher stored as 'grt' saved students
/// under 'grt' while logs and the LAN server used 'gujrat': nobody else ever saw the students.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_madrassa_alias_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.madrassaStudentsBox);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox(LocalStorageService.deadLetterQueueBox);
    await Hive.openBox(LocalStorageService.usersBox);
    await Hive.openBox('app_settings');
    await Hive.openBox('app_flags');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('normalizeBranch folds the same aliases as sanitizeBranchId', () {
    for (final alias in ['grt', 'GJT', 'gujrat', ' Gujrat ']) {
      expect(MadrassaLocalStorage.normalizeBranch(alias), 'gujrat');
      expect(LocalStorageService.sanitizeBranchId(alias), 'gujrat');
    }
    expect(MadrassaLocalStorage.normalizeBranch('jalalpur_jattan'), 'jalalpurjattan');
    expect(MadrassaLocalStorage.normalizeBranch('skt'), 'sialkot');
    expect(MadrassaLocalStorage.normalizeBranch('rwp'), 'rawalpindi');
    expect(MadrassaLocalStorage.normalizeBranch('haji_camp'), 'karachi');
    expect(MadrassaLocalStorage.normalizeBranch('khi'), 'karachi');
    expect(MadrassaLocalStorage.normalizeBranch(''), 'all');
    expect(MadrassaLocalStorage.legacyBranchIds('gujrat'), containsAll(['grt', 'gjt']));
  });

  test('a student saved under the grt alias is listed for gujrat', () async {
    final box = Hive.box(LocalStorageService.madrassaStudentsBox);
    await box.put('grt__std__s1', {'name': 'Alias Student', 'branchId': 'grt', 'status': 'active'});
    await box.put('gujrat__std__s2', {'name': 'Canonical Student', 'branchId': 'gujrat', 'status': 'active'});

    final names = MadrassaLocalStorage.getAllStudentsCached('gujrat').map((s) => s['name']).toSet();
    expect(names, containsAll(['Alias Student', 'Canonical Student']));
    // Asking with the alias gives the same list.
    final viaAlias = MadrassaLocalStorage.getAllStudentsCached('grt').map((s) => s['name']).toSet();
    expect(viaAlias, names);
  });

  test('repair moves alias keys to the canonical key without losing records', () async {
    final box = Hive.box(LocalStorageService.madrassaStudentsBox);
    await box.put('grt__std__s1', {'name': 'Alias Student', 'branchId': 'grt'});
    // Canonical key, alias branchId: the old repair re-put it under the same key and then
    // deleted that key.
    await box.put('gujrat__std__s2', {'name': 'Same Key Student', 'branchId': 'grt'});

    await MadrassaLocalStorage.repairMissingStudentsFromLocalData(force: true);
    // The repair's seeding step queues uploads without awaiting them; let them land.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(box.containsKey('grt__std__s1'), isFalse);
    expect((box.get('gujrat__std__s1') as Map)['name'], 'Alias Student');
    expect((box.get('gujrat__std__s1') as Map)['branchId'], 'gujrat');
    expect((box.get('gujrat__std__s2') as Map)['name'], 'Same Key Student');
    expect((box.get('gujrat__std__s2') as Map)['branchId'], 'gujrat');
  });

  test('LAN payload keeps branchId for madrassa daily logs, fees and offboards', () {
    for (final type in [
      RealtimeEvents.saveMadrassaDailyLog,
      RealtimeEvents.saveMadrassaAttendance,
      RealtimeEvents.saveMadrassaFeePayment,
      RealtimeEvents.saveMadrassaStudent,
    ]) {
      final p = RealtimeEvents.payload(type: type, data: {'branchId': 'gujrat', 'x': 1}, branchId: 'gujrat');
      expect((p['data'] as Map)['branchId'], 'gujrat', reason: type);
    }
    // Non-madrassa types still strip it.
    final token = RealtimeEvents.payload(type: 'save_entry', data: {'branchId': 'gujrat'}, branchId: 'gujrat');
    expect((token['data'] as Map).containsKey('branchId'), isFalse);
  });

  test('cloud copy keeps each image once and download restores the aliases', () {
    final local = {
      'name': 'S',
      'photoUrl': 'P',
      'photoBase64': 'P',
      'studentPhotoBase64': 'P',
      'bFormUrl': '',
      'bFormBase64': 'B',
      'guardianCnicUrl': 'G',
      'guardianCnicBase64': 'G',
      'hifzCertificateUrl': '',
      'hifzCertificateBase64': '',
    };
    final cloud = MadrassaLocalStorage.compactMediaForCloud(local);
    expect(cloud['photoUrl'], 'P');
    expect(cloud.containsKey('photoBase64'), isFalse);
    expect(cloud.containsKey('studentPhotoBase64'), isFalse);
    expect(cloud['bFormUrl'], 'B'); // promoted from the only non-empty copy
    expect(cloud.containsKey('bFormBase64'), isFalse);
    expect(cloud.containsKey('guardianCnicBase64'), isFalse);
    expect(cloud['name'], 'S');

    // An old alias still in the cloud doc must not win over the current primary.
    final back = MadrassaLocalStorage.expandMediaFromCloud({...cloud, 'photoBase64': 'OLD'});
    expect(back['photoBase64'], 'P');
    expect(back['studentPhotoBase64'], 'P');
    expect(back['bFormBase64'], 'B');
    expect(back['guardianCnicBase64'], 'G');
  });

  test('pendingStudentUploads counts queued and dead-lettered student saves', () async {
    await Hive.box(LocalStorageService.syncBox).put('a', {'type': 'save_madrassa_student'});
    await Hive.box(LocalStorageService.syncBox).put('b', {'type': 'save_entry'});
    await Hive.box(LocalStorageService.deadLetterQueueBox).put('c', {'type': 'save_madrassa_admission'});
    expect(MadrassaLocalStorage.pendingStudentUploads(), 2);
  });
}
