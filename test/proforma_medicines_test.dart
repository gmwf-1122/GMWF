// test/proforma_medicines_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/master_proforma_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_proforma_test');
    Hive.init(tempDir.path);
    if (!Hive.isBoxOpen(MasterProformaService.boxName)) {
      await Hive.openBox(MasterProformaService.boxName);
    }
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Master Proforma Catalog & Medicine Formula Tests', () {
    test('Catalog contains 400mg Panadol, Orphenadrine Citrate + Paracetamol, and Paracetamol + CPM + Dextromethorphan', () {
      final all = MasterProformaService.getAllProformaItems();

      final para400 = all.firstWhere((e) => e['code'] == 'MED-PARA-400', orElse: () => {});
      expect(para400.isNotEmpty, isTrue);
      expect(para400['dose'], equals('400 mg'));
      expect(para400['name'], contains('Paracetamol'));

      final orph = all.firstWhere((e) => e['code'] == 'MED-ORPH-PARA-TAB', orElse: () => {});
      expect(orph.isNotEmpty, isTrue);
      expect(orph['formula'], equals('Orphenadrine Citrate + Paracetamol (Norgesic)'));

      final coldTab = all.firstWhere((e) => e['code'] == 'MED-PARA-CPM-DXM-TAB', orElse: () => {});
      expect(coldTab.isNotEmpty, isTrue);
      expect(coldTab['formula'], contains('Dextromethorphan'));

      final coldSyr = all.firstWhere((e) => e['code'] == 'MED-PARA-CPM-DXM-SYR', orElse: () => {});
      expect(coldSyr.isNotEmpty, isTrue);
      expect(coldSyr['type'], equals('Syrup'));
    });

    test('cleanBrandToFormula canonicalizes Orphenadrine and Panadol CF formulas correctly', () {
      expect(
        MasterProformaService.cleanBrandToFormula('Orphnadrin-Citre-Paracetamol'),
        equals('Orphenadrine Citrate + Paracetamol (Norgesic)'),
      );

      expect(
        MasterProformaService.cleanBrandToFormula('Paracetamol-Chlorpheramine-Dextromethorphan'),
        equals('Paracetamol + Chlorpheniramine + Dextromethorphan (Panadol CF / T-Day)'),
      );

      expect(
        MasterProformaService.cleanBrandToFormula('Panadol 400mg'),
        equals('Paracetamol (Panadol)'),
      );
    });
  });
}
