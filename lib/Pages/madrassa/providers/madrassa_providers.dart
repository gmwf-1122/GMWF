import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils/madrassa_local_storage.dart';
import '../models/madrassa_config.dart';

// Selected Date Provider for the daily log (keyed by branchId)
final madrassaSelectedDateProvider = StateProvider.family<DateTime, String>((ref, branchId) => DateTime.now());

// Config Stream Provider
final madrassaConfigProvider = StreamProvider.family<MadrassaConfig, String>((ref, branchId) {
  return FirebaseFirestore.instance
      .collection('branches')
      .doc(branchId)
      .collection('madrassa_config')
      .doc('current')
      .snapshots()
      .map((s) => MadrassaConfig.fromFirestore(s));
});

// Students List Stream Provider (from Hive local storage)
final madrassaStudentsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, branchId) {
  return MadrassaLocalStorage.streamStudentsCached(branchId);
});

// Holidays List Stream Provider (from Hive local storage)
final madrassaHolidaysProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, branchId) {
  return MadrassaLocalStorage.streamHolidaysCached(branchId);
});

// Daily Log Stream Provider (from Hive local storage)
final madrassaDailyLogProvider = StreamProvider.family<Map<String, dynamic>, ({String branchId, String dateKey})>((ref, arg) {
  return MadrassaLocalStorage.streamLogCached(arg.branchId, arg.dateKey);
});

// Monthly Logs Stream Provider (from Hive local storage)
final madrassaMonthlyLogsProvider = StreamProvider.family<List<Map<String, dynamic>>, ({String branchId, int year, int month})>((ref, arg) {
  return MadrassaLocalStorage.streamLogsForMonthCached(arg.branchId, arg.year, arg.month);
});

// Filtered Students Provider for Daily Attendance Log (combines students roster, selected date, and log maps reactively)
final madrassaFilteredStudentsProvider = Provider.family<AsyncValue<List<Map<String, dynamic>>>, ({String branchId, DateTime selectedDate})>((ref, arg) {
  final studentsAsync = ref.watch(madrassaStudentsProvider(arg.branchId));
  final dateKey = DateFormat('yyyy-MM-dd').format(arg.selectedDate);
  final logAsync = ref.watch(madrassaDailyLogProvider((branchId: arg.branchId, dateKey: dateKey)));

  return studentsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (allStudents) {
      return logAsync.when(
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
        data: (activeLogData) {
          final endOfSelected = DateTime(
            arg.selectedDate.year,
            arg.selectedDate.month,
            arg.selectedDate.day,
            23, 59, 59, 999,
          );
          
          final filtered = allStudents.where((d) {
            final studentId = d['id'];
            if (studentId != null && activeLogData.containsKey(studentId)) {
              return true;
            }
            final statusVal = d['status'];
            final isActive = (statusVal == null || statusVal == '')
                ? (d['active'] == true)
                : (statusVal == 'active');
            
            final joinDateVal = d['joinDate'];
            DateTime? joinDateTime;
            if (joinDateVal is String) {
              joinDateTime = DateTime.tryParse(joinDateVal);
            } else if (joinDateVal is Timestamp) {
              joinDateTime = joinDateVal.toDate();
            }
            
            if (joinDateTime != null) {
              return isActive && !joinDateTime.isAfter(endOfSelected);
            }
            return isActive;
          }).toList();

          filtered.sort((a, b) {
            final aVal = int.tryParse(a['rollNumber']?.toString() ?? '') ?? 999999;
            final bVal = int.tryParse(b['rollNumber']?.toString() ?? '') ?? 999999;
            return aVal.compareTo(bVal);
          });

          return AsyncValue.data(filtered);
        },
      );
    },
  );
});
