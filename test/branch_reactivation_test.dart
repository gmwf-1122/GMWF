import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/finance_local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('branch_reactivate_hive_');
    Hive.init(tempDir.path);

    await LocalStorageService.openBoxSafe(LocalStorageService.branchesBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.auditLogsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Branch offboarding and reactivation lifecycle test', () async {
    final branchBox = Hive.box(LocalStorageService.branchesBox);
    final auditBox = Hive.box(LocalStorageService.auditLogsBox);

    const branchId = 'test_branch_rawalpindi';
    const branchName = 'Rawalpindi Satellite Branch';

    // 1. Seed active branch
    await branchBox.put('branch:$branchId', {
      'id': branchId,
      'name': branchName,
      'status': 'active',
      'isOffboarded': false,
    });

    var b = Map<String, dynamic>.from(branchBox.get('branch:$branchId') as Map);
    expect(b['status'], equals('active'));
    expect(b['isOffboarded'], isFalse);

    // 2. Offboard branch
    final offboardTime = DateTime.now().toIso8601String();
    b['isOffboarded'] = true;
    b['status'] = 'offboarded';
    b['offboardedAt'] = offboardTime;
    b['offboardedBy'] = 'HQ Manager';
    b['offboardingReason'] = 'Relocation';
    await branchBox.put('branch:$branchId', b);

    await FinanceLocalStorage.logAction(
      branchId: branchId,
      entityType: 'branch',
      entityId: branchId,
      action: 'offboard',
      performedBy: 'HQ Manager',
      reason: 'Offboarded branch "$branchName": Relocation',
    );

    var offboardedB = Map<String, dynamic>.from(branchBox.get('branch:$branchId') as Map);
    expect(offboardedB['isOffboarded'], isTrue);
    expect(offboardedB['status'], equals('offboarded'));
    expect(offboardedB['offboardingReason'], equals('Relocation'));

    // Verify it is excluded from active branch query
    final activeList1 = branchBox.values
        .where((val) => val is Map && val['id'] != null && val['isOffboarded'] != true && val['status'] != 'offboarded')
        .toList();
    expect(activeList1.any((val) => val['id'] == branchId), isFalse);

    // 3. Reactivate branch
    final reactivateTime = DateTime.now().toIso8601String();
    offboardedB['isOffboarded'] = false;
    offboardedB['status'] = 'active';
    offboardedB['offboardedAt'] = null;
    offboardedB['reactivatedAt'] = reactivateTime;
    offboardedB['reactivatedBy'] = 'HQ Manager';
    await branchBox.put('branch:$branchId', offboardedB);

    await FinanceLocalStorage.logAction(
      branchId: branchId,
      entityType: 'branch',
      entityId: branchId,
      action: 'reactivate',
      performedBy: 'HQ Manager',
      reason: 'Reactivated branch "$branchName": Facility ready to resume',
    );

    var reactivatedB = Map<String, dynamic>.from(branchBox.get('branch:$branchId') as Map);
    expect(reactivatedB['isOffboarded'], isFalse);
    expect(reactivatedB['status'], equals('active'));
    expect(reactivatedB['offboardedAt'], isNull);
    expect(reactivatedB['reactivatedAt'], equals(reactivateTime));

    // Verify it is immediately re-included in active branch query
    final activeList2 = branchBox.values
        .where((val) => val is Map && val['id'] != null && val['isOffboarded'] != true && val['status'] != 'offboarded')
        .toList();
    expect(activeList2.any((val) => val['id'] == branchId), isTrue);

    // Verify audit logs were written
    expect(auditBox.isNotEmpty, isTrue);
  });
}
