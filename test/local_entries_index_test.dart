import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';

/// getLocalEntries keeps a per-branch index that is updated from box change events instead
/// of re-scanning the whole token history after every write. These tests check that the
/// index follows puts, updates and deletes, and that duplicate merging never edits the
/// shared index copies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_entries_index_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox('app_settings');
    await Hive.openBox('app_flags');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Map<String, dynamic> token(String serial, {String status = 'waiting', String branch = 'gujrat'}) => {
        'serial': serial,
        'branchId': branch,
        'dateKey': serial.split('-').first,
        'patientName': 'Patient $serial',
        'status': status,
      };

  List<String> serials(String branch) =>
      LocalStorageService.getLocalEntries(branch).map((e) => e['serial'].toString()).toList()..sort();

  test('follows puts, updates and deletes after the first build', () async {
    final box = Hive.box(LocalStorageService.entriesBox);
    await box.put('gujrat-171026-GUJ-001', token('171026-GUJ-001'));
    await box.put('sialkot-171026-SKT-001', token('171026-SKT-001', branch: 'sialkot'));

    expect(serials('gujrat'), ['171026-GUJ-001']);

    await box.put('gujrat-171026-GUJ-002', token('171026-GUJ-002'));
    expect(serials('gujrat'), ['171026-GUJ-001', '171026-GUJ-002']);

    await box.put('gujrat-171026-GUJ-001', token('171026-GUJ-001', status: 'completed'));
    final first = LocalStorageService.getLocalEntries('gujrat').firstWhere((e) => e['serial'] == '171026-GUJ-001');
    expect(first['status'], 'completed');

    await box.delete('gujrat-171026-GUJ-002');
    expect(serials('gujrat'), ['171026-GUJ-001']);

    // Other branches are unaffected.
    expect(serials('sialkot'), ['171026-SKT-001']);
  });

  test('merging duplicates does not change the stored or indexed copies', () async {
    final box = Hive.box(LocalStorageService.entriesBox);
    // Same token under a lower-case legacy key and the canonical key; only the legacy copy
    // is dispensed.
    await box.put('gujrat-171026-guj-003', {...token('171026-guj-003'), 'dispenseStatus': 'dispensed'});
    await box.put('gujrat-171026-GUJ-003', token('171026-GUJ-003'));

    final merged = LocalStorageService.getLocalEntries('gujrat');
    expect(merged.length, 1);
    expect(merged.single['dispenseStatus'], 'dispensed');
    expect(merged.single['status'], 'completed');

    // The canonical record in Hive is untouched by the merge.
    expect((box.get('gujrat-171026-GUJ-003') as Map)['status'], 'waiting');

    // A later write to an unrelated key rebuilds the result from unmodified index copies.
    await box.put('gujrat-171026-GUJ-004', token('171026-GUJ-004'));
    final again = LocalStorageService.getLocalEntries('gujrat');
    expect(again.length, 2);
    expect(again.firstWhere((e) => e['serial'] == '171026-GUJ-003')['status'], 'completed');
  });
}
