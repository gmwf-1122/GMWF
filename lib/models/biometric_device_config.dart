// lib/models/biometric_device_config.dart

class BiometricDeviceConfig {
  final String deviceId;
  final String deviceName;
  final String buildingLocation; // 'Office/Dasterkhwaan', 'Dispensary', 'Madrassa'
  final String branchId;         // Assigned branch e.g. 'gujrat', 'sialkot', 'branch_a', 'main'
  final String ipAddress;
  final int port;
  final String serialNumber;
  final String status; // 'Online', 'Offline', 'Syncing'
  final DateTime? lastHeartbeat;
  final DateTime? lastSyncTimestamp;
  final bool enabled;

  BiometricDeviceConfig({
    required this.deviceId,
    required this.deviceName,
    required this.buildingLocation,
    this.branchId = '',
    required this.ipAddress,
    this.port = 4370,
    this.serialNumber = '',
    this.status = 'Offline',
    this.lastHeartbeat,
    this.lastSyncTimestamp,
    this.enabled = true,
  });

  factory BiometricDeviceConfig.fromMap(Map<dynamic, dynamic> map) {
    return BiometricDeviceConfig(
      deviceId: map['deviceId']?.toString() ?? '',
      deviceName: map['deviceName']?.toString() ?? 'Biometric Device',
      buildingLocation: map['buildingLocation']?.toString() ?? 'Office',
      branchId: map['branchId']?.toString() ?? '',
      ipAddress: map['ipAddress']?.toString() ?? '192.168.1.100',
      port: int.tryParse(map['port']?.toString() ?? '') ?? 4370,
      serialNumber: map['serialNumber']?.toString() ?? '',
      status: map['status']?.toString() ?? 'Offline',
      lastHeartbeat: map['lastHeartbeat'] != null ? DateTime.tryParse(map['lastHeartbeat'].toString()) : null,
      lastSyncTimestamp: map['lastSyncTimestamp'] != null ? DateTime.tryParse(map['lastSyncTimestamp'].toString()) : null,
      enabled: map['enabled'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'buildingLocation': buildingLocation,
      'branchId': branchId,
      'ipAddress': ipAddress,
      'port': port,
      'serialNumber': serialNumber,
      'status': status,
      'lastHeartbeat': lastHeartbeat?.toIso8601String(),
      'lastSyncTimestamp': lastSyncTimestamp?.toIso8601String(),
      'enabled': enabled,
    };
  }

  BiometricDeviceConfig copyWith({
    String? deviceId,
    String? deviceName,
    String? buildingLocation,
    String? branchId,
    String? ipAddress,
    int? port,
    String? serialNumber,
    String? status,
    DateTime? lastHeartbeat,
    DateTime? lastSyncTimestamp,
    bool? enabled,
  }) {
    return BiometricDeviceConfig(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      buildingLocation: buildingLocation ?? this.buildingLocation,
      branchId: branchId ?? this.branchId,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      serialNumber: serialNumber ?? this.serialNumber,
      status: status ?? this.status,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
      enabled: enabled ?? this.enabled,
    );
  }
}
