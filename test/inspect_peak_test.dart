import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/finance_local_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gmwf/firebase_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('inspect peak only', () async {
    final srcPath = r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive';
    final tempDir = Directory.systemTemp.createTempSync('hive_inspect_');
    Hive.init(tempDir.path);

    final eSrc = File('$srcPath\\local_entries.hive');
    if (eSrc.existsSync()) {
      eSrc.copySync('${tempDir.path}\\local_entries.hive');
    }
    final eBox = await Hive.openBox('local_entries');
    print('\n=== ENTRIES FOR 160926 (${eBox.length} total) ===');
    int e16 = 0;
    for (final key in eBox.keys) {
      final val = eBox.get(key);
      if (val is Map) {
        final dk = val['dateKey']?.toString();
        final dt = val['date']?.toString() ?? val['createdAt']?.toString();
        if (dk == '160926' || (dt != null && dt.contains('2026-09-16'))) {
          print('ENTRY 16-Sep: $val');
          e16++;
        }
      }
    }
    print('Total entries on 16-Sep in local_entries: $e16');

    final pSrc = File('$srcPath\\local_patients.hive');
    if (pSrc.existsSync()) {
      pSrc.copySync('${tempDir.path}\\local_patients.hive');
    }
    final pBox = await Hive.openBox('local_patients');
    print('\n=== PATIENTS BOX (${pBox.length} total) ===');
    int p16 = 0;
    for (final key in pBox.keys) {
      final val = pBox.get(key);
      if (val is Map) {
        final cd = val['createdAt']?.toString() ?? val['date']?.toString();
        if (cd != null && cd.contains('2026-09-16')) {
          p16++;
        }
      }
    }
    print('Total patients with createdAt 2026-09-16 in local_patients: $p16');

    Hive.init(tempDir.path);
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      final db = FirebaseFirestore.instance;

      print('\n=== FIRESTORE BRANCH DOCUMENTS ===');
      for (final bId in ['karachi', 'gujrat']) {
        final bDoc = await db.collection('branches').doc(bId).get();
        print('Branch $bId doc data: ${bDoc.data()}');

        final subCols = ['dispensary_summaries', 'daily_summaries', 'summaries', 'records', 'serials'];
        for (final sc in subCols) {
          try {
            final snap = await db.collection('branches').doc(bId).collection(sc).limit(10).get();
            if (snap.docs.isNotEmpty) {
              print('  Sub-collection branches/$bId/$sc has ${snap.docs.length} docs:');
              for (final d in snap.docs) {
                print('    Doc ${d.id} => ${d.data()}');
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      print('Firestore inspect error: $e');
    }
  });
}
