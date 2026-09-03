// test/madrassa_money_factor_toggle_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/pages/madrassa/models/madrassa_config.dart';
import 'package:gmwf/pages/madrassa/models/madrassa_fee_logic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_fee_toggle_test');
    Hive.init(tempDir.path);
    if (!Hive.isBoxOpen(LocalStorageService.branchesBox)) {
      await Hive.openBox(LocalStorageService.branchesBox);
    }
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Madrassa Money Factor (Fee Enable / Disable Toggle) Tests', () {
    test('LocalStorageService.isMadrassaFeeEnabled defaults to true for new or unset branches', () {
      expect(LocalStorageService.isMadrassaFeeEnabled('gujrat'), isTrue);
      expect(LocalStorageService.isMadrassaFeeEnabled('non_existent_branch'), isTrue);
    });

    test('LocalStorageService.isMadrassaFeeEnabled returns false when explicitly disabled', () async {
      final box = Hive.box(LocalStorageService.branchesBox);
      
      // Store branch with madrassaFeeEnabled: false
      await box.put('branch:gujrat', {
        'id': 'gujrat',
        'name': 'Gujrat Branch',
        'madrassaFeeEnabled': false,
        'sessionsConfig': {
          'madrassa': {
            'enableFees': false,
          },
        },
      });

      expect(LocalStorageService.isMadrassaFeeEnabled('gujrat'), isFalse);

      // Store branch with madrassaFeeEnabled: true
      await box.put('branch:sialkot', {
        'id': 'sialkot',
        'name': 'Sialkot Branch',
        'madrassaFeeEnabled': true,
        'sessionsConfig': {
          'madrassa': {
            'enableFees': true,
          },
        },
      });

      expect(LocalStorageService.isMadrassaFeeEnabled('sialkot'), isTrue);
    });

    test('MadrassaFeeLogic.calculateStudentFee behaves normally when enableFees is true', () {
      final config = MadrassaConfig(
        id: 'current',
        year: 2026,
        month: 8,
        baseFee: 3000,
        ptmDeduction: 700,
        messageTotalDeduction: 1300,
        attendanceMaxDeduction: 500,
        uniformMaxDeduction: 500,
        enableFees: true,
      );

      final studentData = {
        'id': 'student_1',
        'name': 'Ahmad Ali',
        'joinDate': '2026-08-01',
      };

      final logs = [
        {
          'student_1': {
            'attendance': 'present',
            'uniform': true,
            'parentReplied': true,
            'ptm': true,
          },
        },
      ];

      final fee = MadrassaFeeLogic.calculateStudentFee(
        studentId: 'student_1',
        studentData: studentData,
        logs: logs,
        config: config,
        totalWorkingDays: 20,
        holidays: [],
      );

      expect(fee['enableFees'], isTrue);
      expect(fee['proRatedBaseFee'], greaterThan(0));
      expect(fee['totalSavings'], greaterThan(0));
      expect(fee['amountDue'], isNotNull);
    });

    test('MadrassaFeeLogic.calculateStudentFee returns zero dues and zero savings when enableFees is false', () {
      final config = MadrassaConfig(
        id: 'current',
        year: 2026,
        month: 8,
        baseFee: 3000,
        ptmDeduction: 700,
        messageTotalDeduction: 1300,
        attendanceMaxDeduction: 500,
        uniformMaxDeduction: 500,
        enableFees: false, // Money factor removed
      );

      final studentData = {
        'id': 'student_1',
        'name': 'Ahmad Ali',
        'joinDate': '2026-08-01',
      };

      final logs = [
        {
          'student_1': {
            'attendance': 'present',
            'uniform': true,
            'parentReplied': true,
            'ptm': true,
          },
        },
      ];

      final fee = MadrassaFeeLogic.calculateStudentFee(
        studentId: 'student_1',
        studentData: studentData,
        logs: logs,
        config: config,
        totalWorkingDays: 20,
        holidays: [],
      );

      // Academic metrics still tracked
      expect(fee['present'], equals(1));
      expect(fee['uniform'], equals(1));
      expect(fee['message'], equals(1));
      expect(fee['ptm'], isTrue);

      // All financial values cleanly suppressed to 0.0
      expect(fee['enableFees'], isFalse);
      expect(fee['proRatedBaseFee'], equals(0.0));
      expect(fee['attSavings'], equals(0.0));
      expect(fee['uniSavings'], equals(0.0));
      expect(fee['msgSavings'], equals(0.0));
      expect(fee['ptmSavings'], equals(0.0));
      expect(fee['totalSavings'], equals(0.0));
      expect(fee['amountDue'], equals(0.0));
    });

    test('MadrassaConfig serialization maintains enableFees flag', () {
      final configTrue = MadrassaConfig(
        id: 'c1',
        year: 2026,
        month: 8,
        enableFees: true,
      );
      expect(configTrue.toMap()['enableFees'], isTrue);

      final configFalse = MadrassaConfig(
        id: 'c2',
        year: 2026,
        month: 8,
        enableFees: false,
      );
      expect(configFalse.toMap()['enableFees'], isFalse);
    });
  });
}
