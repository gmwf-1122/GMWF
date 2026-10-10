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
    tempDir = await Directory.systemTemp.createTemp('doc_flow_test');
    Hive.init(tempDir.path);
    final stockBox = await Hive.openBox(LocalStorageService.stockBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox('app_settings');
    await Hive.openBox(MasterProformaService.boxName);

    // Seed stock identical to jalalpurjattan real data
    await stockBox.put('panadol_500', {
      'id': 'panadol--tablet--500-mg--2027-08-12',
      'name': 'Paracetamol (Panadol)',
      'formula': 'Paracetamol (Panadol)',
      'dose': '500 mg',
      'type': 'Tablet',
      'quantity': 97.0,
      'branchId': 'jalalpurjattan',
      'campId': null,
    });
    await stockBox.put('amoxil_250', {
      'id': 'amoxil--capsule--250-mg--2027-08-12',
      'name': 'Amoxicillin (Amoxil)',
      'formula': 'Amoxicillin (Amoxil)',
      'dose': '250 mg',
      'type': 'Capsule',
      'quantity': 1.0,
      'branchId': 'jalalpurjattan',
      'campId': null,
    });
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Complete workflow for doc account on jalalpurjattan', (WidgetTester tester) async {
    final prescriptions = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoctorRightPanel(
            branchId: 'jalalpurjattan',
            serialId: '091026-JLJ-001',
            selectedPatientData: {
              'name': '07',
              'serial': '091026-JLJ-001',
              'queueType': 'zakat',
            },
            doctorId: 'doc',
            doctorName: 'doc',
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

    // 1. Open Search & Select Medicines dialog
    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();
    expect(find.text('Select Prescription Medicine'), findsOneWidget);

    // 2. Select Paracetamol (Panadol)
    final panadolFinder = find.text('Paracetamol (Panadol)');
    expect(panadolFinder, findsWidgets);
    await tester.tap(panadolFinder.first);
    await tester.pumpAndSettle();

    // 3. Sub-dialog "Add Inventory Medicine" should be open
    expect(find.text('Add Inventory Medicine'), findsOneWidget);
    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();

    // Prescriptions should now have 1 item
    expect(prescriptions.length, equals(1));
    expect(prescriptions.first['name'], equals('Paracetamol (Panadol)'));
    expect(find.textContaining('Paracetamol (Panadol)'), findsWidgets);

    // 4. Open dialog again to add a Custom Medicine
    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();
    expect(find.text('Select Prescription Medicine'), findsOneWidget);

    // Tap "Add Custom Medicine"
    await tester.tap(find.text('Add Custom Medicine'));
    await tester.pumpAndSettle();
    expect(find.text('Add Custom Medicine'), findsNWidgets(2));

    // Fill in medicine name
    final nameField = find.widgetWithText(TextField, 'Medicine Name');
    await tester.enterText(nameField, 'Custom Syrup Multi-Action');
    await tester.pumpAndSettle();

    // Tap Add & Done
    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();

    // Prescriptions should now have 2 items
    expect(prescriptions.length, equals(2));
    expect(prescriptions.any((m) => m['name'] == 'Custom Syrup Multi-Action'), isTrue);
    expect(find.textContaining('Custom Syrup Multi-Action'), findsWidgets);

    // 5. Open dialog again and add another Custom Medicine with "Add & Keep Browsing"
    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Custom Medicine'));
    await tester.pumpAndSettle();

    final nameField2 = find.widgetWithText(TextField, 'Medicine Name');
    await tester.enterText(nameField2, 'Custom Vitamin D Drops');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();

    // Still in selection dialog
    expect(find.text('Select Prescription Medicine'), findsOneWidget);
    // Tap "Done (3)" at bottom
    final done3Btn = find.textContaining('Done (3)');
    expect(done3Btn, findsOneWidget);
    await tester.tap(done3Btn);
    await tester.pumpAndSettle();

    // Prescriptions should now have 3 items
    expect(prescriptions.length, equals(3));
    expect(prescriptions.any((m) => m['name'] == 'Custom Vitamin D Drops'), isTrue);
    expect(find.textContaining('Custom Vitamin D Drops'), findsWidgets);
  });
}
