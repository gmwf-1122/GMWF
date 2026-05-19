import 'package:cloud_firestore/cloud_firestore.dart';

class MadrassaConfig {
  final String id;
  final int year;
  final int month;

  final double baseFee;
  final double ptmDeduction;
  final double messageTotalDeduction;
  final double attendanceMaxDeduction;
  final double uniformMaxDeduction;
  final int ptmDay; // Day of the month (1-31)
  final List<Map<String, dynamic>> auditLog;

  MadrassaConfig({
    required this.id,
    required this.year,
    required this.month,
    this.baseFee = 3000,
    this.ptmDeduction = 700,
    this.messageTotalDeduction = 1300,
    this.attendanceMaxDeduction = 500,
    this.uniformMaxDeduction = 500,
    this.ptmDay = 0,
    this.auditLog = const [],
  });

  factory MadrassaConfig.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final now = DateTime.now();
    return MadrassaConfig(
      id: doc.id,
      year: data['year'] ?? now.year,
      month: data['month'] ?? now.month,
      baseFee: (data['baseFee'] ?? 3000).toDouble(),
      ptmDeduction: (data['ptmDeduction'] ?? 700).toDouble(),
      messageTotalDeduction: (data['messageTotalDeduction'] ?? 1300).toDouble(),
      attendanceMaxDeduction: (data['attendanceMaxDeduction'] ?? 500).toDouble(),
      uniformMaxDeduction: (data['uniformMaxDeduction'] ?? 500).toDouble(),
      ptmDay: data['ptmDay'] ?? 0,
      auditLog: List<Map<String, dynamic>>.from(data['auditLog'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'year': year,
      'month': month,
      'baseFee': baseFee,
      'ptmDeduction': ptmDeduction,
      'messageTotalDeduction': messageTotalDeduction,
      'attendanceMaxDeduction': attendanceMaxDeduction,
      'uniformMaxDeduction': uniformMaxDeduction,
      'ptmDay': ptmDay,
      'auditLog': auditLog,
    };
  }

  DateTime getPtmDate() {
    if (ptmDay > 0) return DateTime(year, month, ptmDay);
    // Find first Friday
    DateTime date = DateTime(year, month, 1);
    while (date.weekday != DateTime.friday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }
}
