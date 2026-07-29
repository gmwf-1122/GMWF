import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/finance_local_storage.dart';
import 'package:gmwf/services/local_storage_service.dart';

void main() {
  setUpAll(() async {
    // Initialize Hive with a temporary directory
    final tempDir = Directory.systemTemp.createTempSync();
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.financeHolidaysBox);
    await Hive.openBox(LocalStorageService.branchesBox);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    await Hive.box(LocalStorageService.financeHolidaysBox).clear();
    await Hive.box(LocalStorageService.branchesBox).clear();
  });

  test('isHoliday matches holiday date, branch, and department scope correctly', () async {
    final holidaysBox = Hive.box(LocalStorageService.financeHolidaysBox);

    // Save a holiday under Rawalpindi and Islamabad branch contexts
    final holidayData = {
      'id': 'eid1',
      'name': 'Eid Holiday',
      'date': '2026-07-02',
      'branches': ['all'],
      'departments': ['all'],
      'exceptions': [
        {'branchId': 'all', 'department': 'Office'},
        {'branchId': 'islamabad', 'department': 'Kitchen'},
      ],
    };

    await holidaysBox.put('rawalpindi__hol__eid1', holidayData);
    await holidaysBox.put('islamabad__hol__eid1', holidayData);

    // Case 1: Holiday applies to Dispensary in rawalpindi
    final case1 = FinanceLocalStorage.isHoliday(
      branchId: 'rawalpindi',
      department: 'Dispensary',
      dateStr: '2026-07-02',
    );
    expect(case1, isTrue);

    // Case 2: Holiday is excepted (excluded) for Office in rawalpindi
    final case2 = FinanceLocalStorage.isHoliday(
      branchId: 'rawalpindi',
      department: 'Office',
      dateStr: '2026-07-02',
    );
    expect(case2, isFalse);

    // Case 3: Holiday is excepted (excluded) for Kitchen in islamabad
    final case3 = FinanceLocalStorage.isHoliday(
      branchId: 'islamabad',
      department: 'Kitchen',
      dateStr: '2026-07-02',
    );
    expect(case3, isFalse);

    // Case 4: Non-matching date should be false
    final case4 = FinanceLocalStorage.isHoliday(
      branchId: 'rawalpindi',
      department: 'Dispensary',
      dateStr: '2026-07-03',
    );
    expect(case4, isFalse);
  });
}
