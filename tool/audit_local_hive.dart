import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_hive_audit');
  if (tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }
  tempDir.createSync(recursive: true);

  // Copy .hive files to temp dir to avoid lock conflicts
  for (final file in hiveSourceDir.listSync()) {
    if (file is File && file.path.endsWith('.hive')) {
      final destPath = '${tempDir.path}\\${file.uri.pathSegments.last}';
      file.copySync(destPath);
    }
  }

  Hive.init(tempDir.path);

  print('=== 📦 LOCAL HIVE DATA AUDIT ===\n');

  // 1. Audit Patients Box
  print('--- 1. PATIENTS (local_patients) ---');
  try {
    final box = await Hive.openBox('local_patients');
    print('Total Patient Records: ${box.length}');
    final Map<String, int> queueTypes = {};
    int countGeneral = 0;
    int countGmwf = 0;
    int countZakat = 0;
    int countNonZakat = 0;
    int countNull = 0;

    for (var key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        final qt = (raw['queueType'] ?? raw['category'] ?? raw['status'] ?? 'NULL').toString().toLowerCase();
        queueTypes[qt] = (queueTypes[qt] ?? 0) + 1;
        if (qt.contains('general')) countGeneral++;
        if (qt.contains('gmwf') || qt.contains('gm-wf') || qt.contains('gm_wf')) countGmwf++;
        if (qt == 'zakat') countZakat++;
        if (qt.contains('non')) countNonZakat++;
        if (qt == 'null') countNull++;
      }
    }
    print('Detailed Queue/Category/Status field distribution: $queueTypes');
    print('  -> Showing "general": $countGeneral');
    print('  -> Showing "gmwf": $countGmwf');
    print('  -> Showing "zakat": $countZakat');
    print('  -> Showing "non-zakat": $countNonZakat');
    print('  -> NULL / Unset: $countNull');
  } catch (e) {
    print('Error reading local_patients: $e');
  }

  // 2. Audit Entries (Tokens / Queue Serials)
  print('\n--- 2. ENTRIES / TOKENS / SERIALS (local_entries) ---');
  try {
    final box = await Hive.openBox('local_entries');
    print('Total Entry Records: ${box.length}');
    final Map<String, int> queueTypes = {};
    final Map<String, int> queueFieldOnly = {};
    int countGeneral = 0;
    int countGmwf = 0;
    int countZakat = 0;
    int countNonZakat = 0;
    int countNull = 0;
    final samples = <String, Map<String, dynamic>>{};

    for (var key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        final explicitQt = raw['queueType']?.toString().toLowerCase() ?? 'NONE';
        queueFieldOnly[explicitQt] = (queueFieldOnly[explicitQt] ?? 0) + 1;

        final qt = (raw['queueType'] ?? raw['category'] ?? raw['status'] ?? 'NULL').toString().toLowerCase();
        queueTypes[qt] = (queueTypes[qt] ?? 0) + 1;
        if (qt.contains('general')) {
          countGeneral++;
          if (samples.length < 3) samples['general_$key'] = Map<String, dynamic>.from(raw);
        }
        if (qt.contains('gmwf') || qt.contains('gm-wf') || qt.contains('gm_wf')) countGmwf++;
        if (qt == 'zakat') countZakat++;
        if (qt.contains('non')) countNonZakat++;
        if (qt == 'null') countNull++;
      }
    }
    print('Explicit "queueType" field only: $queueFieldOnly');
    print('Resolved (queueType / category / status): $queueTypes');
    print('  -> Showing "general": $countGeneral');
    print('  -> Showing "gmwf": $countGmwf');
    print('  -> Showing "zakat": $countZakat');
    print('  -> Showing "non-zakat": $countNonZakat');
    print('  -> NULL / Unset: $countNull');
    if (samples.isNotEmpty) {
      print('\nSamples of records with "general":');
      for (var entry in samples.entries) {
        print('  ${entry.key}: serial=${entry.value['serial']}, patientName=${entry.value['patientName']}, dateKey=${entry.value['dateKey']}, queueType=${entry.value['queueType']}, category=${entry.value['category']}');
      }
    }
  } catch (e) {
    print('Error reading local_entries: $e');
  }

  // 3. Audit Dispensary
  print('\n--- 3. DISPENSARY (local_dispensary) ---');
  try {
    final box = await Hive.openBox('local_dispensary');
    print('Total Dispensary Records: ${box.length}');
    final Map<String, int> queueTypes = {};
    for (var key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        final qt = (raw['queueType'] ?? raw['category'] ?? raw['status'] ?? 'NULL').toString().toLowerCase();
        queueTypes[qt] = (queueTypes[qt] ?? 0) + 1;
      }
    }
    print('Queue distribution: $queueTypes');
  } catch (e) {
    print('Error reading local_dispensary: $e');
  }

  // 4. Audit Sync Queue
  print('\n--- 4. SYNC QUEUE (sync_queue / server_sync_queue) ---');
  try {
    final box = await Hive.openBox('sync_queue');
    print('Total Items in sync_queue: ${box.length}');
  } catch (e) {
    print('Error reading sync_queue: $e');
  }

  // Clean up temp
  await Hive.close();
  try {
    tempDir.deleteSync(recursive: true);
  } catch (_) {}

  print('\n=== ✅ AUDIT FINISHED ===');
}
