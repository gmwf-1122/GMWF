import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  group('Dual-Lane Priority Queue Logic & Ordering Verification', () {
    final todayKey = DateFormat('ddMMyy').format(DateTime.now());
    final todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());

    bool isBacklogItem(Map item) {
      if (item['backlog'] == true) return true;

      final createdStr = (item['createdAt'] ?? item['enqueuedAt'])?.toString();
      if (createdStr != null && createdStr.isNotEmpty) {
        final created = DateTime.tryParse(createdStr);
        if (created != null && DateTime.now().difference(created).inHours.abs() >= 24) {
          return true;
        }
      }

      final serial = (item['serial'] ?? (item['data'] is Map ? item['data']['serial'] : null))?.toString().trim();
      if (serial != null && serial.isNotEmpty) {
        if (serial.length >= 6) {
          final prefix = serial.substring(0, 6);
          if (RegExp(r'^\d{6}$').hasMatch(prefix) && prefix != todayKey) {
            return true;
          }
        }
      }

      final dateKey = (item['dateKey'] ?? item['date'] ?? (item['data'] is Map ? (item['data']['dateKey'] ?? item['data']['date']) : null))?.toString().trim();
      if (dateKey != null && dateKey.isNotEmpty) {
        if (dateKey.length == 6 && RegExp(r'^\d{6}$').hasMatch(dateKey)) {
          if (dateKey != todayKey) return true;
        } else if (dateKey.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(dateKey)) {
          if (!dateKey.startsWith(todayIso)) return true;
        }
      }

      return false;
    }

    int actionPrecedence(Map action) {
      final type = (action['type'] ?? '').toString();
      switch (type) {
        case 'save_patient':
          return 1;
        case 'save_entry':
          return 2;
        case 'save_prescription':
          return 3;
        case 'update_serial_status':
          return 4;
        case 'update_inventory':
        case 'add_inventory_stock':
          return 5;
        case 'save_donation':
          return 6;
        case 'save_attendance_record':
        case 'save_attendance':
        case 'save_employee_attendance':
          return 7;
        default:
          return 10;
      }
    }

    int compareSyncActions(Map a, Map b) {
      final precA = actionPrecedence(a);
      final precB = actionPrecedence(b);
      if (precA != precB) return precA.compareTo(precB);

      final timeA = (a['createdAt'] ?? a['enqueuedAt'] ?? '') as String;
      final timeB = (b['createdAt'] ?? b['enqueuedAt'] ?? '') as String;
      if (timeA.isNotEmpty && timeB.isNotEmpty) {
        final cmp = timeA.compareTo(timeB);
        if (cmp != 0) return cmp;
      }
      return 0;
    }

    test('1. Accurately categorizes Express Lane (live today) vs Freight Lane (backlog)', () {
      final liveToken = {
        'type': 'save_entry',
        'serial': '${todayKey}M-SADD-001',
        'createdAt': DateTime.now().toIso8601String(),
      };
      final livePatient = {
        'type': 'save_patient',
        'id': '42101-1234567-1',
        'createdAt': DateTime.now().toIso8601String(),
      };
      final oldBacklogAttendance = {
        'type': 'save_attendance_record',
        'createdAt': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
      };
      final pastDateSerial = {
        'type': 'save_entry',
        'serial': '101026E-SADD-001', // different date
        'createdAt': DateTime.now().toIso8601String(),
      };
      final sweepMarkedBacklog = {
        'type': 'save_patient',
        'backlog': true,
        'createdAt': DateTime.now().toIso8601String(),
      };

      expect(isBacklogItem(liveToken), isFalse, reason: 'Today serial must be Express');
      expect(isBacklogItem(livePatient), isFalse, reason: 'Today patient must be Express');
      expect(isBacklogItem(oldBacklogAttendance), isTrue, reason: '>24h must be Freight/Backlog');
      expect(isBacklogItem(pastDateSerial), isTrue, reason: 'Past serial date must be Freight/Backlog');
      expect(isBacklogItem(sweepMarkedBacklog), isTrue, reason: 'Explicit backlog must be Freight');
    });

    test('2. Causal Entity Precedence guarantees Patient -> Entry -> Prescription -> Dispense ordering', () {
      final actions = [
        {'type': 'update_serial_status', 'serial': '${todayKey}M-SADD-001', 'createdAt': '2026-10-14T10:15:00'},
        {'type': 'save_prescription', 'serial': '${todayKey}M-SADD-001', 'createdAt': '2026-10-14T10:10:00'},
        {'type': 'save_entry', 'serial': '${todayKey}M-SADD-001', 'createdAt': '2026-10-14T10:05:00'},
        {'type': 'save_patient', 'id': '42101-1234567-1', 'createdAt': '2026-10-14T10:00:00'},
      ];

      actions.sort(compareSyncActions);

      expect(actions[0]['type'], equals('save_patient'), reason: 'Patient must be first');
      expect(actions[1]['type'], equals('save_entry'), reason: 'Token entry must be second');
      expect(actions[2]['type'], equals('save_prescription'), reason: 'Prescription must be third');
      expect(actions[3]['type'], equals('update_serial_status'), reason: 'Dispense status must be fourth');
    });

    test('3. FIFO within same entity type preserves state transition order', () {
      final punches = [
        {'type': 'save_attendance_record', 'punchSequence': 2, 'createdAt': '2026-10-14T14:00:00'},
        {'type': 'save_attendance_record', 'punchSequence': 1, 'createdAt': '2026-10-14T09:00:00'},
      ];

      punches.sort(compareSyncActions);

      expect(punches[0]['punchSequence'], equals(1), reason: 'Morning check-in must precede afternoon check-out');
      expect(punches[1]['punchSequence'], equals(2));
    });

    test('4. Dual-Lane 80/20 Scheduler prioritizes Live items while steadily draining Backlog', () {
      // 100 live items, 50 backlog items
      final liveList = List.generate(100, (i) => 'live_$i');
      final backlogList = List.generate(50, (i) => 'backlog_$i');

      const maxBatchSize = 100;
      final expressCount = liveList.length > 80 ? 80 : liveList.length;
      final remainingCapacity = maxBatchSize - expressCount;
      final freightCount = backlogList.length > remainingCapacity ? remainingCapacity : backlogList.length;

      final batch = <String>[];
      batch.addAll(liveList.take(expressCount));
      batch.addAll(backlogList.take(freightCount));

      expect(batch.length, equals(100));
      expect(batch.where((k) => k.startsWith('live_')).length, equals(80), reason: 'Express gets 80 slots');
      expect(batch.where((k) => k.startsWith('backlog_')).length, equals(20), reason: 'Freight gets 20 slots');
    });

    test('5. Dynamic capacity shifts to 100% when one lane has fewer items', () {
      // Only 5 live items, but 100 backlog items
      final liveList = List.generate(5, (i) => 'live_$i');
      final backlogList = List.generate(100, (i) => 'backlog_$i');

      const maxBatchSize = 100;
      final expressCount = liveList.length > 80 ? 80 : liveList.length;
      final remainingCapacity = maxBatchSize - expressCount;
      final freightCount = backlogList.length > remainingCapacity ? remainingCapacity : backlogList.length;

      final batch = <String>[];
      batch.addAll(liveList.take(expressCount));
      batch.addAll(backlogList.take(freightCount));

      expect(batch.length, equals(100));
      expect(batch.where((k) => k.startsWith('live_')).length, equals(5), reason: 'All 5 live items taken');
      expect(batch.where((k) => k.startsWith('backlog_')).length, equals(95), reason: 'Remaining 95 slots used for backlog');
    });
  });
}
