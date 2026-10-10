import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/master_proforma_service.dart';
import 'package:gmwf/pages/dispensary/doctor/doctor_right_panel.dart';
import 'package:gmwf/pages/dispensary/dispensar/patient_form.dart';
import 'package:gmwf/pages/dispensary/dispensar/patient_form_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('doc_temp_flow_test');
    Hive.init(tempDir.path);
    final stockBox = await Hive.openBox(LocalStorageService.stockBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox('app_settings');
    await Hive.openBox(MasterProformaService.boxName);

    // Seed stock for jalalpurjattan matching real database
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
      'quantity': 10.0,
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

  testWidgets('Doctor (doc account) tests medicine selection & custom medicine flow', (WidgetTester tester) async {
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
            onRemoveMedicine: (idx) => prescriptions.removeAt(idx),
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

    // 1. Open "Search & Select Medicines..." modal
    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();
    expect(find.text('Select Prescription Medicine'), findsOneWidget);

    // 2. Select stock medicine Paracetamol
    await tester.tap(find.text('Paracetamol (Panadol)').first);
    await tester.pumpAndSettle();

    // In Add Inventory Medicine dialog, click "Add & Keep Browsing"
    expect(find.text('Add Inventory Medicine'), findsOneWidget);
    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();

    // Dialog stays open, Selected Medicines tray shows 1 medicine
    expect(find.text('Selected Medicines (1)'), findsOneWidget);
    expect(find.textContaining('Paracetamol (Panadol)'), findsWidgets);

    // 3. Add Custom Medicine while inside dialog
    await tester.tap(find.text('Add Custom Medicine'));
    await tester.pumpAndSettle();

    expect(find.text('Add Custom Medicine'), findsNWidgets(2));
    final nameField = find.widgetWithText(TextField, 'Medicine Name');
    await tester.enterText(nameField, 'Custom Cough Expectorant');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();

    // Selected Medicines tray now shows 2 medicines: Paracetamol and Custom Cough Expectorant!
    expect(find.text('Selected Medicines (2)'), findsOneWidget);
    expect(find.textContaining('Custom Cough Expectorant'), findsWidgets);

    // 4. Click "Done (2)" to close selection modal
    final done2Btn = find.textContaining('Done (2)');
    expect(done2Btn, findsOneWidget);
    await tester.tap(done2Btn);
    await tester.pumpAndSettle();

    // 5. Back on DoctorRightPanel: Both medicines are present!
    expect(prescriptions.length, equals(2));
    expect(find.text('Inventory Medicines'), findsOneWidget);
    expect(find.text('Custom Medicines'), findsOneWidget);
    expect(find.textContaining('Custom Cough Expectorant'), findsOneWidget);

    // 6. Test "+ Custom" shortcut button directly on right panel
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.text('Add Custom Medicine'), findsOneWidget);

    final nameFieldDirect = find.widgetWithText(TextField, 'Medicine Name');
    await tester.enterText(nameFieldDirect, 'Custom Ointment Derm');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();

    // Now prescriptions has 3 medicines!
    expect(prescriptions.length, equals(3));
    expect(find.textContaining('Custom Ointment Derm'), findsOneWidget);
  });

  testWidgets('Dispenser (temp account) properly displays and formats custom medicines', (WidgetTester tester) async {
    final prescriptions = [
      {
        'name': 'Paracetamol (Panadol)',
        'type': 'Tablet',
        'dose': '500 mg',
        'timing': '1+0+1',
        'quantity': 6,
        'inventoryId': 'panadol--tablet--500-mg--2027-08-12',
      },
      {
        'name': 'Custom Cough Expectorant',
        'type': 'Syrup',
        'timing': '1+1+1',
        'quantity': 1,
        'inventoryId': null,
      },
      {
        'name': 'Custom Inj Neurobion',
        'type': 'Injection',
        'quantity': 2,
        'inventoryId': null,
      },
    ];

    // Helper functions classification
    expect(PatientFormHelper.isInventoryMed(prescriptions[0]), isTrue);
    expect(PatientFormHelper.isInventoryMed(prescriptions[1]), isFalse);
    expect(PatientFormHelper.isInventoryMed(prescriptions[2]), isFalse);

    expect(PatientFormHelper.isInjectable(prescriptions[0]), isFalse);
    expect(PatientFormHelper.isInjectable(prescriptions[1]), isFalse);
    expect(PatientFormHelper.isInjectable(prescriptions[2]), isTrue);

    // Test print slip generation with custom items
    final slip = await PatientFormHelper.generatePrintSlip(
      data: {
        'prescriptions': prescriptions,
        'labResults': [],
      },
      branchName: 'Jalalpur Jattan',
    );
    expect(slip.isNotEmpty, isTrue);
  });
}
