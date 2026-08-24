import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/zkteco_network_service.dart';
import 'package:gmwf/models/biometric_credential.dart';
import 'package:gmwf/services/finance_local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('zkteco_test_hive_');
    Hive.init(tempDir.path);

    await LocalStorageService.openBoxSafe(LocalStorageService.attendanceBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.biometricCredentialsBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.biometricDevicesBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.crossBranchPunchesBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.unmappedPunchesBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.schoolLogsBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.madrassaLogsBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.employeesBox);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Employee punch records check-in and check-out in attendanceBox', () async {
    final now = DateTime(2026, 8, 21, 8, 30);
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    const empId = 'EMP_TEST_001';
    const pin = '101';

    // Register credential
    await ZkTecoNetworkService.registerBiometricCredential(BiometricCredential(
      id: 'cred_1',
      biometricPin: pin,
      entityId: empId,
      entityName: 'John Doe',
      entityType: 'employee',
      branchId: 'main_branch',
      enrolledAt: DateTime.now(),
    ));

    // 1. First scan -> Check-In
    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: now,
      deviceIp: '192.168.1.150',
      source: 'zkteco_test',
    );

    final box = Hive.box(LocalStorageService.attendanceBox);
    final rec = box.get('${empId}_$dateStr');
    expect(rec, isNotNull);
    expect(rec['status'], 'present');
    expect(rec['checkInTime'], DateFormat('hh:mm a').format(now));
    expect(rec['checkOutTime'], isNull);

    // 2. Second scan 6 hours later -> Check-Out
    final checkoutTime = now.add(const Duration(hours: 6));
    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: checkoutTime,
      deviceIp: '192.168.1.150',
      source: 'zkteco_test',
    );

    final updatedRec = box.get('${empId}_$dateStr');
    expect(updatedRec['status'], 'present');
    expect(updatedRec['checkInTime'], DateFormat('hh:mm a').format(now));
    expect(updatedRec['checkOutTime'], DateFormat('hh:mm a').format(checkoutTime));
    expect(updatedRec['departureTime'], DateFormat('hh:mm a').format(checkoutTime));
  });

  test('School Teacher punch updates school teacher log', () async {
    final now = DateTime(2026, 8, 21, 7, 45);
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    const teacherId = 'TCH_TEST_001';
    const pin = '201';
    const branchId = 'school_branch';

    await ZkTecoNetworkService.registerBiometricCredential(BiometricCredential(
      id: 'cred_2',
      biometricPin: pin,
      entityId: teacherId,
      entityName: 'Professor Smith',
      entityType: 'teacher',
      branchId: branchId,
      enrolledAt: DateTime.now(),
    ));

    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: now,
      deviceIp: '192.168.1.153',
      source: 'zkteco_test',
    );

    final schoolBox = Hive.box(LocalStorageService.schoolLogsBox);
    final tchLog = schoolBox.get('${branchId}__tchlog__$dateStr');
    expect(tchLog, isNotNull);
    final entries = tchLog['entries'] as Map;
    expect(entries[teacherId], isNotNull);
    expect(entries[teacherId]['status'], 'present');
    expect(entries[teacherId]['time'], DateFormat('hh:mm a').format(now));
  });

  test('Madrassa Student punch updates Madrassa daily log entries map', () async {
    final now = DateTime(2026, 8, 21, 6, 0);
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    const studentId = 'MAD_ST_001';
    const pin = '301';
    const branchId = 'madrassa_branch';

    await ZkTecoNetworkService.registerBiometricCredential(BiometricCredential(
      id: 'cred_3',
      biometricPin: pin,
      entityId: studentId,
      entityName: 'Ali Khan',
      entityType: 'madrassa_student',
      branchId: branchId,
      enrolledAt: DateTime.now(),
    ));

    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: now,
      deviceIp: '192.168.1.152',
      source: 'zkteco_test',
    );

    final madBox = Hive.box(LocalStorageService.madrassaLogsBox);
    final madLog = madBox.get('${branchId}__log__$dateStr');
    expect(madLog, isNotNull);
    expect(madLog[studentId], isNotNull);
    expect(madLog[studentId]['status'], 'P');
    expect(madLog[studentId]['attendance'], 'present');
  });

  test('School Student punch updates School daily log document entries map', () async {
    final now = DateTime(2026, 8, 21, 8, 0);
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    const studentId = 'SCH_ST_001';
    const pin = '401';
    const branchId = 'school_branch';

    await ZkTecoNetworkService.registerBiometricCredential(BiometricCredential(
      id: 'cred_4',
      biometricPin: pin,
      entityId: studentId,
      entityName: 'Zain Ahmed',
      entityType: 'school_student',
      branchId: branchId,
      enrolledAt: DateTime.now(),
    ));

    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: now,
      deviceIp: '192.168.1.153',
      source: 'zkteco_test',
    );

    final schBox = Hive.box(LocalStorageService.schoolLogsBox);
    final schLog = schBox.get('${branchId}__log__$dateStr');
    expect(schLog, isNotNull);
    final entries = schLog['entries'] as Map;
    expect(entries[studentId], isNotNull);
    expect(entries[studentId]['status'], 'present');
  });
}
