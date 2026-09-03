// lib/services/staff_patient_link_service.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/pages/dispensary/doctor/patient_history.dart';

class StaffPatientLinkService {
  /// Normalizes a CNIC string by stripping non-digit characters.
  static String normalizeCnic(String? cnic) {
    if (cnic == null) return '';
    return cnic.replaceAll(RegExp(r'\D'), '').trim();
  }

  /// Normalizes a human name (lowercase, trims, removes punctuation).
  static String normalizeName(String? name) {
    if (name == null) return '';
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();
  }

  /// Looks up whether a patient with [cnic] or [name] is a registered staff member/employee.
  /// Returns a map with staff role, designation, branch, and name, or null if not staff.
  static Map<String, dynamic>? getStaffInfoForPatient({
    String? cnic,
    String? name,
  }) {
    final cleanCnic = normalizeCnic(cnic);
    final cleanName = normalizeName(name);

    if (cleanCnic.isEmpty && cleanName.isEmpty) return null;

    // 1. Search in local_employees
    if (Hive.isBoxOpen(LocalStorageService.employeesBox)) {
      final empBox = Hive.box(LocalStorageService.employeesBox);
      for (final key in empBox.keys) {
        final val = empBox.get(key);
        if (val is! Map) continue;
        final emp = Map<String, dynamic>.from(val);

        if (emp['isActive'] == false) continue;

        final empCnic = normalizeCnic(emp['cnic']?.toString());
        final empName = normalizeName(emp['name']?.toString() ?? emp['employeeName']?.toString());

        final cnicMatch = cleanCnic.isNotEmpty && empCnic.isNotEmpty && cleanCnic == empCnic;
        final nameMatch = cleanName.isNotEmpty && empName.isNotEmpty && cleanName == empName;

        if (cnicMatch || nameMatch) {
          final role = (emp['role'] ?? emp['designation'] ?? 'Staff').toString();
          final dept = (emp['department'] ?? 'Office').toString();
          final branch = (emp['branchId'] ?? 'Main').toString();
          final displayName = (emp['name'] ?? emp['employeeName'] ?? name ?? 'Staff').toString();

          return {
            'isStaff': true,
            'role': role,
            'department': dept,
            'branchId': branch,
            'name': displayName,
            'employeeId': emp['localId'] ?? key,
            'userId': emp['userId'],
          };
        }
      }
    }

    // 2. Search in local_users as fallback
    if (Hive.isBoxOpen(LocalStorageService.usersBox)) {
      final uBox = Hive.box(LocalStorageService.usersBox);
      for (final key in uBox.keys) {
        final val = uBox.get(key);
        if (val is! Map) continue;
        final user = Map<String, dynamic>.from(val);

        final roleLower = (user['role'] ?? '').toString().toLowerCase();
        if (roleLower.contains('server') || user['isServerAccount'] == true) continue;

        final uCnic = normalizeCnic(user['cnic']?.toString());
        final uName = normalizeName(user['name']?.toString() ?? user['username']?.toString());

        final cnicMatch = cleanCnic.isNotEmpty && uCnic.isNotEmpty && cleanCnic == uCnic;
        final nameMatch = cleanName.isNotEmpty && uName.isNotEmpty && cleanName == uName;

        if (cnicMatch || nameMatch) {
          final role = (user['role'] ?? 'Staff').toString();
          final branch = (user['branchId'] ?? 'Main').toString();
          final displayName = (user['name'] ?? user['username'] ?? name ?? 'Staff').toString();

          return {
            'isStaff': true,
            'role': role,
            'department': user['department'] ?? 'General',
            'branchId': branch,
            'name': displayName,
            'userId': user['uid'] ?? key,
          };
        }
      }
    }

    return null;
  }

  /// Locates patient data for a staff member using their CNIC or Name.
  /// Checks local_patients first, then reconstructs from local_prescriptions if needed.
  static Map<String, dynamic>? getPatientForStaff({
    String? cnic,
    String? name,
    String? userId,
  }) {
    final cleanCnic = normalizeCnic(cnic);
    final cleanName = normalizeName(name);

    if (cleanCnic.isEmpty && cleanName.isEmpty) return null;

    // 1. Check local_patients
    if (Hive.isBoxOpen(LocalStorageService.patientsBox)) {
      final pBox = Hive.box(LocalStorageService.patientsBox);

      // Direct CNIC lookup
      if (cleanCnic.isNotEmpty) {
        final direct = pBox.get(cleanCnic);
        if (direct is Map) return Map<String, dynamic>.from(direct);
      }

      // Linear search
      for (final key in pBox.keys) {
        final val = pBox.get(key);
        if (val is! Map) continue;
        final p = Map<String, dynamic>.from(val);
        final pCnic = normalizeCnic(p['cnic']?.toString() ?? p['patientCnic']?.toString());
        final pName = normalizeName(p['name']?.toString() ?? p['patientName']?.toString());

        if ((cleanCnic.isNotEmpty && pCnic == cleanCnic) ||
            (cleanName.isNotEmpty && pName == cleanName)) {
          return p;
        }
      }
    }

    // 2. Check local_prescriptions for matching clinical history
    if (Hive.isBoxOpen(LocalStorageService.prescriptionsBox)) {
      final prBox = Hive.box(LocalStorageService.prescriptionsBox);
      for (final key in prBox.keys) {
        final val = prBox.get(key);
        if (val is! Map) continue;
        final pr = Map<String, dynamic>.from(val);
        final prCnic = normalizeCnic(pr['patientCnic']?.toString() ?? pr['cnic']?.toString());
        final prName = normalizeName(pr['patientName']?.toString() ?? pr['name']?.toString());

        if ((cleanCnic.isNotEmpty && prCnic == cleanCnic) ||
            (cleanName.isNotEmpty && prName == cleanName)) {
          return {
            'id': pr['patientId'] ?? 'staff_${cleanCnic.isNotEmpty ? cleanCnic : cleanName}',
            'patientId': pr['patientId'] ?? 'staff_${cleanCnic.isNotEmpty ? cleanCnic : cleanName}',
            'name': pr['patientName'] ?? pr['name'] ?? name ?? 'Staff Member',
            'patientName': pr['patientName'] ?? pr['name'] ?? name ?? 'Staff Member',
            'cnic': pr['patientCnic'] ?? pr['cnic'] ?? cnic ?? '',
            'branchId': pr['branchId'] ?? 'all',
            'age': pr['age'] ?? 30,
            'gender': pr['gender'] ?? 'Male',
            'isStaff': true,
          };
        }
      }
    }

    return null;
  }

  /// Opens the PatientHistoryPage for a staff member immediately.
  static void openStaffMedicalHistory(
    BuildContext context, {
    required String name,
    String? cnic,
    String? branchId,
    String? role,
  }) {
    final effectiveBranch = (branchId != null && branchId.isNotEmpty && branchId != 'all')
        ? branchId
        : 'karachi';

    final patientRecord = getPatientForStaff(cnic: cnic, name: name) ?? {
      'id': 'staff_${normalizeCnic(cnic).isNotEmpty ? normalizeCnic(cnic) : normalizeName(name)}',
      'patientId': 'staff_${normalizeCnic(cnic).isNotEmpty ? normalizeCnic(cnic) : normalizeName(name)}',
      'name': name,
      'patientName': name,
      'cnic': cnic ?? '',
      'patientCnic': cnic ?? '',
      'branchId': effectiveBranch,
      'isStaff': true,
      'staffRole': role ?? 'Employee',
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientHistoryPage(
          branchId: effectiveBranch,
          patientData: patientRecord,
        ),
      ),
    );
  }

  /// Builds a visual Staff Badge widget for patient cards and queue items.
  static Widget buildStaffBadge(Map<String, dynamic> staffInfo, {bool isDark = false}) {
    final role = staffInfo['role']?.toString() ?? 'Staff';
    final dept = staffInfo['department']?.toString() ?? '';
    final displayText = dept.isNotEmpty && dept != 'General' && dept != 'Office'
        ? '$role · $dept'
        : role;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.5) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0xFF60A5FA).withValues(alpha: 0.6) : const Color(0xFF3B82F6),
          width: 0.9,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.badge_rounded,
            size: 11,
            color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
          ),
          const SizedBox(width: 4),
          Text(
            'Staff: $displayText',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
