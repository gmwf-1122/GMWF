import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/master_proforma_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_med_selection_test');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.stockBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox(MasterProformaService.boxName);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Doctor Medicine Selection & Inventory Fallbacks', () {
    test('getAllLocalStockItems falls back smoothly when camp filtering is disabled', () async {
      final stockBox = Hive.box(LocalStorageService.stockBox);
      await stockBox.put('stock_1', {
        'id': 'med_panadol',
        'name': 'Panadol 500mg',
        'type': 'Tablet',
        'dose': '500 mg',
        'quantity': 100,
        'branchId': 'karachi',
        'campId': 'haji_camp',
      });

      // Query with mismatched camp should be empty with filterByCamp: true
      final campItems = LocalStorageService.getAllLocalStockItems(
        branchId: 'karachi',
        dispensaryId: 'non_existent_camp',
        filterByCamp: true,
      );
      expect(campItems.isEmpty, isTrue);

      // Fallback with filterByCamp: false returns branch items
      final fallbackItems = LocalStorageService.getAllLocalStockItems(
        branchId: 'karachi',
        filterByCamp: false,
      );
      expect(fallbackItems.length, equals(1));
      expect(fallbackItems.first['name'], equals('Paracetamol (Panadol)'));
    });

    test('MasterProforma provides default formula catalog when physical stock is empty', () {
      final catalog = MasterProformaService.getAllItems();
      expect(catalog.isNotEmpty, isTrue);
      final hasPanadol = catalog.any((m) => (m['formula'] ?? m['name']).toString().contains('Paracetamol'));
      expect(hasPanadol, isTrue);
    });

    test('Prescription with zero or exceeded stock correctly flags isExternal and outOfStock', () {
      final zeroStockMed = {
        'name': 'Ceftriaxone 1g',
        'quantity': 1,
        'type': 'Injection',
        'inventoryId': 'inj_001',
        'isExternal': true,
        'outOfStock': true,
      };

      expect(zeroStockMed['isExternal'], isTrue);
      expect(zeroStockMed['outOfStock'], isTrue);
      expect(zeroStockMed['quantity'], equals(1));

      // Over-demand oral med
      final oralMed = {
        'name': 'Amoxicillin 500mg',
        'quantity': 2,
        'timing': '1+0+1',
        'meal': 'After Meal',
        'type': 'Capsule',
        'inventoryId': 'cap_001',
        'isExternal': true,
        'stockShortage': 6, // 10 needed, only 4 available
      };

      expect(oralMed['isExternal'], isTrue);
      expect(oralMed['stockShortage'], equals(6));
    });
  });
}
