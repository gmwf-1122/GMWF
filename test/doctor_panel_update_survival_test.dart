import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/master_proforma_service.dart';
import 'package:gmwf/pages/dispensary/doctor/doctor_right_panel.dart';

/// Regression test for "medicines can't be selected / dialog never appears".
///
/// DoctorScreen used to bump the panel's ValueKey whenever a prescription-update
/// event arrived for the open patient. That disposed the panel while its medicine
/// dialog was open, so the next tap hit `if (!mounted) return null;` and nothing
/// happened. The fix updates data in place and keeps the same key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('panel_survival_test');
    Hive.init(tempDir.path);
    final stockBox = await Hive.openBox(LocalStorageService.stockBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox('app_settings');
    await Hive.openBox(MasterProformaService.boxName);
    await stockBox.put('stock_panadol', {
      'id': 'panadol_1',
      'name': 'Paracetamol (Panadol)',
      'formula': 'Paracetamol',
      'dose': '500 mg',
      'type': 'Tablet',
      'quantity': 100,
      'branchId': 'karachi',
      'campId': 'haji_camp',
    });
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  // DoctorScreen passes the same patient map instance across rebuilds; reuse it so
  // didUpdateWidget does not treat every rebuild as a patient change.
  final patient = <String, dynamic>{'name': 'Test Patient', 'serial': '091026-JLJ-001'};

  Widget host({
    required int panelKey,
    required List<Map<String, dynamic>> prescriptions,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: DoctorRightPanel(
          key: ValueKey(panelKey),
          branchId: 'karachi',
          serialId: '091026-JLJ-001',
          selectedPatientData: patient,
          doctorId: 'doc_1',
          doctorName: 'Dr. Test',
          isPhysiotherapist: false,
          queueType: 'OPD',
          complaintController: TextEditingController(),
          diagnosisController: TextEditingController(),
          prescriptions: prescriptions,
          labResults: [],
          isSaving: false,
          onAddLabResult: () {},
          onRemoveLabResult: (_) {},
          onRemoveMedicine: (_) {},
          onAddMedicine: (_) {},
          onEditMedicine: (_) {},
          onSavePrescription: () async {},
          onEntryCompleted: () {},
          onRepeatData: (_) {},
          onSkipPatient: () {},
        ),
      ),
    );
  }

  testWidgets('in-place update with the SAME key keeps the dialog usable', (tester) async {
    final prescriptions = <Map<String, dynamic>>[];
    await tester.pumpWidget(host(panelKey: 0, prescriptions: prescriptions));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();
    expect(find.text('Select Prescription Medicine'), findsOneWidget);

    // Simulate the fixed DoctorScreen: data changes, key does not.
    prescriptions.add({'name': 'Some other med', 'quantity': 1, 'type': 'Tablet'});
    await tester.pumpWidget(host(panelKey: 0, prescriptions: prescriptions));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+ Select').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Inventory Medicine'), findsOneWidget,
        reason: 'medicine dialog must still open after an in-place update');
  });

  testWidgets('even if the panel is re-keyed under an open dialog, the medicine still adds', (tester) async {
    final prescriptions = <Map<String, dynamic>>[];
    await tester.pumpWidget(host(panelKey: 0, prescriptions: prescriptions));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();
    expect(find.text('Select Prescription Medicine'), findsOneWidget);

    // Key bump disposes the panel State that owns the open dialog (the root cause of
    // "tapping a medicine does nothing"). The dialog must keep working anyway.
    await tester.pumpWidget(host(panelKey: 1, prescriptions: prescriptions));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+ Select').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Inventory Medicine'), findsOneWidget,
        reason: 'dialog must open even though its owning State was disposed');

    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();
    expect(prescriptions.length, equals(1),
        reason: 'medicine must be written to the parent list without throwing');
  });
}
