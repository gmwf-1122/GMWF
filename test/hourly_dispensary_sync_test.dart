import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/hourly_dispensary_sync.dart';
import 'package:gmwf/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_hourly_sync_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox('app_settings');
    await Hive.openBox('app_flags');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Map<String, dynamic> stockChange(String serial, String medicineId, double delta, {DateTime? at}) => {
        'type': 'update_inventory',
        'branchId': 'gujrat',
        'medicineId': medicineId,
        'delta': delta,
        'serial': serial,
        'data': {'medicineId': medicineId, 'delta': delta, 'serial': serial},
        'createdAt': (at ?? DateTime.now()).toIso8601String(),
        'attempts': 0,
        'status': 'pending',
      };

  test('recent stock changes are held; old or folded ones are not', () {
    expect(HourlyDispensarySync.isHeld(stockChange('171026-GUJ-001', 'para', -2)), isTrue);
    final old = stockChange('171026-GUJ-001', 'para', -2, at: DateTime.now().subtract(const Duration(hours: 2)));
    expect(HourlyDispensarySync.isHeld(old), isFalse);
    expect(HourlyDispensarySync.isHeld({...stockChange('x', 'para', -1), 'aggregated': true}), isFalse);
    expect(HourlyDispensarySync.isHeld({'type': 'save_entry', 'createdAt': DateTime.now().toIso8601String()}), isFalse);
  });

  test('folds changes per medicine into one upload each', () async {
    final box = Hive.box(LocalStorageService.syncBox);
    await box.put('sync_inv_gujrat_001_para', stockChange('171026-GUJ-001', 'para', -2));
    await box.put('sync_inv_gujrat_002_para', stockChange('171026-GUJ-002', 'para', -3));
    await box.put('sync_inv_gujrat_002_amox', stockChange('171026-GUJ-002', 'amox', -6));
    await box.put('sync_inv_gujrat_003_amox', stockChange('171026-GUJ-003', 'amox', 6)); // cancels out
    await box.put('sync_serial_gujrat_171026-GUJ-001', {'type': 'save_entry', 'serial': '171026-GUJ-001'});

    final folded = await HourlyDispensarySync.foldNow();
    expect(folded, 4);

    final stock = box.values.whereType<Map>().where((v) => v['type'] == 'update_inventory').toList();
    expect(stock.length, 1, reason: 'amox cancelled out, para folded into one');
    expect(stock.single['medicineId'], 'para');
    expect(stock.single['delta'], -5);
    expect(stock.single['aggregated'], isTrue);
    expect(HourlyDispensarySync.isHeld(stock.single), isFalse);

    // Other queued work is left alone.
    expect(box.containsKey('sync_serial_gujrat_171026-GUJ-001'), isTrue);

    // The pending total is what a cloud stock download must take off again.
    expect(HourlyDispensarySync.pendingStockChanges()['para'], -5);
  });

  test('a change already folded before a crash is not sent twice', () async {
    final box = Hive.box(LocalStorageService.syncBox);
    final source = stockChange('171026-GUJ-001', 'para', -2);
    await box.put('sync_inv_gujrat_001_para', source);
    // The aggregate was written but the app stopped before the source was deleted.
    await box.put('sync_inv_agg_gujrat_para_1', {
      ...stockChange('171026-GUJ-001', 'para', -2),
      'aggregated': true,
      'mergedFrom': ['sync_inv_gujrat_001_para|${source['createdAt']}'],
    });

    await HourlyDispensarySync.foldNow();

    final stock = box.values.whereType<Map>().where((v) => v['type'] == 'update_inventory').toList();
    expect(stock.length, 1);
    expect(stock.single['delta'], -2);
  });

  test('a dispense line queues its stock change only once', () {
    expect(HourlyDispensarySync.claimStockDeduction('sync_dispense_gujrat_S1_inv_para'), isTrue);
    expect(HourlyDispensarySync.claimStockDeduction('sync_dispense_gujrat_S1_inv_para'), isFalse);
    expect(HourlyDispensarySync.claimStockDeduction('sync_dispense_gujrat_S1_inv_amox'), isTrue);
  });
}
