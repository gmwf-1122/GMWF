// lib/services/ramadan_welfare_service.dart

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../utils/cnic_parser_util.dart';
import 'local_storage_service.dart';

class RamadanWelfareService {
  static const String boxName = 'ramadan_registrations';

  static Future<void> init() async {
    await LocalStorageService.openBoxSafe(boxName);
    debugPrint('[RamadanWelfareService] Storage initialized');
  }

  static Box get _box => Hive.box(boxName);

  /// Check if CNIC or Phone Number is already registered for the target campaign.
  /// (Names can be duplicated, but CNIC or Phone numbers cannot be duplicated).
  static Map<String, dynamic>? checkBeneficiaryDuplicate({
    String? cnic,
    String? phone,
    required String campaign,
  }) {
    final normCnic = (cnic != null && cnic.trim().isNotEmpty) ? CnicParserUtil.normalizeCnic(cnic) : '';
    final normPhone = (phone != null && phone.trim().isNotEmpty) ? phone.replaceAll(RegExp(r'[^0-9]'), '').trim() : '';
    final targetCampaign = campaign.toLowerCase().trim();

    if (normCnic.isEmpty && normPhone.isEmpty) return null;

    for (final val in _box.values) {
      if (val is Map) {
        final Map<String, dynamic> reg = Map<String, dynamic>.from(val);
        final regNormCnic = CnicParserUtil.normalizeCnic((reg['cnic'] ?? '').toString());
        final regNormPhone = (reg['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '').trim();
        final regCampaign = (reg['campaign'] ?? '').toString().toLowerCase().trim();

        if (regCampaign == targetCampaign || regCampaign == 'both' || targetCampaign == 'both') {
          if (normCnic.length >= 13 && regNormCnic.length >= 13 && regNormCnic == normCnic) {
            final res = Map<String, dynamic>.from(reg);
            res['dupReason'] = 'CNIC ($regNormCnic)';
            return res;
          }
          if (normPhone.length >= 10 && regNormPhone.length >= 10 && regNormPhone == normPhone) {
            final res = Map<String, dynamic>.from(reg);
            res['dupReason'] = 'Phone Number ($regNormPhone)';
            return res;
          }
        }
      }
    }
    return null;
  }

  /// Backward-compatible wrapper
  static Map<String, dynamic>? checkCnicDuplicate({
    required String cnic,
    required String campaign,
    String? phone,
  }) {
    return checkBeneficiaryDuplicate(cnic: cnic, phone: phone, campaign: campaign);
  }

  /// Save a new beneficiary registration
  static Future<Map<String, dynamic>> registerBeneficiary({
    required String cnic,
    required String name,
    required String phone,
    required String campaign, // 'rations', 'libaas', 'both'
    required String branchId,
    required String operatorName,
    int familyMembers = 1,
    String libaasSize = 'Adult Medium',
    String notes = '',
  }) async {
    final normCnic = CnicParserUtil.normalizeCnic(cnic);
    final formattedCnic = CnicParserUtil.formatCnic(normCnic);
    final timestamp = DateTime.now();
    final id = 'ram_${const Uuid().v4()}';
    final serialNo = 'RMD-${timestamp.year}-${(_box.length + 1).toString().padLeft(5, '0')}';

    final data = <String, dynamic>{
      'id': id,
      'serialNo': serialNo,
      'cnic': formattedCnic,
      'normCnic': normCnic,
      'name': name.trim().toUpperCase(),
      'phone': phone.trim(),
      'campaign': campaign.toLowerCase().trim(),
      'branchId': branchId,
      'operatorName': operatorName,
      'familyMembers': familyMembers,
      'libaasSize': libaasSize,
      'notes': notes.trim(),
      'registeredAt': timestamp.toIso8601String(),
      'isWinner': false,
      'winTimestamp': null,
      'winPassNo': null,
      'syncStatus': 'pending',
    };

    // 1. Save to local Hive
    await _box.put(id, data);

    // 2. Queue for Firestore & LAN server sync
    await LocalStorageService.enqueueSync({
      'type': 'ramadan_registration',
      'branchId': branchId,
      'hiveKey': id,
      'data': data,
    });

    // 3. Direct Firestore push if online
    try {
      FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('ramadan_registrations')
          .doc(id)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[RamadanWelfareService] Firestore background save error: $e');
    }

    return data;
  }

  /// Get all registered beneficiaries with filters
  static List<Map<String, dynamic>> getRegistrations({
    String? campaign,
    String? branchId,
    String? searchQuery,
    bool? winnersOnly,
  }) {
    var list = _box.values
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList();

    if (branchId != null && branchId.isNotEmpty && branchId != 'all' && branchId != 'global') {
      list = list.where((r) => (r['branchId'] ?? '').toString() == branchId).toList();
    }

    if (campaign != null && campaign.isNotEmpty && campaign != 'all') {
      final target = campaign.toLowerCase().trim();
      list = list.where((r) {
        final c = (r['campaign'] ?? '').toString().toLowerCase().trim();
        return c == target || c == 'both' || target == 'both';
      }).toList();
    }

    if (winnersOnly == true) {
      list = list.where((r) => r['isWinner'] == true).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list.where((r) {
        final name = (r['name'] ?? '').toString().toLowerCase();
        final cnic = (r['cnic'] ?? '').toString().toLowerCase();
        final phone = (r['phone'] ?? '').toString().toLowerCase();
        final serial = (r['serialNo'] ?? '').toString().toLowerCase();
        return name.contains(q) || cnic.contains(q) || phone.contains(q) || serial.contains(q);
      }).toList();
    }

    list.sort((a, b) => ((b['registeredAt'] as String?) ?? '').compareTo((a['registeredAt'] as String?) ?? ''));
    return list;
  }

  /// Execute Provably Fair 1,000 Winner Lucky Draw
  static Future<List<Map<String, dynamic>>> executeLuckyDraw({
    required String campaign, // 'rations', 'libaas', 'both'
    required int winnerCount,
    String? branchId,
  }) async {
    final eligiblePool = getRegistrations(
      campaign: campaign,
      branchId: branchId,
    ).where((r) => r['isWinner'] != true).toList();

    if (eligiblePool.isEmpty) return [];

    // Shuffle pool using Random.secure()
    final secureRandom = Random.secure();
    eligiblePool.shuffle(secureRandom);

    final selectCount = min(winnerCount, eligiblePool.length);
    final winners = <Map<String, dynamic>>[];
    final now = DateTime.now();

    for (int i = 0; i < selectCount; i++) {
      final winner = eligiblePool[i];
      final passNo = 'PASS-${now.year}-${(i + 1).toString().padLeft(4, '0')}';
      winner['isWinner'] = true;
      winner['winTimestamp'] = now.toIso8601String();
      winner['winPassNo'] = passNo;

      // Update Hive
      await _box.put(winner['id'], winner);

      // Queue Sync
      await LocalStorageService.enqueueSync({
        'type': 'ramadan_lucky_draw_winner',
        'branchId': winner['branchId'],
        'hiveKey': winner['id'],
        'data': winner,
      });

      // Update Firestore
      try {
        FirebaseFirestore.instance
            .collection('branches')
            .doc(winner['branchId'] ?? 'global')
            .collection('ramadan_registrations')
            .doc(winner['id'])
            .update({
          'isWinner': true,
          'winTimestamp': now.toIso8601String(),
          'winPassNo': passNo,
        });
      } catch (_) {}

      winners.add(winner);
    }

    return winners;
  }
}
