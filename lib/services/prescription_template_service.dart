// lib/services/prescription_template_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';

class PrescriptionTemplateService {
  static const String boxName = 'doctor_prescription_templates';
  static const int maxTemplatesPerDoctor = 5;

  // No hardcoded templates forced - doctor creates and manages their own
  static const List<Map<String, dynamic>> defaultTemplates = [];

  static Future<Box> _getBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return await Hive.openBox(boxName);
  }

  /// Get list of templates created specifically by this doctor (max 5)
  /// Automatically synchronizes from Firestore so templates persist across any device/PC.
  static Future<List<Map<String, dynamic>>> loadTemplates(String branchId, {String? doctorId, bool syncCloud = true}) async {
    final List<Map<String, dynamic>> list = [];
    final targetDoctor = (doctorId ?? '').trim().toLowerCase();

    // 1. Fetch from Firestore if doctorId is provided to sync across devices
    if (syncCloud && targetDoctor.isNotEmpty) {
      try {
        final box = await _getBox();
        final effectiveBranch = branchId.isNotEmpty ? branchId : 'karachi';

        // Query 1: Branch templates collection
        final branchSnap = await FirebaseFirestore.instance
            .collection('branches')
            .doc(effectiveBranch)
            .collection('doctor_templates')
            .where('doctorId', isEqualTo: doctorId)
            .get()
            .timeout(const Duration(seconds: 6));

        for (final doc in branchSnap.docs) {
          final data = doc.data();
          if (data.isNotEmpty) {
            await box.put(doc.id, data);
          }
        }

        // Query 2: Direct user account templates for global roaming across all branches
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(doctorId)
            .collection('doctor_templates')
            .get()
            .timeout(const Duration(seconds: 6));

        for (final doc in userSnap.docs) {
          final data = doc.data();
          if (data.isNotEmpty) {
            await box.put(doc.id, data);
          }
        }
      } catch (e) {
        debugPrint('[TemplateService] Cloud template sync notice: $e');
      }
    }

    try {
      final box = await _getBox();

      final seenSignatures = <String>{};
      final duplicates = <dynamic>[];
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map) {
          final item = Map<String, dynamic>.from(raw);
          final tplDoctor = (item['doctorId'] ?? item['userId'] ?? '').toString().trim().toLowerCase();

          // Strictly include only templates belonging to this doctor if doctorId specified
          if (targetDoctor.isNotEmpty) {
            if (tplDoctor != targetDoctor) {
              continue; // Belongs to another doctor or unassigned, skip
            }
          }

          // Exact copies (same owner, name and content) are removed: earlier versions created a
          // new template every time Save was pressed.
          String signature;
          try {
            signature = '$tplDoctor|${(item['name'] ?? '').toString().trim().toLowerCase()}|'
                '${jsonEncode(item['medicines'])}|${jsonEncode(item['labResults'])}|'
                '${item['complaint']}|${item['diagnosis']}|${item['defaultDays']}';
          } catch (_) {
            signature = key.toString();
          }
          if (!seenSignatures.add(signature)) {
            duplicates.add(key);
            continue;
          }
          list.add(item);
        }
      }
      if (duplicates.isNotEmpty) {
        debugPrint('[TemplateService] Removing ${duplicates.length} duplicate template(s)');
        for (final key in duplicates) {
          final id = key.toString();
          unawaited(deleteTemplate(branchId, id, doctorId: doctorId));
        }
      }
    } catch (e) {
      debugPrint('[TemplateService] loadTemplates error: $e');
    }

    // Sort alphabetically by name
    list.sort((a, b) {
      final na = (a['name'] ?? '').toString().toLowerCase();
      final nb = (b['name'] ?? '').toString().toLowerCase();
      return na.compareTo(nb);
    });

    // Enforce max 5 limit
    if (list.length > maxTemplatesPerDoctor) {
      return list.sublist(0, maxTemplatesPerDoctor);
    }

    return list;
  }

  /// Save or update a custom template (scoped per doctor, max 5 per doctor)
  static Future<void> saveTemplate(String branchId, Map<String, dynamic> template, {String? doctorId}) async {
    try {
      final box = await _getBox();
      var id = template['id'] ?? 'tpl_${DateTime.now().millisecondsSinceEpoch}';
      final effectiveDoctorId = (doctorId ?? template['doctorId'] ?? template['userId'] ?? '').toString().trim();
      final effectiveBranch = branchId.isNotEmpty ? branchId : 'karachi';

      // Saving a template whose name this doctor already uses UPDATES that template instead of
      // creating another copy (pressing Save twice used to create duplicates with new ids).
      final nameKey = (template['name'] ?? '').toString().trim().toLowerCase();
      if (effectiveDoctorId.isNotEmpty && nameKey.isNotEmpty) {
        for (final k in box.keys) {
          final raw = box.get(k);
          if (raw is! Map) continue;
          final owner = (raw['doctorId'] ?? raw['userId'] ?? '').toString().trim().toLowerCase();
          final name = (raw['name'] ?? '').toString().trim().toLowerCase();
          if (owner == effectiveDoctorId.toLowerCase() && name == nameKey) {
            id = raw['id']?.toString() ?? k.toString();
            break;
          }
        }
      }

      // Check current count for this doctor if this is a new template
      if (effectiveDoctorId.isNotEmpty) {
        final existingTemplates = await loadTemplates(effectiveBranch, doctorId: effectiveDoctorId);
        final isExisting = existingTemplates.any((t) => t['id'] == id);
        if (!isExisting && existingTemplates.length >= maxTemplatesPerDoctor) {
          throw Exception('Maximum limit of $maxTemplatesPerDoctor quick-select disease templates reached for this doctor. Please edit or delete an existing template.');
        }
      }

      template['id'] = id;
      template['branchId'] = effectiveBranch;
      if (effectiveDoctorId.isNotEmpty) {
        template['doctorId'] = effectiveDoctorId;
        template['userId'] = effectiveDoctorId;
      }
      template['updatedAt'] = DateTime.now().toIso8601String();

      await box.put(id, template);

      // Cloud sync runs in the background and never blocks the UI: Firestore write futures
      // only complete once the server acknowledges, so awaiting them left the "Save Template"
      // dialog stuck whenever the connection was slow or the write stream was stalled.
      final cloudCopy = Map<String, dynamic>.from(template);
      unawaited(() async {
        try {
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(effectiveBranch)
              .collection('doctor_templates')
              .doc(id)
              .set(cloudCopy, SetOptions(merge: true))
              .timeout(const Duration(seconds: 20));

          if (effectiveDoctorId.isNotEmpty) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(effectiveDoctorId)
                .collection('doctor_templates')
                .doc(id)
                .set(cloudCopy, SetOptions(merge: true))
                .timeout(const Duration(seconds: 20));
          }
        } catch (e) {
          debugPrint('[TemplateService] Cloud template save deferred: $e');
        }
      }());

      // LAN broadcast
      try {
        RealtimeManager().sendMessage(RealtimeEvents.payload(
          type: 'save_prescription_template',
          branchId: effectiveBranch,
          data: template,
        ));
      } catch (_) {}
    } catch (e) {
      debugPrint('[TemplateService] saveTemplate error: $e');
      rethrow;
    }
  }

  /// Delete a template
  static Future<void> deleteTemplate(String branchId, String templateId, {String? doctorId}) async {
    try {
      final box = await _getBox();
      await box.delete(templateId);
      final effectiveBranch = branchId.isNotEmpty ? branchId : 'karachi';
      final effectiveDoctorId = (doctorId ?? '').trim();

      unawaited(() async {
        try {
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(effectiveBranch)
              .collection('doctor_templates')
              .doc(templateId)
              .delete()
              .timeout(const Duration(seconds: 20));

          if (effectiveDoctorId.isNotEmpty) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(effectiveDoctorId)
                .collection('doctor_templates')
                .doc(templateId)
                .delete()
                .timeout(const Duration(seconds: 20));
          }
        } catch (e) {
          debugPrint('[TemplateService] Cloud template delete error: $e');
        }
      }());

      // LAN broadcast deletion
      try {
        RealtimeManager().sendMessage(RealtimeEvents.payload(
          type: 'delete_prescription_template',
          branchId: effectiveBranch,
          data: {'id': templateId, if (doctorId != null) 'doctorId': doctorId},
        ));
      } catch (_) {}
    } catch (e) {
      debugPrint('[TemplateService] deleteTemplate error: $e');
    }
  }

  static IconData getIcon(String? iconName) {
    switch (iconName) {
      case 'cough':
        return FontAwesomeIcons.headSideCough;
      case 'bacteria':
        return FontAwesomeIcons.bacteria;
      case 'thermometer':
        return FontAwesomeIcons.temperatureHigh;
      case 'heart':
        return FontAwesomeIcons.heartPulse;
      case 'bone':
        return FontAwesomeIcons.bone;
      case 'lungs':
        return FontAwesomeIcons.lungs;
      case 'brain':
        return FontAwesomeIcons.brain;
      default:
        return FontAwesomeIcons.stethoscope;
    }
  }
}
