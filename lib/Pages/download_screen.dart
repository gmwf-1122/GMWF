// lib/pages/download_screen.dart
// FINAL VERSION - SEPARATE BUTTONS FOR JSON AND EXCEL BACKUP
// Two independent buttons: "Download JSON Backup" and "Download Excel Backup"
// You can use one or both as needed

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), _sanitizeValue(v)));
    if (value is List) return value.map(_sanitizeValue).toList();
    return value ?? '';
  }

  Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key.toString(), _sanitizeValue(value)));
  }

  void _addSheet(Excel excel, String sheetName, List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      excel[sheetName];
      return;
    }

    final sheet = excel[sheetName];
    final headers = data.first.keys.toList();

    sheet.appendRow(headers.map((h) => TextCellValue(h.toString())).toList());

    for (final row in data) {
      final values = headers.map((h) => TextCellValue(row[h].toString())).toList();
      sheet.appendRow(values);
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
        final snap = await db.collection('branches').doc(bid).collection('patients').get();
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
        final serialsSnap = await db.collection('branches').doc(bid).collection('serials').get();
        for (final dateDoc in serialsSnap.docs) {
          final types = ['zakat', 'non-zakat', 'gmwf'];
          for (final type in types) {
            try {
              final queueSnap = await dateDoc.reference.collection(type).get();
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
        final patientSnap = await db.collection('branches').doc(bid).collection('prescriptions').get();
        for (final patientDoc in patientSnap.docs) {
          try {
            final prescSnap = await patientDoc.reference.collection('prescriptions').get();
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

      // Dispensary (Inventory)
      try {
        final snap = await db.collection('branches').doc(bid).collection('inventory').get();
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

  Future<void> _downloadJson() async {
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

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      final jsonBytes = utf8.encode(jsonString);

      final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JSON Backup Saved!\nLocation: $result'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(label: 'Close', onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar()),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('JSON backup cancelled'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JSON backup failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isDownloadingJson = false;
        if (!_isDownloadingExcel) _statusMessage = 'Ready';
      });
    }
  }

  Future<void> _downloadExcel() async {
    setState(() {
      _isDownloadingExcel = true;
      _statusMessage = 'Preparing Excel backup...';
    });

    try {
      final data = await _fetchAllData();

      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Patients');
      _addSheet(excel, 'Patients', data['patients']);
      _addSheet(excel, 'Tokens', data['tokens']);
      _addSheet(excel, 'Prescriptions', data['prescriptions']);
      _addSheet(excel, 'Dispensary', data['dispensary']);

      final excelBytesList = excel.encode();
      final Uint8List excelBytes = excelBytesList != null ? Uint8List.fromList(excelBytesList) : Uint8List(0);

      final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel Backup Saved!\nLocation: $result'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(label: 'Close', onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar()),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel backup cancelled'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel backup failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isDownloadingExcel = false;
        if (!_isDownloadingJson) _statusMessage = 'Ready';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isBusy = _isDownloadingJson || _isDownloadingExcel;

    return Scaffold(
      appBar: AppBar(title: const Text("Download Backup"), backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Clinic Backup Options", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
              const Text("Choose format: JSON (structured data) or Excel (spreadsheets)", style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 40),

              DropdownButtonFormField<String>(
                value: _selectedBranch,
                decoration: const InputDecoration(labelText: "Select Branch", prefixIcon: Icon(Icons.account_tree)),
                items: branches.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: isBusy ? null : (v) => setState(() => _selectedBranch = v),
              ),

              const SizedBox(height: 60),

              if (isBusy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 24),
                Row(children: [const CircularProgressIndicator(), const SizedBox(width: 24), Expanded(child: Text(_statusMessage))]),
                const SizedBox(height: 20),
                Text('Collected: Patients $_totalPatients | Tokens $_totalTokens | Prescriptions $_totalPrescriptions | Dispensary $_totalDispensary'),
                const SizedBox(height: 40),
              ],

              if (!isBusy && _selectedBranch != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isDownloadingExcel ? null : _downloadJson,
                      icon: const Icon(Icons.data_object, size: 28),
                      label: const Text("Download JSON", style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                      ),
                    ),
                    const SizedBox(width: 30),
                    ElevatedButton.icon(
                      onPressed: _isDownloadingJson ? null : _downloadExcel,
                      icon: const Icon(Icons.table_chart, size: 28),
                      label: const Text("Download Excel", style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Patients: $_totalPatients | Tokens: $_totalTokens\nPrescriptions: $_totalPrescriptions | Dispensary: $_totalDispensary',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
              ],

              if (!isBusy && _selectedBranch == null)
                const Center(child: Text("Select a branch to enable downloads", style: TextStyle(fontSize: 18, color: Colors.grey))),
            ],
          ),
        ),
      ),
    );
  }
}