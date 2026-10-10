import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/master_proforma_service.dart';
import 'package:gmwf/pages/dispensary/doctor/doctor_right_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('med_tap_test');
    Hive.init(tempDir.path);
    final stockBox = await Hive.openBox(LocalStorageService.stockBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox('app_settings');
    await Hive.openBox(MasterProformaService.boxName);

    // Put a test stock item
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
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Test clicking + Select on medicine opens dialog and adds medicine', (WidgetTester tester) async {
    final prescriptions = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoctorRightPanel(
            branchId: 'karachi',
            serialId: '091026-JLJ-001',
            selectedPatientData: {
              'name': 'Test Patient',
              'serial': '091026-JLJ-001',
            },
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
            onAddMedicine: (m) {
              print('onAddMedicine callback called: ${m['name']}');
            },
            onEditMedicine: (_) {},
            onSavePrescription: () async {},
            onEntryCompleted: () {},
            onRepeatData: (_) {},
            onSkipPatient: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    print('DoctorRightPanel pumped');

    // 1. Open the selection dialog by tapping search
    final searchFinder = find.text('Search & Select Medicines...');
    await tester.tap(searchFinder);
    await tester.pumpAndSettle();
    print('Dialog opened. Checking for Select Prescription Medicine title...');
    expect(find.text('Select Prescription Medicine'), findsOneWidget);

    // 2. Look for '+ Select' button
    final selectBtnFinder = find.text('+ Select');
    print('Found + Select count: ${selectBtnFinder.evaluate().length}');
    expect(selectBtnFinder, findsWidgets);

    await tester.tap(selectBtnFinder.first);
    await tester.pumpAndSettle();
    expect(find.text('Add Inventory Medicine'), findsOneWidget);
    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();
    expect(prescriptions.length, equals(1));
  });

  testWidgets('Test clicking medicine name directly opens dialog and adds medicine', (WidgetTester tester) async {
    final prescriptions = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoctorRightPanel(
            branchId: 'karachi',
            serialId: '091026-JLJ-001',
            selectedPatientData: {
              'name': 'Test Patient',
              'serial': '091026-JLJ-001',
            },
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
            onAddMedicine: (m) {},
            onEditMedicine: (_) {},
            onSavePrescription: () async {},
            onEntryCompleted: () {},
            onRepeatData: (_) {},
            onSkipPatient: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Open the selection dialog by tapping search
    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();

    // 2. Tap the medicine NAME text directly (not + Select button)
    final medNameFinder = find.text('Paracetamol (Panadol)');
    expect(medNameFinder, findsOneWidget);
    await tester.tap(medNameFinder);
    await tester.pumpAndSettle();

    // 3. Check if _addMedicineDialog opened
    print('Tapped med name. Checking if Add Inventory Medicine dialog opened...');
    final addDialogTitle = find.text('Add Inventory Medicine');
    expect(addDialogTitle, findsOneWidget);

    // 4. Tap 'Add & Done'
    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();

    print('After tapping med name and Add & Done, prescriptions: ${prescriptions.length}');
    expect(prescriptions.length, equals(1));
  });

  testWidgets('Test Add & Keep Browsing then tapping Done button at bottom', (WidgetTester tester) async {
    final prescriptions = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoctorRightPanel(
            branchId: 'karachi',
            serialId: '091026-JLJ-001',
            selectedPatientData: {
              'name': 'Test Patient',
              'serial': '091026-JLJ-001',
            },
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
            onAddMedicine: (m) {},
            onEditMedicine: (_) {},
            onSavePrescription: () async {},
            onEntryCompleted: () {},
            onRepeatData: (_) {},
            onSkipPatient: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Open the selection dialog
    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();

    // 2. Tap + Select
    await tester.tap(find.text('+ Select').first);
    await tester.pumpAndSettle();

    // 3. Tap 'Add & Keep Browsing'
    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();

    // 4. Check if we are back at Select Prescription Medicine
    expect(find.text('Select Prescription Medicine'), findsOneWidget);

    // 5. Look for the Done button at bottom
    final doneBtnFinder = find.textContaining('Done');
    print('Done button text: ${doneBtnFinder.evaluate().map((e) => (e.widget as Text).data)}');
    await tester.tap(doneBtnFinder.first);
    await tester.pumpAndSettle();

    // 6. Check prescriptions
    print('After Done button at bottom, prescriptions: ${prescriptions.length}');
    expect(prescriptions.length, equals(1));
  });
}
