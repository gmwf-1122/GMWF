import 'package:cloud_firestore/cloud_firestore.dart';
import 'madrassa_config.dart';

class MadrassaFeeLogic {
  static Map<String, dynamic> calculateStudentFee({
    required String studentId,
    required Map<String, dynamic> studentData,
    required List<QueryDocumentSnapshot> logs,
    required MadrassaConfig config,
    required int totalWorkingDays,
  }) {
    int presentDays = 0;
    int leaveDays = 0;
    int uniformDays = 0;
    int messageDays = 0;
    bool ptmAttended = false;

    for (var doc in logs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final sLog = data[studentId] as Map<String, dynamic>?;
      if (sLog != null) {
        if (sLog['attendance'] == 'present') presentDays++;
        if (sLog['attendance'] == 'leave') leaveDays++;
        if (sLog['uniform'] == true) uniformDays++;
        if (sLog['parentReplied'] == true) messageDays++;
        if (sLog['ptm'] == true) ptmAttended = true;
      }
    }

    final activeWorkingDays = _calculateActiveWorkingDays(
      studentData: studentData,
      year: config.year,
      month: config.month,
    );

    double proRatedBaseFee = totalWorkingDays > 0
        ? (activeWorkingDays / totalWorkingDays) * config.baseFee
        : 0;

    double attSavings = totalWorkingDays > 0
        ? ((presentDays + leaveDays) / totalWorkingDays) *
            config.attendanceMaxDeduction
        : 0;
    double uniSavings = totalWorkingDays > 0
        ? (uniformDays / totalWorkingDays) * config.uniformMaxDeduction
        : 0;
    double msgSavings = totalWorkingDays > 0
        ? (messageDays / totalWorkingDays) * config.messageTotalDeduction
        : 0;
    double ptmSavings = ptmAttended ? config.ptmDeduction : 0;

    double totalSavings = attSavings + uniSavings + msgSavings + ptmSavings;
    double amountDue = (proRatedBaseFee - totalSavings).clamp(0, double.infinity);

    return {
      'present': presentDays,
      'leave': leaveDays,
      'absent': activeWorkingDays - (presentDays + leaveDays),
      'uniform': uniformDays,
      'message': messageDays,
      'ptm': ptmAttended,
      'attSavings': attSavings,
      'uniSavings': uniSavings,
      'msgSavings': msgSavings,
      'ptmSavings': ptmSavings,
      'totalSavings': totalSavings,
      'amountDue': amountDue,
      'activeWorkingDays': activeWorkingDays,
      'proRatedBaseFee': proRatedBaseFee,
    };
  }

  static int _calculateActiveWorkingDays({
    required Map<String, dynamic> studentData,
    required int year,
    required int month,
  }) {
    final joinDate = (studentData['joinDate'] as Timestamp?)?.toDate() ??
        DateTime(year, month, 1);
    final auditLog = List<Map<String, dynamic>>.from(studentData['auditLog'] ?? []);

    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 0);

    int activeCount = 0;
    DateTime date = monthStart;
    while (date.isBefore(monthEnd) || date.isAtSameMomentAs(monthEnd)) {
      if (date.weekday != DateTime.sunday) {
        if (_isStudentActiveOnDate(date, joinDate, auditLog)) {
          activeCount++;
        }
      }
      date = date.add(const Duration(days: 1));
    }
    return activeCount;
  }

  static bool _isStudentActiveOnDate(
    DateTime date,
    DateTime joinDate,
    List<Map<String, dynamic>> auditLog,
  ) {
    if (date.isBefore(DateTime(joinDate.year, joinDate.month, joinDate.day))) {
      return false;
    }
    final sortedLog = [...auditLog]..sort((a, b) =>
        (b['date'] as Timestamp).compareTo(a['date'] as Timestamp));

    for (var entry in sortedLog) {
      final entryDate = (entry['date'] as Timestamp).toDate();
      if (date.isAfter(entryDate) ||
          (date.year == entryDate.year &&
              date.month == entryDate.month &&
              date.day == entryDate.day)) {
        return entry['status'] == 'active';
      }
    }
    return true;
  }

  static int getWorkingDaysCount(int year, int month) {
    int count = 0;
    DateTime date = DateTime(year, month, 1);
    while (date.month == month) {
      if (date.weekday != DateTime.sunday) count++;
      date = date.add(const Duration(days: 1));
    }
    return count;
  }
}
