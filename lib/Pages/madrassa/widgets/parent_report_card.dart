// lib/pages/madrassa/widgets/parent_report_card.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import '../madrassa_strings.dart';
import '../models/madrassa_config.dart';
import '../models/madrassa_fee_logic.dart';
import '../widgets/madrassa_common_widgets.dart';
import '../utils/madrassa_report_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/offline_auth_service.dart';
import '../../../services/local_storage_service.dart';

Map<String, dynamic>? _asStringMap(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

DateTime _parseDateTime(dynamic val, [DateTime? fallback]) {
  if (val == null) return fallback ?? DateTime.now();
  if (val is Timestamp) return val.toDate();
  if (val is String) {
    return DateTime.tryParse(val) ?? fallback ?? DateTime.now();
  }
  if (val is DateTime) return val;
  return fallback ?? DateTime.now();
}

class ParentReportCard extends StatefulWidget {
  final String branchId;
  final String studentId;
  final Map<String, dynamic> studentData;
  final int? year;
  final int? month;
  final VoidCallback? onLogout;

  static const Color primaryColor = Color(0xFF1B4332);
  static const Color accentColor = Color(0xFFD4A017);
  static const Color surfaceColor = Color(0xFFF9F6EF);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color textPrimaryColor = Color(0xFF1A1A1A);
  static const Color textMutedColor = Color(0xFF6B7280);
  static const Color errorColor = Color(0xFFDC2626);
  static const Color successColor = Color(0xFF16A34A);

  const ParentReportCard({
    super.key,
    required this.branchId,
    required this.studentId,
    required this.studentData,
    this.year,
    this.month,
    this.onLogout,
  });

  @override
  State<ParentReportCard> createState() => _ParentReportCardState();
}

class _ParentReportCardState extends State<ParentReportCard> {
  late int _selectedYear;
  late int _selectedMonth;
  late DateTime _selectedDate;
  int _selectedTab = 0;

  late Stream<QuerySnapshot> _logsStream;
  late Stream<MadrassaConfig> _configStream;
  late Stream<QuerySnapshot> _holidaysStream;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = widget.year ?? now.year;
    _selectedMonth = widget.month ?? now.month;
    _selectedDate = now;
    _initStreams();
  }

  void _initStreams() {
    _logsStream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('madrassa_daily_logs')
        .snapshots();
    _configStream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('madrassa_config')
        .doc('current')
        .snapshots()
        .map((s) => MadrassaConfig.fromFirestore(s));
    _holidaysStream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('madrassa_holidays')
        .snapshots();
  }

  @override
  void didUpdateWidget(covariant ParentReportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool shouldReinit = false;
    if (widget.year != oldWidget.year || widget.month != oldWidget.month) {
      setState(() {
        _selectedYear = widget.year ?? DateTime.now().year;
        _selectedMonth = widget.month ?? DateTime.now().month;
      });
    }
    if (widget.branchId != oldWidget.branchId) {
      _initStreams();
      shouldReinit = true;
    }
    if (shouldReinit) {
      setState(() {});
    }
  }

  Future<void> _requestReplyVerification(BuildContext context, String branchId, String dateStr, String studentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('madrassa_daily_logs')
          .doc(dateStr)
          .set({
        studentId: {
          'parentRepliedRequested': true,
          'timestamp': FieldValue.serverTimestamp()
        }
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.isUrdu 
                ? 'جواب کی تصدیق کی درخواست بھیج دی گئی ہے۔' 
                : 'Reply verification request submitted successfully.'),
            backgroundColor: Colors.purple,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showLeaveReasonDialog(BuildContext context, String branchId, String todayStr, String studentId) async {
    final TextEditingController reasonController = TextEditingController();
    String? reasonError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDs) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(context.t('Request Leave'), style: TextStyle(fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: context.t('Leave Reason'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B), fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                  decoration: InputDecoration(
                    hintText: context.t('Enter reason here...'),
                    hintStyle: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                    errorText: reasonError != null ? context.t(reasonError!) : null,
                    errorStyle: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: reasonError != null ? const Color(0xFFD32F2F) : const Color(0xFFD0D3D9)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF4C4DDC), width: 2),
                    ),
                  ),
                  onChanged: (v) {
                    if (reasonError != null) setDs(() => reasonError = null);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.t('Cancel'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (reasonController.text.trim().isEmpty) {
                    setDs(() => reasonError = 'Leave reason is required');
                    return;
                  }
                  await FirebaseFirestore.instance
                      .collection('branches')
                      .doc(branchId)
                      .collection('madrassa_daily_logs')
                      .doc(todayStr)
                      .set({
                    studentId: {
                      'attendance': 'leave_requested',
                      'isParentRequested': true,
                      'leaveReason': reasonController.text.trim(),
                      'leaveStatus': 'pending',
                      'timestamp': FieldValue.serverTimestamp()
                    }
                  }, SetOptions(merge: true));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ParentReportCard.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text(context.t('Submit'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showRejoinDialog(BuildContext context) async {
    final reasonCtrl = TextEditingController();
    String? reasonError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDs) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(context.t('Request Rejoining'), style: TextStyle(fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('Please specify the reason/notes for requesting to rejoin the Madrassa.'),
                  style: TextStyle(fontSize: 13, color: Colors.grey, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: context.t('Rejoining Reason'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B), fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                  decoration: InputDecoration(
                    hintText: context.t('e.g. Relocating back, student wants to resume.'),
                    hintStyle: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                    errorText: reasonError != null ? context.t(reasonError!) : null,
                    errorStyle: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: reasonError != null ? const Color(0xFFD32F2F) : const Color(0xFFD0D3D9)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF4C4DDC), width: 2),
                    ),
                  ),
                  onChanged: (v) {
                    if (reasonError != null) setDs(() => reasonError = null);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.t('Cancel'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (reasonCtrl.text.trim().isEmpty) {
                    setDs(() => reasonError = 'Rejoining reason is required');
                    return;
                  }
                  await FirebaseFirestore.instance
                      .collection('branches')
                      .doc(widget.branchId)
                      .collection('madrassa_students')
                      .doc(widget.studentId)
                      .update({
                    'rejoinRequestStatus': 'pending',
                    'rejoinRequestReason': reasonCtrl.text.trim(),
                    'rejoinRequestDate': FieldValue.serverTimestamp(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ParentReportCard.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text(context.t('Submit Request'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final oldPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final confirmPwCtrl = TextEditingController();
    
    String? oldPwError;
    String? newPwError;
    String? confirmPwError;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDs) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(
              context.t('Change Password'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: context.isUrdu ? 'Noori' : null,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTf(
                    oldPwCtrl,
                    context.t('Old Password'),
                    Icons.lock_open_rounded,
                    context,
                    obscure: true,
                    isRequired: true,
                    errorText: oldPwError,
                    onChanged: (v) {
                      if (oldPwError != null) setDs(() => oldPwError = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  buildTf(
                    newPwCtrl,
                    context.t('New Password'),
                    Icons.lock_outline_rounded,
                    context,
                    obscure: true,
                    isRequired: true,
                    errorText: newPwError,
                    onChanged: (v) {
                      if (newPwError != null) setDs(() => newPwError = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  buildTf(
                    confirmPwCtrl,
                    context.t('Confirm Password'),
                    Icons.lock_outline_rounded,
                    context,
                    obscure: true,
                    isRequired: true,
                    errorText: confirmPwError,
                    onChanged: (v) {
                      if (confirmPwError != null) setDs(() => confirmPwError = null);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: Text(
                  context.t('Cancel'),
                  style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                ),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final navigator = Navigator.of(ctx);
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final successMsg = context.t('Password changed successfully!');
                        final incorrectPwMsg = context.t('Incorrect old password');
                        final failedMsg = context.t('Failed to change password');

                        bool isValid = true;
                        if (oldPwCtrl.text.trim().isEmpty) {
                          oldPwError = context.t('Old password is required');
                          isValid = false;
                        }
                        if (newPwCtrl.text.trim().isEmpty) {
                          newPwError = context.t('New password is required');
                          isValid = false;
                        } else if (newPwCtrl.text.trim().length < 6) {
                          newPwError = context.t('Password must be at least 6 characters');
                          isValid = false;
                        }
                        if (confirmPwCtrl.text.trim().isEmpty) {
                          confirmPwError = context.t('Confirm password is required');
                          isValid = false;
                        } else if (newPwCtrl.text.trim() != confirmPwCtrl.text.trim()) {
                          confirmPwError = context.t('Passwords do not match');
                          isValid = false;
                        }

                        if (!isValid) {
                          setDs(() {});
                          return;
                        }

                        setDs(() => isSaving = true);
                        try {
                          final currentUser = FirebaseAuth.instance.currentUser;
                          if (currentUser == null) {
                            throw Exception(context.t('No active login session found'));
                          }
                          final email = currentUser.email;
                          if (email == null || email.isEmpty) {
                            throw Exception(context.t('User email is not set'));
                          }

                          // Re-authenticate
                          final cred = EmailAuthProvider.credential(
                            email: email,
                            password: oldPwCtrl.text.trim(),
                          );
                          await currentUser.reauthenticateWithCredential(cred);

                          // Update Auth Password
                          await currentUser.updatePassword(newPwCtrl.text.trim());

                          // Update offline auth cache password
                          await OfflineAuthService.updateCachedPassword(
                            newPwCtrl.text.trim(),
                            usernameOrEmail: email,
                          );

                          // Update Firestore documents copy
                          final uid = currentUser.uid;
                          final updates = {
                            'password': newPwCtrl.text.trim(),
                            'passwordHash': LocalStorageService.hashPassword(newPwCtrl.text.trim()),
                            'lastUpdatedAt': FieldValue.serverTimestamp(),
                          };
                          await FirebaseFirestore.instance.collection('users').doc(uid).set(updates, SetOptions(merge: true));
                          await FirebaseFirestore.instance
                              .collection('branches')
                              .doc(widget.branchId)
                              .collection('users')
                              .doc(uid)
                              .set(updates, SetOptions(merge: true));

                          if (ctx.mounted) {
                            navigator.pop();
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(successMsg),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } on FirebaseAuthException catch (e) {
                          setDs(() => isSaving = false);
                          if (e.code == 'wrong-password') {
                            oldPwError = incorrectPwMsg;
                          } else {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(e.message ?? failedMsg),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          setDs(() {});
                        } catch (e) {
                          setDs(() => isSaving = false);
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ParentReportCard.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        context.t('Confirm'),
                        style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _updateSelectedDateForNewMonth() {
    final now = DateTime.now();
    if (_selectedYear == now.year && _selectedMonth == now.month) {
      _selectedDate = now;
    } else {
      _selectedDate = DateTime(_selectedYear, _selectedMonth, 1);
    }
  }

  String _formatRemainingTime(double days) {
    if (days.isInfinite || days.isNaN || days <= 0) {
      return context.isUrdu ? 'کارکردگی کی معلومات درکار ہیں' : 'No pace data';
    }
    final int totalDays = days.round();
    final int years = totalDays ~/ 365;
    final int months = (totalDays % 365) ~/ 30;
    final int remainingDays = (totalDays % 365) % 30;

    if (context.isUrdu) {
      final parts = <String>[];
      if (years > 0) parts.add('$years سال');
      if (months > 0) parts.add('$months مہینے');
      if (years == 0 && months == 0) parts.add('$remainingDays دن');
      return parts.join('، ');
    } else {
      final parts = <String>[];
      if (years > 0) parts.add('$years ${years == 1 ? "year" : "years"}');
      if (months > 0) parts.add('$months ${months == 1 ? "month" : "months"}');
      if (years == 0 && months == 0) parts.add('$remainingDays ${remainingDays == 1 ? "day" : "days"}');
      return parts.join(', ');
    }
  }

  String _formatDuration(DateTime start, DateTime end) {
    int years = end.year - start.year;
    int months = end.month - start.month;
    int days = end.day - start.day;

    if (days < 0) {
      months -= 1;
      final prevMonth = DateTime(end.year, end.month, 0);
      days += prevMonth.day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }

    if (context.isUrdu) {
      final parts = <String>[];
      if (years > 0) parts.add('$years سال');
      if (months > 0) parts.add('$months مہینے');
      if (days > 0 || parts.isEmpty) parts.add('$days دن');
      return parts.join('، ');
    } else {
      final parts = <String>[];
      if (years > 0) parts.add('$years ${years == 1 ? "year" : "years"}');
      if (months > 0) parts.add('$months ${months == 1 ? "month" : "months"}');
      if (days > 0 || parts.isEmpty) parts.add('$days ${days == 1 ? "day" : "days"}');
      return parts.join(', ');
    }
  }

  String _formatMonthYear(DateTime date) {
    if (context.isUrdu) {
      final monthsUr = {
        1: 'جنوری',
        2: 'فروری',
        3: 'مارچ',
        4: 'اپریل',
        5: 'مئی',
        6: 'جون',
        7: 'جولائی',
        8: 'اگست',
        9: 'ستمبر',
        10: 'اکتوبر',
        11: 'نومبر',
        12: 'دسمبر',
      };
      return '${monthsUr[date.month]} ${date.year}';
    }
    return DateFormat('MMMM yyyy').format(date);
  }

  String _formatMonth(DateTime date) {
    if (context.isUrdu) {
      final monthsUr = {
        1: 'جنوری',
        2: 'فروری',
        3: 'مارچ',
        4: 'اپریل',
        5: 'مئی',
        6: 'جون',
        7: 'جولائی',
        8: 'اگست',
        9: 'ستمبر',
        10: 'اکتوبر',
        11: 'نومبر',
        12: 'دسمبر',
      };
      return monthsUr[date.month] ?? '';
    }
    return DateFormat('MMMM').format(date);
  }

  Widget _buildCongratulatoryCard({
    required DateTime joinDate,
    required DateTime completionDate,
    required String studentName,
  }) {
    final durationStr = _formatDuration(joinDate, completionDate);
    final joinDateStr = context.isUrdu 
        ? DateFormat('dd-MM-yyyy').format(joinDate)
        : DateFormat('MMMM d, yyyy').format(joinDate);
    final compDateStr = context.isUrdu
        ? DateFormat('dd-MM-yyyy').format(completionDate)
        : DateFormat('MMMM d, yyyy').format(completionDate);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F5132), Color(0xFF0D6EFD)], // Emerald to Royal Blue
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F5132).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.stars_rounded,
                  color: Colors.amber,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alhamdulillah! 🎉',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                    Text(
                      context.t('Hifz Completed Successfully'),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            context.isUrdu
                ? 'محترم والدین، ہم آپ کو اور آپ کے خاندان کو دلی مبارکباد پیش کرتے ہیں! اللہ تعالیٰ کے فضل و کرم سے، $studentName نے قرآن پاک کا حفظ (8,640 لائنیں) مکمل کر لیا ہے۔'
                : 'Dear Parents, we offer our warmest congratulations to you and your family! By the grace of Almighty Allah, $studentName has completed the memorization of the Holy Quran (8,640 lines).',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
              fontFamily: context.isUrdu ? 'Noori' : null,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.t('Time Taken:'),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                    Text(
                      durationStr,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.t('Started Hifz:'),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                    Text(
                      joinDateStr,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.t('Completed Hifz:'),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                    Text(
                      compDateStr,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastTile({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color color,
    bool isLongValue = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isLongValue ? 15 : 18, 
              fontWeight: FontWeight.bold, 
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ParentReportCard.primaryColor),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ParentReportCard.textPrimaryColor),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: ParentReportCard.textMutedColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String label;

    switch (status) {
      case 'active':
        color = ParentReportCard.successColor;
        label = 'Active';
        break;
      case 'left':
        color = ParentReportCard.errorColor;
        label = 'Left';
        break;
      case 'archived':
        color = Colors.orange;
        label = 'Archived';
        break;
      case 'hifz_completed':
        color = ParentReportCard.primaryColor;
        label = 'Hifz Completed';
        break;
      default:
        color = Colors.grey;
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            context.t(label),
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13, fontFamily: context.isUrdu ? 'Noori' : null),
          ),
        ],
      ),
    );
  }

  Widget _buildRejoinUI(String status, String? rejoinRequestStatus, String? rejoinReason, Timestamp? rejoinDate) {
    if (status != 'left') return const SizedBox();

    if (rejoinRequestStatus == 'pending') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_empty_rounded, color: Colors.amber.shade900, size: 18),
                const SizedBox(width: 8),
                Text(
                  context.t('Rejoin Request Pending'),
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.isUrdu 
                  ? 'وجہ: "${rejoinReason ?? 'وجہ درج نہیں ہے'}"'
                  : 'Reason: "${rejoinReason ?? 'No reason specified'}"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.amber.shade800, fontFamily: context.isUrdu ? 'Noori' : null),
            ),
            if (rejoinDate != null) ...[
              const SizedBox(height: 4),
              Text(
                context.isUrdu
                    ? 'درخواست کی تاریخ: ${DateFormat('yyyy-MM-dd HH:mm').format(rejoinDate.toDate())}'
                    : 'Requested on: ${DateFormat('yyyy-MM-dd HH:mm').format(rejoinDate.toDate())}',
                style: TextStyle(fontSize: 10, color: Colors.amber.shade700, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
            ],
          ],
        ),
      );
    } else {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _showRejoinDialog(context),
          icon: const Icon(Icons.keyboard_return_rounded, color: Colors.white),
          label: Text(context.t('Request Rejoining'), style: TextStyle(color: Colors.white, fontFamily: context.isUrdu ? 'Noori' : null)),
          style: ElevatedButton.styleFrom(
            backgroundColor: ParentReportCard.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
    }
  }

  Widget _buildTimeline(List<Map<String, dynamic>> auditList) {
    if (auditList.isEmpty) {
      return Center(
        child: Text(
          context.t('No history records found.'),
          style: TextStyle(color: ParentReportCard.textMutedColor, fontFamily: context.isUrdu ? 'Noori' : null),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('Status History Timeline'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: ParentReportCard.textPrimaryColor,
            fontFamily: context.isUrdu ? 'Noori' : null,
          ),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: auditList.length,
          itemBuilder: (context, idx) {
            final log = auditList[idx];
            final logStatus = log['status'] ?? 'unknown';
            final logType = log['type'] ?? 'info';
            final logDateTs = log['date'] as Timestamp?;
            final logDate = logDateTs?.toDate() ?? DateTime.now();
            final logReason = log['reason'] ?? '';

            Color dotColor = Colors.grey;
            IconData icon = Icons.circle;
            if (logStatus == 'active' || logType == 'enrollment' || logType == 'rejoin_approval') {
              dotColor = ParentReportCard.successColor;
              icon = Icons.check_circle_outline;
            } else if (logStatus == 'left' || logType == 'rejoin_rejection') {
              dotColor = ParentReportCard.errorColor;
              icon = Icons.error_outline;
            } else if (logStatus == 'archived') {
              dotColor = Colors.orange;
              icon = Icons.archive_outlined;
            } else if (logStatus == 'hifz_completed') {
              dotColor = ParentReportCard.primaryColor;
              icon = Icons.stars_outlined;
            }

            String displayStatus = context.t(logStatus);
            if (displayStatus == logStatus) {
              displayStatus = logStatus.toUpperCase();
            }
            String displayType = context.t(logType);
            if (displayType == logType) {
              displayType = logType.replaceAll('_', ' ');
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Icon(icon, color: dotColor, size: 20),
                      if (idx < auditList.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: Colors.grey[300],
                            margin: const EdgeInsets.symmetric(vertical: 4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$displayStatus ($displayType)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: dotColor,
                              fontFamily: context.isUrdu ? 'Noori' : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            logReason,
                            style: TextStyle(
                              fontSize: 12,
                              color: ParentReportCard.textPrimaryColor,
                              fontFamily: context.isUrdu ? 'Noori' : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.isUrdu
                                ? DateFormat('dd-MM-yyyy, hh:mm a').format(logDate)
                                : DateFormat('dd MMMM yyyy, hh:mm a').format(logDate),
                            style: const TextStyle(
                              color: ParentReportCard.textMutedColor,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMonthSelector() {
    final date = DateTime(_selectedYear, _selectedMonth);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: ParentReportCard.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ParentReportCard.primaryColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: ParentReportCard.primaryColor),
            onPressed: () {
              setState(() {
                if (_selectedMonth == 1) {
                  _selectedMonth = 12;
                  _selectedYear--;
                } else {
                  _selectedMonth--;
                }
                _updateSelectedDateForNewMonth();
              });
            },
          ),
          Row(
            children: [
              const Icon(Icons.calendar_month, color: ParentReportCard.primaryColor),
              const SizedBox(width: 12),
              Text(
                _formatMonthYear(date),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: ParentReportCard.primaryColor,
                  fontFamily: context.isUrdu ? 'Noori' : null,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, color: ParentReportCard.primaryColor),
            onPressed: () {
              setState(() {
                if (_selectedMonth == 12) {
                  _selectedMonth = 1;
                  _selectedYear++;
                } else {
                  _selectedMonth++;
                }
                _updateSelectedDateForNewMonth();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeroHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ParentReportCard.primaryColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: widget.studentData['photoUrl'] != null && widget.studentData['photoUrl'].toString().isNotEmpty
                  ? Image.network(
                      widget.studentData['photoUrl'],
                      fit: BoxFit.cover,
                      width: 56,
                      height: 56,
                      errorBuilder: (ctx, err, stack) => const Icon(Icons.person, color: ParentReportCard.primaryColor, size: 28),
                    )
                  : Text(
                      widget.studentData['name']?[0] ?? '?',
                      style: const TextStyle(color: ParentReportCard.primaryColor, fontWeight: FontWeight.bold, fontSize: 24),
                    ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentData['name'] ?? '',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
                const SizedBox(height: 4),
                Text(
                  context.isUrdu 
                      ? 'رول نمبر: ${widget.studentData['rollNumber'] ?? '?'} • کلاس: ${context.t(widget.studentData['class'] ?? 'Hifz')}'
                      : 'Roll: ${widget.studentData['rollNumber'] ?? '?'} • Class: ${widget.studentData['class'] ?? 'Hifz'}',
                  style: TextStyle(fontSize: 13, color: Colors.white70, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int getLinesCompletedOnDate(DateTime targetDate, List<QueryDocumentSnapshot> allLogs, String studentId) {
    final targetStr = DateFormat('yyyy-MM-dd').format(targetDate);
    final sorted = [...allLogs]..sort((a, b) => a.id.compareTo(b.id)); // oldest first
    
    int targetIndex = sorted.indexWhere((l) => l.id == targetStr);
    if (targetIndex == -1) return 0;
    
    final targetLog = sorted[targetIndex].data() as Map<String, dynamic>?;
    final targetLines = targetLog?[studentId]?['currentLines'] as int?;
    if (targetLines == null) return 0;
    
    int prevLines = 0;
    for (int i = targetIndex - 1; i >= 0; i--) {
      final log = sorted[i].data() as Map<String, dynamic>?;
      final lines = log?[studentId]?['currentLines'] as int?;
      if (lines != null) {
        prevLines = lines;
        break;
      }
    }
    
    if (prevLines == 0) {
      prevLines = int.tryParse(widget.studentData['prevHifzLines']?.toString() ?? '0') ?? 0;
    }
    
    return (targetLines - prevLines).clamp(0, 9999);
  }

  Widget _buildDailyDetailsCard(List<QueryDocumentSnapshot> allLogs, List<Map<String, dynamic>> holidaysData, MadrassaConfig config) {
    final joinDate = _parseDateTime(widget.studentData['joinDate']);
    
    final selectedZero = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final joinZero = joinDate != null ? DateTime(joinDate.year, joinDate.month, joinDate.day) : null;
    final now = DateTime.now();
    final nowZero = DateTime(now.year, now.month, now.day);
    final isSelectedToday = _selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day;
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    
    final dateStrFormatted = context.isUrdu
        ? '${_selectedDate.day} ${_formatMonth(_selectedDate)} ${_selectedDate.year}'
        : DateFormat('d MMMM yyyy').format(_selectedDate);

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    Map<String, dynamic>? statusData;
    try {
      final doc = allLogs.firstWhere((l) => l.id == dateStr);
      final rawData = doc.data();
      if (rawData is Map) {
        statusData = _asStringMap(rawData[widget.studentId]);
      }
    } catch (_) {}

    final ptmDate = config.getPtmDate();
    final isSelectedPtm = _selectedDate.year == ptmDate.year &&
        _selectedDate.month == ptmDate.month &&
        _selectedDate.day == ptmDate.day;
    final isSelectedPast = _selectedDate.isBefore(nowZero);

    Widget? ptmBanner;
    if (isSelectedPtm) {
      final ptmAttended = statusData?['ptm'] == true;
      final isFutureOrToday = !isSelectedPast;
      
      Color bannerColor;
      IconData bannerIcon;
      String bannerTitle;
      String bannerSubtitle;
      
      if (isFutureOrToday) {
        bannerColor = ParentReportCard.accentColor;
        bannerIcon = Icons.people_rounded;
        bannerTitle = context.isUrdu ? 'پی ٹی ایم میٹنگ (آج/عنقریب)' : 'PTM Meeting (Today/Upcoming)';
        bannerSubtitle = context.isUrdu 
            ? 'سرپرست اور اساتذہ کی میٹنگ شیڈول ہے۔' 
            : 'Scheduled Parent Teacher Meeting.';
      } else {
        if (ptmAttended) {
          bannerColor = const Color(0xFF1B4332);
          bannerIcon = Icons.people_rounded;
          bannerTitle = context.isUrdu ? 'پی ٹی ایم: شامل ہوئے' : 'PTM: Joined';
          bannerSubtitle = context.isUrdu 
              ? 'آپ کامیابی کے ساتھ میٹنگ میں شامل ہوئے تھے۔' 
              : 'You successfully attended this meeting.';
        } else {
          bannerColor = const Color(0xFFDC2626);
          bannerIcon = Icons.people_outline_rounded;
          bannerTitle = context.isUrdu ? 'پی ٹی ایم: شامل نہیں ہوئے' : 'PTM: Missed';
          bannerSubtitle = context.isUrdu 
              ? 'آپ اس میٹنگ میں شامل نہیں ہو سکے۔' 
              : 'You missed this meeting.';
        }
      }
      
      ptmBanner = Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bannerColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: bannerColor.withValues(alpha: 0.25), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bannerColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(bannerIcon, color: bannerColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bannerTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: bannerColor,
                      fontFamily: context.isUrdu ? 'Noori' : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bannerSubtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: bannerColor.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                      fontFamily: context.isUrdu ? 'Noori' : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    Widget content;
    
    if (joinZero != null && selectedZero.isBefore(joinZero)) {
      content = Column(
        children: [
          if (ptmBanner != null) ptmBanner,
          _buildStatusInfoRow(
            icon: Icons.info_outline_rounded,
            color: Colors.blueGrey,
            title: context.isUrdu ? '$dateStrFormatted کا کوئی ریکارڈ نہیں' : "No data for $dateStrFormatted",
            subtitle: context.t("Student was not enrolled in the Madrassa yet."),
          ),
        ],
      );
    } else if (selectedZero.isAfter(nowZero)) {
      content = Column(
        children: [
          if (ptmBanner != null) ptmBanner,
          _buildStatusInfoRow(
            icon: Icons.hourglass_empty_rounded,
            color: Colors.blue,
            title: context.isUrdu ? '$dateStrFormatted کا کوئی ریکارڈ نہیں' : "No data for $dateStrFormatted",
            subtitle: context.t("This is a future date."),
          ),
        ],
      );
    } else if (_selectedDate.weekday == DateTime.sunday) {
      content = Column(
        children: [
          if (ptmBanner != null) ptmBanner,
          _buildStatusInfoRow(
            icon: Icons.weekend_rounded,
            color: Colors.grey,
            title: context.isUrdu ? 'اتوار ($dateStrFormatted)' : "Sunday ($dateStrFormatted)",
            subtitle: context.t("Madrassa is closed on Sundays."),
          ),
        ],
      );
    } else {
      Map<String, dynamic>? holidayDoc;
      for (final h in holidaysData) {
        final hDate = h['date'] as DateTime?;
        if (hDate != null && hDate.year == _selectedDate.year && hDate.month == _selectedDate.month && hDate.day == _selectedDate.day) {
          holidayDoc = h;
          break;
        }
      }
      if (holidayDoc != null) {
        content = Column(
          children: [
            if (ptmBanner != null) ptmBanner,
            _buildStatusInfoRow(
              icon: Icons.flag_rounded,
              color: Colors.green,
              title: context.isUrdu ? 'تعطیل ($dateStrFormatted)' : "Holiday ($dateStrFormatted)",
              subtitle: context.isUrdu ? 'مدرسہ بند ہے: ${holidayDoc['name']}. خوشی سے چھٹی منائیں!' : "Madrassa Closed: ${holidayDoc['name']}. Enjoy your holiday!",
            ),
          ],
        );
      } else {
        if (statusData == null) {
          content = Column(
            children: [
              if (ptmBanner != null) ptmBanner,
              _buildStatusInfoRow(
                icon: Icons.warning_amber_rounded,
                color: Colors.orange,
                title: context.isUrdu ? '$dateStrFormatted کا کوئی ریکارڈ نہیں' : "No data for $dateStrFormatted",
                subtitle: context.t("No records found for this active day."),
              ),
              if (isSelectedToday) ...[
                const SizedBox(height: 16),
                _ActionButton(
                  label: context.t('Request Leave'),
                  icon: Icons.email_outlined,
                  color: ParentReportCard.primaryColor,
                  isSelected: false,
                  isActive: true,
                  onTap: () => _showLeaveReasonDialog(context, widget.branchId, todayStr, widget.studentId),
                ),
              ],
            ],
          );
        } else {
          final att = statusData['attendance']?.toString() ?? 'absent';
          final uni = statusData['uniform'] == true;
          final msg = statusData['parentReplied'] == true;
          final parentRepliedRequested = statusData['parentRepliedRequested'] == true;
          final leaveReason = statusData['leaveReason']?.toString() ?? '';
          final leaveStatus = statusData['leaveStatus']?.toString() ?? 'pending';
          final currentLines = statusData['currentLines'] as int? ?? 0;
          
          Color attColor;
          IconData attIcon;
          String attLabel;
          
          if (att == 'present') {
            attColor = ParentReportCard.successColor;
            attIcon = Icons.check_circle_rounded;
            attLabel = "Present";
          } else if (att == 'leave') {
            attColor = Colors.orange;
            attIcon = Icons.email_rounded;
            attLabel = "On Leave";
          } else if (att == 'leave_requested') {
            attColor = Colors.amber.shade800;
            attIcon = Icons.mail_outline_rounded;
            attLabel = "Leave Requested";
          } else {
            attColor = ParentReportCard.errorColor;
            attIcon = Icons.cancel_rounded;
            attLabel = "Absent";
          }
          
          final linesRead = getLinesCompletedOnDate(_selectedDate, allLogs, widget.studentId);
          
          final int sabkiParaVal = statusData['sabkiPara'] is int ? statusData['sabkiPara'] as int : (int.tryParse(statusData['sabkiPara']?.toString() ?? '') ?? 0);
          final String? sabkiRatioVal = statusData['sabkiRatio']?.toString();
          final int manzilParaVal = statusData['manzilPara'] is int ? statusData['manzilPara'] as int : (int.tryParse(statusData['manzilPara']?.toString() ?? '') ?? 0);
          final String? manzilRatioVal = statusData['manzilRatio']?.toString();

          String formatRatio(String? ratio) {
            if (ratio == '1/4') return context.isUrdu ? 'پاؤ (1/4)' : 'Pao (1/4)';
            if (ratio == '1/2') return context.isUrdu ? 'نصف (1/2)' : 'Nisf (1/2)';
            if (ratio == '3/4') return context.isUrdu ? 'ثلاثہ (3/4)' : 'Salasa (3/4)';
            if (ratio == '1') return context.isUrdu ? 'پارہ (1)' : 'Para (1)';
            if (ratio == 'nahi_sunaya') return context.isUrdu ? 'نہیں سنایا' : 'Nahi Sunaya';
            return ratio ?? '';
          }

          String sabkiText = context.t('No test today');
          if (sabkiParaVal > 0 && sabkiRatioVal != null && sabkiRatioVal.isNotEmpty && sabkiRatioVal != '-') {
            sabkiText = context.isUrdu
                ? 'پارہ $sabkiParaVal • ${formatRatio(sabkiRatioVal)}'
                : 'Para $sabkiParaVal • ${formatRatio(sabkiRatioVal)}';
          } else if (sabkiRatioVal == 'nahi_sunaya') {
            sabkiText = context.isUrdu ? 'نہیں سنایا' : 'Nahi Sunaya';
          }

          String manzilText = context.t('No test today');
          if (manzilParaVal > 0 && manzilRatioVal != null && manzilRatioVal.isNotEmpty && manzilRatioVal != '-') {
            manzilText = context.isUrdu
                ? 'پارہ $manzilParaVal • ${formatRatio(manzilRatioVal)}'
                : 'Para $manzilParaVal • ${formatRatio(manzilRatioVal)}';
          } else if (manzilRatioVal == 'nahi_sunaya') {
            manzilText = context.isUrdu ? 'نہیں سنایا' : 'Nahi Sunaya';
          }

          final isLeaveButtonActive = att == 'unknown' || att == 'absent';
          
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ptmBanner != null) ptmBanner,
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: attColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(attIcon, color: attColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t(attLabel),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: attColor, fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                      Text(
                        context.t("Attendance Status"),
                        style: TextStyle(fontSize: 11, color: Colors.grey, fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                    ],
                  ),
                ],
              ),
              if (att == 'present') ...[
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final gridWidth = constraints.maxWidth;
                    final isSmall = gridWidth < 300;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildDetailMetricCard(
                          width: isSmall ? gridWidth : (gridWidth - 16) / 2,
                          icon: Icons.checkroom_rounded,
                          label: context.t("Uniform"),
                          value: uni ? context.t("Checked & Clean") : context.t("Incomplete/Not Clean"),
                          color: uni ? Colors.blue : Colors.red,
                        ),
                        _buildDetailMetricCard(
                          width: isSmall ? gridWidth : (gridWidth - 16) / 2,
                          icon: Icons.reply_rounded,
                          label: context.t("Message Response"),
                          value: msg 
                              ? context.t("Replied to Teacher") 
                              : (parentRepliedRequested 
                                  ? (context.isUrdu ? "جواب کی تصدیق زیر التواء" : "Verification Pending") 
                                  : context.t("No Response")),
                          color: msg 
                              ? Colors.purple 
                              : (parentRepliedRequested ? Colors.orange : Colors.amber),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ParentReportCard.primaryColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: ParentReportCard.primaryColor.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ParentReportCard.primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.menu_book_rounded, color: ParentReportCard.primaryColor, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.t("Lesson Progress"),
                              style: TextStyle(fontSize: 12, color: ParentReportCard.textMutedColor, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                            ),
                            const SizedBox(height: 8),
                            // Sabak
                            Row(
                              children: [
                                Text(
                                  '${context.t('Sabak')}: ',
                                  style: TextStyle(fontSize: 13, color: ParentReportCard.textMutedColor, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                                ),
                                Expanded(
                                  child: Text(
                                    linesRead > 0
                                        ? (context.isUrdu ? "+$linesRead لائنیں مکمل ہوئیں" : "+$linesRead lines completed")
                                        : context.t("No lines recorded"),
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: ParentReportCard.primaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Sabki
                            Row(
                              children: [
                                Text(
                                  '${context.t('Sabki')}: ',
                                  style: TextStyle(fontSize: 13, color: ParentReportCard.textMutedColor, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                                ),
                                Expanded(
                                  child: Text(
                                    sabkiText,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFED6C02), fontFamily: context.isUrdu ? 'Noori' : null),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Manzil
                            Row(
                              children: [
                                Text(
                                  '${context.t('Manzil')}: ',
                                  style: TextStyle(fontSize: 13, color: ParentReportCard.textMutedColor, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                                ),
                                Expanded(
                                  child: Text(
                                    manzilText,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF4C4DDC), fontFamily: context.isUrdu ? 'Noori' : null),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(),
                            const SizedBox(height: 6),
                            Text(
                              context.isUrdu ? "مجموعی: لائن $currentLines" : "Cumulative: Line $currentLines",
                              style: TextStyle(fontSize: 11, color: ParentReportCard.textMutedColor, fontFamily: context.isUrdu ? 'Noori' : null),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (msg != true) ...[
                  const SizedBox(height: 16),
                  _ActionButton(
                    label: parentRepliedRequested 
                        ? (context.isUrdu ? 'جواب کی تصدیق کی درخواست بھیج دی گئی ہے' : 'Reply Verification Requested') 
                        : (context.isUrdu ? 'جواب کی تصدیق کی درخواست کریں' : 'Request Reply Verification'),
                    icon: Icons.mark_chat_read_outlined,
                    color: Colors.purple,
                    isSelected: parentRepliedRequested,
                    isActive: !parentRepliedRequested,
                    onTap: () => _requestReplyVerification(context, widget.branchId, dateStr, widget.studentId),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                if (att == 'leave' || att == 'leave_requested') ...[
                  if (leaveReason.isNotEmpty) ...[
                    Text(context.t("Leave Reason:"), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, fontFamily: context.isUrdu ? 'Noori' : null)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        leaveReason,
                        style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Text(context.t("Approval Status: "), style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: context.isUrdu ? 'Noori' : null)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (leaveStatus == 'approved' ? Colors.green : (leaveStatus == 'denied' ? Colors.red : Colors.amber)).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          context.t(leaveStatus).toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: leaveStatus == 'approved' ? Colors.green : (leaveStatus == 'denied' ? Colors.red : Colors.amber.shade900),
                            fontFamily: context.isUrdu ? 'Noori' : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              if (isSelectedToday) ...[
                const SizedBox(height: 20),
                _ActionButton(
                  label: att == 'leave_requested' ? context.t('Leave Requested') : (att == 'leave' ? context.t('On Leave') : context.t('Request Leave')),
                  icon: Icons.email_outlined,
                  color: ParentReportCard.primaryColor,
                  isSelected: att == 'leave_requested' || att == 'leave',
                  isActive: isLeaveButtonActive,
                  onTap: () => _showLeaveReasonDialog(context, widget.branchId, todayStr, widget.studentId),
                ),
              ],
            ],
          );
        }
      }
    }
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
        border: Border.all(color: const Color(0xFFE0E2E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: ParentReportCard.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                context.t("Daily Details"),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
              const Spacer(),
              Text(
                context.isUrdu
                    ? '${_selectedDate.day} ${_formatMonth(_selectedDate)}'
                    : DateFormat('MMM d').format(_selectedDate),
                style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 20),
          content,
        ],
      ),
    );
  }

  Widget _buildStatusInfoRow({required IconData icon, required Color color, required String title, required String subtitle}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color, fontFamily: context.isUrdu ? 'Noori' : null)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: context.isUrdu ? 'Noori' : null)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailMetricCard({
    required double width,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color, fontFamily: context.isUrdu ? 'Noori' : null), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminders(bool isPtm, bool needsReply, String leaveStatus) {
    return Column(
      children: [
        if (isPtm) _reminderItem('PTM Today', 'Today is the Parent Teacher Meeting. Please visit the Madrassa.', Icons.people, Colors.orange),
        if (needsReply) _reminderItem('Reply Needed', 'Please reply to the teacher\'s message regarding today\'s status.', Icons.message, Colors.purple),
        if (leaveStatus == 'denied') _reminderItem('Leave Denied', 'Your leave request for ${widget.studentData['name'] ?? 'the student'} was denied. They are marked absent.', Icons.error_outline, Colors.red),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _reminderItem(String en, String body, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(en, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                Text(body, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab({
    required bool isDesktop,
    required bool isTablet,
    required Map<String, dynamic> todaySLog,
    required String currentStatus,
    required String leaveStatus,
    required bool isPtmToday,
    required bool needsReply,
    required List<QueryDocumentSnapshot> allLogs,
    required List<Map<String, dynamic>> holidaysData,
    required MadrassaConfig config,
    required MadrassaConfig displayConfig,
    required List<QueryDocumentSnapshot> monthLogs,
    required List<DateTime> holidays,
    required Map<String, dynamic> fee,
    required int currentTotalLines,
  }) {
    // 1. Month Selector
    final monthSelector = _buildMonthSelector();

    // 2. Progress Overview Components
    const total = 8640;
    final pct = (currentTotalLines / total * 100).toStringAsFixed(1);
    final remainingLines = (total - currentTotalLines).clamp(0, total);
    
    final joinDate = _parseDateTime(widget.studentData['joinDate'], DateTime.now().subtract(const Duration(days: 1)));
    final daysEnrolled = DateTime.now().difference(joinDate).inDays.clamp(1, 99999);
    
    final prevHifzLines = int.tryParse(widget.studentData['prevHifzLines']?.toString() ?? '0') ?? 0;
    final linesMemorizedHere = (currentTotalLines - prevHifzLines).clamp(0, total);
    final double overallPace = (linesMemorizedHere / daysEnrolled).clamp(0.0, total.toDouble()); // lines per day
    final double daysRemaining = overallPace > 0.0001 ? (remainingLines / overallPace) : 0.0;
    final paceWeekly = overallPace * 7;
    final estCompletionStr = overallPace > 0 ? _formatRemainingTime(daysRemaining) : context.t('Requires memorized lines');

    final isHifzCompleted = currentTotalLines >= 8640 || widget.studentData['status'] == 'hifz_completed';
    Widget? congratsCard;
    if (isHifzCompleted) {
      DateTime completionDate = DateTime.now();
      if (widget.studentData['hifzCompletionDate'] != null) {
        completionDate = (widget.studentData['hifzCompletionDate'] as Timestamp).toDate();
      } else {
        DateTime? earliestCompletion;
        for (var logDoc in allLogs) {
          final date = DateTime.tryParse(logDoc.id);
          if (date != null) {
            final log = logDoc.data() as Map<String, dynamic>?;
            final lines = log?[widget.studentId]?['currentLines'] as int?;
            if (lines != null && lines >= 8640) {
              if (earliestCompletion == null || date.isBefore(earliestCompletion)) {
                earliestCompletion = date;
              }
            }
          }
        }
        if (earliestCompletion != null) {
          completionDate = earliestCompletion;
        }
      }
      congratsCard = _buildCongratulatoryCard(
        joinDate: joinDate,
        completionDate: completionDate,
        studentName: widget.studentData['name'] ?? 'the student',
      );
    }

    final selectedMonthStart = DateTime(_selectedYear, _selectedMonth, 1);
    int prevMonthLines = prevHifzLines;
    final sortedDescLogs = [...allLogs]..sort((a, b) => b.id.compareTo(a.id));
    for (var logDoc in sortedDescLogs) {
      final logDate = DateTime.tryParse(logDoc.id);
      if (logDate != null && logDate.isBefore(selectedMonthStart)) {
        final logMap = logDoc.data() as Map<String, dynamic>?;
        final lines = logMap?[widget.studentId]?['currentLines'] as int?;
        if (lines != null) {
          prevMonthLines = lines;
          break;
        }
      }
    }

    final monthKey = DateFormat('yyyy-MM').format(DateTime(_selectedYear, _selectedMonth));
    final monthLogsFiltered = allLogs.where((l) => l.id.startsWith(monthKey)).toList();
    final sortedMonthLogs = [...monthLogsFiltered]..sort((a, b) => b.id.compareTo(a.id));
    
    int monthGain = 0;
    if (sortedMonthLogs.isNotEmpty) {
      final latestMap = sortedMonthLogs.first.data() as Map<String, dynamic>?;
      final studentLatestLog = latestMap?[widget.studentId] as Map<String, dynamic>?;
      final latestLines = studentLatestLog?['currentLines'] as int? ?? currentTotalLines;
      monthGain = latestLines - prevMonthLines;
    }

    final monthGainWidget = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ParentReportCard.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ParentReportCard.accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: ParentReportCard.accentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.isUrdu ? 'اس مہینے کی پیش رفت: +$monthGain لائنیں حفظ کیں' : 'Progress this month: +$monthGain lines memorized',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ParentReportCard.primaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
            ),
          ),
        ],
      ),
    );

    final progressCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ParentReportCard.primaryColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        children: [
          Text(
            context.t('Overall Quran Memorization Progress'),
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500, fontFamily: context.isUrdu ? 'Noori' : null),
          ),
          const SizedBox(height: 20),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: (currentTotalLines / total).clamp(0.0, 1.0),
                  strokeWidth: 10,
                  color: ParentReportCard.accentColor,
                  backgroundColor: Colors.white12,
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            context.isUrdu ? 'کل $total میں سے لائن $currentTotalLines مکمل' : 'Line $currentTotalLines of $total completed',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
          ),
          const SizedBox(height: 4),
          Text(
            context.isUrdu ? '$remainingLines لائنیں باقی ہیں' : '$remainingLines lines remaining',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, fontFamily: context.isUrdu ? 'Noori' : null),
          ),
        ],
      ),
    );

    final forecastWidget = Row(
      children: [
        Expanded(
          child: _buildForecastTile(
            icon: Icons.speed_rounded,
            label: context.t('Weekly Pace'),
            value: context.isUrdu ? '${paceWeekly.toStringAsFixed(1)} لائنیں' : '${paceWeekly.toStringAsFixed(1)} lines',
            sub: context.isUrdu ? '${overallPace.toStringAsFixed(1)} لائنیں/دن' : '${overallPace.toStringAsFixed(1)} lines/day',
            color: ParentReportCard.primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildForecastTile(
            icon: Icons.event_repeat_rounded,
            label: context.t('Est. Completion'),
            value: overallPace > 0 
                ? (context.isUrdu 
                    ? (daysRemaining < 365 ? '${(daysRemaining / 30).toStringAsFixed(1)} مہینے' : '${(daysRemaining / 365).toStringAsFixed(1)} سال')
                    : (daysRemaining < 365 ? '${(daysRemaining / 30).toStringAsFixed(1)} mos' : '${(daysRemaining / 365).toStringAsFixed(1)} yrs'))
                : '—',
            sub: estCompletionStr,
            color: ParentReportCard.accentColor,
            isLongValue: true,
          ),
        ),
      ],
    );

    final calendarWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: context.t('Attendance Calendar'), icon: Icons.calendar_month),
        const SizedBox(height: 12),
        const _CalendarLegend(),
        const SizedBox(height: 16),
        _AttendanceCalendar(
          studentId: widget.studentId,
          logs: allLogs,
          year: _selectedYear,
          month: _selectedMonth,
          config: displayConfig,
          selectedDate: _selectedDate,
          holidaysData: holidaysData,
          onDateSelected: (date) {
            setState(() {
              _selectedDate = date;
            });
          },
        ),
      ],
    );

    // 3. Fees Section
    final due = (fee['amountDue'] as num?)?.toDouble() ?? 0.0;
    final attSavings = (fee['attSavings'] as num?)?.toDouble() ?? 0.0;
    final uniSavings = (fee['uniSavings'] as num?)?.toDouble() ?? 0.0;
    final msgSavings = (fee['msgSavings'] as num?)?.toDouble() ?? 0.0;
    final ptmSavings = (fee['ptmSavings'] as num?)?.toDouble() ?? 0.0;
    final proRatedBaseFee = (fee['proRatedBaseFee'] as num?)?.toDouble() ?? 0.0;
    final totalSavings = (fee['totalSavings'] as num?)?.toDouble() ?? 0.0;
    final activeWorkingDays = (fee['activeWorkingDays'] as num?)?.toInt() ?? 0;

    final joinDateVal = widget.studentData['joinDate'] != null ? _parseDateTime(widget.studentData['joinDate']) : null;
    final isProRated = proRatedBaseFee < displayConfig.baseFee;
    final joinDateStr = joinDateVal != null
        ? (context.isUrdu
            ? DateFormat('dd-MM-yyyy').format(joinDateVal)
            : DateFormat('dd MMMM yyyy').format(joinDateVal))
        : '';

    final amountDueCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: due > 0 ? ParentReportCard.errorColor.withValues(alpha: 0.08) : ParentReportCard.successColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: due > 0 ? ParentReportCard.errorColor.withValues(alpha: 0.2) : ParentReportCard.successColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('Amount Due'),
                style: TextStyle(color: due > 0 ? ParentReportCard.errorColor : ParentReportCard.successColor, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
              const SizedBox(height: 4),
              Text(
                _formatMonthYear(DateTime(_selectedYear, _selectedMonth)),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
            ],
          ),
          Text(
            context.isUrdu ? 'روپے ${due.toStringAsFixed(0)}' : 'Rs. ${due.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: due > 0 ? ParentReportCard.errorColor : ParentReportCard.successColor, fontFamily: context.isUrdu ? 'Noori' : null),
          ),
        ],
      ),
    );

    Widget buildSavingsTile(String label, double amount, Color color, IconData icon) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(label),
                    style: TextStyle(fontSize: 11, color: ParentReportCard.textMutedColor, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.isUrdu ? 'روپے ${amount.toStringAsFixed(0)}-' : '-Rs. ${amount.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color, fontFamily: context.isUrdu ? 'Noori' : null),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final savingsGrid = Column(
      children: [
        Row(
          children: [
            Expanded(child: buildSavingsTile('Attendance', attSavings, Colors.green, Icons.calendar_today)),
            const SizedBox(width: 12),
            Expanded(child: buildSavingsTile('Uniform', uniSavings, Colors.blue, Icons.checkroom)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: buildSavingsTile('Teacher Response', msgSavings, Colors.purple, Icons.chat_bubble_outline)),
            const SizedBox(width: 12),
            Expanded(child: buildSavingsTile('PTM Meeting', ptmSavings, Colors.orange, Icons.people_outline)),
          ],
        ),
      ],
    );

    final visualFlowCard = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ParentReportCard.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('Fee Calculation Flow'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
          ),
          const SizedBox(height: 20),
          
          _buildFlowStep(
            title: context.t('Pro-rated Base Fee'),
            subtitle: context.isUrdu ? 'سرگرم داخلہ: $activeWorkingDays تعلیمی دن' : 'Active enrollment: $activeWorkingDays working days',
            amount: context.isUrdu ? 'روپے ${proRatedBaseFee.toStringAsFixed(0)}' : 'Rs. ${proRatedBaseFee.toStringAsFixed(0)}',
            color: ParentReportCard.textPrimaryColor,
            icon: Icons.account_balance,
          ),
          if (isProRated && joinDateVal != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.isUrdu
                          ? 'بنیادی فیس (عام طور پر روپے ${displayConfig.baseFee.toStringAsFixed(0)}) تناسب کی بنیاد پر ہے کیونکہ طالب علم کی شمولیت کی تاریخ $joinDateStr ہے۔'
                          : 'Base fee (Rs. ${displayConfig.baseFee.toStringAsFixed(0)} standard) is pro-rated because the student joined on $joinDateStr.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.bold,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Icon(Icons.remove_circle_outline, color: ParentReportCard.errorColor, size: 20),
          )),
          
          _buildFlowStep(
            title: context.t('Total Savings / Deductions'),
            subtitle: context.t('Combined rewards for attendance, behavior & PTM'),
            amount: context.isUrdu ? 'روپے ${totalSavings.toStringAsFixed(0)}-' : '-Rs. ${totalSavings.toStringAsFixed(0)}',
            color: Colors.green,
            icon: Icons.savings_outlined,
          ),
          
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Icon(Icons.drag_handle, color: ParentReportCard.textMutedColor, size: 20),
          )),
          
          _buildFlowStep(
            title: context.t('Final Net Amount Due'),
            subtitle: context.isUrdu
                ? 'مہینہ برائے ${_formatMonth(DateTime(_selectedYear, _selectedMonth))} جمع کرائی گئی'
                : 'Submitted for the month of ${DateFormat('MMMM').format(DateTime(_selectedYear, _selectedMonth))}',
            amount: context.isUrdu ? 'روپے ${due.toStringAsFixed(0)}' : 'Rs. ${due.toStringAsFixed(0)}',
            color: due > 0 ? ParentReportCard.errorColor : ParentReportCard.successColor,
            icon: Icons.receipt,
            isFinal: true,
          ),
        ],
      ),
    );

    final headerRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          context.t('Monthly Statement'),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
        ),
        ExportButton(
          onExcel: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(context.t('Preparing your Excel report...')),
              backgroundColor: ParentReportCard.primaryColor,
            ));
            MadrassaReportHelper.exportIndividualExcel(
              config: displayConfig,
              studentId: widget.studentId,
              studentData: widget.studentData,
              logs: monthLogs,
              holidays: holidays,
            );
          },
          onPdf: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(context.t('Preparing your PDF report...')),
              backgroundColor: ParentReportCard.primaryColor,
            ));
            MadrassaReportHelper.exportIndividualPdf(
              config: displayConfig,
              studentId: widget.studentId,
              studentData: widget.studentData,
              logs: monthLogs,
              holidays: holidays,
            );
          },
          isSmall: true,
        ),
      ],
    );

    // 4. News Widget (Reminders & Notices)
    final noticesList = config.auditLog.where((l) => l['type'] == 'ptm_reschedule' && l['month'] == displayConfig.month && l['year'] == displayConfig.year).toList();
    final hasRemindersOrNotices = isPtmToday || needsReply || (currentStatus == 'absent' && leaveStatus == 'denied') || noticesList.isNotEmpty;

    final newsWidget = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPtmToday || needsReply || (currentStatus == 'absent' && leaveStatus == 'denied')) ...[
            _SectionTitle(label: context.t('Reminders'), icon: Icons.warning_amber_rounded),
            const SizedBox(height: 12),
            _buildReminders(isPtmToday, needsReply, leaveStatus),
            const SizedBox(height: 16),
          ],
          if (noticesList.isNotEmpty) ...[
            _SectionTitle(label: context.t('Recent Notices'), icon: Icons.campaign_rounded),
            const SizedBox(height: 12),
            ...noticesList.map((log) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_repeat_rounded, color: Colors.amber),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.isUrdu ? 'پی ٹی ایم دوبارہ شیڈول: ${log['oldValue']} → ${log['newValue']}' : 'PTM Rescheduled: ${log['oldValue']} → ${log['newValue']}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900, fontFamily: context.isUrdu ? 'Noori' : null),
                          ),
                          Text(
                            context.t('Parent Teacher Meeting date has been updated.'),
                            style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (!hasRemindersOrNotices)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: ParentReportCard.primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ParentReportCard.primaryColor.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_none_rounded, color: ParentReportCard.primaryColor, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    context.t("No announcements today."),
                    style: TextStyle(
                      color: ParentReportCard.primaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: context.isUrdu ? 'Noori' : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    // 5. Layout Rendering
    if (isDesktop || isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          monthSelector,
          const SizedBox(height: 16),
          if (congratsCard != null) congratsCard,
          newsWidget,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Column 1: Progress & Fees
              Expanded(
                child: Column(
                  children: [
                    progressCard,
                    const SizedBox(height: 16),
                    monthGainWidget,
                    const SizedBox(height: 16),
                    forecastWidget,
                    const SizedBox(height: 24),
                    headerRow,
                    const SizedBox(height: 16),
                    amountDueCard,
                    const SizedBox(height: 16),
                    savingsGrid,
                    const SizedBox(height: 16),
                    visualFlowCard,
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // Column 2: Calendar, Daily Details
              Expanded(
                child: Column(
                  children: [
                    calendarWidget,
                    const SizedBox(height: 16),
                    _buildDailyDetailsCard(allLogs, holidaysData, config),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      // Mobile Single Column Layout
      return Column(
        children: [
          monthSelector,
          const SizedBox(height: 16),
          if (congratsCard != null) congratsCard,
          newsWidget,
          progressCard,
          const SizedBox(height: 16),
          monthGainWidget,
          const SizedBox(height: 16),
          forecastWidget,
          const SizedBox(height: 24),
          calendarWidget,
          const SizedBox(height: 16),
          _buildDailyDetailsCard(allLogs, holidaysData, config),
          const SizedBox(height: 24),
          headerRow,
          const SizedBox(height: 16),
          amountDueCard,
          const SizedBox(height: 16),
          savingsGrid,
          const SizedBox(height: 24),
          visualFlowCard,
        ],
      );
    }
  }

  Widget _buildFlowStep({
    required String title,
    required String subtitle,
    required String amount,
    required Color color,
    required IconData icon,
    bool isFinal = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isFinal ? color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isFinal ? color.withValues(alpha: 0.2) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: isFinal ? color : ParentReportCard.textMutedColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isFinal ? color : ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11, color: ParentReportCard.textMutedColor, fontFamily: context.isUrdu ? 'Noori' : null)),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color, fontFamily: context.isUrdu ? 'Noori' : null),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTab({
    required bool isDesktop,
    required bool isTablet,
    required String status,
    required String? rejoinRequestStatus,
    required String? rejoinReason,
    required Timestamp? rejoinDate,
    required List<Map<String, dynamic>> auditList,
  }) {
    final studentInfoCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ParentReportCard.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: ParentReportCard.primaryColor.withValues(alpha: 0.1),
                child: ClipOval(
                  child: widget.studentData['photoUrl'] != null && widget.studentData['photoUrl'].toString().isNotEmpty
                      ? Image.network(
                          widget.studentData['photoUrl'],
                          fit: BoxFit.cover,
                          width: 56,
                          height: 56,
                          errorBuilder: (ctx, err, stack) => const Icon(Icons.person, color: ParentReportCard.primaryColor, size: 28),
                        )
                      : Text(
                          widget.studentData['name']?[0] ?? '?',
                          style: const TextStyle(color: ParentReportCard.primaryColor, fontWeight: FontWeight.bold, fontSize: 24),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.studentData['name'] ?? '',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.isUrdu 
                          ? 'رول نمبر: ${widget.studentData['rollNumber'] ?? '?'} • کلاس: ${context.t(widget.studentData['class'] ?? 'Hifz')}'
                          : 'Roll: ${widget.studentData['rollNumber'] ?? '?'} • Class: ${widget.studentData['class'] ?? 'Hifz'}',
                      style: TextStyle(fontSize: 13, color: ParentReportCard.textMutedColor, fontFamily: context.isUrdu ? 'Noori' : null),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.credit_card, context.t('Student CNIC'), widget.studentData['studentCnic'] ?? context.t('Not Provided')),
          _buildDetailRow(
            Icons.calendar_today,
            context.t('Join Date'),
            widget.studentData['joinDate'] != null
                ? (context.isUrdu 
                    ? DateFormat('dd-MM-yyyy').format(_parseDateTime(widget.studentData['joinDate']))
                    : DateFormat('dd MMMM yyyy').format(_parseDateTime(widget.studentData['joinDate'])))
                : context.t('Not Provided'),
          ),
          if (widget.studentData['hasPrevMadrassa'] == true) ...[
            _buildDetailRow(Icons.school, context.t('Prev Madrassa'), widget.studentData['prevMadrassaName'] ?? context.t('Not Provided')),
            _buildDetailRow(Icons.auto_stories, context.t('Prev Hifz Lines'), context.isUrdu ? '${widget.studentData['prevHifzLines'] ?? 0} لائنیں' : '${widget.studentData['prevHifzLines'] ?? 0} lines'),
          ],
        ],
      ),
    );

    final guardianInfoCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ParentReportCard.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.family_restroom, color: ParentReportCard.primaryColor),
              const SizedBox(width: 12),
              Text(
                context.t('Guardian Details'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.person_outline, context.t('Guardian Name'), widget.studentData['guardianName'] ?? context.t('Not Provided')),
          _buildDetailRow(Icons.credit_card_outlined, context.t('Guardian CNIC'), widget.studentData['guardianCnic'] ?? context.t('Not Provided')),
          _buildDetailRow(Icons.phone_outlined, context.t('Phone'), widget.studentData['contactPhone'] ?? context.t('Not Provided')),
        ],
      ),
    );

    final languageInfoCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ParentReportCard.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.language, color: ParentReportCard.primaryColor),
              const SizedBox(width: 12),
              Text(
                context.t('Change Language'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: ParentReportCard.textPrimaryColor,
                  fontFamily: context.isUrdu ? 'Noori' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('Select Language'),
                  style: TextStyle(
                    fontSize: 14,
                    color: ParentReportCard.textPrimaryColor,
                    fontFamily: context.isUrdu ? 'Noori' : null,
                  ),
                ),
              ),
              DropdownButton<String>(
                value: context.languageCode,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'ur', child: Text('اردو', style: TextStyle(fontFamily: 'Noori'))),
                ],
                onChanged: (val) {
                  if (val != null) {
                    Provider.of<MadrassaLanguageProvider>(context, listen: false).setLanguage(val);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );

    final changePasswordCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ParentReportCard.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_reset_rounded, color: ParentReportCard.primaryColor),
              const SizedBox(width: 12),
              Text(
                context.t('Change Password'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: ParentReportCard.textPrimaryColor,
                  fontFamily: context.isUrdu ? 'Noori' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            context.t('Update your account password for security.'),
            style: TextStyle(
              fontSize: 13,
              color: ParentReportCard.textMutedColor,
              fontFamily: context.isUrdu ? 'Noori' : null,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showChangePasswordDialog(context),
              icon: const Icon(Icons.password_rounded, size: 18),
              label: Text(
                context.t('Change Password'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: context.isUrdu ? 'Noori' : null,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ParentReportCard.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );

    final rejoinWidget = _buildRejoinUI(status, rejoinRequestStatus, rejoinReason, rejoinDate);

    final timelineWidget = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ParentReportCard.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: _buildTimeline(auditList),
    );

    Widget? logoutBtn;
    if (widget.onLogout != null) {
      logoutBtn = SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout_rounded, color: ParentReportCard.errorColor),
          label: Text(context.t('Log Out Account'), style: TextStyle(color: ParentReportCard.errorColor, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: ParentReportCard.errorColor),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
    }

    if (isTablet) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _buildStatusChip(status),
                const SizedBox(height: 16),
                if (status == 'left') ...[
                  rejoinWidget,
                  const SizedBox(height: 16),
                ],
                studentInfoCard,
                const SizedBox(height: 16),
                guardianInfoCard,
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                languageInfoCard,
                const SizedBox(height: 16),
                changePasswordCard,
                const SizedBox(height: 16),
                timelineWidget,
                if (logoutBtn != null) ...[
                  const SizedBox(height: 24),
                  logoutBtn,
                ],
              ],
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          _buildStatusChip(status),
          const SizedBox(height: 16),
          if (status == 'left') ...[
            rejoinWidget,
            const SizedBox(height: 16),
          ],
          studentInfoCard,
          const SizedBox(height: 16),
          guardianInfoCard,
          const SizedBox(height: 16),
          languageInfoCard,
          const SizedBox(height: 16),
          changePasswordCard,
          const SizedBox(height: 24),
          timelineWidget,
          if (logoutBtn != null) ...[
            const SizedBox(height: 24),
            logoutBtn,
          ],
        ],
      );
    }
  }

  Widget _buildTabContent(
    int selectedTab, {
    required bool isDesktop,
    required bool isTablet,
    required Map<String, dynamic> todaySLog,
    required String currentStatus,
    required String leaveStatus,
    required bool isPtmToday,
    required bool needsReply,
    required List<QueryDocumentSnapshot> allLogs,
    required List<Map<String, dynamic>> holidaysData,
    required MadrassaConfig config,
    required MadrassaConfig displayConfig,
    required List<QueryDocumentSnapshot> monthLogs,
    required List<DateTime> holidays,
    required Map<String, dynamic> fee,
    required int currentTotalLines,
    required String status,
    required String? rejoinRequestStatus,
    required String? rejoinReason,
    required Timestamp? rejoinDate,
    required List<Map<String, dynamic>> auditList,
  }) {
    switch (selectedTab) {
      case 0:
        return _buildHomeTab(
          isDesktop: isDesktop,
          isTablet: isTablet,
          todaySLog: todaySLog,
          currentStatus: currentStatus,
          leaveStatus: leaveStatus,
          isPtmToday: isPtmToday,
          needsReply: needsReply,
          allLogs: allLogs,
          holidaysData: holidaysData,
          config: config,
          displayConfig: displayConfig,
          monthLogs: monthLogs,
          holidays: holidays,
          fee: fee,
          currentTotalLines: currentTotalLines,
        );
      case 1:
        return _buildAccountTab(
          isDesktop: isDesktop,
          isTablet: isTablet,
          status: status,
          rejoinRequestStatus: rejoinRequestStatus,
          rejoinReason: rejoinReason,
          rejoinDate: rejoinDate,
          auditList: auditList,
        );
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _logsStream,
      builder: (context, logSnap) {
        debugPrint("[Diagnostic] logSnap connectionState: ${logSnap.connectionState}, hasData: ${logSnap.hasData}, hasError: ${logSnap.hasError}, error: ${logSnap.error}");
        if (logSnap.hasError) return _ErrorView('Logs Error: ${logSnap.error}');
        
        return StreamBuilder<MadrassaConfig>(
          stream: _configStream,
          builder: (context, configSnap) {
            debugPrint("[Diagnostic] configSnap connectionState: ${configSnap.connectionState}, hasData: ${configSnap.hasData}, hasError: ${configSnap.hasError}, error: ${configSnap.error}");
            if (configSnap.hasError) return _ErrorView('Config Error: ${configSnap.error}');
            
            return StreamBuilder<QuerySnapshot>(
              stream: _holidaysStream,
              builder: (context, holidaySnap) {
                debugPrint("[Diagnostic] holidaySnap connectionState: ${holidaySnap.connectionState}, hasData: ${holidaySnap.hasData}, hasError: ${holidaySnap.hasError}, error: ${holidaySnap.error}");
                if (holidaySnap.hasError) return _ErrorView('Holidays Error: ${holidaySnap.error}');

                if (logSnap.connectionState == ConnectionState.waiting ||
                    configSnap.connectionState == ConnectionState.waiting ||
                    holidaySnap.connectionState == ConnectionState.waiting) {
                  return const ColoredBox(
                    color: ParentReportCard.surfaceColor,
                    child: Center(child: CircularProgressIndicator(color: ParentReportCard.primaryColor)),
                  );
                }

                if (!logSnap.hasData || !configSnap.hasData || !holidaySnap.hasData) {
                  return const _ErrorView('Waiting for data...');
                }

                final now = DateTime.now();
                final allLogs = logSnap.data?.docs ?? [];
                final config = configSnap.data ?? MadrassaConfig(id: 'current', year: now.year, month: now.month);
                
                final currentYear = _selectedYear;
                final currentMonth = _selectedMonth;
                final monthKey = DateFormat('yyyy-MM').format(DateTime(currentYear, currentMonth));
                final workingDays = MadrassaFeeLogic.getWorkingDaysCount(currentYear, currentMonth);
                final monthLogs = allLogs.where((l) => l.id.startsWith(monthKey)).toList();

                final displayConfig = MadrassaConfig(
                  id: config.id,
                  year: currentYear,
                  month: currentMonth,
                  ptmDay: config.ptmDay,
                  baseFee: config.baseFee,
                  ptmDeduction: config.ptmDeduction,
                  messageTotalDeduction: config.messageTotalDeduction,
                  attendanceMaxDeduction: config.attendanceMaxDeduction,
                  uniformMaxDeduction: config.uniformMaxDeduction,
                  auditLog: config.auditLog,
                );

                final holidays = (holidaySnap.data!.docs)
                    .map((d) => (d['date'] as Timestamp).toDate())
                    .toList();

                final fee = MadrassaFeeLogic.calculateStudentFee(
                  studentId: widget.studentId,
                  studentData: widget.studentData,
                  logs: monthLogs,
                  config: displayConfig,
                  totalWorkingDays: workingDays,
                  holidays: holidays,
                );


                int currentTotalLines = int.tryParse(widget.studentData['currentLines']?.toString() ?? '0') ?? 0;

                final status = widget.studentData['status'] ?? 'active';
                final rejoinRequestStatus = widget.studentData['rejoinRequestStatus'];
                final rejoinReason = widget.studentData['rejoinRequestReason'];
                final rejoinDate = widget.studentData['rejoinRequestDate'] as Timestamp?;


                final todayStr = DateFormat('yyyy-MM-dd').format(now);
                Map<String, dynamic> todaySLog = {};
                try {
                  final todayDoc = allLogs.firstWhere((l) => l.id == todayStr);
                  final tData = todayDoc.data() as Map<String, dynamic>?;
                  todaySLog = (tData?[widget.studentId] is Map ? tData![widget.studentId] as Map<String, dynamic> : {});
                } catch (_) {}
                final currentStatus = todaySLog['attendance']?.toString() ?? 'unknown';

                final ptmDate = displayConfig.getPtmDate();
                final isPtmToday = now.year == ptmDate.year && now.month == ptmDate.month && now.day == ptmDate.day;
                final needsReply = todaySLog['parentReplied'] != true && currentStatus == 'present';
                final leaveStatus = todaySLog['leaveStatus'] ?? 'pending';

                final holidaysData = (holidaySnap.data!.docs).map((d) {
                  final date = (d['date'] as Timestamp).toDate();
                  final name = d.data() is Map && (d.data() as Map).containsKey('name') ? d['name']?.toString() ?? 'Holiday' : 'Holiday';
                  return {'date': date, 'name': name};
                }).toList();

                final rawAudit = widget.studentData['auditLog'];
                final auditListRaw = rawAudit is List ? rawAudit : [];
                final auditList = List<Map<String, dynamic>>.from(
                  auditListRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
                );

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 900;
                    final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth <= 900;

                    if (isDesktop) {
                      return Scaffold(
                        backgroundColor: ParentReportCard.surfaceColor,
                        body: Row(
                          children: [
                            NavigationRail(
                              backgroundColor: ParentReportCard.primaryColor,
                              unselectedIconTheme: const IconThemeData(color: Colors.white60),
                              selectedIconTheme: const IconThemeData(color: ParentReportCard.accentColor),
                              unselectedLabelTextStyle: const TextStyle(color: Colors.white60),
                              selectedLabelTextStyle: const TextStyle(color: ParentReportCard.accentColor, fontWeight: FontWeight.bold),
                              indicatorColor: Colors.white10,
                              extended: constraints.maxWidth > 1100,
                              leading: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24.0),
                                child: Image.asset('assets/logo/gmwf-1.png', height: 48),
                              ),
                              destinations: [
                                NavigationRailDestination(
                                  icon: const Icon(Icons.home_outlined),
                                  selectedIcon: const Icon(Icons.home_rounded),
                                  label: Text(context.t('Home'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
                                ),
                                NavigationRailDestination(
                                  icon: const Icon(Icons.manage_accounts_outlined),
                                  selectedIcon: const Icon(Icons.manage_accounts),
                                  label: Text(context.t('Account'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
                                ),
                              ],
                              selectedIndex: _selectedTab,
                              onDestinationSelected: (idx) {
                                setState(() {
                                  _selectedTab = idx;
                                });
                              },
                            ),
                            const VerticalDivider(thickness: 1, width: 1),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Center(
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 800),
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildDesktopHeroHeader(),
                                        const SizedBox(height: 24),
                                        _buildTabContent(
                                          _selectedTab,
                                          isDesktop: true,
                                          isTablet: false,
                                          todaySLog: todaySLog,
                                          currentStatus: currentStatus,
                                          leaveStatus: leaveStatus,
                                          isPtmToday: isPtmToday,
                                          needsReply: needsReply,
                                          allLogs: allLogs,
                                          holidaysData: holidaysData,
                                          config: config,
                                          displayConfig: displayConfig,
                                          monthLogs: monthLogs,
                                          holidays: holidays,
                                          fee: fee,
                                          currentTotalLines: currentTotalLines,
                                          status: status,
                                          rejoinRequestStatus: rejoinRequestStatus,
                                          rejoinReason: rejoinReason,
                                          rejoinDate: rejoinDate,
                                          auditList: auditList,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      return Scaffold(
                        backgroundColor: ParentReportCard.surfaceColor,
                        appBar: AppBar(
                          backgroundColor: ParentReportCard.primaryColor,
                          elevation: 0,
                          iconTheme: const IconThemeData(color: Colors.white),
                          leading: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Image.asset('assets/logo/gmwf-1.png', fit: BoxFit.contain),
                          ),
                          title: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.white,
                                child: ClipOval(
                                  child: widget.studentData['photoUrl'] != null && widget.studentData['photoUrl'].toString().isNotEmpty
                                      ? Image.network(
                                          widget.studentData['photoUrl'],
                                          fit: BoxFit.cover,
                                          width: 36,
                                          height: 36,
                                          errorBuilder: (ctx, err, stack) => const Icon(Icons.person, color: ParentReportCard.primaryColor),
                                        )
                                      : Text(
                                          widget.studentData['name']?[0] ?? '?',
                                          style: const TextStyle(color: ParentReportCard.primaryColor, fontWeight: FontWeight.bold),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.studentData['name'] ?? '',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: context.isUrdu ? 'Noori' : null),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      context.isUrdu 
                                          ? 'رول نمبر: ${widget.studentData['rollNumber'] ?? '?'} • کلاس: ${context.t(widget.studentData['class'] ?? 'Hifz')}'
                                          : 'Roll: ${widget.studentData['rollNumber'] ?? '?'} • Class: ${widget.studentData['class'] ?? 'Hifz'}',
                                      style: TextStyle(fontSize: 11, color: Colors.white70, fontFamily: context.isUrdu ? 'Noori' : null),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: _buildTabContent(
                            _selectedTab,
                            isDesktop: false,
                            isTablet: isTablet,
                            todaySLog: todaySLog,
                            currentStatus: currentStatus,
                            leaveStatus: leaveStatus,
                            isPtmToday: isPtmToday,
                            needsReply: needsReply,
                            allLogs: allLogs,
                            holidaysData: holidaysData,
                            config: config,
                            displayConfig: displayConfig,
                            monthLogs: monthLogs,
                            holidays: holidays,
                            fee: fee,
                            currentTotalLines: currentTotalLines,
                            status: status,
                            rejoinRequestStatus: rejoinRequestStatus,
                            rejoinReason: rejoinReason,
                            rejoinDate: rejoinDate,
                            auditList: auditList,
                          ),
                        ),
                        bottomNavigationBar: BottomNavigationBar(
                          backgroundColor: Colors.white,
                          selectedItemColor: ParentReportCard.primaryColor,
                          unselectedItemColor: ParentReportCard.textMutedColor,
                          currentIndex: _selectedTab,
                          type: BottomNavigationBarType.fixed,
                          onTap: (idx) {
                            setState(() {
                              _selectedTab = idx;
                            });
                          },
                          items: [
                            BottomNavigationBarItem(
                              icon: const Icon(Icons.home_outlined),
                              activeIcon: const Icon(Icons.home_rounded),
                              label: context.t('Home'),
                            ),
                            BottomNavigationBarItem(
                              icon: const Icon(Icons.manage_accounts_outlined),
                              activeIcon: const Icon(Icons.manage_accounts),
                              label: context.t('Account'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView(this.message);
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(message, style: const TextStyle(color: ParentReportCard.errorColor))));
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionTitle({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: ParentReportCard.primaryColor),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: ParentReportCard.textPrimaryColor)),
      ],
    );
  }
}



class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isActive, isSelected;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.isActive, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isActive ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? color : (isActive ? color.withValues(alpha: 0.1) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : (isActive ? color.withValues(alpha: 0.2) : Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.white : (isActive ? color : Colors.grey)),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : (isActive ? color : Colors.grey))),
          ],
        ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    final items = [
      (const Color(0xFFE8F5E9), 'Present', null, false, false),
      (const Color(0xFFFFEBEE), 'Absent', null, false, false),
      (const Color(0xFFE0F2F1), 'Holiday', Icons.flag_rounded, false, false),
      (const Color(0xFF1B4332), 'PTM Joined', null, true, true),
      (const Color(0xFFDC2626), 'PTM Missed', null, true, false),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: items.map((t) {
        final isPtm = t.$4;
        final ptmJoined = t.$5;
        Widget indicator;
        if (isPtm) {
          indicator = Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: t.$1,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              ptmJoined ? (context.isUrdu ? 'شامل' : 'JOINED') : (context.isUrdu ? 'شامل نہیں' : 'MISSED'),
              style: const TextStyle(fontSize: 6.5, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          );
        } else {
          indicator = Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: t.$1, borderRadius: BorderRadius.circular(3)),
            alignment: Alignment.center,
            child: t.$3 != null ? Icon(t.$3, size: 6, color: const Color(0xFF00796B)) : null,
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            indicator,
            const SizedBox(width: 4),
            Text(context.t(t.$2), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        );
      }).toList(),
    );
  }
}

class _AttendanceCalendar extends StatelessWidget {
  final String studentId;
  final List<QueryDocumentSnapshot> logs;
  final int year, month;
  final MadrassaConfig config;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final List<Map<String, dynamic>> holidaysData;

  const _AttendanceCalendar({
    required this.studentId,
    required this.logs,
    required this.year,
    required this.month,
    required this.config,
    required this.selectedDate,
    required this.onDateSelected,
    required this.holidaysData,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = firstDay.weekday; 
    const dayHeaders = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final ptmDate = config.getPtmDate();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)]),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: dayHeaders.map((d) => Text(d, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))).toList()),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: daysInMonth + (firstWeekday - 1),
            itemBuilder: (context, index) {
              if (index < firstWeekday - 1) return const SizedBox();
              final day = index - (firstWeekday - 2);
              final date = DateTime(year, month, day);
              final dateStr = DateFormat('yyyy-MM-dd').format(date);
              final isPtm = date.year == ptmDate.year && date.month == ptmDate.month && date.day == ptmDate.day;
              final isPast = date.isBefore(DateTime(now.year, now.month, now.day));
              final isToday = day == now.day && month == now.month && year == now.year;
              final isSelectedDate = day == selectedDate.day && month == selectedDate.month && year == selectedDate.year;

              Map<String, dynamic>? holidayDoc;
              for (final h in holidaysData) {
                final hDate = h['date'] as DateTime?;
                if (hDate != null && hDate.year == date.year && hDate.month == date.month && hDate.day == date.day) {
                  holidayDoc = h;
                  break;
                }
              }
              final isHoliday = holidayDoc != null;

              Map<String, dynamic>? statusData;
              try {
                final doc = logs.firstWhere((l) => l.id == dateStr);
                final rawData = doc.data();
                if (rawData is Map) {
                  statusData = _asStringMap(rawData[studentId]);
                }
              } catch (_) {}

              Color bg = const Color(0xFFF1F4F9);
              Color textCol = Colors.grey.shade400;
              bool ptmAttended = statusData?['ptm'] == true;

              if (isHoliday) {
                bg = const Color(0xFFE0F2F1);
                textCol = const Color(0xFF00796B);
              } else if (statusData != null) {
                final att = statusData['attendance']?.toString();
                if (att == 'present') { bg = const Color(0xFFE8F5E9); textCol = const Color(0xFF2E7D32); }
                else if (att == 'leave' || att == 'leave_requested') { bg = const Color(0xFFFFF3E0); textCol = const Color(0xFFEF6C00); }
                else if (att == 'absent') { bg = const Color(0xFFFFEBEE); textCol = const Color(0xFFC62828); }
              }

              BoxDecoration decoration = BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: isSelectedDate
                    ? Border.all(color: ParentReportCard.primaryColor, width: 2.5)
                    : (isToday ? Border.all(color: ParentReportCard.accentColor.withValues(alpha: 0.5), width: 1.5) : null),
              );
              
              if (isHoliday) {
                return GestureDetector(
                  onTap: () => onDateSelected(date),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(12),
                      border: isSelectedDate
                          ? Border.all(color: ParentReportCard.primaryColor, width: 2.5)
                          : Border.all(color: const Color(0xFF00796B).withValues(alpha: 0.3), width: 1.0),
                    ),
                    child: Stack(
                      children: [
                        const Positioned(
                          top: 2,
                          right: 2,
                          child: Icon(Icons.flag_rounded, size: 10, color: Color(0xFF00796B)),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$day', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00796B))),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  context.isUrdu ? 'تعطیل' : 'Holiday',
                                  style: const TextStyle(fontSize: 6, fontWeight: FontWeight.w900, color: Color(0xFF00796B)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (isPtm && isPast) {
                return GestureDetector(
                  onTap: () => onDateSelected(date),
                  child: Container(
                    decoration: decoration,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 4),
                        Text('$day', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textCol)),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            margin: const EdgeInsets.only(bottom: 2),
                            decoration: BoxDecoration(
                              color: ptmAttended ? const Color(0xFF1B4332) : const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ptmAttended ? (context.isUrdu ? 'شامل' : 'JOINED') : (context.isUrdu ? 'شامل نہیں' : 'MISSED'),
                              style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (isPtm && !isPast) {
                return GestureDetector(
                  onTap: () => onDateSelected(date),
                  child: _PulsingPtmCell(
                    day: day,
                    textCol: isToday ? ParentReportCard.primaryColor : Colors.grey.shade600,
                    isSelected: isSelectedDate,
                  ),
                );
              }

              return GestureDetector(
                onTap: () => onDateSelected(date),
                child: Container(
                  decoration: decoration,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text('$day', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textCol)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PulsingPtmCell extends StatefulWidget {
  final int day;
  final Color textCol;
  final bool isSelected;
  const _PulsingPtmCell({required this.day, required this.textCol, required this.isSelected});
  @override
  State<_PulsingPtmCell> createState() => _PulsingPtmCellState();
}

class _PulsingPtmCellState extends State<_PulsingPtmCell> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                ParentReportCard.primaryColor.withValues(alpha: 0.05 + (0.1 * _controller.value)),
                ParentReportCard.primaryColor.withValues(alpha: 0.1 + (0.2 * _controller.value)),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: widget.isSelected
                  ? ParentReportCard.accentColor
                  : ParentReportCard.primaryColor.withValues(alpha: 0.2 + (0.4 * _controller.value)),
              width: widget.isSelected ? 2.5 : (1 + _controller.value),
            ),
            boxShadow: [BoxShadow(color: ParentReportCard.primaryColor.withValues(alpha: 0.1 * _controller.value), blurRadius: 8, spreadRadius: 2)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              Text('${widget.day}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: widget.textCol)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: ParentReportCard.accentColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    context.isUrdu ? 'پی ٹی ایم' : 'PTM',
                    style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}




