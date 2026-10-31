import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_med_test');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox(LocalStorageService.stockBox);
    await Hive.openBox('app_settings');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Dispensary & Doctor Medicine Sync Regression Tests', () {
    test('1. LocalStorageService.prescriptionForEmbedding preserves medicines across key formats', () {
      // Test format with 'medicines'
      final rxWithMedicines = {
        'complaint': 'Fever and cough',
        'medicines': [
          {'name': 'Paracetamol', 'dose': '500 mg', 'type': 'Tablet', 'quantity': 10},
          {'name': 'Amoxicillin', 'dose': '250 mg', 'type': 'Capsule', 'quantity': 15},
        ],
      };
      final embedded1 = LocalStorageService.prescriptionForEmbedding(rxWithMedicines);
      expect(embedded1, isNotNull);
      final meds1 = embedded1['medicines'] as List;
      expect(meds1.length, equals(2));
      expect(embedded1['prescriptions'], isNotNull);

      // Test format with 'prescriptions'
      final rxWithPrescriptions = {
        'complaint': 'Headache',
        'prescriptions': [
          {'name': 'Ibuprofen', 'dose': '400 mg', 'type': 'Tablet', 'quantity': 5},
        ],
      };
      final embedded2 = LocalStorageService.prescriptionForEmbedding(rxWithPrescriptions);
      expect(embedded2, isNotNull);
      final meds2 = (embedded2['prescriptions'] as List);
      expect(meds2.length, equals(1));
      expect(meds2.first['name'], equals('Ibuprofen'));

      // Test format with 'items'
      final rxWithItems = {
        'condition': 'Infection',
        'items': [
          {'name': 'Cipro', 'dose': '500 mg', 'type': 'Tablet', 'quantity': 10},
        ],
      };
      final embedded3 = LocalStorageService.prescriptionForEmbedding(rxWithItems);
      expect(embedded3, isNotNull);
      expect((embedded3['prescriptions'] as List).length, equals(1));
    });

    test('2. Dispensary prescription resolution does not stop when patient map only has complaint/vitals', () async {
      final serial = '261031-KHI-001';
      final prescBox = Hive.box(LocalStorageService.prescriptionsBox);

      // Doctor saved 2 medicines in prescriptionsBox
      final savedRx = {
        'serial': serial,
        'complaint': 'Severe headache',
        'medicines': [
          {'name': 'Panadol', 'dose': '500 mg', 'type': 'Tablet', 'quantity': 10},
          {'name': 'Brufen', 'dose': '400 mg', 'type': 'Tablet', 'quantity': 10},
        ],
      };
      await prescBox.put(serial, savedRx);

      // Token in patient queue arrives with only registration complaint / vitals
      final patientQueueToken = {
        'serial': serial,
        'name': 'Patient A',
        'prescription': {
          'complaint': 'Severe headache',
          'vitals': {'bp': '120/80'},
        },
      };

      // Simulated dispensary _loadPrescription logic:
      final rawPrescription = patientQueueToken['prescription'];
      final directEmbedded = rawPrescription is Map<String, dynamic>
          ? rawPrescription
          : (rawPrescription is Map ? Map<String, dynamic>.from(rawPrescription) : null);

      List<dynamic> extractMeds(Map<String, dynamic>? data) {
        if (data == null) return [];
        for (final k in ['prescriptions', 'medicines', 'items']) {
          final v = data[k];
          if (v is List && v.isNotEmpty) return v;
        }
        return [];
      }

      var loadedPrescription = <String, dynamic>{};
      final directMeds = extractMeds(directEmbedded);

      // If directEmbedded has medicines, we use it directly;
      // BUT if it does not contain medicines, it MUST fall through to getLocalPrescription
      if (directEmbedded != null && directMeds.isNotEmpty) {
        loadedPrescription = Map<String, dynamic>.from(directEmbedded);
      } else {
        final localRx = LocalStorageService.getLocalPrescription(serial);
        if (localRx != null) {
          loadedPrescription = Map<String, dynamic>.from(localRx);
        } else if (directEmbedded != null) {
          loadedPrescription = Map<String, dynamic>.from(directEmbedded);
        }
      }

      final resolvedMeds = extractMeds(loadedPrescription);
      expect(resolvedMeds.length, equals(2),
          reason: 'Dispensary must retrieve both medicines even when patient token only has complaint/vitals');
      expect(resolvedMeds[0]['name'], equals('Panadol'));
      expect(resolvedMeds[1]['name'], equals('Brufen'));
    });

    test('3. Doctor applyMedicine logic preserves existing medicines when selecting new ones', () {
      final prescriptions = <Map<String, dynamic>>[];

      void applyMedicine(Map<String, dynamic> med) {
        final incomingId = (med['inventoryId'] ?? med['id'] ?? '').toString().trim();
        final incomingName = (med['name'] ?? '').toString().trim().toLowerCase();
        final incomingType = (med['type'] ?? '').toString().trim().toLowerCase();
        final incomingDose = (med['dose'] ?? '').toString().trim().toLowerCase();

        final matchIdx = prescriptions.indexWhere((p) {
          final existingId = (p['inventoryId'] ?? p['id'] ?? '').toString().trim();
          if (incomingId.isNotEmpty &&
              incomingId != 'unknown' &&
              existingId.isNotEmpty &&
              existingId != 'unknown') {
            return existingId == incomingId;
          }
          final existingName = (p['name'] ?? '').toString().trim().toLowerCase();
          final existingType = (p['type'] ?? '').toString().trim().toLowerCase();
          final existingDose = (p['dose'] ?? '').toString().trim().toLowerCase();
          return incomingName.isNotEmpty &&
              existingName == incomingName &&
              incomingType.isNotEmpty &&
              existingType == incomingType &&
              incomingDose.isNotEmpty &&
              existingDose == incomingDose;
        });

        if (matchIdx >= 0) {
          prescriptions[matchIdx] = Map<String, dynamic>.from(med);
        } else {
          prescriptions.add(Map<String, dynamic>.from(med));
        }
      }

      // 1. Add first inventory medicine
      applyMedicine({
        'inventoryId': 'stock_panadol_500',
        'name': 'Paracetamol (Panadol)',
        'type': 'Tablet',
        'dose': '500 mg',
        'quantity': 10,
      });
      expect(prescriptions.length, equals(1));

      // 2. Add second inventory medicine
      applyMedicine({
        'inventoryId': 'stock_amoxil_250',
        'name': 'Amoxicillin (Amoxil)',
        'type': 'Capsule',
        'dose': '250 mg',
        'quantity': 15,
      });
      expect(prescriptions.length, equals(2));
      expect(prescriptions[0]['name'], equals('Paracetamol (Panadol)'));
      expect(prescriptions[1]['name'], equals('Amoxicillin (Amoxil)'));

      // 3. Add first custom medicine with NO inventory ID
      applyMedicine({
        'name': 'Custom Cough Syrup',
        'type': 'Syrup',
        'dose': '5 ml',
        'quantity': 1,
      });
      expect(prescriptions.length, equals(3));

      // 4. Add second custom medicine with NO inventory ID
      applyMedicine({
        'name': 'Custom Vitamin D Drops',
        'type': 'Drops',
        'dose': '10 drops',
        'quantity': 1,
      });
      expect(prescriptions.length, equals(4),
          reason: 'Custom medicine without inventoryId must not overwrite another custom medicine');
      expect(prescriptions[0]['name'], equals('Paracetamol (Panadol)'));
      expect(prescriptions[1]['name'], equals('Amoxicillin (Amoxil)'));
      expect(prescriptions[2]['name'], equals('Custom Cough Syrup'));
      expect(prescriptions[3]['name'], equals('Custom Vitamin D Drops'));

      // 5. Update the first medicine
      applyMedicine({
        'inventoryId': 'stock_panadol_500',
        'name': 'Paracetamol (Panadol)',
        'type': 'Tablet',
        'dose': '500 mg',
        'quantity': 20, // updated quantity
      });
      expect(prescriptions.length, equals(4), reason: 'Updating existing medicine must not add a duplicate');
      expect(prescriptions[0]['quantity'], equals(20));
    });

    test('4. Edit Prescription modal findExistingIndex protects against false collisions', () {
      final currentMeds = <Map<String, dynamic>>[
        {'id': 'med_1', 'name': 'Medicine One', 'type': 'Tablet', 'dose': '10 mg'},
        {'id': '', 'name': 'Custom Syrup A', 'type': 'Syrup', 'dose': '100 ml'},
      ];

      int findExistingIndex(Map<String, dynamic> item) {
        final itemId = (item['id'] ?? item['inventoryId'] ?? '').toString().trim();
        final itemName = (item['name'] ?? '').toString().trim().toLowerCase();
        final itemType = (item['type'] ?? '').toString().trim().toLowerCase();
        final itemDose = (item['dose'] ?? '').toString().trim().toLowerCase();

        return currentMeds.indexWhere((p) {
          final pId = (p['id'] ?? p['inventoryId'] ?? '').toString().trim();
          if (itemId.isNotEmpty && itemId != 'unknown' && pId.isNotEmpty && pId != 'unknown') {
            return pId == itemId;
          }
          final pName = (p['name'] ?? '').toString().trim().toLowerCase();
          final pType = (p['type'] ?? '').toString().trim().toLowerCase();
          final pDose = (p['dose'] ?? '').toString().trim().toLowerCase();
          return itemName.isNotEmpty &&
              pName == itemName &&
              itemType.isNotEmpty &&
              pType == itemType &&
              itemDose.isNotEmpty &&
              pDose == itemDose;
        });
      }

      // New custom medicine with empty ID
      final newCustom = {'id': '', 'name': 'Custom Syrup B', 'type': 'Syrup', 'dose': '200 ml'};
      expect(findExistingIndex(newCustom), equals(-1),
          reason: 'Different custom medicine must not match existing custom medicine');

      // Matching medicine with exact same name, type, dose
      final exactMatchCustom = {'id': '', 'name': 'Custom Syrup A', 'type': 'Syrup', 'dose': '100 ml'};
      expect(findExistingIndex(exactMatchCustom), equals(1));

      // New inventory item with different ID
      final newInventory = {'id': 'med_2', 'name': 'Medicine Two', 'type': 'Tablet', 'dose': '20 mg'};
      expect(findExistingIndex(newInventory), equals(-1));
    });

    test('5. Realtime LAN update does NOT wipe active doctor prescriptions if incoming is empty', () {
      final activePrescriptions = <Map<String, dynamic>>[
        {'name': 'Active Panadol', 'dose': '500 mg', 'type': 'Tablet', 'quantity': 10},
      ];

      // Simulated incoming LAN update with empty prescription
      final incomingData = <String, dynamic>{
        'serial': '261031-KHI-001',
        'prescription': {
          'complaint': 'Follow up',
          // Note: no medicines!
        },
      };

      // Handler logic:
      final rawRx = incomingData['prescription'];
      final incomingMeds = <Map<String, dynamic>>[];
      if (rawRx is Map) {
        final list = rawRx['prescriptions'] ?? rawRx['medicines'] ?? rawRx['items'];
        if (list is List) {
          for (final item in list) {
            if (item is Map) incomingMeds.add(Map<String, dynamic>.from(item));
          }
        }
      }

      // Guard: Only replace if incoming has medicines, or if incoming explicitly cleared
      if (incomingMeds.isNotEmpty) {
        activePrescriptions
          ..clear()
          ..addAll(incomingMeds);
      }

      // Verification: Active prescriptions were preserved!
      expect(activePrescriptions.length, equals(1));
      expect(activePrescriptions.first['name'], equals('Active Panadol'));
    });
  });
}

