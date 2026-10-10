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
    tempDir = await Directory.systemTemp.createTemp('repro_test');
    Hive.init(tempDir.path);
    final stockBox = await Hive.openBox(LocalStorageService.stockBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox('app_settings');
    await Hive.openBox(MasterProformaService.boxName);

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
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Exact Screenshot 1 & 2 repro', (WidgetTester tester) async {
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
              'gender': 'Male',
              'age': '24',
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

    // Open Search & Select Medicines
    await tester.tap(find.text('Search & Select Medicines...'));
    await tester.pumpAndSettle();

    // Now open Add Custom Medicine (Screenshot 1)
    await tester.tap(find.text('Add Custom Medicine'));
    await tester.pumpAndSettle();

    // Enter "1"
    final nameField = find.widgetWithText(TextField, 'Medicine Name');
    await tester.enterText(nameField, '1');
    await tester.pumpAndSettle();

    // Tap "0+1+0" chip
    await tester.tap(find.text('0+1+0'));
    await tester.pumpAndSettle();

    // Tap "Add & Done"
    print('Tapping Add & Done...');
    await tester.tap(find.text('Add & Done'));
    await tester.pumpAndSettle();

    print('Prescriptions length: ${prescriptions.length}');
    print('Prescriptions: $prescriptions');
    print('Is Select Prescription Medicine still visible? ${find.text('Select Prescription Medicine').evaluate().isNotEmpty}');
    print('Is Add Custom Medicine still visible? ${find.text('Add Custom Medicine').evaluate().isNotEmpty}');
  });
}
