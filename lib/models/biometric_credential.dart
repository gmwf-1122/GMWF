// lib/models/biometric_credential.dart

class BiometricCredential {
  final String id;
  final String biometricPin; // Current Numeric PIN used on ZKTeco device e.g. "101"
  final List<String> pinHistory; // Historical / previous PINs e.g. ["101", "102"]
  final String entityId;     // Internal ID of Student / Employee
  final String entityName;   // Full name of Person
  final String entityType;   // 'employee', 'madrassa_student', 'school_student', 'dispensary_staff'
  final String branchId;
  final DateTime enrolledAt;
  final String deviceSource; // 'zkteco', 'android_fingerprint', 'windows_hello'
  final bool active;

  BiometricCredential({
    required this.id,
    required this.biometricPin,
    this.pinHistory = const [],
    required this.entityId,
    required this.entityName,
    required this.entityType,
    required this.branchId,
    required this.enrolledAt,
    this.deviceSource = 'zkteco',
    this.active = true,
  });

  factory BiometricCredential.fromMap(Map<dynamic, dynamic> map) {
    final historyRaw = map['pinHistory'] ?? map['previousPins'];
    final history = <String>[];
    if (historyRaw is List) {
      for (final p in historyRaw) {
        if (p != null && p.toString().trim().isNotEmpty) {
          history.add(p.toString().trim());
        }
      }
    }
    return BiometricCredential(
      id: map['id']?.toString() ?? '',
      biometricPin: map['biometricPin']?.toString() ?? '',
      pinHistory: history,
      entityId: map['entityId']?.toString() ?? '',
      entityName: map['entityName']?.toString() ?? 'User',
      entityType: map['entityType']?.toString() ?? 'employee',
      branchId: map['branchId']?.toString() ?? '',
      enrolledAt: map['enrolledAt'] != null 
          ? (DateTime.tryParse(map['enrolledAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
      deviceSource: map['deviceSource']?.toString() ?? 'zkteco',
      active: map['active'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'biometricPin': biometricPin,
      'pinHistory': pinHistory,
      'entityId': entityId,
      'entityName': entityName,
      'entityType': entityType,
      'branchId': branchId,
      'enrolledAt': enrolledAt.toIso8601String(),
      'deviceSource': deviceSource,
      'active': active,
    };
  }
}
