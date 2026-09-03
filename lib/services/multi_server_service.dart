// lib/services/multi_server_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'auto_update_service.dart';
import '../utils/network_utils.dart';
import '../config/constants.dart';

class ServerNodeInfo {
  final String serverId;
  final String serverName;
  final String branchId;
  final String ipAddress;
  final int port;
  final String role; // 'primary', 'secondary', 'standby'
  final bool isOnline;
  final int connectedClients;
  final int syncQueueSize;
  final DateTime lastHeartbeat;
  final String appVersion;

  ServerNodeInfo({
    required this.serverId,
    required this.serverName,
    required this.branchId,
    required this.ipAddress,
    required this.port,
    required this.role,
    required this.isOnline,
    required this.connectedClients,
    required this.syncQueueSize,
    required this.lastHeartbeat,
    required this.appVersion,
  });

  factory ServerNodeInfo.fromMap(Map<String, dynamic> map, String id) {
    return ServerNodeInfo(
      serverId: id,
      serverName: map['serverName'] ?? 'Branch Server',
      branchId: map['branchId'] ?? '',
      ipAddress: map['ipAddress'] ?? '127.0.0.1',
      port: map['port'] as int? ?? AppNetwork.websocketPort,
      role: map['role'] ?? 'secondary',
      isOnline: map['isOnline'] as bool? ?? false,
      connectedClients: map['connectedClients'] as int? ?? 0,
      syncQueueSize: map['syncQueueSize'] as int? ?? 0,
      lastHeartbeat: map['lastHeartbeat'] is Timestamp
          ? (map['lastHeartbeat'] as Timestamp).toDate()
          : DateTime.now(),
      appVersion: map['appVersion'] ?? AutoUpdateService.currentVersion,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'serverId': serverId,
      'serverName': serverName,
      'branchId': branchId,
      'ipAddress': ipAddress,
      'port': port,
      'role': role,
      'isOnline': isOnline,
      'connectedClients': connectedClients,
      'syncQueueSize': syncQueueSize,
      'lastHeartbeat': FieldValue.serverTimestamp(),
      'appVersion': appVersion,
    };
  }
}

class MultiServerService {
  static final MultiServerService _instance = MultiServerService._internal();
  factory MultiServerService() => _instance;
  MultiServerService._internal();

  Timer? _heartbeatTimer;
  String? _currentServerId;

  /// Registers and periodically updates this machine's server node record.
  Future<void> registerAndHeartbeat({
    required String branchId,
    required String serverRole, // 'primary', 'secondary', 'standby'
    required int connectedClientsCount,
    required int syncQueueSize,
  }) async {
    try {
      final ip = await getPrimaryLanIp() ?? '192.168.1.x';
      final hostName = Platform.localHostname.isNotEmpty ? Platform.localHostname : 'Branch-Server';
      final serverId = 'srv_${hostName.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
      _currentServerId = serverId;

      final serverData = {
        'serverId': serverId,
        'serverName': '$hostName Server',
        'branchId': branchId,
        'ipAddress': ip,
        'port': AppNetwork.websocketPort,
        'role': serverRole,
        'isOnline': true,
        'connectedClients': connectedClientsCount,
        'syncQueueSize': syncQueueSize,
        'lastHeartbeat': FieldValue.serverTimestamp(),
        'appVersion': AutoUpdateService.currentVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 1. Update Firestore under branches/{branchId}/servers/{serverId}
      if (branchId.isNotEmpty && branchId != 'all') {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('servers')
            .doc(serverId)
            .set(serverData, SetOptions(merge: true));

        // 2. Also keep global branch active server record for clients auto-discovery
        if (serverRole == 'primary') {
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(branchId)
              .set({'activeServerIp': ip, 'activeServerPort': AppNetwork.websocketPort}, SetOptions(merge: true));
        }
      }

      // 3. Cache locally in Hive
      final hiveData = Map<String, dynamic>.from(serverData);
      hiveData['lastHeartbeat'] = DateTime.now().toIso8601String();
      hiveData['updatedAt'] = DateTime.now().toIso8601String();

      final box = await Hive.openBox('branch_servers');
      await box.put(serverId, hiveData);

      debugPrint('[MultiServerService] Node heartbeat recorded for $serverId ($ip:$serverRole)');
    } catch (e) {
      debugPrint('[MultiServerService] Heartbeat recording error: $e');
    }
  }

  /// Starts periodic heartbeat updates (runs every 15 seconds)
  void startHeartbeatLoop({
    required String branchId,
    required String Function() roleSupplier,
    required int Function() clientsSupplier,
    required int Function() queueSupplier,
  }) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      registerAndHeartbeat(
        branchId: branchId,
        serverRole: roleSupplier(),
        connectedClientsCount: clientsSupplier(),
        syncQueueSize: queueSupplier(),
      );
    });
  }

  /// Stops heartbeat loop and marks node as offline
  Future<void> stopHeartbeat(String branchId) async {
    _heartbeatTimer?.cancel();
    if (_currentServerId != null && branchId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('servers')
            .doc(_currentServerId)
            .set({'isOnline': false, 'lastHeartbeat': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[MultiServerService] Failed to mark server offline: $e');
      }
    }
  }

  /// Real-time stream of all servers for a specific branch or all branches
  Stream<List<ServerNodeInfo>> getBranchServersStream(String branchId) {
    if (branchId.isEmpty || branchId == 'all' || branchId == 'global') {
      return FirebaseFirestore.instance
          .collectionGroup('servers')
          .snapshots()
          .map((snap) {
        return snap.docs.map((doc) => ServerNodeInfo.fromMap(doc.data(), doc.id)).toList();
      });
    }

    return FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('servers')
        .snapshots()
        .map((snap) {
      return snap.docs.map((doc) => ServerNodeInfo.fromMap(doc.data(), doc.id)).toList();
    });
  }

  /// Sets a specific server node as the Primary Server for the branch
  Future<void> promoteToPrimary(String branchId, String targetServerId, String targetIp) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final serversRef = FirebaseFirestore.instance.collection('branches').doc(branchId).collection('servers');

      final docs = await serversRef.get();
      for (final doc in docs.docs) {
        if (doc.id == targetServerId) {
          batch.update(doc.reference, {'role': 'primary', 'updatedAt': FieldValue.serverTimestamp()});
        } else {
          batch.update(doc.reference, {'role': 'secondary', 'updatedAt': FieldValue.serverTimestamp()});
        }
      }

      // Update primary branch active IP pointer
      final branchRef = FirebaseFirestore.instance.collection('branches').doc(branchId);
      batch.set(branchRef, {'activeServerIp': targetIp}, SetOptions(merge: true));

      await batch.commit();
      debugPrint('[MultiServerService] Promoted $targetServerId ($targetIp) to Primary Server');
    } catch (e) {
      debugPrint('[MultiServerService] Failed to promote primary server: $e');
    }
  }
}
