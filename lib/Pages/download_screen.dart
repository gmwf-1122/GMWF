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
  /// When non-null, the screen is locked to this branch only.
  /// Pass this for branch managers and supervisors.
  final String? lockedBranchId;

  const DownloadScreen({super.key, this.lockedBranchId});

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
  int _totalPatients = 0, _totalTokens = 0, _totalPrescriptions = 0;
  int _totalDonations = 0, _totalFood = 0, _totalCredits = 0, _totalDispensary = 0;
  int _totalMadrassaS = 0, _totalMadrassaL = 0;

  // Animation controllers
  late AnimationController _cardController;
  late AnimationController _statsController;
  late Animation<double> _cardFade;
  late Animation<double> _statsFade;

  final List<Map<String, String>> _availableBranches = [];
  final Set<String> _selectedCategories = {'dispensary', 'donations'};
  bool _isLoadingBranches = true;

  final List<Map<String, dynamic>> _categoryDef = [
    {'id': 'dispensary', 'label': 'Dispensary', 'icon': Icons.medication_outlined, 'color': const Color(0xFF0D9488)},
    {'id': 'dasterkhwaan', 'label': 'Dasterkhwaan', 'icon': Icons.restaurant_rounded, 'color': const Color(0xFFEA580C)},
    {'id': 'madrassa', 'label': 'Madrassa', 'icon': Icons.menu_book_rounded, 'color': const Color(0xFF4F46E5)},
    {'id': 'donations', 'label': 'Donations', 'icon': Icons.volunteer_activism_outlined, 'color': const Color(0xFFBE185D)},
  ];

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

    // Pre-select locked branch immediately.
    if (widget.lockedBranchId != null && widget.lockedBranchId!.isNotEmpty) {
      _selectedBranch = widget.lockedBranchId;
    }

    _loadBranches();
  }

  Future<void> _loadBranches() async {
    // ── Branch-locked mode: only fetch the one assigned branch ────────────
    if (widget.lockedBranchId != null && widget.lockedBranchId!.isNotEmpty) {
      final bid = widget.lockedBranchId!;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(bid)
            .get();
        final name = (doc.data()?['name'] as String?) ?? bid;
        if (mounted) {
          setState(() {
            _availableBranches
              ..clear()
              ..add({'id': bid, 'name': name});
            _selectedBranch = bid;
            _isLoadingBranches = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _availableBranches
              ..clear()
              ..add({'id': bid, 'name': bid});
            _selectedBranch = bid;
            _isLoadingBranches = false;
          });
        }
      }
      return;
    }
    // ── Global roles: fetch all branches ─────────────────────────────────
    try {
      final snap = await FirebaseFirestore.instance.collection('branches').get();
      final list = snap.docs.map((d) {
        final data = d.data();
        return {'id': d.id, 'name': (data['name'] ?? d.id).toString()};
      }).toList();
      
      if (mounted) {
        setState(() {
          _availableBranches.clear();
          _availableBranches.add({'id': 'all', 'name': 'All Branches'});
          _availableBranches.addAll(list);
          _isLoadingBranches = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingBranches = false);
    }
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
      branchIdsToProcess = _availableBranches
          .where((b) => b['id'] != 'all')
          .map((b) => b['id']!)
          .toList();
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
    final List<Map<String, dynamic>> allMadrassaStudents = [];
    final List<Map<String, dynamic>> allMadrassaLogs = [];

    int patients = 0, tokens = 0, prescriptions = 0, donations = 0, food = 0, credits = 0, dispensary = 0, madrassaS = 0, madrassaL = 0;

    // Pre-calculate date keys
    List<String> dsLegacyKeys = []; // ddMMyy
    List<String> dsDashKeys   = []; // yyyy-MM-dd

    if (_dateMode != DateFilterMode.allTime) {
      DateTime start = _dateMode == DateFilterMode.singleDay ? _singleDate! : _rangeStart!;
      DateTime end   = _dateMode == DateFilterMode.singleDay ? _singleDate! : _rangeEnd!;
      start = DateTime(start.year, start.month, start.day);
      end   = DateTime(end.year, end.month, end.day);
      int days = end.difference(start).inDays + 1;
      if (days > 400) days = 400;

      for (int i = 0; i < days; i++) {
        final d = start.add(Duration(days: i));
        dsLegacyKeys.add(DateFormat('ddMMyy').format(d));
        dsDashKeys.add(DateFormat('yyyy-MM-dd').format(d));
      }
    }

    final hasDispensary    = _selectedCategories.contains('dispensary');
    final hasDasterkhwaan  = _selectedCategories.contains('dasterkhwaan');
    final hasMadrassa      = _selectedCategories.contains('madrassa');
    final hasDonations     = _selectedCategories.contains('donations');

    for (final bid in branchIdsToProcess) {
      final bName = _availableBranches.firstWhere((b) => b['id'] == bid, orElse: () => {'name': bid})['name'] ?? bid;
      setState(() => _statusMessage = 'Fetching $bName records...');

      // ── Dispensary ──
      if (hasDispensary) {
        try {
          final snap = await db.collection('branches').doc(bid).collection('patients').get();
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            data['patientId'] = doc.id; data['branchId'] = bid;
            final sanitized = _sanitizeForJson(data);
            if (_isDateInRange(sanitized['registrationDate'] ?? sanitized['createdAt'])) {
              allPatients.add(sanitized); patients++;
            }
          }
        } catch (_) {}

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
            await Future.wait(dsLegacyKeys.map((key) async {
              final dateDoc = db.collection('branches').doc(bid).collection('serials').doc(key);
              await Future.wait(['zakat', 'non-zakat', 'gmwf'].map((type) async {
                try {
                  final qSnap = await dateDoc.collection(type).get();
                  for (final doc in qSnap.docs) {
                    final d = doc.data();
                    d['serial'] = doc.id; d['date'] = key; d['queueType'] = type; d['branchId'] = bid;
                    allTokens.add(_sanitizeForJson(d)); tokens++;
                  }
                } catch (_) {}
              }));
            }));
          }
        } catch (_) {}

        try {
          final patientSnap = await db.collection('branches').doc(bid).collection('prescriptions').get();
          for (final pDoc in patientSnap.docs) {
            final prescSnap = await pDoc.reference.collection('prescriptions').get();
            for (final doc in prescSnap.docs) {
              final data = doc.data();
              data['prescriptionId'] = doc.id; data['patientCnic'] = pDoc.id; data['branchId'] = bid;
              final sanitized = _sanitizeForJson(data);
              if (_isDateInRange(sanitized['date'] ?? sanitized['createdAt'])) {
                allPrescriptions.add(sanitized); prescriptions++;
              }
            }
          }
        } catch (_) {}

        try {
          final snap = await db.collection('branches').doc(bid).collection('inventory').get();
          for (final doc in snap.docs) {
            final data = doc.data();
            data['itemId'] = doc.id; data['branchId'] = bid;
            allDispensary.add(_sanitizeForJson(data)); dispensary++;
          }
        } catch (_) {}
      }

      // ── Dasterkhwaan ──
      if (hasDasterkhwaan) {
        try {
          if (_dateMode == DateFilterMode.allTime) {
            final snap = await db.collection('branches').doc(bid).collection('dasterkhwaan').get();
            for (final dateDoc in snap.docs) {
              final qSnap = await dateDoc.reference.collection('tokens').get();
              for (final doc in qSnap.docs) {
                final d = doc.data();
                d['id'] = doc.id; d['date'] = dateDoc.id; d['branchId'] = bid;
                allFood.add(_sanitizeForJson(d)); food++;
              }
            }
          } else {
            await Future.wait(dsDashKeys.map((key) async {
              try {
                final qSnap = await db.collection('branches').doc(bid).collection('dasterkhwaan').doc(key).collection('tokens').get();
                for (final doc in qSnap.docs) {
                  final d = doc.data();
                  d['id'] = doc.id; d['date'] = key; d['branchId'] = bid;
                  allFood.add(_sanitizeForJson(d)); food++;
                }
              } catch (_) {}
            }));
          }
        } catch (_) {}
      }

      // ── Donations ──
      if (hasDonations) {
        try {
          Query q = db.collection('branches').doc(bid).collection('donations');
          if (_dateMode != DateFilterMode.allTime) {
            q = q.where('date', isGreaterThanOrEqualTo: dsDashKeys.first).where('date', isLessThanOrEqualTo: dsDashKeys.last);
          }
          final snap = await q.get();
          for (final doc in snap.docs) {
            if (doc.id == 'credit_ledger') continue;
            final d = doc.data() as Map<String, dynamic>;
            d['id'] = doc.id; d['branchId'] = bid;
            allDonations.add(_sanitizeForJson(d)); donations++;
          }
        } catch (_) {}

        try {
          Query q = db.collection('branches').doc(bid).collection('creditLedger');
          if (_dateMode != DateFilterMode.allTime) {
            q = q.where('date', isGreaterThanOrEqualTo: dsDashKeys.first).where('date', isLessThanOrEqualTo: dsDashKeys.last);
          }
          final snap = await q.get();
          for (final doc in snap.docs) {
            final d = doc.data() as Map<String, dynamic>;
            d['id'] = doc.id; d['branchId'] = bid;
            allCredits.add(_sanitizeForJson(d)); credits++;
          }
        } catch (_) {}
      }

      // ── Madrassa ──
      if (hasMadrassa) {
        try {
          final snap = await db.collection('branches').doc(bid).collection('madrassa_students').get();
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            data['studentId'] = doc.id; data['branchId'] = bid;
            allMadrassaStudents.add(_sanitizeForJson(data)); madrassaS++;
          }
        } catch (_) {}

        try {
          if (_dateMode == DateFilterMode.allTime) {
            final snap = await db.collection('branches').doc(bid).collection('madrassa_daily_logs').get();
            for (final doc in snap.docs) {
              final d = doc.data() as Map<String, dynamic>;
              d['date'] = doc.id; d['branchId'] = bid;
              allMadrassaLogs.add(_sanitizeForJson(d)); madrassaL++;
            }
          } else {
            await Future.wait(dsDashKeys.map((key) async {
              try {
                final doc = await db.collection('branches').doc(bid).collection('madrassa_daily_logs').doc(key).get();
                if (doc.exists) {
                  final d = doc.data() as Map<String, dynamic>;
                  d['date'] = doc.id; d['branchId'] = bid;
                  allMadrassaLogs.add(_sanitizeForJson(d)); madrassaL++;
                }
              } catch (_) {}
            }));
          }
        } catch (_) {}
      }

      setState(() {
        _totalPatients = patients; _totalTokens = tokens; _totalPrescriptions = prescriptions;
        _totalDonations = donations; _totalFood = food; _totalCredits = credits; _totalDispensary = dispensary;
        _totalMadrassaS = madrassaS; _totalMadrassaL = madrassaL;
      });
    }

    // Sort lists
    if (hasDispensary) {
      _sortByDate(allPatients, ['registrationDate', 'createdAt']);
      _sortByDate(allTokens, ['date', 'createdAt']);
      _sortByDate(allPrescriptions, ['date', 'createdAt']);
    }
    if (hasDonations) {
      _sortByDate(allDonations, ['date', 'timestamp']);
      _sortByDate(allCredits, ['date', 'timestamp']);
    }
    if (hasDasterkhwaan) {
      _sortByDate(allFood, ['date', 'timestamp']);
    }
    if (hasMadrassa) {
      _sortByDate(allMadrassaLogs, ['date', 'updatedAt']);
    }

    return {
      if (hasDispensary) 'patients': allPatients,
      if (hasDispensary) 'tokens': allTokens,
      if (hasDispensary) 'prescriptions': allPrescriptions,
      if (hasDonations) 'donations': allDonations,
      if (hasDasterkhwaan) 'food': allFood,
      if (hasDonations) 'credits': allCredits,
      if (hasDispensary) 'dispensary': allDispensary,
      if (hasMadrassa) 'madrassa_students': allMadrassaStudents,
      if (hasMadrassa) 'madrassa_logs': allMadrassaLogs,
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
        'branchSelection': _availableBranches.firstWhere((b) => b['id'] == _selectedBranch, orElse: () => {'name': _selectedBranch ?? 'Unknown'})['name'],
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
          : _availableBranches.firstWhere((b) => b['id'] == _selectedBranch, orElse: () => {'name': _selectedBranch ?? 'Unknown'})['name']!.toLowerCase();
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
      excel.rename('Sheet1', 'Instructions');
      excel['Instructions'].appendRow([xl.TextCellValue('GMWF Data Export Summary')]);
      excel['Instructions'].appendRow([xl.TextCellValue('Date Range: $_dateLabel')]);
      excel['Instructions'].appendRow([xl.TextCellValue('Generated At: ${DateTime.now()}')]);

      if (data.containsKey('patients')) _addSheet(excel, 'Patients', data['patients']);
      if (data.containsKey('tokens')) _addSheet(excel, 'Tokens', data['tokens']);
      if (data.containsKey('prescriptions')) _addSheet(excel, 'Prescriptions', data['prescriptions']);
      if (data.containsKey('donations')) _addSheet(excel, 'Donations', data['donations']);
      if (data.containsKey('food')) _addSheet(excel, 'Food', data['food']);
      if (data.containsKey('credits')) _addSheet(excel, 'Credits', data['credits']);
      if (data.containsKey('dispensary')) _addSheet(excel, 'Inventory', data['dispensary']);
      if (data.containsKey('madrassa_students')) _addSheet(excel, 'Madrassa_Students', data['madrassa_students']);
      if (data.containsKey('madrassa_logs')) _addSheet(excel, 'Madrassa_Logs', data['madrassa_logs']);

      final excelBytesList = excel.encode();
      final Uint8List excelBytes = excelBytesList != null
          ? Uint8List.fromList(excelBytesList)
          : Uint8List(0);
      final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final rangeStr = _buildFilenameDateSuffix();
      final branchStr = _selectedBranch == 'all'
          ? 'all_branches'
          : _availableBranches.firstWhere((b) => b['id'] == _selectedBranch, orElse: () => {'name': _selectedBranch ?? 'Unknown'})['name']!.toLowerCase();
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
                  _buildCategoryCard(t, isBusy),
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

  Widget _buildHeaderCard(RoleThemeData t) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 24, vertical: 20),
      decoration: _cardDecor(t),
      child: Column(
        children: [
          Row(children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 10 : 14),
              decoration: BoxDecoration(color: t.accentMuted, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.cloud_download_rounded, color: t.accent, size: isMobile ? 20 : 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Clinic Data Backup',
                      style: TextStyle(fontSize: isMobile ? 16 : 20, fontWeight: FontWeight.w800, color: t.textPrimary, letterSpacing: -0.3)),
                  const SizedBox(height: 2),
                  Text('Export records by branch & range',
                      style: TextStyle(fontSize: isMobile ? 11 : 12, color: t.textSecondary)),
                ],
              ),
            ),
            if (!isMobile) ...[
              _buildFormatBadge('JSON', t.accent, t),
              const SizedBox(width: 8),
              _buildFormatBadge('XLSX', t.accentLight, t),
            ],
          ]),
          if (isMobile) ...[
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              _buildFormatBadge('JSON', t.accent, t),
              const SizedBox(width: 8),
              _buildFormatBadge('XLSX', t.accentLight, t),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildFormatBadge(String label, Color color, RoleThemeData t) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      );

  // ─── Branch card ─────────────────────────────────────────────────────────────
  Widget _buildBranchCard(RoleThemeData t, bool isBusy) {
    // ── Branch-locked mode: show read-only pill, no dropdown ─────────────
    final isLocked = widget.lockedBranchId != null && widget.lockedBranchId!.isNotEmpty;
    if (isLocked) {
      final branchName = _availableBranches.isNotEmpty
          ? (_availableBranches.first['name'] ?? widget.lockedBranchId!)
          : widget.lockedBranchId!;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecor(t),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(Icons.account_tree_outlined, 'Branch', t),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.accent.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                Icon(Icons.lock_outline_rounded, color: t.accent, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    branchName,
                    style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Your Branch',
                      style: TextStyle(
                          color: t.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ],
        ),
      );
    }
    // ── Global roles: full branch selector ───────────────────────────────
    return Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecor(t),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(Icons.account_tree_outlined, 'Branch', t),
            const SizedBox(height: 14),
            if (_isLoadingBranches)
              const LinearProgressIndicator()
            else
              DropdownButtonFormField<String>(
                value: _selectedBranch,
                dropdownColor: t.bgCard,
                decoration: _inputDecor(
                    'Select Branch', Icons.business_outlined, t),
                items: _availableBranches
                    .map((e) => DropdownMenuItem(
                        value: e['id'],
                        child: Row(children: [
                          Icon(
                              e['id'] == 'all'
                                  ? Icons.hub_outlined
                                  : Icons.location_on_outlined,
                              size: 16,
                              color: t.textTertiary),
                          const SizedBox(width: 8),
                          Text(e['name'] ?? '',
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
  }

  // ─── Category card ──────────────────────────────────────────────────────────
  Widget _buildCategoryCard(RoleThemeData t, bool isBusy) => Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecor(t),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(Icons.category_outlined, 'Data Categories', t),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _categoryDef.map((cat) {
                final selected = _selectedCategories.contains(cat['id']);
                final color = cat['color'] as Color;
                return FilterChip(
                  label: Text(cat['label']),
                  selected: selected,
                  selectedColor: color.withValues(alpha: 0.2),
                  checkmarkColor: color,
                  labelStyle: TextStyle(
                    color: selected ? color : t.textSecondary,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                  avatar: Icon(cat['icon'], size: 16, color: selected ? color : t.textTertiary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: selected ? color : t.bgRule),
                  ),
                  onSelected: isBusy ? null : (v) {
                    setState(() {
                      if (v) _selectedCategories.add(cat['id']);
                      else if (_selectedCategories.length > 1) _selectedCategories.remove(cat['id']);
                    });
                  },
                );
              }).toList(),
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
                  color: t.accentMuted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: t.accent.withValues(alpha: 0.2)),
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
              color: t.accentMuted.withValues(alpha: 0.5),
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
                  ? t.accent.withValues(alpha: 0.4)
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
    final hasDispensary = _selectedCategories.contains('dispensary');
    final hasDasterkhwaan = _selectedCategories.contains('dasterkhwaan');
    final hasDonations = _selectedCategories.contains('donations');
    final hasMadrassa = _selectedCategories.contains('madrassa');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (hasDispensary) ...[
            _miniStat('Patients', _totalPatients, Icons.people_outline, t),
            const SizedBox(width: 16),
            _miniStat('Tokens', _totalTokens, Icons.confirmation_number_outlined, t),
            const SizedBox(width: 16),
            _miniStat('Rx', _totalPrescriptions, Icons.medication_outlined, t),
            const SizedBox(width: 16),
          ],
          if (hasDonations) ...[
            _miniStat('Donations', _totalDonations, Icons.volunteer_activism_outlined, t),
            const SizedBox(width: 16),
            _miniStat('Credits', _totalCredits, Icons.payments_outlined, t),
            const SizedBox(width: 16),
          ],
          if (hasDasterkhwaan) ...[
            _miniStat('Food', _totalFood, Icons.restaurant_outlined, t),
            const SizedBox(width: 16),
          ],
          if (hasDispensary) ...[
            _miniStat('Inventory', _totalDispensary, Icons.inventory_2_outlined, t),
            const SizedBox(width: 16),
          ],
          if (hasMadrassa) ...[
            _miniStat('Students', _totalMadrassaS, Icons.school_outlined, t),
            const SizedBox(width: 16),
            _miniStat('Study Logs', _totalMadrassaL, Icons.history_edu_rounded, t),
            const SizedBox(width: 16),
          ],
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
        _totalDispensary +
        _totalMadrassaS +
        _totalMadrassaL;
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
                if (_totalPatients > 0) _statTile('Patients', _totalPatients, Icons.people_rounded, const Color(0xFF4CAF50), total, t),
                if (_totalTokens > 0) _statTile('Tokens', _totalTokens, Icons.confirmation_number_rounded, const Color(0xFF2196F3), total, t),
                if (_totalPrescriptions > 0) _statTile('Prescriptions', _totalPrescriptions, Icons.medication_rounded, const Color(0xFFFF9800), total, t),
                if (_totalDonations > 0) _statTile('Donations', _totalDonations, Icons.volunteer_activism_rounded, const Color(0xFFE91E63), total, t),
                if (_totalFood > 0) _statTile('Food Tokens', _totalFood, Icons.restaurant_rounded, const Color(0xFF795548), total, t),
                if (_totalCredits > 0) _statTile('Credits', _totalCredits, Icons.payments_rounded, const Color(0xFF009688), total, t),
                if (_totalDispensary > 0) _statTile('Inventory', _totalDispensary, Icons.inventory_2_rounded, const Color(0xFF9C27B0), total, t),
                if (_totalMadrassaS > 0) _statTile('Madrassa Students', _totalMadrassaS, Icons.school_rounded, const Color(0xFF4F46E5), total, t),
                if (_totalMadrassaL > 0) _statTile('Madrassa Logs', _totalMadrassaL, Icons.menu_book_rounded, const Color(0xFF3F51B5), total, t),
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
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: color.withValues(alpha: 0.18)),
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
      (_totalMadrassaS / total, const Color(0xFF4F46E5)),
      (_totalMadrassaL / total, const Color(0xFF3F51B5)),
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
                    '${_availableBranches.firstWhere((b) => b['id'] == _selectedBranch, orElse: () => {'name': _selectedBranch ?? 'Unknown'})['name']}  ·  $_dateLabel',
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
                '${_selectedCategories.length + 3} sheets · sorted · human-readable',
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
                onTap != null ? color : color.withValues(alpha: 0.3),
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
                      color: Colors.white.withValues(alpha: 0.7),
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
              color: Colors.black.withValues(alpha: 0.05),
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
