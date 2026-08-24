import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/zkteco_network_service.dart';
import 'package:gmwf/models/biometric_credential.dart';
import 'package:gmwf/models/biometric_device_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('multi_shift_test_hive_');
    Hive.init(tempDir.path);

    await LocalStorageService.openBoxSafe(LocalStorageService.attendanceBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.biometricCredentialsBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.biometricDevicesBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.crossBranchPunchesBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.unmappedPunchesBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.employeesBox);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Employee working 2 shifts in same branch records distinct morning and evening shifts', () async {
    final morningIn = DateTime(2026, 8, 22, 8, 30);
    final morningOut = DateTime(2026, 8, 22, 13, 30);
    final eveningIn = DateTime(2026, 8, 22, 16, 30);
    final eveningOut = DateTime(2026, 8, 22, 21, 30);
    final dateStr = DateFormat('yyyy-MM-dd').format(morningIn);

    const empId = 'EMP_DUAL_SHIFT_001';
    const pin = '888';

    await ZkTecoNetworkService.registerBiometricCredential(BiometricCredential(
      id: 'cred_multi_1',
      biometricPin: pin,
      entityId: empId,
      entityName: 'Dr. Multi Shift',
      entityType: 'employee',
      branchId: 'gujrat',
      enrolledAt: DateTime.now(),
    ));

    // 1. Morning Shift Check-In
    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: morningIn,
      deviceIp: '192.168.1.150',
      source: 'zkteco_test',
    );

    final box = Hive.box(LocalStorageService.attendanceBox);
    var rec = box.get('${empId}_$dateStr');
    expect(rec, isNotNull);
    expect(rec['status'], 'present');
    expect(rec['checkInTime'], DateFormat('hh:mm a').format(morningIn));
    expect(rec['shifts'], isNotNull);
    expect(rec['shifts']['morning'], isNotNull);
    expect(rec['shifts']['morning']['checkInTime'], DateFormat('hh:mm a').format(morningIn));
    expect(rec['shifts']['morning']['checkOutTime'], isNull);

    // 2. Morning Shift Check-Out
    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: morningOut,
      deviceIp: '192.168.1.150',
      source: 'zkteco_test',
    );

    rec = box.get('${empId}_$dateStr');
    expect(rec['shifts']['morning']['checkOutTime'], DateFormat('hh:mm a').format(morningOut));

    // 3. Evening Shift Check-In
    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: eveningIn,
      deviceIp: '192.168.1.150',
      source: 'zkteco_test',
    );

    rec = box.get('${empId}_$dateStr');
    expect(rec['shifts']['evening'], isNotNull);
    expect(rec['shifts']['evening']['checkInTime'], DateFormat('hh:mm a').format(eveningIn));
    expect(rec['shifts']['evening']['checkOutTime'], isNull);
    // Morning shift is preserved intact!
    expect(rec['shifts']['morning']['checkInTime'], DateFormat('hh:mm a').format(morningIn));
    expect(rec['shifts']['morning']['checkOutTime'], DateFormat('hh:mm a').format(morningOut));

    // 4. Evening Shift Check-Out
    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: eveningOut,
      deviceIp: '192.168.1.150',
      source: 'zkteco_test',
    );

    rec = box.get('${empId}_$dateStr');
    expect(rec['shifts']['evening']['checkOutTime'], DateFormat('hh:mm a').format(eveningOut));
    // Overall Day Check-In should be earliest (morningIn) and Check-Out should be latest (eveningOut)
    expect(rec['checkInTime'], DateFormat('hh:mm a').format(morningIn));
    expect(rec['checkOutTime'], DateFormat('hh:mm a').format(eveningOut));
    expect(rec['status'], 'present');
  });

  test('Employee working across 2 separate branches/camps automatically authorizes and records both shifts', () async {
    final morningIn = DateTime(2026, 8, 22, 8, 45);
    final eveningIn = DateTime(2026, 8, 22, 17, 00);
    final dateStr = DateFormat('yyyy-MM-dd').format(morningIn);

    const empId = 'EMP_MULTI_BRANCH_002';
    const pin = '999';

    // Register employee profile with multiple assigned branches
    final empBox = Hive.box(LocalStorageService.employeesBox);
    await empBox.put(empId, {
      'id': empId,
      'name': 'Dr. Fatima',
      'branchId': 'karachi',
      'assignedBranches': ['karachi', 'sialkot'],
      'campSchedule': [
        {'branchId': 'karachi', 'campId': 'saddar', 'session': 'morning'},
        {'branchId': 'sialkot', 'campId': 'main', 'session': 'evening'},
      ],
    });

    // Register devices
    final devBox = Hive.box(LocalStorageService.biometricDevicesBox);
    await devBox.put('dev_saddar', BiometricDeviceConfig(
      deviceId: 'dev_saddar',
      deviceName: 'Saddar Scanner',
      buildingLocation: 'Saddar Dispensary',
      branchId: 'karachi',
      ipAddress: '192.168.1.160',
    ).toMap());

    await devBox.put('dev_sialkot', BiometricDeviceConfig(
      deviceId: 'dev_sialkot',
      deviceName: 'Sialkot Scanner',
      buildingLocation: 'Sialkot Main',
      branchId: 'sialkot',
      ipAddress: '192.168.1.161',
    ).toMap());

    await ZkTecoNetworkService.registerBiometricCredential(BiometricCredential(
      id: 'cred_multi_2',
      biometricPin: pin,
      entityId: empId,
      entityName: 'Dr. Fatima',
      entityType: 'employee',
      branchId: 'karachi',
      enrolledAt: DateTime.now(),
    ));

    // 1. Morning punch at Karachi Saddar scanner
    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: morningIn,
      deviceIp: '192.168.1.160',
      source: 'zkteco_test',
    );

    // 2. Evening punch at Sialkot scanner
    await ZkTecoNetworkService.processIncomingPunch(
      pin: pin,
      timestamp: eveningIn,
      deviceIp: '192.168.1.161',
      source: 'zkteco_test',
    );

    final box = Hive.box(LocalStorageService.attendanceBox);
    final rec = box.get('${empId}_$dateStr');
    expect(rec, isNotNull);
    expect(rec['shifts'], isNotNull);
    expect(rec['shifts']['morning'], isNotNull);
    expect(rec['shifts']['morning']['branchId'], 'karachi');
    expect(rec['shifts']['evening'], isNotNull);
    expect(rec['shifts']['evening']['branchId'], 'sialkot');

    // Verify no cross-branch pending locks were triggered
    final crossBox = Hive.box(LocalStorageService.crossBranchPunchesBox);
    final pendingForEmp = crossBox.values.where((p) => (p is Map) && p['entityId'] == empId && p['status'] == 'pending');
    expect(pendingForEmp.isEmpty, isTrue);
  });
}
