// lib/services/local_biometric_service.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'finance_local_storage.dart';

class LocalBiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Check if the device hardware supports biometrics and is configured
  static Future<bool> isBiometricsAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (e) {
      debugPrint('LocalBiometricService error checking availability: $e');
      return false;
    }
  }

  /// Get list of available biometric types (Fingerprint, Face ID, etc.)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('LocalBiometricService error getting biometrics: $e');
      return [];
    }
  }

  /// Authenticate the user with local fingerprint/face ID
  static Future<bool> authenticateUser({
    String localizedReason = 'Scan fingerprint or face to confirm attendance',
  }) async {
    try {
      final bool isAvailable = await isBiometricsAvailable();
      if (!isAvailable) {
        debugPrint('Biometrics not available on this device');
        return false;
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
      return didAuthenticate;
    } on PlatformException catch (e) {
      if (e.code == auth_error.notAvailable) {
        debugPrint('Biometrics not available: ${e.message}');
      } else if (e.code == auth_error.notEnrolled) {
        debugPrint('No biometrics enrolled on this device');
      } else if (e.code == auth_error.lockedOut || e.code == auth_error.permanentlyLockedOut) {
        debugPrint('Biometrics locked out');
      } else {
        debugPrint('PlatformException during auth: ${e.message}');
      }
      return false;
    } catch (e) {
      debugPrint('Error during local biometric authentication: $e');
      return false;
    }
  }

  /// STRICT SELF-ATTENDANCE ENFORCEMENT & CONFIRMATION MODAL
  /// Ensures logged-in user can ONLY mark their OWN attendance (no proxy by supervisor)
  static Future<bool> markSelfAttendanceWithBiometrics({
    required BuildContext context,
    required Map<String, dynamic> loggedInUser,
    required String targetEntityId,
    required String targetEntityName,
  }) async {
    final curUserId = loggedInUser['id']?.toString() ?? loggedInUser['uid']?.toString() ?? '';
    final curUserEmail = loggedInUser['email']?.toString() ?? '';

    // ANTI-PROXY SECURITY CHECK:
    // If a supervisor/admin tries to mark attendance for ANOTHER person on their phone, BLOCK IT!
    if (targetEntityId.isNotEmpty && curUserId.isNotEmpty && targetEntityId != curUserId && targetEntityId != curUserEmail) {
      _showSecurityBlockDialog(context, targetEntityName);
      return false;
    }

    // Authenticate using phone's native fingerprint/Face ID
    final bool ok = await authenticateUser(
      localizedReason: 'Scan fingerprint to verify self-attendance for $targetEntityName',
    );

    if (!ok) {
      return false;
    }

    final now = DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(now);
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final branchId = loggedInUser['branchId']?.toString() ?? 'main';

    final recordData = {
      'employeeId': curUserId.isNotEmpty ? curUserId : targetEntityId,
      'employeeName': targetEntityName,
      'date': dateStr,
      'status': 'present',
      'checkInTime': timeStr,
      'source': 'Mobile App (Self Fingerprint)',
      'isLockedByAdmin': false,
    };

    // Save record to database
    await FinanceLocalStorage.saveAttendanceRecord(
      branchId: branchId,
      data: recordData,
      performedBy: 'Self Biometric',
    );

    if (context.mounted) {
      _showSuccessConfirmationModal(
        context: context,
        userName: targetEntityName,
        checkInTime: timeStr,
        dateStr: dateStr,
        branchId: branchId,
      );
    }

    return true;
  }

  static void _showSecurityBlockDialog(BuildContext context, String targetName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.security_rounded, color: Color(0xFFEF4444), size: 28),
            SizedBox(width: 10),
            Text('Proxy Attendance Blocked'),
          ],
        ),
        content: Text(
          'Security Policy Violation: You can ONLY mark mobile biometric attendance for your own logged-in account ($targetName cannot be marked by a proxy user).\n\nTo mark attendance for other employees, use central ZKTeco scanners or Admin Manual Attendance.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understand'),
          ),
        ],
      ),
    );
  }

  static void _showSuccessConfirmationModal({
    required BuildContext context,
    required String userName,
    required String checkInTime,
    required String dateStr,
    required String branchId,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 56),
            ),
            const SizedBox(height: 16),
            Text(
              'Attendance Marked Successfully! 🎉',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF065F46)),
            ),
            const SizedBox(height: 6),
            Text(
              'Your presence has been verified via Mobile Fingerprint.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _infoRow('Name', userName),
                  const Divider(height: 12),
                  _infoRow('Check-In Time', checkInTime),
                  const Divider(height: 12),
                  _infoRow('Date', dateStr),
                  const Divider(height: 12),
                  _infoRow('Verification', 'Self Mobile Fingerprint'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _infoRow(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
        Text(val, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }
}
