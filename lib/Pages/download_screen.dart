// lib/pages/download_screen.dart — Role-Theme Aware
// Note: excel package aliased as 'xl' to avoid Border conflict with Flutter

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/role_theme_provider.dart';
import '../theme/app_theme.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  String? _selectedBranch;
  bool _isDownloadingJson = false;
  bool _isDownloadingExcel = false;
  String _statusMessage = 'Ready';
  int _totalPatients = 0;
  int _totalTokens = 0;
  int _totalPrescriptions = 0;
  int _totalDispensary = 0;

  final Map<String, String> branches = {
    "all": "All Branches",
    "gujrat": "Gujrat",
    "sialkot": "Sialkot",
    "karachi-1": "Karachi-1",
    "karachi-2": "Karachi-2",
  };

  dynamic _sanitizeValue(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is Map)
      return value.map(
          (k, v) => MapEntry(k.toString(), _sanitizeValue(v)));
    if (value is List) return value.map(_sanitizeValue).toList();
    return value ?? '';
  }

  Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> data) {
    return data.map(
        (key, value) => MapEntry(key.toString(), _sanitizeValue(value)));
  }

  // Use xl.Excel, xl.TextCellValue to avoid Border ambiguity
  void _addSheet(xl.Excel excel, String sheetName,
      List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      excel[sheetName];
      return;
    }
    final sheet = excel[sheetName];
    final headers = data.first.keys.toList();
    sheet.appendRow(
        headers.map((h) => xl.TextCellValue(h.toString())).toList());
    for (final row in data) {
      sheet.appendRow(
          headers.map((h) => xl.TextCellValue(row[h].toString())).toList());
    }
  }

  Future<Map<String, dynamic>> _fetchAllData() async {
    final selectedId = _selectedBranch!;
    final bool downloadAll = selectedId == 'all';
    final db = FirebaseFirestore.instance;

    List<String> branchIdsToProcess = [];
    if (downloadAll) {
      final snap = await db.collection('branches').get();
      branchIdsToProcess = snap.docs.map((d) => d.id).toList();
      if (branchIdsToProcess.isEmpty) throw 'No branches found';
    } else {
      branchIdsToProcess = [selectedId];
    }

    final List<Map<String, dynamic>> allPatients = [];
    final List<Map<String, dynamic>> allTokens = [];
    final List<Map<String, dynamic>> allPrescriptions = [];
    final List<Map<String, dynamic>> allDispensary = [];
    int patients = 0, tokens = 0, prescriptions = 0, dispensary = 0;

    for (final bid in branchIdsToProcess) {
      // Patients
      try {
        final snap = await db
            .collection('branches')
            .doc(bid)
            .collection('patients')
            .get();
        for (final doc in snap.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          data['patientId'] = doc.id;
          data['branchId'] = bid;
          allPatients.add(_sanitizeForJson(data));
          patients++;
        }
      } catch (e) {}

      // Tokens
      try {
        final serialsSnap = await db
            .collection('branches')
            .doc(bid)
            .collection('serials')
            .get();
        for (final dateDoc in serialsSnap.docs) {
          for (final type in ['zakat', 'non-zakat', 'gmwf']) {
            try {
              final queueSnap =
                  await dateDoc.reference.collection(type).get();
              for (final doc in queueSnap.docs) {
                final data = Map<String, dynamic>.from(doc.data());
                data['serial'] = doc.id;
                data['date'] = dateDoc.id;
                data['queueType'] = type;
                data['branchId'] = bid;
                allTokens.add(_sanitizeForJson(data));
                tokens++;
              }
            } catch (e) {}
          }
        }
      } catch (e) {}

      // Prescriptions
      try {
        final patientSnap = await db
            .collection('branches')
            .doc(bid)
            .collection('prescriptions')
            .get();
        for (final patientDoc in patientSnap.docs) {
          try {
            final prescSnap = await patientDoc.reference
                .collection('prescriptions')
                .get();
            for (final doc in prescSnap.docs) {
              final data = Map<String, dynamic>.from(doc.data());
              data['prescriptionId'] = doc.id;
              data['patientCnic'] = patientDoc.id;
              data['branchId'] = bid;
              allPrescriptions.add(_sanitizeForJson(data));
              prescriptions++;
            }
          } catch (e) {}
        }
      } catch (e) {}

      // Dispensary / Inventory
      try {
        final snap = await db
            .collection('branches')
            .doc(bid)
            .collection('inventory')
            .get();
        for (final doc in snap.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          data['itemId'] = doc.id;
          data['branchId'] = bid;
          allDispensary.add(_sanitizeForJson(data));
          dispensary++;
        }
      } catch (e) {}
    }

    setState(() {
      _totalPatients = patients;
      _totalTokens = tokens;
      _totalPrescriptions = prescriptions;
      _totalDispensary = dispensary;
    });

    return {
      'patients': allPatients,
      'tokens': allTokens,
      'prescriptions': allPrescriptions,
      'dispensary': allDispensary,
    };
  }

  Future<void> _downloadJson(RoleThemeData t) async {
    setState(() {
      _isDownloadingJson = true;
      _statusMessage = 'Preparing JSON backup...';
    });
    try {
      final data = await _fetchAllData();
      final backupData = {
        'backupDate': DateTime.now().toIso8601String(),
        'branchSelection': branches[_selectedBranch],
        'counts': {
          'patients': _totalPatients,
          'tokens': _totalTokens,
          'prescriptions': _totalPrescriptions,
          'dispensary': _totalDispensary,
        },
        'data': data,
      };
      final jsonString =
          const JsonEncoder.withIndent('  ').convert(backupData);
      final jsonBytes = utf8.encode(jsonString);
      final dateStr =
          DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final fileName = _selectedBranch == 'all'
          ? 'full_backup_all_branches_$dateStr.json'
          : 'backup_${branches[_selectedBranch]!.toLowerCase()}_$dateStr.json';

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save JSON Backup',
        fileName: fileName,
        bytes: jsonBytes,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null) {
        Clipboard.setData(ClipboardData(text: result));
        _showSnack('JSON Backup Saved!\nLocation: $result',
            color: t.accent);
      } else {
        _showSnack('JSON backup cancelled',
            color: Colors.orange.shade700);
      }
    } catch (e) {
      _showSnack('JSON backup failed: $e', color: t.danger);
    } finally {
      setState(() {
        _isDownloadingJson = false;
        if (!_isDownloadingExcel) _statusMessage = 'Ready';
      });
    }
  }

  Future<void> _downloadExcel(RoleThemeData t) async {
    setState(() {
      _isDownloadingExcel = true;
      _statusMessage = 'Preparing Excel backup...';
    });
    try {
      final data = await _fetchAllData();
      final excel = xl.Excel.createExcel();
      excel.rename('Sheet1', 'Patients');
      _addSheet(excel, 'Patients', data['patients']);
      _addSheet(excel, 'Tokens', data['tokens']);
      _addSheet(excel, 'Prescriptions', data['prescriptions']);
      _addSheet(excel, 'Dispensary', data['dispensary']);

      final excelBytesList = excel.encode();
      final Uint8List excelBytes = excelBytesList != null
          ? Uint8List.fromList(excelBytesList)
          : Uint8List(0);
      final dateStr =
          DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final fileName = _selectedBranch == 'all'
          ? 'full_backup_all_branches_$dateStr.xlsx'
          : 'backup_${branches[_selectedBranch]!.toLowerCase()}_$dateStr.xlsx';

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Excel Backup',
        fileName: fileName,
        bytes: excelBytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (result != null) {
        Clipboard.setData(ClipboardData(text: result));
        _showSnack('Excel Backup Saved!\nLocation: $result',
            color: const Color(0xFF2E7D32));
      } else {
        _showSnack('Excel backup cancelled',
            color: Colors.orange.shade700);
      }
    } catch (e) {
      _showSnack('Excel backup failed: $e', color: Colors.red);
    } finally {
      setState(() {
        _isDownloadingExcel = false;
        if (!_isDownloadingJson) _statusMessage = 'Ready';
      });
    }
  }

  void _showSnack(String msg, {required Color color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(
        label: 'Close',
        textColor: Colors.white,
        onPressed: () =>
            ScaffoldMessenger.of(context).hideCurrentSnackBar(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final bool isBusy = _isDownloadingJson || _isDownloadingExcel;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Text('Download Backup',
            style: TextStyle(
                color: t.textPrimary, fontWeight: FontWeight.w700)),
        backgroundColor: t.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: t.textSecondary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.bgRule),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: t.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.bgRule),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: t.accentMuted,
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.cloud_download_outlined,
                        color: t.accent, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Clinic Backup',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: t.textPrimary)),
                        Text(
                            'JSON (structured data) or Excel (spreadsheet)',
                            style: TextStyle(
                                fontSize: 13,
                                color: t.textSecondary)),
                      ],
                    ),
                  ),
                ]),

                const SizedBox(height: 32),

                // ── Branch selector ──────────────────────────────────
                DropdownButtonFormField<String>(
                  value: _selectedBranch,
                  dropdownColor: t.bgCard,
                  decoration: InputDecoration(
                    labelText: 'Select Branch',
                    labelStyle: TextStyle(
                        color: t.textTertiary, fontSize: 13),
                    floatingLabelStyle: TextStyle(
                        color: t.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    prefixIcon: Icon(Icons.account_tree_outlined,
                        color: t.textTertiary, size: 20),
                    filled: true,
                    fillColor: t.bg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: t.bgRule)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: t.bgRule)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: t.accent, width: 2)),
                  ),
                  items: branches.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: t.textPrimary))))
                      .toList(),
                  onChanged: isBusy
                      ? null
                      : (v) => setState(() => _selectedBranch = v),
                ),

                const SizedBox(height: 40),

                // ── Busy indicator ───────────────────────────────────
                if (isBusy) ...[
                  LinearProgressIndicator(
                    color: t.accent,
                    backgroundColor: t.accentMuted,
                  ),
                  const SizedBox(height: 24),
                  Row(children: [
                    CircularProgressIndicator(
                        color: t.accent, strokeWidth: 2.5),
                    const SizedBox(width: 24),
                    Expanded(
                        child: Text(_statusMessage,
                            style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 14))),
                  ]),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: t.accentMuted.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.bgRule),
                    ),
                    child: Text(
                      'Collected: Patients $_totalPatients  |  Tokens $_totalTokens  |  Prescriptions $_totalPrescriptions  |  Dispensary $_totalDispensary',
                      style: TextStyle(
                          color: t.textSecondary, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],

                // ── Download buttons ─────────────────────────────────
                if (!isBusy && _selectedBranch != null) ...[
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isDownloadingExcel
                            ? null
                            : () => _downloadJson(t),
                        icon: const Icon(Icons.data_object, size: 22),
                        label: const Text('Download JSON',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              t.accent.withOpacity(0.35),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isDownloadingJson
                            ? null
                            : () => _downloadExcel(t),
                        icon:
                            const Icon(Icons.table_chart, size: 22),
                        label: const Text('Download Excel',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.accentLight,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              t.accentLight.withOpacity(0.35),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: t.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.bgRule),
                      ),
                      child: Text(
                        'Patients: $_totalPatients  ·  Tokens: $_totalTokens  ·  Prescriptions: $_totalPrescriptions  ·  Dispensary: $_totalDispensary',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: t.textSecondary),
                      ),
                    ),
                  ),
                ],

                if (!isBusy && _selectedBranch == null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Select a branch to enable downloads',
                        style: TextStyle(
                            fontSize: 15, color: t.textTertiary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}