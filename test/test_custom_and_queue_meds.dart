import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/master_proforma_service.dart';
import 'package:gmwf/pages/dispensary/doctor/doctor_right_panel.dart';
import 'package:gmwf/pages/dispensary/doctor/patient_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('med_custom_test');
    Hive.init(tempDir.path);
    final stockBox = await Hive.openBox(LocalStorageService.stockBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox('app_settings');
    await Hive.openBox(MasterProformaService.boxName);

    // Stock for jalalpurjattan
    await stockBox.put('stock_jlj_panadol', {
      'id': 'jlj_panadol_1',
      'name': 'Panadol Tab 500mg',
      'formula': 'Paracetamol',
      'dose': '500 mg',
      'type': 'Tablet',
      'quantity': 50,
      'branchId': 'jalalpurjattan',
      'campId': 'jalalpurjattan',
    });
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Test Add Custom Medicine in DoctorRightPanel', (WidgetTester tester) async {
    final prescriptions = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoctorRightPanel(
            branchId: 'jalalpurjattan',
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

    // 1. Open Search & Select
    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();

    // 2. Click "Add Custom Medicine"
    final addCustomBtn = find.text('Add Custom Medicine');
    expect(addCustomBtn, findsOneWidget);
    await tester.tap(addCustomBtn);
    await tester.pumpAndSettle();

    // 3. Check if Add Custom Medicine dialog opened
    print('Add Custom Medicine dialog opened. Title check:');
    expect(find.text('Add Custom Medicine'), findsNWidgets(2));

    // 4. Enter custom medicine name in the text field
    final nameField = find.widgetWithText(TextField, 'Medicine Name');
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, 'Azithromycin 250mg');
    await tester.pumpAndSettle();

    // 5. Tap "Add & Done"
    final addDoneBtn = find.text('Add & Done');
    expect(addDoneBtn, findsOneWidget);
    await tester.tap(addDoneBtn);
    await tester.pumpAndSettle();

    print('Prescriptions after Add & Done: ${prescriptions.length}');
    expect(prescriptions.length, equals(1));
    expect(prescriptions.first['name'], equals('Azithromycin 250mg'));

    // Check if the custom medicine chip is rendered on DoctorRightPanel!
    print('Checking if custom medicine chip is visible on DoctorRightPanel...');
    expect(find.textContaining('Azithromycin 250mg'), findsWidgets);
  });

  testWidgets('Test Add Custom Medicine with Add & Keep Browsing then Done at bottom', (WidgetTester tester) async {
    final prescriptions = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoctorRightPanel(
            branchId: 'jalalpurjattan',
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

    // 1. Open Search & Select
    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();

    // 2. Click "Add Custom Medicine"
    await tester.tap(find.text('Add Custom Medicine'));
    await tester.pumpAndSettle();

    // 3. Enter custom medicine name
    final nameField = find.widgetWithText(TextField, 'Medicine Name');
    await tester.enterText(nameField, 'Custom Syrup XYZ');
    await tester.pumpAndSettle();

    // 4. Tap "Add & Keep Browsing"
    final keepBrowsingBtn = find.text('Add & Done');
    expect(keepBrowsingBtn, findsOneWidget);
    await tester.tap(keepBrowsingBtn);
    await tester.pumpAndSettle();

    print('Prescriptions after Add & Keep Browsing: ${prescriptions.length}');
    expect(prescriptions.length, equals(1));

    // 5. Check the selection dialog footer "Done (1)" button
    final doneFinder = find.textContaining('Done (1)');
    expect(doneFinder, findsOneWidget);
    await tester.tap(doneFinder);
    await tester.pumpAndSettle();

    print('Prescriptions after tapping Done at bottom: ${prescriptions.length}');
    expect(prescriptions.length, equals(1));
    expect(find.textContaining('Custom Syrup XYZ'), findsWidgets);
  });
}
