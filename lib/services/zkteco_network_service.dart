// lib/services/zkteco_network_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/biometric_device_config.dart';
import '../models/biometric_credential.dart';
import 'local_storage_service.dart';
import '../realtime/realtime_events.dart';
import '../realtime/realtime_manager.dart';

class ZkTecoNetworkService {
  static const int defaultHttpPort = 8088;
  static const int defaultSocketPort = 4370;
  static const Uuid _uuid = Uuid();

  static HttpServer? _httpServer;
  static RawDatagramSocket? _udpSocket;
  static bool _isListening = false;
  static Timer? _activePollingTimer;
  static StreamSubscription? _firestorePunchesSub;
  static final Set<String> _lastKnownLogKeys = {}; // Dedup: "IP_PIN_TIMESTAMP"

  // Streams & Notifiers for UI update
  static final StreamController<Map<String, dynamic>> _punchStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get punchStream => _punchStreamController.stream;

  static final ValueNotifier<bool> isServerRunningNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<int> totalPunchesReceivedNotifier = ValueNotifier<int>(0);

  // ── Initialization & Start ──────────────────────────────────────────────────

  /// Starts the embedded HTTP Server (for ZKTeco ADMS Push) and UDP socket listener
  static Future<bool> startServer({int httpPort = defaultHttpPort}) async {
    if (kIsWeb) return false;
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

      // 3. Start active polling timer to pull attendance logs from ZKTeco devices
      _startActivePolling();

      // 4. Start listening to Cloud Firestore for biometric punches from Python services
      listenToFirestorePunches();

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
    _activePollingTimer?.cancel();
    _activePollingTimer = null;
    _firestorePunchesSub?.cancel();
    _firestorePunchesSub = null;
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

    // Broadcast realtime event to UI & LAN Server
    _punchStreamController.add(punchRecord);

    try {
      RealtimeManager().sendMessage({
        'event_type': RealtimeEvents.saveBiometricLog,
        'data': punchRecord,
      });
    } catch (e) {
      debugPrint('[ZkTecoNetworkService] Realtime broadcast notice: $e');
    }

    // Sync to Cloud Firestore (Works on both Web & Windows, handles offline queue automatically)
    try {
      final docId = '${deviceIp}_${pin}_${timestamp.millisecondsSinceEpoch}';
      await FirebaseFirestore.instance
          .collection('biometric_punches')
          .doc(docId)
          .set(punchRecord, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ZkTecoNetworkService] Firestore punch sync notice: $e');
    }
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

    if (type == 'employee' || type == 'dispensary_staff' || type == 'dasterkhwaan_staff' || type == 'teacher' || type == 'staff') {
      // Record in Office / Department Staff Employee Attendance Box
      await _recordEmployeeAttendance(credential, dateStr, timeStr, source, location);
    } else if (type == 'madrassa_student' || type == 'madrassa') {
      // Record in Madrassa Student Log Box
      await _recordMadrassaStudentAttendance(credential, dateStr, timeStr, source);
    } else if (type == 'school_student' || type == 'school') {
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
    final now = DateTime.now();
    final List<BiometricDeviceConfig> result = [];
    for (var v in box.values) {
      if (v is Map) {
        try {
          final cfg = BiometricDeviceConfig.fromMap(v);
          final isRecentlyActive = cfg.lastHeartbeat != null &&
              now.difference(cfg.lastHeartbeat!).inSeconds < 120;
          result.add(cfg.copyWith(status: isRecentlyActive ? 'Online' : 'Offline'));
        } catch (_) {}
      }
    }
    return result;
  }

  static Future<void> saveDeviceConfig(BiometricDeviceConfig config) async {
    if (!Hive.isBoxOpen(LocalStorageService.biometricDevicesBox)) {
      await LocalStorageService.openBoxSafe(LocalStorageService.biometricDevicesBox);
    }
    final box = Hive.box(LocalStorageService.biometricDevicesBox);
    await box.put(config.deviceId, config.toMap());
  }

  /// Pings a ZKTeco device over LAN and waits for genuine network socket response
  static Future<bool> pingDevice(String ipAddress, {int port = 4370}) async {
    if (kIsWeb) return false;

    // 1. Try TCP handshake (ADMS Web Push 8088 / ZKTeco TCP 4370)
    try {
      final socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 2));
      socket.destroy();
      await _updateDeviceOnlineStatus(ipAddress);
      return true;
    } catch (_) {}

    // 2. Try ZKTeco UDP Datagram handshake with strict response wait
    try {
      final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      
      // Send proper ZKTeco CMD_CONNECT packet with checksum
      final command = _buildZkPacket(command: 0x03E8, sessionId: 0, replyId: 0);

      udp.send(command, InternetAddress(ipAddress), port);

      Completer<bool> completer = Completer<bool>();
      Timer timer = Timer(const Duration(seconds: 2), () {
        if (!completer.isCompleted) {
          udp.close();
          completer.complete(false);
        }
      });

      udp.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = udp.receive();
          if (dg != null && dg.data.isNotEmpty) {
            timer.cancel();
            udp.close();
            if (!completer.isCompleted) {
              completer.complete(true);
            }
          }
        }
      });

      final result = await completer.future;
      if (result) {
        await _updateDeviceOnlineStatus(ipAddress);
      } else {
        await _markDeviceOffline(ipAddress);
      }
      return result;
    } catch (_) {
      await _markDeviceOffline(ipAddress);
      return false;
    }
  }

  static Future<void> _updateDeviceOnlineStatus(String ipAddress) async {
    final devices = getAllDevices();
    for (final dev in devices) {
      if (dev.ipAddress == ipAddress) {
        final updated = dev.copyWith(
          lastHeartbeat: DateTime.now(),
          status: 'Online',
        );
        await saveDeviceConfig(updated);
      }
    }
  }

  static Future<void> _markDeviceOffline(String ipAddress) async {
    final devices = getAllDevices();
    for (final dev in devices) {
      if (dev.ipAddress == ipAddress) {
        final updated = dev.copyWith(
          status: 'Offline',
        );
        await saveDeviceConfig(updated);
      }
    }
  }

  // ── Firestore Snapshot Listener ─────────────────────────────────────────────

  /// Listens to Cloud Firestore for biometric punches synced from Python services or remote apps
  static void listenToFirestorePunches() {
    _firestorePunchesSub?.cancel();
    try {
      _firestorePunchesSub = FirebaseFirestore.instance
          .collection('biometric_punches')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots()
          .listen((snap) {
        for (var doc in snap.docChanges) {
          if (doc.type == DocumentChangeType.added) {
            final data = doc.doc.data();
            if (data != null) {
              final pin = data['pin']?.toString() ?? '';
              final timeStr = data['timestamp']?.toString() ?? '';
              final deviceIp = data['deviceIp']?.toString() ?? '192.168.1.100';
              final source = data['source']?.toString() ?? 'firestore_sync';

              if (pin.isNotEmpty && timeStr.isNotEmpty) {
                final timestamp = DateTime.tryParse(timeStr) ?? DateTime.now();
                final dedupKey = '${deviceIp}_${pin}_$timeStr';
                if (!_lastKnownLogKeys.contains(dedupKey)) {
                  _lastKnownLogKeys.add(dedupKey);
                  processIncomingPunch(
                    pin: pin,
                    timestamp: timestamp,
                    deviceIp: deviceIp,
                    source: source,
                  );
                }
              }
            }
          }
        }
      });
    } catch (e) {
      debugPrint('[ZkTecoNetworkService] Firestore listener notice: $e');
    }
  }

  // ── Active ZKTeco Device Polling & Keep-Alive (Pull-Based) ─────────────────────────────

  /// Starts a periodic timer that actively connects to each online ZKTeco device
  /// and pulls new attendance log records using the ZK UDP protocol.
  static void _startActivePolling() {
    _activePollingTimer?.cancel();
    // Poll every 15 seconds
    _activePollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pollAllDevices();
    });
    // Also do an immediate first poll
    _pollAllDevices();
  }

  static Future<void> _pollAllDevices() async {
    if (kIsWeb) return;
    final devices = getAllDevices();
    for (final device in devices) {
      if (device.ipAddress.isNotEmpty) {
        try {
          // Automatic Keep-Alive Ping: Keeps status Online continuously without manual checking!
          final isReachable = await pingDevice(device.ipAddress, port: device.port);
          if (isReachable) {
            await _pullAttendanceLogsFromDevice(device);
          }
        } catch (e) {
          debugPrint('[ZkTecoNetworkService] Poll error for ${device.ipAddress}: $e');
        }
      }
    }
  }

  /// Connects to a ZKTeco device via UDP and requests attendance logs.
  /// ZK Protocol flow: CMD_CONNECT → get session → CMD_ATTLOG_RRQ → read log data → CMD_FREE_DATA → CMD_EXIT
  static Future<void> _pullAttendanceLogsFromDevice(BiometricDeviceConfig device) async {
    final ip = device.ipAddress;
    final port = device.port;
    RawDatagramSocket? udp;

    try {
      udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      // ── Step 1: CMD_CONNECT (0x03E8) ──
      final connectPacket = _buildZkPacket(command: 0x03E8, sessionId: 0, replyId: 0);
      udp.send(connectPacket, InternetAddress(ip), port);

      final connectReply = await _waitForReply(udp, timeout: const Duration(seconds: 3));
      if (connectReply == null || connectReply.length < 8) {
        udp.close();
        return; // Device didn't respond
      }

      // Parse session ID from connect reply (bytes 4-5, little-endian)
      final replyCommand = connectReply[0] | (connectReply[1] << 8);
      if (replyCommand != 0x07D0) {
        // 0x07D0 = CMD_ACK_OK
        debugPrint('[ZkTecoNetworkService] CMD_CONNECT rejected by $ip (reply: 0x${replyCommand.toRadixString(16)})');
        udp.close();
        return;
      }

      final sessionId = connectReply[4] | (connectReply[5] << 8);
      int replyId = 1;

      // Update device online status
      await _updateDeviceOnlineStatus(ip);

      // ── Step 2: CMD_DISABLEDEVICE (0x003C) – prevent concurrent operations ──
      final disablePacket = _buildZkPacket(command: 0x003C, sessionId: sessionId, replyId: replyId++);
      udp.send(disablePacket, InternetAddress(ip), port);
      await _waitForReply(udp, timeout: const Duration(seconds: 2)); // ACK

      // ── Step 3: CMD_ATTLOG_RRQ (0x000D) – request attendance log records ──
      final attlogPacket = _buildZkPacket(command: 0x000D, sessionId: sessionId, replyId: replyId++);
      udp.send(attlogPacket, InternetAddress(ip), port);

      // Collect all data chunks (device may send multiple packets)
      final allData = BytesBuilder();
      bool receivedPrepare = false;

      // Wait for CMD_PREPARE_DATA (0x05DC) or CMD_DATA (0x05DD) or direct ACK
      while (true) {
        final chunk = await _waitForReply(udp, timeout: const Duration(seconds: 3));
        if (chunk == null) break;

        final cmd = chunk[0] | (chunk[1] << 8);

        if (cmd == 0x05DC) {
          // CMD_PREPARE_DATA – device is preparing to send data
          receivedPrepare = true;
          continue;
        } else if (cmd == 0x05DD) {
          // CMD_DATA – actual attendance data chunk
          if (chunk.length > 8) {
            allData.add(chunk.sublist(8));
          }
          continue;
        } else if (cmd == 0x07D0) {
          // CMD_ACK_OK – done sending
          break;
        } else {
          break;
        }
      }

      // ── Step 4: CMD_FREE_DATA (0x000C) – acknowledge receipt ──
      final freeDataPacket = _buildZkPacket(command: 0x000C, sessionId: sessionId, replyId: replyId++);
      udp.send(freeDataPacket, InternetAddress(ip), port);
      await _waitForReply(udp, timeout: const Duration(seconds: 1));

      // ── Step 5: CMD_ENABLEDEVICE (0x003D) – re-enable the device ──
      final enablePacket = _buildZkPacket(command: 0x003D, sessionId: sessionId, replyId: replyId++);
      udp.send(enablePacket, InternetAddress(ip), port);
      await _waitForReply(udp, timeout: const Duration(seconds: 1));

      // ── Step 6: CMD_EXIT (0x03E9) – disconnect session ──
      final exitPacket = _buildZkPacket(command: 0x03E9, sessionId: sessionId, replyId: replyId++);
      udp.send(exitPacket, InternetAddress(ip), port);

      udp.close();
      udp = null;

      // ── Parse attendance records ──
      if (allData.length > 0) {
        _parseZkAttendanceData(allData.toBytes(), ip, device.serialNumber);
      } else if (!receivedPrepare) {
        debugPrint('[ZkTecoNetworkService] No attendance data from $ip (may be empty or unsupported)');
      }
    } catch (e) {
      debugPrint('[ZkTecoNetworkService] Error polling device at $ip: $e');
    } finally {
      udp?.close();
    }
  }

  /// Builds a minimal ZKTeco UDP packet.
  /// ZK Protocol header: [0x50, 0x50, 0x82, 0x7D, CMD_LO, CMD_HI, 0x00, 0x00, SESSION_LO, SESSION_HI, REPLY_LO, REPLY_HI]
  static Uint8List _buildZkPacket({required int command, required int sessionId, required int replyId, List<int>? data}) {
    final dataBytes = data ?? [];

    final buf = ByteData(8 + dataBytes.length);

    // Command (2 bytes LE)
    buf.setUint16(0, command, Endian.little);
    // Checksum placeholder (2 bytes) – will be filled
    buf.setUint16(2, 0, Endian.little);
    // Session ID (2 bytes LE)
    buf.setUint16(4, sessionId, Endian.little);
    // Reply ID (2 bytes LE)
    buf.setUint16(6, replyId, Endian.little);

    // Data payload
    for (int i = 0; i < dataBytes.length; i++) {
      buf.setUint8(8 + i, dataBytes[i]);
    }

    final bytes = Uint8List.view(buf.buffer);

    // Calculate checksum over entire packet body
    int chksum = 0;
    for (int i = 0; i < bytes.length; i += 2) {
      if (i == 2) continue; // skip checksum field
      int word = bytes[i];
      if (i + 1 < bytes.length) word |= bytes[i + 1] << 8;
      chksum += word;
    }
    chksum = (chksum ^ 0xFFFF) + 1;
    chksum &= 0xFFFF;
    bytes[2] = chksum & 0xFF;
    bytes[3] = (chksum >> 8) & 0xFF;

    // Wrap with ZK transport header: magic (0x5050827D) + length
    final fullPacket = Uint8List(4 + bytes.length);
    fullPacket[0] = 0x50;
    fullPacket[1] = 0x50;
    fullPacket[2] = 0x82;
    fullPacket[3] = 0x7D;
    fullPacket.setRange(4, fullPacket.length, bytes);

    return fullPacket;
  }

  /// Waits for a UDP reply and strips the transport header, returning the payload.
  static Future<Uint8List?> _waitForReply(RawDatagramSocket udp, {required Duration timeout}) async {
    final completer = Completer<Uint8List?>();
    late StreamSubscription sub;
    late Timer timer;

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.complete(null);
      }
    });

    sub = udp.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = udp.receive();
        if (dg != null && dg.data.isNotEmpty) {
          timer.cancel();
          sub.cancel();
          if (!completer.isCompleted) {
            // Strip 4-byte transport header if present
            final raw = dg.data;
            if (raw.length > 4 && raw[0] == 0x50 && raw[1] == 0x50 && raw[2] == 0x82 && raw[3] == 0x7D) {
              completer.complete(Uint8List.fromList(raw.sublist(4)));
            } else {
              completer.complete(Uint8List.fromList(raw));
            }
          }
        }
      }
    });

    return completer.future;
  }

  /// Parses binary ZKTeco attendance log data.
  /// Each record is typically 40 bytes (newer firmware) or variable-length text.
  static void _parseZkAttendanceData(Uint8List data, String deviceIp, String deviceSn) {
    // Try text-based parsing first (some firmware returns tab-separated text)
    final textData = utf8.decode(data, allowMalformed: true);

    if (textData.contains('\t') || textData.contains('\n')) {
      // Text-format attendance records: PIN\tTIMESTAMP\tSTATUS\tVERIFY\t...
      final lines = textData.split('\n');
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        final parts = line.split('\t');
        if (parts.length >= 2) {
          final pin = parts[0].trim();
          final timeStr = parts[1].trim();
          final timestamp = DateTime.tryParse(timeStr) ?? DateTime.now();

          if (pin.isNotEmpty) {
            final dedupKey = '${deviceIp}_${pin}_$timeStr';
            if (!_lastKnownLogKeys.contains(dedupKey)) {
              _lastKnownLogKeys.add(dedupKey);
              // Prevent unlimited memory growth
              if (_lastKnownLogKeys.length > 10000) {
                final toRemove = _lastKnownLogKeys.take(5000).toList();
                _lastKnownLogKeys.removeAll(toRemove);
              }
              processIncomingPunch(
                pin: pin,
                timestamp: timestamp,
                deviceIp: deviceIp,
                deviceSn: deviceSn,
                source: 'zkteco_pull',
              );
            }
          }
        }
      }
      return;
    }

    // Binary-format parsing (40-byte fixed-length records)
    const recordSize = 40;
    if (data.length < recordSize) {
      debugPrint('[ZkTecoNetworkService] Attendance data too short: ${data.length} bytes');
      return;
    }

    final recordCount = data.length ~/ recordSize;
    debugPrint('[ZkTecoNetworkService] Parsing $recordCount binary attendance records from $deviceIp');

    for (int i = 0; i < recordCount; i++) {
      final offset = i * recordSize;
      try {
        // Bytes 0-8: User ID (null-terminated string)
        final userIdBytes = data.sublist(offset, offset + 9);
        final nullIdx = userIdBytes.indexOf(0);
        final pin = utf8.decode(userIdBytes.sublist(0, nullIdx > 0 ? nullIdx : 9), allowMalformed: true).trim();

        // Bytes 24-27: Timestamp (encoded as seconds since 2000-01-01)
        if (offset + 27 < data.length) {
          final timeEncoded = data[offset + 24] |
              (data[offset + 25] << 8) |
              (data[offset + 26] << 16) |
              (data[offset + 27] << 24);

          final timestamp = _decodeZkTime(timeEncoded);

          if (pin.isNotEmpty) {
            final dedupKey = '${deviceIp}_${pin}_${timestamp.toIso8601String()}';
            if (!_lastKnownLogKeys.contains(dedupKey)) {
              _lastKnownLogKeys.add(dedupKey);
              if (_lastKnownLogKeys.length > 10000) {
                final toRemove = _lastKnownLogKeys.take(5000).toList();
                _lastKnownLogKeys.removeAll(toRemove);
              }
              processIncomingPunch(
                pin: pin,
                timestamp: timestamp,
                deviceIp: deviceIp,
                deviceSn: deviceSn,
                source: 'zkteco_pull',
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[ZkTecoNetworkService] Error parsing record $i: $e');
      }
    }
  }

  /// Decodes ZKTeco encoded timestamp (seconds since 2000-01-01 00:00:00)
  static DateTime _decodeZkTime(int encoded) {
    final second = encoded % 60;
    encoded ~/= 60;
    final minute = encoded % 60;
    encoded ~/= 60;
    final hour = encoded % 24;
    encoded ~/= 24;
    final day = (encoded % 31) + 1;
    encoded ~/= 31;
    final month = (encoded % 12) + 1;
    encoded ~/= 12;
    final year = encoded + 2000;
    return DateTime(year, month, day, hour, minute, second);
  }

  // ── Credential & PIN Registry Management ────────────────────────────────────

  static BiometricCredential? getCredentialByPin(String pin) {
    if (!Hive.isBoxOpen(LocalStorageService.biometricCredentialsBox)) return null;
    final box = Hive.box(LocalStorageService.biometricCredentialsBox);
    for (var val in box.values) {
      if (val is Map) {
        try {
          final cred = BiometricCredential.fromMap(val);
          if (cred.biometricPin == pin && cred.active) {
            return cred;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  static List<BiometricCredential> getAllCredentials() {
    if (!Hive.isBoxOpen(LocalStorageService.biometricCredentialsBox)) return [];
    final box = Hive.box(LocalStorageService.biometricCredentialsBox);
    final List<BiometricCredential> result = [];
    for (var v in box.values) {
      if (v is Map) {
        try {
          result.add(BiometricCredential.fromMap(v));
        } catch (_) {}
      }
    }
    return result;
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
