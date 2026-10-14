import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'holiday_management_view.dart';
import '../madrassa_strings.dart';
import '../utils/madrassa_csv_service.dart';
import '../utils/madrassa_local_storage.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/user_theme_service.dart';
import '../../../design/design_system.dart';

// Breakpoints for responsive configuration sizing
const double kConfigMobileBreakpoint = GBreakpoint.compact;

class MadrassaConfigView extends StatefulWidget {
  final String branchId;
  final String username;
  final String role;
  const MadrassaConfigView({
    super.key,
    required this.branchId,
    required this.username,
    this.role = 'Madrassa Admin',
  });

  @override
  State<MadrassaConfigView> createState() => _MadrassaConfigViewState();
}

class _MadrassaConfigViewState extends State<MadrassaConfigView> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  int _ptmDay = 0;
  
  final _baseFeeController = TextEditingController();
  final _ptmDeductionController = TextEditingController();
  final _msgDeductionController = TextEditingController();
  final _maxAttDeductionController = TextEditingController();
  final _maxUniDeductionController = TextEditingController();
  
  int _initialPtmDay = 0;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isImporting = false;

  String? _baseFeeError;
  String? _ptmDeductionError;
  String? _msgDeductionError;
  String? _maxAttDeductionError;
  String? _maxUniDeductionError;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _baseFeeController.dispose();
    _ptmDeductionController.dispose();
    _msgDeductionController.dispose();
    _maxAttDeductionController.dispose();
    _maxUniDeductionController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    // 1. Try local cache first (instant load, zero Firestore reads)
    try {
      final box = await LocalStorageService.ensureBoxOpen(MadrassaLocalStorage.studentsBox);
      final key = '${widget.branchId.toLowerCase().trim()}__config__current';
      final cached = box.get(key);
      if (cached is Map && mounted) {
        final data = Map<String, dynamic>.from(cached);
        setState(() {
          _year = data['year'] ?? _year;
          _month = data['month'] ?? _month;
          _ptmDay = data['ptmDay'] ?? 0;
          _initialPtmDay = _ptmDay;
          _baseFeeController.text = (data['baseFee'] ?? 3000).toString();
          _ptmDeductionController.text = (data['ptmDeduction'] ?? 700).toString();
          _msgDeductionController.text = (data['messageTotalDeduction'] ?? 1300).toString();
          _maxAttDeductionController.text = (data['attendanceMaxDeduction'] ?? 500).toString();
          _maxUniDeductionController.text = (data['uniformMaxDeduction'] ?? 500).toString();
        });
      }
    } catch (_) {}

    // 2. Refresh from Firestore if network is available
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('madrassa_config')
          .doc('current')
          .get();
      if (doc.exists && mounted && doc.data() != null) {
        final data = doc.data()!;
        final box = await LocalStorageService.ensureBoxOpen(MadrassaLocalStorage.studentsBox);
        final key = '${widget.branchId.toLowerCase().trim()}__config__current';
        await box.put(key, LocalStorageService.sanitize(data));
        setState(() {
          _year = data['year'] ?? _year;
          _month = data['month'] ?? _month;
          _ptmDay = data['ptmDay'] ?? 0;
          _initialPtmDay = _ptmDay;
          _baseFeeController.text = (data['baseFee'] ?? 3000).toString();
          _ptmDeductionController.text = (data['ptmDeduction'] ?? 700).toString();
          _msgDeductionController.text = (data['messageTotalDeduction'] ?? 1300).toString();
          _maxAttDeductionController.text = (data['attendanceMaxDeduction'] ?? 500).toString();
          _maxUniDeductionController.text = (data['uniformMaxDeduction'] ?? 500).toString();
        });
      }
    } catch (_) {}
  }

  DateTime _getFirstFriday(int year, int month) {
    DateTime date = DateTime(year, month, 1);
    while (date.weekday != DateTime.friday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  DateTime getPtmDate() {
    if (_ptmDay > 0) return DateTime(_year, _month, _ptmDay);
    return _getFirstFriday(_year, _month);
  }

  Future<void> _migratePtmAttendance(int oldDay, int newDay, int year, int month) async {
    final oldDate = oldDay == 0 ? _getFirstFriday(year, month) : DateTime(year, month, oldDay);
    final newDate = newDay == 0 ? _getFirstFriday(year, month) : DateTime(year, month, newDay);
    
    final oldDateStr = DateFormat('yyyy-MM-dd').format(oldDate);
    final newDateStr = DateFormat('yyyy-MM-dd').format(newDate);

    if (oldDateStr == newDateStr) return;

    final oldDocRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('madrassa_daily_logs')
        .doc(oldDateStr);

    final newDocRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('madrassa_daily_logs')
        .doc(newDateStr);

    try {
      final oldSnap = await oldDocRef.get();
      if (!oldSnap.exists) return;

      final oldData = oldSnap.data() ?? {};
      final Map<String, dynamic> oldUpdates = {};
      final Map<String, dynamic> newUpdates = {};

      bool hasChanges = false;
      oldData.forEach((studentId, studentLog) {
        if (studentLog is Map<String, dynamic> && studentLog.containsKey('ptm')) {
          final ptmVal = studentLog['ptm'];
          newUpdates[studentId] = {
            ...studentLog,
            'ptm': ptmVal,
          };
          final updatedStudentLog = Map<String, dynamic>.from(studentLog);
          updatedStudentLog.remove('ptm');
          oldUpdates[studentId] = updatedStudentLog;
          hasChanges = true;
        }
      });

      if (hasChanges) {
        final batch = FirebaseFirestore.instance.batch();
        batch.set(oldDocRef, oldUpdates, SetOptions(merge: true));
        batch.set(newDocRef, newUpdates, SetOptions(merge: true));
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error migrating PTM attendance: $e');
    }
  }

  Future<void> _save() async {
    bool hasError = false;
    
    setState(() {
      _baseFeeError = null;
      _ptmDeductionError = null;
      _msgDeductionError = null;
      _maxAttDeductionError = null;
      _maxUniDeductionError = null;
    });

    final bool isFeeEnabled = LocalStorageService.isMadrassaFeeEnabled(widget.branchId);

    double? base, ptm, msg, att, uni;

    if (isFeeEnabled) {
      final baseVal = _baseFeeController.text.trim();
      final ptmVal = _ptmDeductionController.text.trim();
      final msgVal = _msgDeductionController.text.trim();
      final attVal = _maxAttDeductionController.text.trim();
      final uniVal = _maxUniDeductionController.text.trim();

      if (baseVal.isEmpty) {
        setState(() => _baseFeeError = 'Base points are required');
        hasError = true;
      }
      if (ptmVal.isEmpty) {
        setState(() => _ptmDeductionError = 'PTM deduction is required');
        hasError = true;
      }
      if (msgVal.isEmpty) {
        setState(() => _msgDeductionError = 'Message deduction is required');
        hasError = true;
      }
      if (attVal.isEmpty) {
        setState(() => _maxAttDeductionError = 'Max attendance deduction is required');
        hasError = true;
      }
      if (uniVal.isEmpty) {
        setState(() => _maxUniDeductionError = 'Max uniform deduction is required');
        hasError = true;
      }

      base = double.tryParse(baseVal);
      ptm = double.tryParse(ptmVal);
      msg = double.tryParse(msgVal);
      att = double.tryParse(attVal);
      uni = double.tryParse(uniVal);

      if (baseVal.isNotEmpty && base == null) {
        setState(() => _baseFeeError = 'Enter a valid number');
        hasError = true;
      }
      if (ptmVal.isNotEmpty && ptm == null) {
        setState(() => _ptmDeductionError = 'Enter a valid number');
        hasError = true;
      }
      if (msgVal.isNotEmpty && msg == null) {
        setState(() => _msgDeductionError = 'Enter a valid number');
        hasError = true;
      }
      if (attVal.isNotEmpty && att == null) {
        setState(() => _maxAttDeductionError = 'Enter a valid number');
        hasError = true;
      }
      if (uniVal.isNotEmpty && uni == null) {
        setState(() => _maxUniDeductionError = 'Enter a valid number');
        hasError = true;
      }

      if (hasError) {
        if (mounted) {
          AppToast.showSnackBar(context, 
            const SnackBar(
              backgroundColor: SoftPalette.red400,
              content: Text('Please correct all validation errors to continue'),
            ),
          );
        }
        return;
      }

      if ((ptm! + msg! + att! + uni!) != base!) {
        if (mounted) {
          AppToast.showSnackBar(context, 
            SnackBar(
              backgroundColor: SoftPalette.red400,
              content: Text('Sum of deductions ($ptm + $msg + $att + $uni = ${ptm + msg + att + uni}) must equal Base Points ($base)'),
            ),
          );
        }
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final Map<String, dynamic> updateData = {
        'year': _year,
        'month': _month,
        'ptmDay': _ptmDay,
      };

      if (isFeeEnabled && base != null) {
        updateData.addAll({
          'baseFee': base,
          'ptmDeduction': ptm,
          'messageTotalDeduction': msg,
          'attendanceMaxDeduction': att,
          'uniformMaxDeduction': uni,
        });
      }

      bool isRescheduled = _ptmDay != _initialPtmDay;
      int oldPtmDay = _initialPtmDay;

      if (isRescheduled) {
        final oldDate = oldPtmDay == 0 ? 'Auto (1st Fri)' : 'Day $oldPtmDay';
        final newDate = _ptmDay == 0 ? 'Auto (1st Fri)' : 'Day $_ptmDay';
        
        updateData['auditLog'] = FieldValue.arrayUnion([
          {
            'type': 'ptm_reschedule',
            'oldValue': oldDate,
            'newValue': newDate,
            'timestamp': Timestamp.now(),
            'month': _month,
            'year': _year,
          }
        ]);
      }

      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('madrassa_config')
          .doc('current')
          .set(updateData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 5));

      // Cache locally in Hive for instant future offline/local-first loading
      try {
        final box = await LocalStorageService.ensureBoxOpen(MadrassaLocalStorage.studentsBox);
        final key = '${widget.branchId.toLowerCase().trim()}__config__current';
        final cached = box.get(key);
        final merged = cached is Map ? Map<String, dynamic>.from(cached) : <String, dynamic>{};
        updateData.forEach((k, v) {
          if (k != 'auditLog') merged[k] = v;
        });
        await box.put(key, LocalStorageService.sanitize(merged));
      } catch (_) {}

      if (isRescheduled) {
        await _migratePtmAttendance(oldPtmDay, _ptmDay, _year, _month);
        _initialPtmDay = _ptmDay;
      }

      final oldDate = oldPtmDay == 0 ? 'Auto' : 'Day $oldPtmDay';
      final newDate = _ptmDay == 0 ? 'Auto' : 'Day $_ptmDay';
      String auditMessage = (isFeeEnabled && base != null)
          ? 'Madrassa configuration updated. Base: Rs. ${base.toInt()}, PTM: $newDate'
          : 'Madrassa configuration updated. PTM: $newDate';
      if (isRescheduled) {
        auditMessage += ' (PTM Rescheduled from $oldDate to $newDate)';
      }

      await MadrassaAuditService.logAction(
        branchId: widget.branchId,
        editor: widget.username,
        role: widget.role,
        type: isRescheduled ? 'ptm_reschedule' : 'config_change',
        message: auditMessage,
      );

      if (mounted) {
        AppToast.showSnackBar(context, 
          SnackBar(content: Text(context.l.configSaved)),
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.showSnackBar(context, 
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _exportCsv(MadrassaCsvType type) async {
    setState(() => _isExporting = true);
    try {
      final saved = type == MadrassaCsvType.unknown
          ? await MadrassaCsvService.exportAll(widget.branchId)
          : await MadrassaCsvService.exportSingle(widget.branchId, type);

      if (!mounted) return;
      if (saved == 0) {
        AppToast.showSnackBar(context, 
          SnackBar(content: Text(context.l.exportCancelled)),
        );
      } else {
        AppToast.showSnackBar(context, 
          SnackBar(
            content: Text(
              type == MadrassaCsvType.unknown
                  ? context.l.exportAllSuccess
                  : context.l.exportSuccess,
            ),
            backgroundColor: SoftPalette.green400,
          ),
        );

        await MadrassaAuditService.logAction(
          branchId: widget.branchId,
          editor: widget.username,
          role: widget.role,
          type: 'csv_export',
          message: 'Madrassa CSV export (${type.name}) completed.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.showSnackBar(context, 
          SnackBar(content: Text('Export failed: $e'), backgroundColor: SoftPalette.red400),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      final csvText = utf8.decode(bytes);
      final detectedType = MadrassaCsvService.detectCsvType(csvText);

      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            context.l.importCsvTitle,
            style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          content: Text(
            '${context.l.importCsvBody}\n\nDetected: ${detectedType.name}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l.cancel, style: context.urduStyle()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: SoftPalette.teal550),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                context.l.importCsv,
                style: context.urduStyle(style: const TextStyle(color: SoftPalette.gray50)),
              ),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      setState(() => _isImporting = true);
      final importResult = await MadrassaCsvService.importCsv(
  branchId: widget.branchId,
  csvText: csvText,
  editor: widget.username,
);

      await MadrassaAuditService.logAction(
        branchId: widget.branchId,
        editor: widget.username,
        role: widget.role,
        type: 'csv_import',
        message: importResult.message,
      );
// Re-download/sync the local cache for any successfully parsed DailyLogs or Students CSV import,
// even if Firestore skipped writing identical rows (so that local Hive matches Firestore).
if (importResult.type == MadrassaCsvType.dailyLogs) {
  final monthsToSync = <String>{};
  final allRows = MadrassaCsvService.parseCsvRows(csvText);
  for (final row in allRows) {
    final d = row['date']?.trim();
    if (d != null && d.length >= 7) {
      monthsToSync.add(d.substring(0, 7));
    }
  }
  for (final ym in monthsToSync) {
    final parts = ym.split('-');
    if (parts.length == 2) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (y != null && m != null) {
        await MadrassaLocalStorage.downloadLogsForMonth(widget.branchId, y, m);
      }
    }
  }
} else if (importResult.type == MadrassaCsvType.students) {
  await MadrassaLocalStorage.downloadStudents(widget.branchId);
}
      if (mounted) {
        AppToast.showSnackBar(context, 
          SnackBar(
            content: Text('${context.l.importSuccess}: ${importResult.message}'),
            backgroundColor: (importResult.imported > 0 || importResult.skipped > 0) ? SoftPalette.green400 : SoftPalette.amber300,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.showSnackBar(context, 
          SnackBar(
            content: Text('${context.l.importFailed}: $e'),
            backgroundColor: SoftPalette.red400,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: UserThemeService.listenable(widget.username),
      builder: (context, _, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark || UserThemeService.isDarkMode(widget.username);
        final scaffoldBg = isDark ? SoftPalette.slate900 : SoftPalette.gray50;

        return Scaffold(
          backgroundColor: scaffoldBg,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < kConfigMobileBreakpoint;
              final bool isFeeEnabled = LocalStorageService.isMadrassaFeeEnabled(widget.branchId);

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 24,
                  vertical: isMobile ? 18 : 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeHeader(context),
                    const SizedBox(height: 24),
                    if (!isFeeEnabled)
                      _buildActivePeriodCard(context)
                    else if (isMobile) ...[
                      _buildActivePeriodCard(context),
                      const SizedBox(height: 20),
                      _buildDeductionsCard(context),
                    ] else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildActivePeriodCard(context)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildDeductionsCard(context)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    _buildSaveConfigBar(context, isMobile: isMobile),
                    const SizedBox(height: 28),
                    _buildDataImportExportCard(context),
                    if (isMobile) ...[
                      const SizedBox(height: 24),
                      _buildAccountCard(context),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSaveConfigBar(BuildContext context, {required bool isMobile}) {
    final isDark = Theme.of(context).brightness == Brightness.dark || UserThemeService.isDarkMode(widget.username);
    final saveButton = ElevatedButton.icon(
      onPressed: _isSaving ? null : _save,
      icon: _isSaving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SoftPalette.gray50,
              ),
            )
          : const Icon(Icons.save_rounded, size: 18),
      label: Text(
        context.l.save,
        style: context.urduStyle(
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: SoftPalette.teal550,
        foregroundColor: SoftPalette.gray50,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
      ),
    );

    if (isMobile) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: saveButton,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? SoftPalette.slate800 : SoftPalette.slate50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? SoftPalette.slate700 : SoftPalette.slate200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: isDark ? SoftPalette.gray50A70 : SoftPalette.slate500,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.isUrdu
                  ? 'تعلیمی سیشن اور کٹوتی کے قواعد محفوظ کرنے کے لیے کلک کریں۔'
                  : 'Changes to academic period and deduction rules will apply immediately upon saving.',
              style: context.urduStyle(
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? SoftPalette.gray50A70 : SoftPalette.slate500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          saveButton,
        ],
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark || UserThemeService.isDarkMode(widget.username);
    final cardBg = isDark ? SoftPalette.slate800 : SoftPalette.gray50;
    final borderColor = isDark ? SoftPalette.slate700 : SoftPalette.slate200;
    final textPrimary = isDark ? SoftPalette.gray50 : SoftPalette.slate800;
    final textMuted = isDark ? SoftPalette.gray50A70 : SoftPalette.slate500;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: SoftPalette.gray900.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.adapt(SoftPalette.teal550).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
                style: TextStyle(
                  color: context.adapt(SoftPalette.teal550),
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.urduStyle(
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.branchId.toUpperCase()} • ${widget.role.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(
                    context.isUrdu ? 'لاگ آؤٹ' : 'Sign Out',
                    style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  content: Text(
                    context.isUrdu ? 'کیا آپ واقعی لاگ آؤٹ کرنا چاہتے ہیں؟' : 'Are you sure you want to sign out?',
                    style: context.urduStyle(),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(context.l.cancel, style: context.urduStyle()),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: context.adapt(SoftPalette.red500)),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        context.isUrdu ? 'لاگ آؤٹ' : 'Sign Out',
                        style: context.urduStyle(style: const TextStyle(color: SoftPalette.gray50, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              if (!context.mounted) return;
              final navigator = Navigator.of(context);
              await FirebaseAuth.instance.signOut();
              navigator.pushNamedAndRemoveUntil('/login', (_) => false);
            },
            icon: Icon(Icons.logout_rounded, size: 15, color: context.adapt(SoftPalette.red500)),
            label: Text(
              context.isUrdu ? 'لاگ آؤٹ' : 'Sign Out',
              style: context.urduStyle(
                style: TextStyle(
                  color: context.adapt(SoftPalette.red500),
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: context.adapt(SoftPalette.red500).withValues(alpha: 0.35)),
              backgroundColor: context.adapt(SoftPalette.red500).withValues(alpha: 0.06),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [SoftPalette.teal550, SoftPalette.emerald350],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: SoftPalette.teal550.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;

          final settingsIconBadge = Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: SoftPalette.gray50.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.settings_suggest_rounded,
              color: SoftPalette.gray50,
              size: 28,
            ),
          );

          final titleText = Text(
            context.l.configTitle,
            style: context.urduStyle(
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: SoftPalette.gray50,
              ),
            ),
          );

          final subtitleText = Text(
            'Set active month and rules',
            style: context.urduStyle(
              style: TextStyle(
                fontSize: 14,
                color: SoftPalette.gray50.withValues(alpha: 0.85),
              ),
            ),
          );

          final manageHolidaysBtn = ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HolidayManagementView(branchId: widget.branchId),
                ),
              );
            },
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: const Text(
              'Manage Holidays',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: SoftPalette.gray50.withValues(alpha: 0.15),
              foregroundColor: SoftPalette.gray50,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
                side: BorderSide(color: SoftPalette.gray50.withValues(alpha: 0.2)),
              ),
            ),
          );

          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    settingsIconBadge,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleText,
                          const SizedBox(height: 2),
                          subtitleText,
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: manageHolidaysBtn,
                ),
              ],
            );
          } else {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      settingsIconBadge,
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            titleText,
                            const SizedBox(height: 4),
                            subtitleText,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                manageHolidaysBtn,
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildActivePeriodCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark || UserThemeService.isDarkMode(widget.username);
    final periodColor = isDark ? SoftPalette.blue350 : HSLColor.fromAHSL(1.0, 210, 0.65, 0.45).toColor();

    return _configCard(
      context: context,
      title: context.l.activePeriod,
      subtitle: 'Select active year, month, and PTM day',
      icon: Icons.calendar_month_rounded,
      hue: 210,
      trailing: TextButton.icon(
        onPressed: () {
          setState(() {
            _year = DateTime.now().year;
            _month = DateTime.now().month;
          });
          AppToast.showSnackBar(context, 
            SnackBar(
              content: Text(
                'Detected current period: ${DateFormat('MMMM yyyy').format(DateTime.now())}',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        icon: Icon(Icons.autorenew_rounded, color: periodColor, size: 18),
        label: Text(
          'Auto Detect',
          style: TextStyle(color: periodColor, fontWeight: FontWeight.bold),
        ),
      ),
      child: Column(
        children: [
          _dropdownField(
            context,
            context.l.year,
            _year,
            List.generate(5, (i) => 2024 + i),
            (v) => setState(() => _year = v!),
            prefixIcon: Icons.calendar_today_rounded,
          ),
          const SizedBox(height: 16),
          _dropdownField(
            context,
            context.l.month,
            _month,
            List.generate(12, (i) => i + 1),
            (v) => setState(() => _month = v!),
            isMonth: true,
            prefixIcon: Icons.date_range_rounded,
          ),
          const SizedBox(height: 16),
          _dropdownField(
            context,
            context.l.ptmDay,
            _ptmDay,
            List.generate(32, (i) => i),
            (v) => setState(() => _ptmDay = v!),
            isPtmDay: true,
            prefixIcon: Icons.event_rounded,
          ),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: MadrassaLocalStorage.streamHolidaysCached(widget.branchId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final ptmDate = getPtmDate();
              final hasHoliday = snapshot.data!.any((doc) {
                final dateObj = doc['date'];
                DateTime? d;
                if (dateObj is Timestamp) {
                  d = dateObj.toDate();
                } else if (dateObj is String) {
                  d = DateTime.tryParse(dateObj);
                } else if (dateObj is DateTime) {
                  d = dateObj;
                }
                if (d != null) {
                  return d.year == ptmDate.year &&
                      d.month == ptmDate.month &&
                      d.day == ptmDate.day;
                }
                return false;
              });

              if (hasHoliday) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? SoftPalette.orange800.withValues(alpha: 0.5) : SoftPalette.pink100m,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? SoftPalette.orange700 : SoftPalette.red200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: isDark ? SoftPalette.red350 : SoftPalette.red500),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Warning: Selected PTM date falls on a holiday.',
                            style: TextStyle(
                              color: isDark ? SoftPalette.red300 : SoftPalette.red550,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDataImportExportCard(BuildContext context) {
    final busy = _isExporting || _isImporting;
    final isDark = Theme.of(context).brightness == Brightness.dark || UserThemeService.isDarkMode(widget.username);

    return _configCard(
      context: context,
      title: context.l.dataImportExport,
      subtitle: context.l.dataImportExportSubtitle,
      icon: Icons.swap_vert_rounded,
      hue: 280,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;

          final studentsTile = _exportTile(
            context,
            label: context.l.exportStudents,
            subtitle: context.isUrdu ? 'طلباء کی فہرست' : 'Students Roster',
            icon: Icons.groups_outlined,
            iconColor: context.adapt(SoftPalette.teal550),
            onPressed: busy ? null : () => _exportCsv(MadrassaCsvType.students),
          );

          final dailyLogsTile = _exportTile(
            context,
            label: context.l.exportDailyLogs,
            subtitle: context.isUrdu ? 'حاضری اور اسباق' : 'Attendance & Logs',
            icon: Icons.event_note_outlined,
            iconColor: context.adapt(SoftPalette.blue350),
            onPressed: busy ? null : () => _exportCsv(MadrassaCsvType.dailyLogs),
          );

          final auditLogTile = _exportTile(
            context,
            label: context.l.exportAuditLog,
            subtitle: context.isUrdu ? 'سرگرمی لاگ' : 'Audit Trail',
            icon: Icons.history_edu_outlined,
            iconColor: context.adapt(SoftPalette.violet550),
            onPressed: busy ? null : () => _exportCsv(MadrassaCsvType.auditLog),
          );

          final exportAllTile = _exportTile(
            context,
            label: context.l.exportAllCsv,
            subtitle: context.isUrdu ? 'مکمل بیک اپ' : 'Complete Backup',
            icon: Icons.folder_zip_outlined,
            iconColor: context.adapt(SoftPalette.emerald350),
            isPrimary: true,
            onPressed: busy ? null : () => _exportCsv(MadrassaCsvType.unknown),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                Row(
                  children: [
                    Expanded(child: studentsTile),
                    const SizedBox(width: 10),
                    Expanded(child: dailyLogsTile),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: auditLogTile),
                    const SizedBox(width: 10),
                    Expanded(child: exportAllTile),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(child: studentsTile),
                    const SizedBox(width: 12),
                    Expanded(child: dailyLogsTile),
                    const SizedBox(width: 12),
                    Expanded(child: auditLogTile),
                    const SizedBox(width: 12),
                    Expanded(child: exportAllTile),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              // Import / Restore Box
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: busy ? null : _importCsv,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? SoftPalette.slate900.withValues(alpha: 0.6)
                          : context.adapt(SoftPalette.teal550).withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: context.adapt(SoftPalette.teal550).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.adapt(SoftPalette.teal550).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: _isImporting
                              ? const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : Icon(
                                  Icons.upload_file_rounded,
                                  color: context.adapt(SoftPalette.teal550),
                                  size: 22,
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l.importCsv,
                                style: context.urduStyle(
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: isDark ? SoftPalette.gray50 : SoftPalette.slate800,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                context.isUrdu
                                    ? 'CSV فائل سے طلباء یا لاگز بحال کریں'
                                    : 'Restore students, daily logs, or audit records from CSV',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? SoftPalette.gray50A70 : SoftPalette.slate500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 13,
                          color: context.adapt(SoftPalette.teal550),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isExporting) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(color: context.adapt(SoftPalette.teal550)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _exportTile(
    BuildContext context, {
    required String label,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback? onPressed,
    bool isPrimary = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark || UserThemeService.isDarkMode(widget.username);
    final cardBg = isDark
        ? (isPrimary ? context.adapt(SoftPalette.teal550).withValues(alpha: 0.16) : SoftPalette.slate900.withValues(alpha: 0.6))
        : (isPrimary ? context.adapt(SoftPalette.teal550).withValues(alpha: 0.08) : SoftPalette.gray50);
    final borderColor = isPrimary
        ? context.adapt(SoftPalette.teal550).withValues(alpha: 0.45)
        : (isDark ? SoftPalette.slate700 : SoftPalette.slate200);
    final textColor = isDark ? SoftPalette.gray50 : SoftPalette.slate800;
    final subColor = isDark ? SoftPalette.gray50A70 : SoftPalette.slate500;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: isPrimary ? 1.2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 17, color: iconColor),
                  ),
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 15,
                    color: isPrimary ? context.adapt(SoftPalette.teal550) : subColor,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.urduStyle(
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.urduStyle(
                  style: TextStyle(
                    fontSize: 10,
                    color: subColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeductionsCard(BuildContext context) {
    final bool isFeeEnabled = LocalStorageService.isMadrassaFeeEnabled(widget.branchId);
    final isDark = Theme.of(context).brightness == Brightness.dark || UserThemeService.isDarkMode(widget.username);

    return _configCard(
      context: context,
      title: context.l.deductionParams,
      subtitle: isFeeEnabled ? 'Rules for calculating pro-rated dues' : 'Financial System & Fees are disabled in Branch Facilities',
      icon: Icons.account_balance_wallet_rounded,
      hue: isFeeEnabled ? 35 : 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isFeeEnabled) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? SoftPalette.orange800.withValues(alpha: 0.5) : SoftPalette.yellow50m,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? SoftPalette.orange700 : SoftPalette.amber300),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: isDark ? SoftPalette.amber200 : SoftPalette.orange400, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Money Factor is disabled for this branch in Branch Facilities. Fee dues and deduction savings are turned off and hidden across all Parent, Teacher, and Principal screens.',
                      style: TextStyle(fontSize: 12, color: isDark ? SoftPalette.yellow150 : SoftPalette.orange600, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: _textField(
                  context,
                  context.l.baseFee,
                  _baseFeeController,
                  isRequired: true,
                  errorText: _baseFeeError,
                  prefixIcon: Icons.money_rounded,
                  onChanged: (v) {
                    if (_baseFeeError != null) setState(() => _baseFeeError = null);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _textField(
                  context,
                  context.l.ptmDeduction,
                  _ptmDeductionController,
                  isRequired: true,
                  errorText: _ptmDeductionError,
                  prefixIcon: Icons.discount_rounded,
                  onChanged: (v) {
                    if (_ptmDeductionError != null) setState(() => _ptmDeductionError = null);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _textField(
            context,
            context.l.messageDeduction,
            _msgDeductionController,
            isRequired: true,
            errorText: _msgDeductionError,
            prefixIcon: Icons.sms_rounded,
            onChanged: (v) {
              if (_msgDeductionError != null) setState(() => _msgDeductionError = null);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _textField(
                  context,
                  context.l.maxAttSavings,
                  _maxAttDeductionController,
                  isRequired: true,
                  errorText: _maxAttDeductionError,
                  prefixIcon: Icons.check_circle_outline_rounded,
                  onChanged: (v) {
                    if (_maxAttDeductionError != null) setState(() => _maxAttDeductionError = null);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _textField(
                  context,
                  context.l.maxUniSavings,
                  _maxUniDeductionController,
                  isRequired: true,
                  errorText: _maxUniDeductionError,
                  prefixIcon: Icons.checkroom_rounded,
                  onChanged: (v) {
                    if (_maxUniDeductionError != null) setState(() => _maxUniDeductionError = null);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _configCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget child,
    required IconData icon,
    required double hue,
    Widget? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark || UserThemeService.isDarkMode(widget.username);
    final cardBg = isDark ? SoftPalette.slate800 : SoftPalette.gray50;
    final borderColor = isDark ? SoftPalette.slate700 : SoftPalette.gray350.withValues(alpha: 0.12);
    final textPrimary = isDark ? SoftPalette.gray50 : SoftPalette.gray900;
    final textMuted = isDark ? SoftPalette.slate350 : SoftPalette.gray350;

    final accentColor = HSLColor.fromAHSL(1.0, hue, 0.65, isDark ? 0.60 : 0.45).toColor();
    final bgTint = HSLColor.fromAHSL(1.0, hue, 0.65, isDark ? 0.20 : 0.94).toColor();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: SoftPalette.gray900.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bgTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.urduStyle(
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: context.urduStyle(
                        style: TextStyle(fontSize: 12, color: textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _textField(
    BuildContext context,
    String label,
    TextEditingController controller, {
    String? errorText,
    bool isRequired = false,
    ValueChanged<String>? onChanged,
    IconData? prefixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark || UserThemeService.isDarkMode(widget.username);
    final inputBg = isDark ? SoftPalette.slate900 : SoftPalette.gray50;
    final borderColor = isDark ? SoftPalette.slate700 : SoftPalette.slate150;
    final textPrimary = isDark ? SoftPalette.gray50 : SoftPalette.gray900;
    final labelColor = isDark ? SoftPalette.gray50A70 : SoftPalette.slate700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isRequired
            ? RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: label,
                      style: context.urduStyle(
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                        ),
                      ),
                    ),
                    TextSpan(
                      text: ' *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: context.adapt(SoftPalette.red500)),
                    ),
                  ],
                ),
              )
            : Text(
                label,
                style: context.urduStyle(
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                ),
              ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          onChanged: onChanged,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
          decoration: InputDecoration(
            errorText: errorText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20, color: isDark ? SoftPalette.slate350 : null) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: errorText != null ? context.adapt(SoftPalette.red500) : borderColor,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.adapt(SoftPalette.teal550), width: 2),
            ),
            filled: true,
            fillColor: inputBg,
          ),
        ),
      ],
    );
  }

  Widget _dropdownField(
    BuildContext context,
    String label,
    int value,
    List<int> items,
    ValueChanged<int?> onChanged, {
    bool isMonth = false,
    bool isPtmDay = false,
    IconData? prefixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark || UserThemeService.isDarkMode(widget.username);
    final cardBg = isDark ? SoftPalette.slate800 : SoftPalette.gray50;
    final inputBg = isDark ? SoftPalette.slate900 : SoftPalette.gray50;
    final borderColor = isDark ? SoftPalette.slate700 : SoftPalette.slate150;
    final textPrimary = isDark ? SoftPalette.gray50 : SoftPalette.gray900A87;
    final labelColor = isDark ? SoftPalette.gray50A70 : SoftPalette.slate700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.urduStyle(
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: value,
          dropdownColor: cardBg,
          items: items.map((i) {
            String text = '$i';
            if (isMonth) text = DateFormat('MMMM').format(DateTime(2024, i));
            if (isPtmDay) text = i == 0 ? 'Auto (1st Friday)' : 'Day $i';
            return DropdownMenuItem(value: i, child: Text(text, style: TextStyle(color: textPrimary)));
          }).toList(),
          onChanged: onChanged,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
          decoration: InputDecoration(
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20, color: isDark ? SoftPalette.slate350 : null) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.adapt(SoftPalette.teal550), width: 2),
            ),
            filled: true,
            fillColor: inputBg,
          ),
        ),
      ],
    );
  }
}
