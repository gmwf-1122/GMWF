// lib/pages/download_screen.dart — Enhanced with Date Range & Visualizations
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

// ─── Date Filter Mode ────────────────────────────────────────────────────────
enum DateFilterMode { allTime, singleDay, dateRange }

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen>
    with TickerProviderStateMixin {
  String? _selectedBranch;
  bool _isDownloadingJson = false;
  bool _isDownloadingExcel = false;
  String _statusMessage = 'Ready';

  // Date filter state
  DateFilterMode _dateMode = DateFilterMode.allTime;
  DateTime? _singleDate;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  // Live counts
  int _totalPatients = 0;
  int _totalTokens = 0;
  int _totalPrescriptions = 0;
  int _totalDonations = 0;
  int _totalFood = 0;
  int _totalCredits = 0;
  int _totalDispensary = 0;

  // Animation controllers
  late AnimationController _cardController;
  late AnimationController _statsController;
  late Animation<double> _cardFade;
  late Animation<double> _statsFade;

  final Map<String, String> branches = {
    "all": "All Branches",
    "gujrat": "Gujrat",
    "sialkot": "Sialkot",
    "karachi-1": "Karachi-1",
    "karachi-2": "Karachi-2",
  };

  @override
  void initState() {
    super.initState();
    _cardController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));
    _statsController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _cardFade = CurvedAnimation(
        parent: _cardController, curve: Curves.easeOutCubic);
    _statsFade = CurvedAnimation(
        parent: _statsController, curve: Curves.easeOutCubic);
    _cardController.forward();
  }

  @override
  void dispose() {
    _cardController.dispose();
    _statsController.dispose();
    super.dispose();
  }

  // ─── Sanitisers ─────────────────────────────────────────────────────────────
  dynamic _sanitizeValue(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is Map)
      return value.map(
          (k, v) => MapEntry(k.toString(), _sanitizeValue(v)));
    if (value is List) return value.map(_sanitizeValue).toList();
    return value ?? '';
  }

  Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> data) =>
      data.map((key, value) =>
          MapEntry(key.toString(), _sanitizeValue(value)));

  // ─── Date helpers ────────────────────────────────────────────────────────────
  String get _dateLabel {
    switch (_dateMode) {
      case DateFilterMode.allTime:
        return 'All Time';
      case DateFilterMode.singleDay:
        return _singleDate != null
            ? DateFormat('dd MMM yyyy').format(_singleDate!)
            : 'Pick a date';
      case DateFilterMode.dateRange:
        if (_rangeStart != null && _rangeEnd != null) {
          return '${DateFormat('dd MMM').format(_rangeStart!)} → ${DateFormat('dd MMM yyyy').format(_rangeEnd!)}';
        }
        return 'Pick range';
    }
  }

  bool _isDateInRange(String? dateStr) {
    if (dateStr == null || _dateMode == DateFilterMode.allTime) return true;
    try {
      // dateStr may be "yyyy-MM-dd" (from serials doc id) or ISO8601
      final date = dateStr.length == 10
          ? DateFormat('yyyy-MM-dd').parse(dateStr)
          : DateTime.parse(dateStr);
      if (_dateMode == DateFilterMode.singleDay && _singleDate != null) {
        return date.year == _singleDate!.year &&
            date.month == _singleDate!.month &&
            date.day == _singleDate!.day;
      }
      if (_dateMode == DateFilterMode.dateRange &&
          _rangeStart != null &&
          _rangeEnd != null) {
        final start =
            DateTime(_rangeStart!.year, _rangeStart!.month, _rangeStart!.day);
        final end = DateTime(
            _rangeEnd!.year, _rangeEnd!.month, _rangeEnd!.day, 23, 59, 59);
        return date.isAfter(start.subtract(const Duration(seconds: 1))) &&
            date.isBefore(end.add(const Duration(seconds: 1)));
      }
    } catch (_) {}
    return true;
  }

  // ─── Date pickers ────────────────────────────────────────────────────────────
  Future<void> _pickSingleDate(RoleThemeData t) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _singleDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => _datePickerTheme(ctx, child, t),
    );
    if (picked != null) setState(() => _singleDate = picked);
  }

  Future<void> _pickDateRange(RoleThemeData t) async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: (_rangeStart != null && _rangeEnd != null)
          ? DateTimeRange(start: _rangeStart!, end: _rangeEnd!)
          : null,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => _datePickerTheme(ctx, child, t),
    );
    if (picked != null) {
      setState(() {
        _rangeStart = picked.start;
        _rangeEnd = picked.end;
      });
    }
  }

  Widget _datePickerTheme(
      BuildContext ctx, Widget? child, RoleThemeData t) {
    return Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: ColorScheme.dark(
          primary: t.accent,
          onPrimary: Colors.white,
          surface: t.bgCard,
          onSurface: t.textPrimary,
        ),
        dialogBackgroundColor: t.bgCard,
      ),
      child: child!,
    );
  }

  // ─── Excel sheet builder ─────────────────────────────────────────────────────
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

  // ─── Core data fetcher (with date filtering) ──────────────────────────────
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
    final List<Map<String, dynamic>> allDonations = [];
    final List<Map<String, dynamic>> allFood = [];
    final List<Map<String, dynamic>> allCredits = [];
    final List<Map<String, dynamic>> allDispensary = [];

    int patients = 0, tokens = 0, prescriptions = 0, donations = 0, food = 0, credits = 0, dispensary = 0;

    // Pre-calculate date keys for range if not allTime
    List<String> dsLegacyKeys = []; // ddMMyy
    List<String> dsDashKeys   = []; // yyyy-MM-dd

    if (_dateMode != DateFilterMode.allTime) {
      DateTime start = _dateMode == DateFilterMode.singleDay ? _singleDate! : _rangeStart!;
      DateTime end   = _dateMode == DateFilterMode.singleDay ? _singleDate! : _rangeEnd!;
      
      // Safety: Normalize times
      start = DateTime(start.year, start.month, start.day);
      end   = DateTime(end.year, end.month, end.day);

      int days = end.difference(start).inDays + 1;
      // Cap at 366 days for safety
      if (days > 366) days = 366;

      for (int i = 0; i < days; i++) {
        final d = start.add(Duration(days: i));
        dsLegacyKeys.add(DateFormat('ddMMyy').format(d));
        dsDashKeys.add(DateFormat('yyyy-MM-dd').format(d));
      }
    }

    for (final bid in branchIdsToProcess) {
      setState(() => _statusMessage = 'Fetching $bid patterns...');

      // ── Patients (Always fetch all for now, but filter by date) ──
      try {
        final snap = await db.collection('branches').doc(bid).collection('patients').get();
        for (final doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          data['patientId'] = doc.id;
          data['branchId'] = bid;
          final sanitized = _sanitizeForJson(data);
          final regDate = sanitized['registrationDate'] ?? sanitized['createdAt'];
          if (_isDateInRange(regDate?.toString())) {
            allPatients.add(sanitized);
            patients++;
          }
        }
      } catch (_) {}

      // ── Tokens (serials: ddMMyy) ──
      try {
        if (_dateMode == DateFilterMode.allTime) {
          final snap = await db.collection('branches').doc(bid).collection('serials').get();
          for (final dateDoc in snap.docs) {
            for (final type in ['zakat', 'non-zakat', 'gmwf']) {
              final qSnap = await dateDoc.reference.collection(type).get();
              for (final doc in qSnap.docs) {
                final d = doc.data() as Map<String, dynamic>;
                d['serial'] = doc.id; d['date'] = dateDoc.id; d['queueType'] = type; d['branchId'] = bid;
                allTokens.add(_sanitizeForJson(d)); tokens++;
              }
            }
          }
        } else {
          // Optimized: Fetch only specific days
          await Future.wait(dsLegacyKeys.map((key) async {
            final dateDoc = db.collection('branches').doc(bid).collection('serials').doc(key);
            await Future.wait(['zakat', 'non-zakat', 'gmwf'].map((type) async {
              try {
                final qSnap = await dateDoc.collection(type).get();
                for (final doc in qSnap.docs) {
                  final d = doc.data() as Map<String, dynamic>;
                  d['serial'] = doc.id; d['date'] = key; d['queueType'] = type; d['branchId'] = bid;
                  allTokens.add(_sanitizeForJson(d)); tokens++;
                }
              } catch (_) {}
            }));
          }));
        }
      } catch (_) {}

      // ── Food Tokens (dasterkhwaan: yyyy-MM-dd) ──
      try {
        if (_dateMode == DateFilterMode.allTime) {
          final snap = await db.collection('branches').doc(bid).collection('dasterkhwaan').get();
          for (final dateDoc in snap.docs) {
            final qSnap = await dateDoc.reference.collection('tokens').get();
            for (final doc in qSnap.docs) {
              final d = doc.data() as Map<String, dynamic>;
              d['id'] = doc.id; d['date'] = dateDoc.id; d['branchId'] = bid;
              allFood.add(_sanitizeForJson(d)); food++;
            }
          }
        } else {
          await Future.wait(dsDashKeys.map((key) async {
            try {
              final qSnap = await db.collection('branches').doc(bid).collection('dasterkhwaan').doc(key).collection('tokens').get();
              for (final doc in qSnap.docs) {
                final d = doc.data() as Map<String, dynamic>;
                d['id'] = doc.id; d['date'] = key; d['branchId'] = bid;
                allFood.add(_sanitizeForJson(d)); food++;
              }
            } catch (_) {}
          }));
        }
      } catch (_) {}

      // ── Donations (date: yyyy-MM-dd) ──
      try {
        Query query = db.collection('branches').doc(bid).collection('donations');
        if (_dateMode != DateFilterMode.allTime) {
          if (_dateMode == DateFilterMode.singleDay) {
            query = query.where('date', isEqualTo: dsDashKeys.first);
          } else {
            query = query.where('date', isGreaterThanOrEqualTo: dsDashKeys.first)
                         .where('date', isLessThanOrEqualTo: dsDashKeys.last);
          }
        }
        final snap = await query.get();
        for (final doc in snap.docs) {
          if (doc.id == 'credit_ledger') continue;
          final d = doc.data() as Map<String, dynamic>;
          d['id'] = doc.id; d['branchId'] = bid;
          allDonations.add(_sanitizeForJson(d)); donations++;
        }
      } catch (_) {}

      // ── Credit Ledger (date: yyyy-MM-dd) ──
      try {
        Query query = db.collection('branches').doc(bid).collection('creditLedger');
        if (_dateMode != DateFilterMode.allTime) {
          if (_dateMode == DateFilterMode.singleDay) {
            query = query.where('date', isEqualTo: dsDashKeys.first);
          } else {
            query = query.where('date', isGreaterThanOrEqualTo: dsDashKeys.first)
                         .where('date', isLessThanOrEqualTo: dsDashKeys.last);
          }
        }
        final snap = await query.get();
        for (final doc in snap.docs) {
          final d = doc.data() as Map<String, dynamic>;
          d['id'] = doc.id; d['branchId'] = bid;
          allCredits.add(_sanitizeForJson(d)); credits++;
        }
      } catch (_) {}

      // ── Prescriptions ──
      try {
        final patientSnap = await db.collection('branches').doc(bid).collection('prescriptions').get();
        for (final patientDoc in patientSnap.docs) {
          final prescSnap = await patientDoc.reference.collection('prescriptions').get();
          for (final doc in prescSnap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            data['prescriptionId'] = doc.id; data['patientCnic'] = patientDoc.id; data['branchId'] = bid;
            final sanitized = _sanitizeForJson(data);
            final prescDate = sanitized['date'] ?? sanitized['createdAt'];
            if (_isDateInRange(prescDate?.toString())) {
              allPrescriptions.add(sanitized); prescriptions++;
            }
          }
        }
      } catch (_) {}

      // ── Inventory ──
      try {
        final snap = await db.collection('branches').doc(bid).collection('inventory').get();
        for (final doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          data['itemId'] = doc.id; data['branchId'] = bid;
          allDispensary.add(_sanitizeForJson(data)); dispensary++;
        }
      } catch (_) {}
      
      // Update intermediate counts for UI
      setState(() {
        _totalPatients = patients; _totalTokens = tokens; _totalPrescriptions = prescriptions;
        _totalDonations = donations; _totalFood = food; _totalCredits = credits; _totalDispensary = dispensary;
      });
    }

    // Sort lists
    _sortByDate(allPatients, ['registrationDate', 'createdAt']);
    _sortByDate(allTokens, ['date', 'createdAt']);
    _sortByDate(allPrescriptions, ['date', 'createdAt']);
    _sortByDate(allDonations, ['date', 'timestamp']);
    _sortByDate(allFood, ['date', 'timestamp']);
    _sortByDate(allCredits, ['date', 'timestamp']);

    return {
      'patients': allPatients,
      'tokens': allTokens,
      'prescriptions': allPrescriptions,
      'donations': allDonations,
      'food': allFood,
      'credits': allCredits,
      'dispensary': allDispensary,
    };
  }

  void _sortByDate(
      List<Map<String, dynamic>> list, List<String> dateKeys) {
    list.sort((a, b) {
      String? aStr, bStr;
      for (final k in dateKeys) {
        if (a[k] != null) { aStr = a[k].toString(); break; }
      }
      for (final k in dateKeys) {
        if (b[k] != null) { bStr = b[k].toString(); break; }
      }
      if (aStr == null && bStr == null) return 0;
      if (aStr == null) return 1;
      if (bStr == null) return -1;
      try {
        return DateTime.parse(bStr).compareTo(DateTime.parse(aStr));
      } catch (_) {
        return bStr.compareTo(aStr);
      }
    });
  }

  // ─── Download handlers ───────────────────────────────────────────────────────
  Future<void> _downloadJson(RoleThemeData t) async {
    setState(() {
      _isDownloadingJson = true;
      _statusMessage = 'Fetching records…';
    });
    try {
      final data = await _fetchAllData();
      setState(() => _statusMessage = 'Encoding JSON…');
      final backupData = {
        'backupDate': DateTime.now().toIso8601String(),
        'branchSelection': branches[_selectedBranch],
        'dateFilter': _buildDateFilterMeta(),
        'counts': {
          'patients': _totalPatients,
          'tokens': _totalTokens,
          'prescriptions': _totalPrescriptions,
          'donations': _totalDonations,
          'food': _totalFood,
          'credits': _totalCredits,
          'dispensary': _totalDispensary,
        },
        'data': data,
      };
      final jsonString =
          const JsonEncoder.withIndent('  ').convert(backupData);
      final jsonBytes = utf8.encode(jsonString);
      final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final rangeStr = _buildFilenameDateSuffix();
      final branchStr = _selectedBranch == 'all'
          ? 'all_branches'
          : branches[_selectedBranch]!.toLowerCase();
      final fileName = 'backup_${branchStr}_${rangeStr}_$dateStr.json';

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save JSON Backup',
        fileName: fileName,
        bytes: jsonBytes,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null) {
        Clipboard.setData(ClipboardData(text: result));
        _showSnack(
            '✓ JSON saved — ${_totalPatients + _totalTokens + _totalPrescriptions + _totalDispensary} records\n$result',
            color: t.accent);
      } else {
        _showSnack('Cancelled', color: Colors.orange.shade700);
      }
    } catch (e) {
      _showSnack('JSON failed: $e', color: t.danger);
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
      _statusMessage = 'Fetching records…';
    });
    try {
      final data = await _fetchAllData();
      setState(() => _statusMessage = 'Building Excel workbook…');
      final excel = xl.Excel.createExcel();
      excel.rename('Sheet1', 'Patients');
      _addSheet(excel, 'Patients', data['patients']);
      _addSheet(excel, 'Tokens', data['tokens']);
      _addSheet(excel, 'Prescriptions', data['prescriptions']);
      _addSheet(excel, 'Donations', data['donations']);
      _addSheet(excel, 'Food', data['food']);
      _addSheet(excel, 'Credits', data['credits']);
      _addSheet(excel, 'Dispensary', data['dispensary']);

      final excelBytesList = excel.encode();
      final Uint8List excelBytes = excelBytesList != null
          ? Uint8List.fromList(excelBytesList)
          : Uint8List(0);
      final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final rangeStr = _buildFilenameDateSuffix();
      final branchStr = _selectedBranch == 'all'
          ? 'all_branches'
          : branches[_selectedBranch]!.toLowerCase();
      final fileName = 'backup_${branchStr}_${rangeStr}_$dateStr.xlsx';

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Excel Backup',
        fileName: fileName,
        bytes: excelBytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (result != null) {
        Clipboard.setData(ClipboardData(text: result));
        _showSnack(
            '✓ Excel saved — 4 sheets, ${_totalPatients + _totalTokens + _totalPrescriptions + _totalDispensary} rows\n$result',
            color: const Color(0xFF2E7D32));
      } else {
        _showSnack('Cancelled', color: Colors.orange.shade700);
      }
    } catch (e) {
      _showSnack('Excel failed: $e', color: Colors.red);
    } finally {
      setState(() {
        _isDownloadingExcel = false;
        if (!_isDownloadingJson) _statusMessage = 'Ready';
      });
    }
  }

  Map<String, dynamic> _buildDateFilterMeta() {
    switch (_dateMode) {
      case DateFilterMode.allTime:
        return {'mode': 'allTime'};
      case DateFilterMode.singleDay:
        return {
          'mode': 'singleDay',
          'date': _singleDate?.toIso8601String()
        };
      case DateFilterMode.dateRange:
        return {
          'mode': 'dateRange',
          'from': _rangeStart?.toIso8601String(),
          'to': _rangeEnd?.toIso8601String(),
        };
    }
  }

  String _buildFilenameDateSuffix() {
    switch (_dateMode) {
      case DateFilterMode.allTime:
        return 'alltime';
      case DateFilterMode.singleDay:
        return _singleDate != null
            ? DateFormat('yyyy-MM-dd').format(_singleDate!)
            : 'alltime';
      case DateFilterMode.dateRange:
        if (_rangeStart != null && _rangeEnd != null) {
          return '${DateFormat('yyyy-MM-dd').format(_rangeStart!)}_to_${DateFormat('yyyy-MM-dd').format(_rangeEnd!)}';
        }
        return 'alltime';
    }
  }

  void _showSnack(String msg, {required Color color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      backgroundColor: color,
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(
        label: 'Close',
        textColor: Colors.white,
        onPressed: () =>
            ScaffoldMessenger.of(context).hideCurrentSnackBar(),
      ),
    ));
  }

  // ─── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final bool isBusy = _isDownloadingJson || _isDownloadingExcel;
    final bool canDownload =
        _selectedBranch != null && _isDateFilterValid();

    return Scaffold(
      backgroundColor: t.bg,
      appBar: _buildAppBar(t),
      body: FadeTransition(
        opacity: _cardFade,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 28),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderCard(t),
                  const SizedBox(height: 16),
                  _buildBranchCard(t, isBusy),
                  const SizedBox(height: 16),
                  _buildDateFilterCard(t, isBusy),
                  const SizedBox(height: 16),
                  if (isBusy) _buildProgressCard(t),
                  if (!isBusy && canDownload) ...[
                    _buildStatsCard(t),
                    const SizedBox(height: 16),
                    _buildDownloadCard(t),
                  ],
                  if (!isBusy && !canDownload) _buildEmptyState(t),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isDateFilterValid() {
    switch (_dateMode) {
      case DateFilterMode.allTime:
        return true;
      case DateFilterMode.singleDay:
        return _singleDate != null;
      case DateFilterMode.dateRange:
        return _rangeStart != null && _rangeEnd != null;
    }
  }

  // ─── AppBar ──────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(RoleThemeData t) => AppBar(
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
      );

  // ─── Header card ─────────────────────────────────────────────────────────────
  Widget _buildHeaderCard(RoleThemeData t) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: _cardDecor(t),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: t.accentMuted,
                borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.cloud_download_rounded,
                color: t.accent, size: 30),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Clinic Data Backup',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary,
                        letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text(
                    'Export records by branch and date range as JSON or Excel',
                    style: TextStyle(
                        fontSize: 13, color: t.textSecondary)),
              ],
            ),
          ),
          _buildFormatBadge('JSON', t.accent, t),
          const SizedBox(width: 8),
          _buildFormatBadge('XLSX', t.accentLight, t),
        ]),
      );

  Widget _buildFormatBadge(String label, Color color, RoleThemeData t) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      );

  // ─── Branch card ─────────────────────────────────────────────────────────────
  Widget _buildBranchCard(RoleThemeData t, bool isBusy) => Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecor(t),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(Icons.account_tree_outlined, 'Branch', t),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _selectedBranch,
              dropdownColor: t.bgCard,
              decoration: _inputDecor(
                  'Select Branch', Icons.business_outlined, t),
              items: branches.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Row(children: [
                        Icon(
                            e.key == 'all'
                                ? Icons.hub_outlined
                                : Icons.location_on_outlined,
                            size: 16,
                            color: t.textTertiary),
                        const SizedBox(width: 8),
                        Text(e.value,
                            style: TextStyle(
                                fontSize: 14, color: t.textPrimary)),
                      ])))
                  .toList(),
              onChanged: isBusy
                  ? null
                  : (v) => setState(() => _selectedBranch = v),
            ),
          ],
        ),
      );

  // ─── Date filter card ────────────────────────────────────────────────────────
  Widget _buildDateFilterCard(RoleThemeData t, bool isBusy) => Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecor(t),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(Icons.date_range_outlined, 'Date Filter', t),
            const SizedBox(height: 14),

            // Mode toggle tabs
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.bgRule),
              ),
              child: Row(children: [
                _modeTab('All Time', DateFilterMode.allTime,
                    Icons.all_inclusive_rounded, t, isBusy),
                _modeTab('Single Day', DateFilterMode.singleDay,
                    Icons.today_rounded, t, isBusy),
                _modeTab('Date Range', DateFilterMode.dateRange,
                    Icons.date_range_rounded, t, isBusy),
              ]),
            ),

            const SizedBox(height: 16),

            // Date picker trigger
            if (_dateMode != DateFilterMode.allTime)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: _buildDatePickerTrigger(t, isBusy),
              ),

            if (_dateMode == DateFilterMode.allTime)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: t.accentMuted.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: t.accent.withOpacity(0.2)),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline,
                      size: 16, color: t.accent),
                  const SizedBox(width: 10),
                  Text('All records across every date will be exported',
                      style: TextStyle(
                          fontSize: 13, color: t.textSecondary)),
                ]),
              ),
          ],
        ),
      );

  Widget _modeTab(String label, DateFilterMode mode, IconData icon,
      RoleThemeData t, bool isBusy) {
    final active = _dateMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: isBusy ? null : () => setState(() => _dateMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? t.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? Colors.white : t.textTertiary),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: active
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: active ? Colors.white : t.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatePickerTrigger(RoleThemeData t, bool isBusy) {
    if (_dateMode == DateFilterMode.singleDay) {
      return GestureDetector(
        key: const ValueKey('single'),
        onTap: isBusy ? null : () => _pickSingleDate(t),
        child: _dateChip(
          _singleDate != null
              ? DateFormat('EEEE, dd MMMM yyyy').format(_singleDate!)
              : 'Tap to pick a date',
          Icons.today_rounded,
          _singleDate != null,
          t,
        ),
      );
    }
    // Date range
    return Column(
      key: const ValueKey('range'),
      children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: isBusy ? null : () => _pickDateRange(t),
              child: _dateChip(
                _rangeStart != null
                    ? 'From: ${DateFormat('dd MMM yyyy').format(_rangeStart!)}'
                    : 'From date',
                Icons.calendar_today_rounded,
                _rangeStart != null,
                t,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward_rounded,
                size: 18, color: t.textTertiary),
          ),
          Expanded(
            child: GestureDetector(
              onTap: isBusy ? null : () => _pickDateRange(t),
              child: _dateChip(
                _rangeEnd != null
                    ? 'To: ${DateFormat('dd MMM yyyy').format(_rangeEnd!)}'
                    : 'To date',
                Icons.event_rounded,
                _rangeEnd != null,
                t,
              ),
            ),
          ),
        ]),
        if (_rangeStart != null && _rangeEnd != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: t.accentMuted.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timelapse_rounded,
                    size: 14, color: t.accent),
                const SizedBox(width: 6),
                Text(
                  '${_rangeEnd!.difference(_rangeStart!).inDays + 1} days selected',
                  style: TextStyle(
                      fontSize: 12,
                      color: t.accent,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ]
      ],
    );
  }

  Widget _dateChip(
      String label, IconData icon, bool hasValue, RoleThemeData t) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: hasValue ? t.accentMuted : t.bg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: hasValue
                  ? t.accent.withOpacity(0.4)
                  : t.bgRule),
        ),
        child: Row(children: [
          Icon(icon,
              size: 16,
              color: hasValue ? t.accent : t.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: hasValue ? t.textPrimary : t.textTertiary,
                    fontWeight: hasValue
                        ? FontWeight.w600
                        : FontWeight.w400)),
          ),
          Icon(Icons.edit_calendar_rounded,
              size: 15,
              color: hasValue ? t.accent : t.textTertiary),
        ]),
      );

  // ─── Progress card ───────────────────────────────────────────────────────────
  Widget _buildProgressCard(RoleThemeData t) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: _cardDecor(t),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: t.accent, strokeWidth: 2.5)),
              const SizedBox(width: 14),
              Text(_statusMessage,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
            ]),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                color: t.accent,
                backgroundColor: t.accentMuted,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 14),
            _buildLiveCountRow(t),
          ],
        ),
      );

  Widget _buildLiveCountRow(RoleThemeData t) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _miniStat('Patients', _totalPatients, Icons.people_outline, t),
          const SizedBox(width: 16),
          _miniStat('Tokens', _totalTokens, Icons.confirmation_number_outlined, t),
          const SizedBox(width: 16),
          _miniStat('Rx', _totalPrescriptions, Icons.medication_outlined, t),
          const SizedBox(width: 16),
          _miniStat('Donations', _totalDonations, Icons.volunteer_activism_outlined, t),
          const SizedBox(width: 16),
          _miniStat('Food', _totalFood, Icons.restaurant_outlined, t),
          const SizedBox(width: 16),
          _miniStat('Credits', _totalCredits, Icons.payments_outlined, t),
          const SizedBox(width: 16),
          _miniStat('Inventory', _totalDispensary, Icons.inventory_2_outlined, t),
        ],
      ),
    );
  }

  Widget _miniStat(
      String label, int value, IconData icon, RoleThemeData t) =>
      Expanded(
        child: Column(children: [
          Icon(icon, size: 16, color: t.textTertiary),
          const SizedBox(height: 4),
          Text('$value',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary)),
          Text(label,
              style:
                  TextStyle(fontSize: 10, color: t.textTertiary)),
        ]),
      );

  // ─── Stats card ──────────────────────────────────────────────────────────────
  Widget _buildStatsCard(RoleThemeData t) {
    final total = _totalPatients +
        _totalTokens +
        _totalPrescriptions +
        _totalDonations +
        _totalFood +
        _totalCredits +
        _totalDispensary;
    if (total == 0) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _statsFade,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecor(t),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(Icons.bar_chart_rounded, 'Records Preview', t),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.2,
              children: [
                _statTile('Patients', _totalPatients, Icons.people_rounded, const Color(0xFF4CAF50), total, t),
                _statTile('Tokens', _totalTokens, Icons.confirmation_number_rounded, const Color(0xFF2196F3), total, t),
                _statTile('Prescriptions', _totalPrescriptions, Icons.medication_rounded, const Color(0xFFFF9800), total, t),
                _statTile('Donations', _totalDonations, Icons.volunteer_activism_rounded, const Color(0xFFE91E63), total, t),
                _statTile('Food Tokens', _totalFood, Icons.restaurant_rounded, const Color(0xFF795548), total, t),
                _statTile('Credits', _totalCredits, Icons.payments_rounded, const Color(0xFF009688), total, t),
                _statTile('Inventory', _totalDispensary, Icons.inventory_2_rounded, const Color(0xFF9C27B0), total, t),
              ],
            ),
            const SizedBox(height: 16),
            // Proportional bar
            if (total > 0) _buildProportionBar(total, t),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '$total total records · sorted newest first',
                style: TextStyle(
                    fontSize: 12, color: t.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, int value, IconData icon,
      Color color, int total, RoleThemeData t) {
    final pct = total > 0 ? (value / total * 100).round() : 0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const Spacer(),
              Text('$pct%',
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text('$value',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary)),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: t.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildProportionBar(int total, RoleThemeData t) {
    final segments = [
      (_totalPatients / total, const Color(0xFF4CAF50)),
      (_totalTokens / total, const Color(0xFF2196F3)),
      (_totalPrescriptions / total, const Color(0xFFFF9800)),
      (_totalDonations / total, const Color(0xFFE91E63)),
      (_totalFood / total, const Color(0xFF795548)),
      (_totalCredits / total, const Color(0xFF009688)),
      (_totalDispensary / total, const Color(0xFF9C27B0)),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: Row(
          children: segments
              .where((s) => s.$1 > 0)
              .map((s) => Flexible(
                    flex: (s.$1 * 1000).round(),
                    child: Container(color: s.$2),
                  ))
              .toList(),
        ),
      ),
    );
  }

  // ─── Download card ───────────────────────────────────────────────────────────
  Widget _buildDownloadCard(RoleThemeData t) => Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecor(t),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
                Icons.download_rounded, 'Export', t),
            const SizedBox(height: 6),
            // Summary chip
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.bgRule),
              ),
              child: Row(children: [
                Icon(Icons.filter_list_rounded,
                    size: 15, color: t.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${branches[_selectedBranch]}  ·  $_dateLabel',
                    style: TextStyle(
                        fontSize: 12,
                        color: t.textSecondary,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            ),
            Row(children: [
              Expanded(
                  child: _downloadButton(
                'Download JSON',
                Icons.data_object_rounded,
                t.accent,
                _isDownloadingExcel ? null : () => _downloadJson(t),
                'Structured · nested · machine-readable',
                t,
              )),
              const SizedBox(width: 14),
              Expanded(
                  child: _downloadButton(
                'Download Excel',
                Icons.table_chart_rounded,
                t.accentLight,
                _isDownloadingJson ? null : () => _downloadExcel(t),
                '7 sheets · sorted · human-readable',
                t,
              )),
            ]),
          ],
        ),
      );

  Widget _downloadButton(String label, IconData icon, Color color,
      VoidCallback? onTap, String subtitle, RoleThemeData t) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color:
                onTap != null ? color : color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 10),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11)),
            ],
          ),
        ),
      );

  // ─── Empty state ─────────────────────────────────────────────────────────────
  Widget _buildEmptyState(RoleThemeData t) => Container(
        padding: const EdgeInsets.symmetric(
            vertical: 40, horizontal: 24),
        decoration: _cardDecor(t),
        child: Column(children: [
          Icon(Icons.tune_rounded, size: 44, color: t.textTertiary),
          const SizedBox(height: 14),
          Text(
            _selectedBranch == null
                ? 'Select a branch to continue'
                : 'Complete the date filter to continue',
            style: TextStyle(
                fontSize: 15, color: t.textSecondary),
            textAlign: TextAlign.center,
          ),
        ]),
      );

  // ─── Shared helpers ──────────────────────────────────────────────────────────
  BoxDecoration _cardDecor(RoleThemeData t) => BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.bgRule),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      );

  Widget _sectionLabel(IconData icon, String label, RoleThemeData t) =>
      Row(children: [
        Icon(icon, size: 16, color: t.accent),
        const SizedBox(width: 7),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.textSecondary,
                letterSpacing: 0.3)),
      ]);

  InputDecoration _inputDecor(
          String label, IconData icon, RoleThemeData t) =>
      InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.textTertiary, fontSize: 13),
        floatingLabelStyle: TextStyle(
            color: t.accent,
            fontSize: 12,
            fontWeight: FontWeight.w600),
        prefixIcon:
            Icon(icon, color: t.textTertiary, size: 18),
        filled: true,
        fillColor: t.bg,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: t.bgRule)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: t.bgRule)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: t.accent, width: 2)),
      );
}