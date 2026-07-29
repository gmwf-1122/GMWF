// lib/services/zkteco_network_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/biometric_device_config.dart';
import '../models/biometric_credential.dart';
import 'local_storage_service.dart';

class ZkTecoNetworkService {
  static const int defaultHttpPort = 8088;
  static const int defaultSocketPort = 4370;
  static const Uuid _uuid = Uuid();

  static HttpServer? _httpServer;
  static RawDatagramSocket? _udpSocket;
  static bool _isListening = false;

  // Streams & Notifiers for UI update
  static final StreamController<Map<String, dynamic>> _punchStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get punchStream => _punchStreamController.stream;

  static final ValueNotifier<bool> isServerRunningNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<int> totalPunchesReceivedNotifier = ValueNotifier<int>(0);

  // ── Initialization & Start ──────────────────────────────────────────────────

  /// Starts the embedded HTTP Server (for ZKTeco ADMS Push) and UDP socket listener
  static Future<bool> startServer({int httpPort = defaultHttpPort}) async {
    if (_isListening) return true;

    try {
      // 1. Start HTTP Server for ZKTeco ADMS Web Push
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, httpPort);
      isServerRunningNotifier.value = true;
      _isListening = true;
      debugPrint('[ZkTecoNetworkService] HTTP Listener started on port $httpPort');

      _httpServer!.listen((HttpRequest request) {
        _handleHttpRequest(request);
      }, onError: (e) {
        debugPrint('[ZkTecoNetworkService] HTTP Server error: $e');
      });

      // 2. Start UDP socket listener on port 4370 for legacy push/heartbeats
      try {
        _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, defaultSocketPort);
        _udpSocket!.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            Datagram? dg = _udpSocket!.receive();
            if (dg != null) {
              _handleUdpPacket(dg);
            }
          }
        });
        debugPrint('[ZkTecoNetworkService] UDP Socket Listener started on port $defaultSocketPort');
      } catch (e) {
        debugPrint('[ZkTecoNetworkService] UDP Socket bind warning (port may be in use): $e');
      }

      return true;
    } catch (e) {
      debugPrint('[ZkTecoNetworkService] Failed to start server: $e');
      isServerRunningNotifier.value = false;
      _isListening = false;
      return false;
    }
  }

  /// Stops the server listeners
  static Future<void> stopServer() async {
    _isListening = false;
    isServerRunningNotifier.value = false;
    await _httpServer?.close(force: true);
    _httpServer = null;
    _udpSocket?.close();
    _udpSocket = null;
    debugPrint('[ZkTecoNetworkService] Server stopped');
  }

  // ── HTTP ADMS PUSH Request Handler ────────────────────────────────────────

  static void _handleHttpRequest(HttpRequest request) async {
    final uri = request.uri;
    final path = uri.path;
    final clientIp = request.connectionInfo?.remoteAddress.address ?? '';
    final queryParams = uri.queryParameters;

    debugPrint('[ZkTecoNetworkService] Request from $clientIp: ${request.method} $path');

    // Register / Update device heartbeat
    final sn = queryParams['SN'] ?? queryParams['sn'] ?? 'UNKNOWN_DEVICE';
    _registerDeviceHeartbeat(sn, clientIp);

    if (request.method == 'GET') {
      // ADMS Handshake / Heartbeat request: ZKTeco devices request commands via GET /iclock/getrequest
      if (path.contains('/iclock/cdata') || path.contains('/iclock/getrequest')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write('OK');
        await request.response.close();
        return;
      }
    } else if (request.method == 'POST') {
      // ADMS Log Data Push: ZKTeco sends attendance records via POST /iclock/cdata
      try {
        final bodyText = await utf8.decoder.bind(request).join();
        
        debugPrint('[ZkTecoNetworkService] Raw PUSH Payload: $bodyText');
        _parseAndProcessAdmsPayload(bodyText, clientIp, sn);

        request.response.headers.contentType = ContentType.text;
        request.response.write('OK');
        await request.response.close();
        return;
      } catch (e) {
        debugPrint('[ZkTecoNetworkService] Error parsing POST body: $e');
      }
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write('OK');
    await request.response.close();
  }

  static void _handleUdpPacket(Datagram dg) {
    try {
      final text = utf8.decode(dg.data, allowMalformed: true);
      final ip = dg.address.address;
      debugPrint('[ZkTecoNetworkService] UDP Packet from $ip: $text');
      _parseAndProcessAdmsPayload(text, ip, 'UDP_DEVICE');
    } catch (_) {}
  }

  // ── ADMS Data Payload Parser ──────────────────────────────────────────────

  /// Parses ZKTeco ADMS tab-separated log entries:
  /// Format example: `101\t2026-07-27 08:30:00\t0\t0\t0\t0`
  static void _parseAndProcessAdmsPayload(String payload, String clientIp, String deviceSn) {
    final lines = payload.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('table=') || line.startsWith('ATTLOG')) continue;

      final parts = line.split('\t');
      if (parts.length >= 2) {
        final pin = parts[0].trim();
        final timeStr = parts[1].trim();
        final timestamp = DateTime.tryParse(timeStr) ?? DateTime.now();

        if (pin.isNotEmpty) {
          processIncomingPunch(
            pin: pin,
            timestamp: timestamp,
            deviceIp: clientIp,
            deviceSn: deviceSn,
            source: 'zkteco',
          );
        }
      }
    }
  }

  // ── Processing Incoming Punch & Module Routing ─────────────────────────────

  /// Processes punch from ZKTeco device or Mobile App
  static Future<void> processIncomingPunch({
    required String pin,
    required DateTime timestamp,
    required String deviceIp,
    String deviceSn = '',
    required String source,
  }) async {
    totalPunchesReceivedNotifier.value++;

    // 1. Resolve physical building location from device config
    final device = getDeviceByIpOrSn(deviceIp, deviceSn);
    final buildingLocation = device?.buildingLocation ?? 'Office';

    // 2. Lookup Biometric Credential mapping
    final credential = getCredentialByPin(pin);

    final punchRecord = {
      'id': _uuid.v4(),
      'pin': pin,
      'timestamp': timestamp.toIso8601String(),
      'deviceIp': deviceIp,
      'deviceSn': deviceSn,
      'buildingLocation': buildingLocation,
      'source': source,
      'isMapped': credential != null,
      'entityId': credential?.entityId,
      'entityName': credential?.entityName ?? 'Unknown User (PIN $pin)',
      'entityType': credential?.entityType ?? 'unmapped',
    };

    debugPrint('[ZkTecoNetworkService] Processing Punch: $punchRecord');

    if (credential != null) {
      // 3. Auto-route to specific entity attendance module
      await _routePunchToModule(credential, timestamp, buildingLocation, source);
    } else {
      // Save to Unmapped Punches box for admin 1-click assignment
      await _saveUnmappedPunch(punchRecord);
    }

    // Broadcast realtime event to UI
    _punchStreamController.add(punchRecord);
  }

  static Future<void> _routePunchToModule(
    BiometricCredential credential,
    DateTime timestamp,
    String location,
    String source,
  ) async {
    final type = credential.entityType.toLowerCase();
    final dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
    final timeStr = DateFormat('hh:mm a').format(timestamp);

    debugPrint('[ZkTecoNetworkService] Routing punch for ${credential.entityName} ($type) to module...');

    if (type == 'employee' || type == 'dispensary_staff') {
      // Record in Office Employee Attendance Box
      await _recordEmployeeAttendance(credential, dateStr, timeStr, source, location);
    } else if (type == 'madrassa_student') {
      // Record in Madrassa Student Log Box
      await _recordMadrassaStudentAttendance(credential, dateStr, timeStr, source);
    } else if (type == 'school_student') {
      // Record in School Daily Attendance Box
      await _recordSchoolStudentAttendance(credential, dateStr, timeStr, source);
    }
  }

  static Future<void> _recordEmployeeAttendance(
    BiometricCredential credential,
    String dateStr,
    String timeStr,
    String source,
    String location,
  ) async {
    try {
      if (!Hive.isBoxOpen(LocalStorageService.attendanceBox)) {
        await LocalStorageService.openBoxSafe(LocalStorageService.attendanceBox);
      }
      final box = Hive.box(LocalStorageService.attendanceBox);
      
      final key = '${credential.entityId}_$dateStr';
      final existing = box.get(key);
      final now = DateTime.now();

      if (existing != null) {
        final existingMap = Map<String, dynamic>.from(existing as Map);

        // RULE: If HQ Manager manually marked user as Absent/Leave and locked it, DO NOT ALLOW biometric override!
        final isLocked = existingMap['isLockedByAdmin'] == true || 
                         existingMap['isManagerLocked'] == true ||
                         existingMap['manualOverride'] == true;
        if (isLocked) {
          debugPrint('[ZkTecoNetworkService] Biometric scan BLOCKED for ${credential.entityName}: Locked by HQ Manager');
          return;
        }

        final lastPunchTimeStr = existingMap['lastPunchTime']?.toString();
        if (lastPunchTimeStr != null) {
          final lastPunch = DateTime.tryParse(lastPunchTimeStr);
          if (lastPunch != null && now.difference(lastPunch).inMinutes < 5) {
            debugPrint('[ZkTecoNetworkService] Duplicate punch ignored (< 5 mins) for ${credential.entityName}');
            return;
          }
        }
        // Update Check-Out time for afternoon/evening scan
        existingMap['checkOutTime'] = timeStr;
        existingMap['lastPunchTime'] = now.toIso8601String();
        await box.put(key, existingMap);
      } else {
        // First scan of the day -> Check-In time
        final newRecord = {
          'id': _uuid.v4(),
          'employeeId': credential.entityId,
          'employeeName': credential.entityName,
          'branchId': credential.branchId,
          'date': dateStr,
          'checkInTime': timeStr,
          'checkOutTime': null,
          'status': 'Present',
          'attendanceType': 'Full Day',
          'source': '$source ($location)',
          'lastPunchTime': now.toIso8601String(),
          'synced': false,
        };
        await box.put(key, newRecord);
      }
      await box.flush();
      debugPrint('[ZkTecoNetworkService] Recorded Employee Attendance for ${credential.entityName}');
    } catch (e) {
      debugPrint('[ZkTecoNetworkService] Error recording employee attendance: $e');
    }
  }

  static Future<void> _recordMadrassaStudentAttendance(
    BiometricCredential credential,
    String dateStr,
    String timeStr,
    String source,
  ) async {
    try {
      if (!Hive.isBoxOpen(LocalStorageService.madrassaLogsBox)) {
        await LocalStorageService.openBoxSafe(LocalStorageService.madrassaLogsBox);
      }
      final box = Hive.box(LocalStorageService.madrassaLogsBox);

      final key = '${credential.entityId}_$dateStr';
      final existing = box.get(key);

      if (existing != null) {
        final existingMap = Map<String, dynamic>.from(existing as Map);
        if (existingMap['isLockedByAdmin'] == true || existingMap['isManagerLocked'] == true) {
          debugPrint('[ZkTecoNetworkService] Biometric scan BLOCKED for Madrassa Student ${credential.entityName}: Locked by HQ Manager');
          return;
        }
      }

      final record = {
        'id': _uuid.v4(),
        'studentId': credential.entityId,
        'studentName': credential.entityName,
        'branchId': credential.branchId,
        'date': dateStr,
        'time': timeStr,
        'status': 'P', // Present
        'source': source,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await box.put(key, record);
      await box.flush();
      debugPrint('[ZkTecoNetworkService] Recorded Madrassa Student Attendance for ${credential.entityName}');
    } catch (e) {
      debugPrint('[ZkTecoNetworkService] Error recording Madrassa student attendance: $e');
    }
  }

  static Future<void> _recordSchoolStudentAttendance(
    BiometricCredential credential,
    String dateStr,
    String timeStr,
    String source,
  ) async {
    try {
      if (!Hive.isBoxOpen(LocalStorageService.schoolLogsBox)) {
        await LocalStorageService.openBoxSafe(LocalStorageService.schoolLogsBox);
      }
      final box = Hive.box(LocalStorageService.schoolLogsBox);

      final key = '${credential.entityId}_$dateStr';
      final existing = box.get(key);

      if (existing != null) {
        final existingMap = Map<String, dynamic>.from(existing as Map);
        if (existingMap['isLockedByAdmin'] == true || existingMap['isManagerLocked'] == true) {
          debugPrint('[ZkTecoNetworkService] Biometric scan BLOCKED for School Student ${credential.entityName}: Locked by HQ Manager');
          return;
        }
      }

      final record = {
        'id': _uuid.v4(),
        'studentId': credential.entityId,
        'studentName': credential.entityName,
        'branchId': credential.branchId,
        'date': dateStr,
        'time': timeStr,
        'status': 'Present',
        'source': source,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await box.put(key, record);
      await box.flush();
      debugPrint('[ZkTecoNetworkService] Recorded School Student Attendance for ${credential.entityName}');
    } catch (e) {
      debugPrint('[ZkTecoNetworkService] Error recording School student attendance: $e');
    }
  }

  static Future<void> _saveUnmappedPunch(Map<String, dynamic> punch) async {
    try {
      if (!Hive.isBoxOpen(LocalStorageService.unmappedPunchesBox)) {
        await LocalStorageService.openBoxSafe(LocalStorageService.unmappedPunchesBox);
      }
      final box = Hive.box(LocalStorageService.unmappedPunchesBox);
      await box.put(punch['id'], punch);
    } catch (e) {
      debugPrint('[ZkTecoNetworkService] Error saving unmapped punch: $e');
    }
  }

  // ── Device Registration & Heartbeat Management ────────────────────────────

  static void _registerDeviceHeartbeat(String sn, String ip) async {
    try {
      if (!Hive.isBoxOpen(LocalStorageService.biometricDevicesBox)) {
        await LocalStorageService.openBoxSafe(LocalStorageService.biometricDevicesBox);
      }
      final box = Hive.box(LocalStorageService.biometricDevicesBox);

      BiometricDeviceConfig? existingDevice;
      String? matchedKey;

      for (var key in box.keys) {
        final val = box.get(key);
        if (val != null) {
          final cfg = BiometricDeviceConfig.fromMap(Map<String, dynamic>.from(val as Map));
          if (cfg.serialNumber == sn || cfg.ipAddress == ip) {
            existingDevice = cfg;
            matchedKey = key.toString();
            break;
          }
        }
      }

      final now = DateTime.now();
      final deviceKey = matchedKey ?? _uuid.v4();

      final updated = (existingDevice ??
              BiometricDeviceConfig(
                deviceId: deviceKey,
                deviceName: 'ZKTeco Device ($sn)',
                buildingLocation: 'Office',
                ipAddress: ip,
                serialNumber: sn,
              ))
          .copyWith(
        status: 'Online',
        lastHeartbeat: now,
        ipAddress: ip,
        serialNumber: sn.isNotEmpty ? sn : existingDevice?.serialNumber,
      );

      await box.put(deviceKey, updated.toMap());
    } catch (e) {
      debugPrint('[ZkTecoNetworkService] Error registering device heartbeat: $e');
    }
  }

  static BiometricDeviceConfig? getDeviceByIpOrSn(String ip, String sn) {
    if (!Hive.isBoxOpen(LocalStorageService.biometricDevicesBox)) return null;
    final box = Hive.box(LocalStorageService.biometricDevicesBox);
    for (var val in box.values) {
      if (val != null) {
        final cfg = BiometricDeviceConfig.fromMap(Map<String, dynamic>.from(val as Map));
        if (cfg.ipAddress == ip || (sn.isNotEmpty && cfg.serialNumber == sn)) {
          return cfg;
        }
      }
    }
    return null;
  }

  static List<BiometricDeviceConfig> getAllDevices() {
    if (!Hive.isBoxOpen(LocalStorageService.biometricDevicesBox)) return [];
    final box = Hive.box(LocalStorageService.biometricDevicesBox);
    return box.values
        .where((v) => v != null)
        .map((v) => BiometricDeviceConfig.fromMap(Map<String, dynamic>.from(v as Map)))
        .toList();
  }

  static Future<void> saveDeviceConfig(BiometricDeviceConfig config) async {
    if (!Hive.isBoxOpen(LocalStorageService.biometricDevicesBox)) {
      await LocalStorageService.openBoxSafe(LocalStorageService.biometricDevicesBox);
    }
    final box = Hive.box(LocalStorageService.biometricDevicesBox);
    await box.put(config.deviceId, config.toMap());
  }

  // ── Credential & PIN Registry Management ────────────────────────────────────

  static BiometricCredential? getCredentialByPin(String pin) {
    if (!Hive.isBoxOpen(LocalStorageService.biometricCredentialsBox)) return null;
    final box = Hive.box(LocalStorageService.biometricCredentialsBox);
    for (var val in box.values) {
      if (val != null) {
        final cred = BiometricCredential.fromMap(Map<String, dynamic>.from(val as Map));
        if (cred.biometricPin == pin && cred.active) {
          return cred;
        }
      }
    }
    return null;
  }

  static List<BiometricCredential> getAllCredentials() {
    if (!Hive.isBoxOpen(LocalStorageService.biometricCredentialsBox)) return [];
    final box = Hive.box(LocalStorageService.biometricCredentialsBox);
    return box.values
        .where((v) => v != null)
        .map((v) => BiometricCredential.fromMap(Map<String, dynamic>.from(v as Map)))
        .toList();
  }

  static Future<void> registerBiometricCredential(BiometricCredential credential) async {
    if (!Hive.isBoxOpen(LocalStorageService.biometricCredentialsBox)) {
      await LocalStorageService.openBoxSafe(LocalStorageService.biometricCredentialsBox);
    }
    final box = Hive.box(LocalStorageService.biometricCredentialsBox);
    await box.put(credential.id, credential.toMap());
  }

  // ── Bulk Auto-Assign Biometric PINs to Existing Users ─────────────────────

  /// Scans all existing Employees and Students in local storage and assigns
  /// unique clean numeric Biometric PINs (e.g. 101, 102...) to any unassigned profiles.
  static Future<int> bulkAutoAssignBiometricPins() async {
    int assignedCount = 0;
    int currentStaffPin = 101;
    int currentMadrassaPin = 3001;
    int currentSchoolPin = 5001;

    final existingCreds = getAllCredentials();
    final usedPins = existingCreds.map((c) => c.biometricPin).toSet();

    // 1. Process Employees in LocalStorageService
    if (Hive.isBoxOpen(LocalStorageService.employeesBox)) {
      final empBox = Hive.box(LocalStorageService.employeesBox);
      for (var key in empBox.keys) {
        final empRaw = empBox.get(key);
        if (empRaw != null && empRaw is Map) {
          final empMap = Map<String, dynamic>.from(empRaw);
          final empId = empMap['id']?.toString() ?? key.toString();
          final name = empMap['name']?.toString() ?? 'Employee';
          final branchId = empMap['branchId']?.toString() ?? '';

          // Check if already mapped
          bool alreadyHas = existingCreds.any((c) => c.entityId == empId);
          if (!alreadyHas) {
            while (usedPins.contains(currentStaffPin.toString())) {
              currentStaffPin++;
            }
            final newPin = currentStaffPin.toString();
            usedPins.add(newPin);

            final cred = BiometricCredential(
              id: _uuid.v4(),
              biometricPin: newPin,
              entityId: empId,
              entityName: name,
              entityType: 'employee',
              branchId: branchId,
              enrolledAt: DateTime.now(),
            );
            await registerBiometricCredential(cred);
            assignedCount++;
            currentStaffPin++;
          }
        }
      }
    }

    // 2. Process Madrassa Students
    if (Hive.isBoxOpen(LocalStorageService.madrassaStudentsBox)) {
      final mBox = Hive.box(LocalStorageService.madrassaStudentsBox);
      for (var key in mBox.keys) {
        final raw = mBox.get(key);
        if (raw != null && raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final stId = map['id']?.toString() ?? key.toString();
          final name = map['name']?.toString() ?? 'Madrassa Student';
          final branchId = map['branchId']?.toString() ?? '';

          bool alreadyHas = existingCreds.any((c) => c.entityId == stId);
          if (!alreadyHas) {
            while (usedPins.contains(currentMadrassaPin.toString())) {
              currentMadrassaPin++;
            }
            final newPin = currentMadrassaPin.toString();
            usedPins.add(newPin);

            final cred = BiometricCredential(
              id: _uuid.v4(),
              biometricPin: newPin,
              entityId: stId,
              entityName: name,
              entityType: 'madrassa_student',
              branchId: branchId,
              enrolledAt: DateTime.now(),
            );
            await registerBiometricCredential(cred);
            assignedCount++;
            currentMadrassaPin++;
          }
        }
      }
    }

    // 3. Process School Students
    if (Hive.isBoxOpen(LocalStorageService.schoolStudentsBox)) {
      final sBox = Hive.box(LocalStorageService.schoolStudentsBox);
      for (var key in sBox.keys) {
        final raw = sBox.get(key);
        if (raw != null && raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final stId = map['id']?.toString() ?? key.toString();
          final name = map['name']?.toString() ?? 'School Student';
          final branchId = map['branchId']?.toString() ?? '';

          bool alreadyHas = existingCreds.any((c) => c.entityId == stId);
          if (!alreadyHas) {
            while (usedPins.contains(currentSchoolPin.toString())) {
              currentSchoolPin++;
            }
            final newPin = currentSchoolPin.toString();
            usedPins.add(newPin);

            final cred = BiometricCredential(
              id: _uuid.v4(),
              biometricPin: newPin,
              entityId: stId,
              entityName: name,
              entityType: 'school_student',
              branchId: branchId,
              enrolledAt: DateTime.now(),
            );
            await registerBiometricCredential(cred);
            assignedCount++;
            currentSchoolPin++;
          }
        }
      }
    }

    return assignedCount;
  }
}
