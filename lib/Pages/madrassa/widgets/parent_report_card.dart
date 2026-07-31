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
import '../../../services/image_upload_service.dart';
import '../../../widgets/read_only_document_tile.dart';

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
  final List<DocumentSnapshot> allDocs;
  final int selectedIndex;
  final ValueChanged<int> onStudentChanged;
  final VoidCallback? onBackToSummary;
  final bool isParentView;

  static const Color primaryColor = Color(0xFF0F6C5A);  // Deep emerald teal
  static const Color accentColor = Color(0xFFFFA726);
  static const Color surfaceColor = Color(0xFFF4F7F6);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color textPrimaryColor = Color(0xFF1E293B);
  static const Color textMutedColor = Color(0xFF64748B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color successColor = Color(0xFF22C55E);

  const ParentReportCard({
    super.key,
    required this.branchId,
    required this.studentId,
    required this.studentData,
    this.year,
    this.month,
    this.onLogout,
    required this.allDocs,
    required this.selectedIndex,
    required this.onStudentChanged,
    this.onBackToSummary,
    this.isParentView = false,
  });

  @override
  State<ParentReportCard> createState() => _ParentReportCardState();
}

class _ParentReportCardState extends State<ParentReportCard> {
  late int _selectedYear;
  late int _selectedMonth;
  late DateTime _selectedDate;
  int _selectedTab = 0;

  Map<String, dynamic>? _liveStudentData;
  Map<String, dynamic> get studentData => _liveStudentData ?? widget.studentData;

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
    if (widget.studentId != oldWidget.studentId) {
      _liveStudentData = null;
    }
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

  Future<void> _submitParentReply(BuildContext context, String branchId, String dateStr, String studentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('madrassa_daily_logs')
          .doc(dateStr)
          .set({
        studentId: {
          'parentReplied': true,
          'timestamp': FieldValue.serverTimestamp()
        }
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.isUrdu 
                ? 'جواب کامیابی کے ساتھ درج کر دیا گیا ہے۔' 
                : 'Reply submitted successfully.'),
            backgroundColor: Colors.green,
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

  Future<void> _showLeaveReasonDialog(BuildContext context, String branchId, String dateStr, String studentId) async {
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
                      .doc(dateStr)
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

  Future<void> _showUnarchiveDialog(BuildContext context) async {
    final reasonCtrl = TextEditingController();
    String? reasonError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDs) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(context.t('Request Unarchive'), style: TextStyle(fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.isUrdu
                      ? 'براہ کرم طالب علم کو دوبارہ فعال کرنے کی وجہ درج کریں۔ اس درخواست کو استاد کی منظوری درکار ہوگی۔'
                      : 'Please specify the reason for requesting to unarchive this student. This request requires teacher approval.',
                  style: TextStyle(fontSize: 13, color: Colors.grey, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: context.isUrdu ? 'وجہ' : 'Reason',
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
                    hintText: context.isUrdu ? 'مثال: طالب علم دوبارہ حاضری دینا چاہتا ہے۔' : 'e.g. Student wants to resume attendance.',
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
                    setDs(() => reasonError = 'Reason is required');
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
                  backgroundColor: Colors.orange,
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
                  PasswordField(
                    controller: oldPwCtrl,
                    label: context.t('Old Password'),
                    icon: Icons.lock_open_rounded,
                    isRequired: true,
                    errorText: oldPwError,
                    onChanged: (v) {
                      if (oldPwError != null) setDs(() => oldPwError = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: newPwCtrl,
                    label: context.t('New Password'),
                    icon: Icons.lock_outline_rounded,
                    isRequired: true,
                    errorText: newPwError,
                    onChanged: (v) {
                      if (newPwError != null) setDs(() => newPwError = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: confirmPwCtrl,
                    label: context.t('Confirm Password'),
                    icon: Icons.lock_outline_rounded,
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

  Future<void> _showSendReplyDialog(BuildContext context, String dateStr) async {
    final replyCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDs) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                const Icon(Icons.reply_rounded, color: ParentReportCard.primaryColor),
                const SizedBox(width: 8),
                Text(
                  context.isUrdu ? 'استاد کو جواب بھیجیں' : 'Reply to Teacher',
                  style: TextStyle(fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.isUrdu ? '$dateStr کی حاضری کا جواب:' : 'Send a response for $dateStr:',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: replyCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: context.isUrdu ? 'اپنا پیغام یہاں درج کریں...' : 'Enter your reply message here...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: Text(context.t('Cancel'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final text = replyCtrl.text.trim();
                        if (text.isEmpty) return;
                        setDs(() => isSaving = true);
                        try {
                          await FirebaseFirestore.instance
                              .collection('branches')
                              .doc(widget.branchId)
                              .collection('madrassa_daily_logs')
                              .doc(dateStr)
                              .set({
                            widget.studentId: {
                              'parentReplied': true,
                              'parentReplyText': text,
                              'parentReplyTime': FieldValue.serverTimestamp(),
                            }
                          }, SetOptions(merge: true));
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.isUrdu ? 'جواب کامیابی سے بھیج دیا گیا!' : 'Reply sent successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setDs(() => isSaving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ParentReportCard.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(context.isUrdu ? 'بھیجیں' : 'Send Reply', style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditGuardianInfoDialog(BuildContext context) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final nameCtrl = TextEditingController(text: studentData['guardianName']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: studentData['contactPhone']?.toString() ?? '');
    final cnicCtrl = TextEditingController(text: studentData['guardianCnic']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: currentUser?.email ?? studentData['guardianEmail']?.toString() ?? '');
    final newPwCtrl = TextEditingController();
    final currentPwCtrl = TextEditingController();

    String? currentPwError;
    String? newPwError;
    String? emailError;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDs) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: ParentReportCard.primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.t('Edit Account Details'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('Update your account, contact, and security details below:'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontFamily: context.isUrdu ? 'Noori' : null),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: context.t('Guardian Name'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: context.t('Phone Number / Username'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cnicCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.t('Guardian CNIC'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.credit_card_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: context.t('Email / Username'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.email_outlined),
                      errorText: emailError,
                    ),
                    onChanged: (v) {
                      if (emailError != null) setDs(() => emailError = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: newPwCtrl,
                    label: context.t('New Password (Optional)'),
                    icon: Icons.lock_outline_rounded,
                    isRequired: false,
                    errorText: newPwError,
                    onChanged: (v) {
                      if (newPwError != null) setDs(() => newPwError = null);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  PasswordField(
                    controller: currentPwCtrl,
                    label: context.t('Current Password (Required)'),
                    icon: Icons.lock_open_rounded,
                    isRequired: true,
                    errorText: currentPwError,
                    onChanged: (v) {
                      if (currentPwError != null) setDs(() => currentPwError = null);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: Text(context.t('Cancel'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final currentPw = currentPwCtrl.text.trim();
                        if (currentPw.isEmpty) {
                          setDs(() => currentPwError = context.t('Current password is required to save changes'));
                          return;
                        }

                        if (newPwCtrl.text.trim().isNotEmpty && newPwCtrl.text.trim().length < 6) {
                          setDs(() => newPwError = context.t('Password must be at least 6 characters'));
                          return;
                        }

                        setDs(() => isSaving = true);
                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          final oldEmail = user?.email ?? '';
                          final newEmail = emailCtrl.text.trim();
                          final newPw = newPwCtrl.text.trim();

                          if (user != null && oldEmail.isNotEmpty) {
                            // Re-authenticate with current password
                            final cred = EmailAuthProvider.credential(
                              email: oldEmail,
                              password: currentPw,
                            );
                            await user.reauthenticateWithCredential(cred);

                            // Update Email if changed
                            if (newEmail.isNotEmpty && newEmail != oldEmail) {
                              await user.verifyBeforeUpdateEmail(newEmail);
                            }

                            // Update Password if provided
                            if (newPw.isNotEmpty) {
                              await user.updatePassword(newPw);
                              await OfflineAuthService.updateCachedPassword(
                                newPw,
                                usernameOrEmail: newEmail.isNotEmpty ? newEmail : oldEmail,
                              );
                            }
                          }

                          final studentUpdates = <String, dynamic>{
                            'guardianName': nameCtrl.text.trim(),
                            'contactPhone': phoneCtrl.text.trim(),
                            'guardianCnic': cnicCtrl.text.trim(),
                            if (newEmail.isNotEmpty) 'guardianEmail': newEmail,
                            'lastUpdatedAt': FieldValue.serverTimestamp(),
                          };

                          await FirebaseFirestore.instance
                              .collection('branches')
                              .doc(widget.branchId)
                              .collection('madrassa_students')
                              .doc(widget.studentId)
                              .update(studentUpdates);

                          // Also update user document if authenticated
                          if (user != null) {
                            final userUpdates = <String, dynamic>{
                              'name': nameCtrl.text.trim(),
                              'phone': phoneCtrl.text.trim(),
                              'cnic': cnicCtrl.text.trim(),
                              if (newEmail.isNotEmpty) 'email': newEmail,
                              if (newPw.isNotEmpty) 'password': newPw,
                              if (newPw.isNotEmpty) 'passwordHash': LocalStorageService.hashPassword(newPw),
                              'lastUpdatedAt': FieldValue.serverTimestamp(),
                            };
                            await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userUpdates, SetOptions(merge: true));
                            await FirebaseFirestore.instance
                                .collection('branches')
                                .doc(widget.branchId)
                                .collection('users')
                                .doc(user.uid)
                                .set(userUpdates, SetOptions(merge: true));
                          }

                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.isUrdu ? 'معلومات کامیابی سے اپ ڈیٹ ہو گئیں!' : 'Account details updated successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } on FirebaseAuthException catch (e) {
                          setDs(() => isSaving = false);
                          if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
                            setDs(() => currentPwError = context.t('Incorrect current password'));
                          } else {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.message ?? 'Failed to update account'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        } catch (e) {
                          setDs(() => isSaving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ParentReportCard.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(context.t('Save Changes'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _claimPtmJoin(BuildContext context) async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('madrassa_daily_logs')
          .doc(todayStr)
          .set({
        widget.studentId: {
          'ptmRequestStatus': 'claimed',
          'timestamp': FieldValue.serverTimestamp()
        }
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.isUrdu 
                ? 'پی ٹی ایم میں شرکت کا دعویٰ بھیج دیا گیا ہے۔ استاد کی منظوری کا انتظار کریں۔' 
                : 'PTM attendance claim submitted. Waiting for teacher approval.'),
            backgroundColor: Colors.green,
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

  Future<void> _showReplyTextDialog(BuildContext context, String todayStr) async {
    final replyCtrl = TextEditingController();
    String? replyError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDs) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(context.t('Reply to Teacher'), style: TextStyle(fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('Please enter your reply/comments for the teacher.'),
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: replyCtrl,
                  maxLines: 3,
                  style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                  decoration: InputDecoration(
                    hintText: context.t('Enter your reply here...'),
                    errorText: replyError != null ? context.t(replyError!) : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (v) {
                    if (replyError != null) setDs(() => replyError = null);
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
                  if (replyCtrl.text.trim().isEmpty) {
                    setDs(() => replyError = 'Reply cannot be empty');
                    return;
                  }
                  
                  await FirebaseFirestore.instance
                      .collection('branches')
                      .doc(widget.branchId)
                      .collection('madrassa_daily_logs')
                      .doc(todayStr)
                      .set({
                    widget.studentId: {
                      'parentReplied': true,
                      'parentReplyMessage': replyCtrl.text.trim(),
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

  Widget _buildQuickActions({
    required BuildContext context,
    required Map<String, dynamic> selectedDateLog,
    required String currentStatus,
    required bool isPtmToday,
    required bool needsReply,
  }) {
    final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final leaveStatus = selectedDateLog['leaveStatus'] ?? 'pending';
    final hasRequestedLeave = selectedDateLog['attendance'] == 'leave_requested' || selectedDateLog['attendance'] == 'leave';
    final selectedDateReplied = selectedDateLog['parentReplied'] == true;
    final ptmRequestStatus = selectedDateLog['ptmRequestStatus'];
    final ptmJoined = selectedDateLog['ptm'] == true;
    final ptmMissed = selectedDateLog['ptm'] == false;

    final primaryActions = <Widget>[];
    final secondaryActions = <Widget>[];

    // Disable all interactive actions for hifz_completed or archived students
    final studentStatus = (studentData['status']?.toString() ?? 'active').toLowerCase().trim();
    final bool isReadOnly = studentStatus == 'hifz_completed' ||
        studentStatus == 'archived' ||
        studentStatus == 'left' ||
        studentStatus == 'dropped' ||
        studentStatus == 'dropped_out' ||
        studentStatus == 'inactive';

    if (!isReadOnly && widget.isParentView && currentStatus != 'present' && currentStatus != 'leave' && !hasRequestedLeave) {
      primaryActions.add(
        _quickActionButton(
          label: context.t('Request Leave'),
          icon: Icons.email_rounded,
          color: Colors.orange,
          onTap: () {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final target = _selectedDate.isBefore(today) ? today : _selectedDate;
            _showLeaveReasonDialog(context, widget.branchId, DateFormat('yyyy-MM-dd').format(target), widget.studentId);
          },
        ),
      );
    } else if (hasRequestedLeave && leaveStatus == 'pending') {
      primaryActions.add(
        _quickActionStatus(
          label: context.t('Leave Pending Approval'),
          icon: Icons.hourglass_empty_rounded,
          color: Colors.orange.shade700,
        ),
      );
    }

    if (!isReadOnly && needsReply && !selectedDateReplied) {
      primaryActions.add(
        _quickActionButton(
          label: context.t('Reply to Teacher'),
          icon: Icons.reply_rounded,
          color: const Color(0xFF4C4DDC),
          onTap: () => _showReplyTextDialog(context, selectedDateStr),
        ),
      );
    } else if (selectedDateReplied) {
      primaryActions.add(
        _quickActionStatus(
          label: context.t('Reply Sent'),
          icon: Icons.check_circle_rounded,
          color: Colors.green,
        ),
      );
    }

    if (!isReadOnly && isPtmToday) {
      if (!ptmJoined && !ptmMissed && ptmRequestStatus == null) {
        secondaryActions.add(
          _quickActionButton(
            label: context.t('Claim PTM Join'),
            icon: Icons.people_rounded,
            color: Colors.teal,
            onTap: () => _claimPtmJoin(context),
          ),
        );
      } else if (ptmRequestStatus == 'claimed') {
        secondaryActions.add(
          _quickActionStatus(
            label: context.t('PTM Claim Pending'),
            icon: Icons.hourglass_empty_rounded,
            color: Colors.teal.shade700,
          ),
        );
      } else if (ptmJoined) {
        secondaryActions.add(
          _quickActionStatus(
            label: context.t('PTM Joined'),
            icon: Icons.check_circle_rounded,
            color: Colors.green,
          ),
        );
      } else if (ptmMissed) {
        secondaryActions.add(
          _quickActionStatus(
            label: context.t('PTM Missed'),
            icon: Icons.cancel_rounded,
            color: Colors.red,
          ),
        );
      }
    }

    final bool isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(label: context.t('Quick Actions'), icon: Icons.bolt),
          const SizedBox(height: 12),
          if (primaryActions.isNotEmpty) ...[
            _buildActionGroup(primaryActions, isMobile),
            if (secondaryActions.isNotEmpty) const SizedBox(height: 8),
          ],
          if (secondaryActions.isNotEmpty) _buildActionGroup(secondaryActions, isMobile),
        ],
      ),
    );
  }

  Widget _buildActionGroup(List<Widget> actions, bool isMobile) {
    if (actions.isEmpty) return const SizedBox();
    if (isMobile) {
      return Column(
        children: actions.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: a,
        )).toList(),
      );
    }

    if (actions.length == 1) {
      return actions.first;
    }

    return Row(
      children: actions.map((a) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0),
          child: a,
        ),
      )).toList(),
    );
  }

  Widget _quickActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: context.isUrdu ? 'Noori' : null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionStatus({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12, fontFamily: context.isUrdu ? 'Noori' : null),
          ),
        ],
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
      return context.isUrdu ? 'رخصت / بغیر رفتار کے' : 'Paused (On Leave)';
    }
    final int totalDays = days.round();
    int years = totalDays ~/ 365;
    int months = (totalDays % 365) ~/ 30;
    int remainingDays = (totalDays % 365) % 30;

    if (months == 12) {
      years += 1;
      months = 0;
    }

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
                : 'Dear Parents, we offer our warmest congratulations to you and your family! By the grace of Almighty Allah, $studentName has completed the memorization of the Holy Quran Majeed (8,640 lines).',
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
    // ── Archived students: show unarchive request ──
    if (status == 'archived') {
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
                    context.t('Unarchive Request Pending'),
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900, fontFamily: context.isUrdu ? 'Noori' : null),
                  ),
                ],
              ),
              if (rejoinReason != null && rejoinReason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  context.isUrdu
                      ? 'وجہ: "$rejoinReason"'
                      : 'Reason: "$rejoinReason"',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade800, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
              ],
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
      }
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _showUnarchiveDialog(context),
          icon: const Icon(Icons.unarchive_rounded, color: Colors.white),
          label: Text(context.t('Request Unarchive'), style: TextStyle(color: Colors.white, fontFamily: context.isUrdu ? 'Noori' : null)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
    }

    // ── Hifz completed: no rejoin action ──
    if (status == 'hifz_completed') return const SizedBox();

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
      prevLines = int.tryParse(studentData['prevHifzLines']?.toString() ?? '0') ?? 0;
    }
    
    return (targetLines - prevLines).clamp(0, 9999);
  }

  Widget _buildDailyDetailsCard(List<QueryDocumentSnapshot> allLogs, List<Map<String, dynamic>> holidaysData, MadrassaConfig config) {
    final joinDate = _parseDateTime(studentData['joinDate']);
    
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
      if (rawData is Map && rawData[widget.studentId] is Map) {
        statusData = Map<String, dynamic>.from(rawData[widget.studentId] as Map);
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
              if (widget.isParentView && isSelectedToday && (studentData['status']?.toString() ?? 'active') == 'active') ...[
                const SizedBox(height: 16),
                _ActionButton(
                  label: context.t('Request Leave'),
                  icon: Icons.email_outlined,
                  color: ParentReportCard.primaryColor,
                  isSelected: false,
                  isActive: true,
                  onTap: () {
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final target = _selectedDate.isBefore(today) ? today : _selectedDate;
                    _showLeaveReasonDialog(context, widget.branchId, DateFormat('yyyy-MM-dd').format(target), widget.studentId);
                  },
                ),
              ],
            ],
          );
        } else {
          final att = statusData['attendance']?.toString() ?? 'absent';

          final leaveReason = statusData['leaveReason']?.toString() ?? '';
          final leaveStatus = statusData['leaveStatus']?.toString() ?? 'pending';
          final currentLines = statusData['currentLines'] as int? ?? 0;
          
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


          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ptmBanner != null) ptmBanner,
              if (att == 'present') ...[
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
              ] else ...[
                if (att == 'leave' || att == 'leave_requested') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.event_busy_rounded, color: Colors.orange, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              context.isUrdu ? 'طالب علم رخصت پر تھا' : 'Student was on Leave',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontFamily: context.isUrdu ? 'Noori' : null),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (leaveReason.isNotEmpty) ...[
                          Text(context.t("Leave Reason:"), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontFamily: context.isUrdu ? 'Noori' : null)),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.shade100),
                            ),
                            child: Text(
                              leaveReason,
                              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade800, fontFamily: context.isUrdu ? 'Noori' : null),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(context.t("Approval Status: "), style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontFamily: context.isUrdu ? 'Noori' : null)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (leaveStatus == 'approved' ? Colors.green : (leaveStatus == 'denied' ? Colors.red : Colors.amber)).withValues(alpha: 0.15),
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
                            if (statusData?['isParentRequested'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  context.isUrdu ? 'والدین کی درخواست' : 'Parent Requested',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontFamily: context.isUrdu ? 'Noori' : null),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // ABSENT CARD
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 22),
                            const SizedBox(width: 10),
                            Text(
                              context.isUrdu ? 'طالب علم غیر حاضر تھا (Absent)' : 'Student Marked ABSENT',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626), fontFamily: context.isUrdu ? 'Noori' : null),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.isUrdu ? 'طالب علم اس تاریخ کو مدرسہ میں غیر حاضر تھا۔' : 'Child did not attend Madrassa on this date.',
                          style: TextStyle(fontSize: 12, color: Colors.red.shade900, fontFamily: context.isUrdu ? 'Noori' : null),
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Colors.redAccent),
                        const SizedBox(height: 8),
                        // Parent Reply Info for Absent Date
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  statusData?['parentReplied'] == true ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                                  size: 16,
                                  color: statusData?['parentReplied'] == true ? Colors.green : const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  statusData?['parentReplied'] == true
                                      ? (context.isUrdu ? 'جواب: بھیج دیا گیا' : 'Parent Reply: Sent')
                                      : (context.isUrdu ? 'جواب: زیر التواء (Pending)' : 'Parent Reply: Pending'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: statusData?['parentReplied'] == true ? Colors.green : const Color(0xFFDC2626),
                                    fontFamily: context.isUrdu ? 'Noori' : null,
                                  ),
                                ),
                              ],
                            ),
                            if (widget.isParentView && statusData?['parentReplied'] != true && (studentData['status']?.toString() ?? 'active') == 'active')
                              ElevatedButton.icon(
                                onPressed: () => _showSendReplyDialog(context, dateStr),
                                icon: const Icon(Icons.reply_rounded, size: 14),
                                label: Text(
                                  context.isUrdu ? 'جواب دیں' : 'Reply to Teacher',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ParentReportCard.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                          ],
                        ),
                        if (statusData?['parentReplied'] == true && statusData?['parentReplyText'] != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Text(
                              '"${statusData!['parentReplyText']}"',
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade800, fontFamily: context.isUrdu ? 'Noori' : null),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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

  Widget _buildReminders(bool isPtm, bool needsReply, String leaveStatus) {
    return Column(
      children: [
        if (isPtm) _reminderItem('PTM Today', 'Today is the Parent Teacher Meeting. Please visit the Madrassa.', Icons.people, Colors.orange),
        if (needsReply) _reminderItem('Reply Needed', 'Please reply to the teacher\'s message regarding today\'s status.', Icons.message, Colors.purple),
        if (leaveStatus == 'denied') _reminderItem('Leave Denied', 'Your leave request for ${studentData['name'] ?? 'the student'} was denied. They are marked absent.', Icons.error_outline, Colors.red),
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

  String _requestStatusFilter = 'all';

  void _showEnlargedPhotoDialog(BuildContext context, String? photoUrl, String name) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: () {
                final str = photoUrl?.toString().trim();
                final bytes = ImageUploadService.decodeBase64ToBytes(str);
                if (bytes != null) {
                  return Image.memory(bytes, fit: BoxFit.contain, width: 300, height: 300);
                } else if (str != null && str.startsWith('http')) {
                  return Image.network(str, fit: BoxFit.contain, width: 300, height: 300);
                }
                return Container(
                  width: 250,
                  height: 250,
                  color: const Color(0xFF2E7D69),
                  alignment: Alignment.center,
                  child: Text(
                    name.isNotEmpty ? name[0] : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 80, fontWeight: FontWeight.bold),
                  ),
                );
              }(),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _showDownloadReportDialog(
    BuildContext context,
    MadrassaConfig displayConfig,
    Map<String, dynamic> studentData,
    List<QueryDocumentSnapshot> monthLogs,
    List<DateTime> holidays,
  ) {
    int selectedYear = _selectedYear;
    int selectedMonth = _selectedMonth;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF2E7D69)),
                  const SizedBox(width: 10),
                  Text(
                    context.isUrdu ? 'رپورٹ ڈاؤن لوڈ کریں' : 'Download Monthly Report',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.isUrdu ? 'براہ کرم جس مہینے کی رپورٹ چاہتے ہیں وہ منتخب کریں:' : 'Select the month for your download:',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DropdownButton<int>(
                        value: selectedMonth,
                        items: List.generate(12, (index) {
                          final m = index + 1;
                          final monthName = DateFormat('MMMM').format(DateTime(selectedYear, m));
                          return DropdownMenuItem(value: m, child: Text(monthName));
                        }),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedMonth = val);
                        },
                      ),
                      const SizedBox(width: 16),
                      DropdownButton<int>(
                        value: selectedYear,
                        items: [DateTime.now().year - 1, DateTime.now().year, DateTime.now().year + 1].map((y) {
                          return DropdownMenuItem(value: y, child: Text('$y'));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedYear = val);
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.isUrdu ? 'منسوخ' : 'Cancel'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D69),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t('Preparing your PDF report...')), backgroundColor: const Color(0xFF2E7D69)),
                    );
                    MadrassaReportHelper.exportIndividualPdf(
                      config: displayConfig,
                      studentId: widget.studentId,
                      studentData: studentData,
                      logs: monthLogs,
                      holidays: holidays,
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('PDF Download'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _calculateEstimationData(List<QueryDocumentSnapshot> allLogs) {
    final currentLines = (studentData['currentLines'] as num?)?.toInt() ?? 0;
    final prevLines = int.tryParse(studentData['prevHifzLines']?.toString() ?? '0') ?? 0;
    final totalMemorized = currentLines + prevLines;

    final dynamic joinField = studentData['joinDate'];
    DateTime? joinDate;
    if (joinField is Timestamp) {
      joinDate = joinField.toDate();
    } else if (joinField is String) {
      joinDate = DateTime.tryParse(joinField);
    }
    final daysSinceJoin = (joinDate != null) ? DateTime.now().difference(joinDate).inDays : 0;
    final overallAvg = daysSinceJoin > 0 ? totalMemorized / daysSinceJoin : 0.0;

    final studentStatus = (studentData['status']?.toString() ?? 'active').toLowerCase().trim();
    final bool isStatusOnLeave = studentStatus == 'leave' ||
        studentStatus == 'on_leave' ||
        studentStatus == 'archived' ||
        studentStatus == 'left' ||
        studentStatus == 'dropped' ||
        studentStatus == 'inactive';

    double recentDailyRate = 0.0;
    bool hasActiveRecentPace = false;
    try {
      final logsList = <MapEntry<DateTime, int>>[];
      for (final doc in allLogs) {
        final date = DateTime.tryParse(doc.id);
        if (date == null) continue;
        final rawData = doc.data() as Map<String, dynamic>?;
        final studentLog = rawData?[widget.studentId] as Map<String, dynamic>?;
        if (studentLog != null) {
          final lines = (studentLog['currentLines'] as num?)?.toInt();
          if (lines != null && lines > 0) {
            logsList.add(MapEntry(date, lines));
          }
        }
      }

      if (logsList.length >= 2) {
        logsList.sort((a, b) => a.key.compareTo(b.key));
        final latest = logsList.last;
        MapEntry<DateTime, int>? bestRef;
        for (int i = logsList.length - 2; i >= 0; i--) {
          final ref = logsList[i];
          final daysDiff = latest.key.difference(ref.key).inDays;
          if (daysDiff >= 7 && daysDiff <= 45) {
            bestRef = ref;
            if (daysDiff >= 14) break;
          }
        }
        if (bestRef == null) {
          for (final ref in logsList) {
            if (ref.key != latest.key) {
              bestRef = ref;
              break;
            }
          }
        }
        if (bestRef != null) {
          final daysDiff = latest.key.difference(bestRef.key).inDays;
          final linesDiff = latest.value - bestRef.value;
          if (daysDiff > 0 && linesDiff >= 0) {
            final pace = linesDiff / daysDiff;
            if (pace >= 0.3) {
              recentDailyRate = pace;
              hasActiveRecentPace = true;
            }
          }
        }
      }
    } catch (_) {}

    final remainingLines = (8640 - totalMemorized).clamp(0, 8640);
    final double effectiveRate = isStatusOnLeave ? 0.0 : (hasActiveRecentPace ? recentDailyRate : overallAvg);
    final bool isPaused = isStatusOnLeave;
    final bool isLowPace = !isPaused && effectiveRate < 1.0;

    final int? estimatedDays = (!isPaused && effectiveRate >= 0.1 && remainingLines > 0)
        ? (remainingLines / effectiveRate).ceil()
        : null;

    String estCompletionStr;
    if (isPaused) {
      estCompletionStr = context.isUrdu ? 'رخصت (رفتار رکی ہوئی ہے)' : 'Paused (On Leave)';
    } else if (isLowPace) {
      estCompletionStr = context.isUrdu ? 'ابتدائی رفتار' : 'Building Pace';
    } else if (estimatedDays != null) {
      final completionDate = DateTime.now().add(Duration(days: estimatedDays.clamp(1, 1095)));
      estCompletionStr = DateFormat('MMM yyyy').format(completionDate);
    } else {
      estCompletionStr = '—';
    }

    final double paceWeekly = effectiveRate * 7;
    final double daysRemainingDouble = (estimatedDays ?? 0).toDouble();

    return {
      'totalMemorized': totalMemorized,
      'recentDailyRate': effectiveRate,
      'remainingLines': remainingLines,
      'estimatedDays': estimatedDays,
      'estCompletionStr': estCompletionStr,
      'paceWeekly': paceWeekly,
      'daysRemaining': daysRemainingDouble,
      'overallAvg': overallAvg,
      'isPaused': isPaused,
      'isLowPace': isLowPace,
    };
  }

  void _showAccountMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.settings_rounded, color: Color(0xFF008080)),
                  const SizedBox(width: 12),
                  Text(
                    context.isUrdu ? 'اکاؤنٹس اور خصوصیات' : 'Accounts & Settings',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      fontFamily: context.isUrdu ? 'Noori' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.allDocs.length > 1) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.isUrdu ? 'طالب علم منتخب کریں:' : 'Switch Student:',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.allDocs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final doc = widget.allDocs[i];
                      final d = doc.data() as Map<String, dynamic>? ?? {};
                      final selected = i == widget.selectedIndex;
                      return ChoiceChip(
                        selected: selected,
                        selectedColor: const Color(0xFF008080),
                        label: Text(
                          d['name'] ?? 'Student ${i + 1}',
                          style: TextStyle(color: selected ? Colors.white : Colors.black87),
                        ),
                        onSelected: (_) {
                          Navigator.pop(ctx);
                          widget.onStudentChanged(i);
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 24),
              ],
              ListTile(
                leading: const Icon(Icons.edit_note_rounded, color: Color(0xFF008080)),
                title: Text(context.t('Edit Account Details')),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditGuardianInfoDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_reset_rounded, color: Color(0xFF008080)),
                title: Text(context.t('Change Password')),
                onTap: () {
                  Navigator.pop(ctx);
                  _showChangePasswordDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.language_rounded, color: Color(0xFF008080)),
                title: Text(context.isUrdu ? 'English میں تبدیل کریں' : 'اردو میں تبدیل کریں'),
                onTap: () {
                  Navigator.pop(ctx);
                  final newLang = context.isUrdu ? 'en' : 'ur';
                  try {
                    Provider.of<MadrassaLanguageProvider>(context, listen: false).setLanguage(newLang);
                  } catch (_) {}
                },
              ),
              if (widget.onLogout != null) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.red),
                  title: Text(context.t('Logout'), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onLogout!();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── New Helper Methods for Redesigned Layout ──────────────────────────────

  Widget _buildHeroBanner({
    required bool isDesktop,
    bool isAccountView = false,
    MadrassaConfig? displayConfig,
    List<QueryDocumentSnapshot>? monthLogs,
    List<DateTime>? holidays,
  }) {
    final name = studentData['name'] ?? studentData['fullName'] ?? 'Student';
    final photoUrl = (studentData['photoBase64'] ??
            studentData['photoUrl'] ??
            studentData['photo'] ??
            studentData['image'] ??
            studentData['studentPhotoBase64'])
        ?.toString();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isDesktop ? 20 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1E5B48),
            Color(0xFF2E8B67),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F1E5B48),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showEnlargedPhotoDialog(context, photoUrl, name),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: ClipOval(
                child: () {
                  final str = photoUrl?.toString().trim();
                  final bytes = ImageUploadService.decodeBase64ToBytes(str);
                  if (bytes != null) {
                    return Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      width: 56,
                      height: 56,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFDDF4EA),
                        alignment: Alignment.center,
                        child: Text(
                          name.isNotEmpty ? name[0] : '?',
                          style: const TextStyle(color: Color(0xFF1E5B48), fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  } else if (str != null && str.startsWith('http')) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: const Color(0xFFDDF4EA),
                          alignment: Alignment.center,
                          child: Text(
                            name.isNotEmpty ? name[0] : '?',
                            style: const TextStyle(color: Color(0xFF1E5B48), fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Image.network(
                          str,
                          fit: BoxFit.cover,
                          width: 56,
                          height: 56,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ],
                    );
                  }
                  return Container(
                    color: const Color(0xFFDDF4EA),
                    alignment: Alignment.center,
                    child: Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: const TextStyle(color: Color(0xFF1E5B48), fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  );
                }(),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: context.isUrdu ? 'Noori' : null,
              ),
            ),
          ),
          if (isAccountView) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E5B48),
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showEditGuardianInfoDialog(context),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: Text(
                context.isUrdu ? 'پروفائل کی ترامیم' : 'Edit Profile',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                _showDownloadReportDialog(
                  context,
                  displayConfig ?? MadrassaConfig(id: widget.branchId, year: _selectedYear, month: _selectedMonth),
                  studentData,
                  monthLogs ?? [],
                  holidays ?? [],
                );
              },
              icon: const Icon(Icons.file_download_rounded, size: 18, color: Colors.white),
              label: Text(
                context.isUrdu ? 'رپورٹ' : 'Report',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _selectedTab = 4),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.settings_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerBadge({required IconData icon, required Color iconColor, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E7D69).withValues(alpha: 0.2)),
        boxShadow: const [
          BoxShadow(color: Color(0x0F17232A), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 12),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF17362E), fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _heroChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildNearingCompletionBanner(int currentTotalLines, String studentName) {
    final remaining = 8640 - currentTotalLines;
    if (currentTotalLines < 8000 || currentTotalLines >= 8640) return const SizedBox();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD4A017), Color(0xFFE6B422)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color(0xFFD4A017).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MashaAllah! 🌟',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
                const SizedBox(height: 4),
                Text(
                  context.isUrdu
                      ? '$studentName حفظ مکمل ہونے کے قریب ہیں — صرف $remaining لائنیں باقی ہیں!'
                      : '$studentName is nearing Hifz completion — only $remaining lines remaining!',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w500, fontFamily: context.isUrdu ? 'Noori' : null),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPills({
    required String currentStatus,
    required bool uniformOk,
    required bool replied,
    required bool ptmJoined,
    required bool ptmClaimed,
    required bool isPtmToday,
    required bool hasPtmStatus,
  }) {
    final attCard = _statusPill(
      icon: Icons.check_circle_outline_rounded,
      label: context.t('Attendance'),
      value: currentStatus == 'present' ? context.t('Present') : (currentStatus == 'leave' || currentStatus == 'leave_requested' ? context.t('Leave') : context.t('Absent')),
      color: currentStatus == 'present' ? ParentReportCard.successColor : (currentStatus == 'leave' || currentStatus == 'leave_requested' ? Colors.orange : ParentReportCard.errorColor),
      onTap: () => setState(() => _selectedTab = 1),
    );
    final uniformCard = _statusPill(
      icon: Icons.checkroom_rounded,
      label: context.t('Cleanliness'),
      value: (currentStatus == 'leave' || currentStatus == 'leave_requested')
          ? context.t('Leave')
          : (currentStatus != 'present'
              ? context.t('Absent')
              : (uniformOk ? context.t('Clean') : context.t('Unclean'))),
      color: (currentStatus == 'leave' || currentStatus == 'leave_requested')
          ? Colors.orange
          : (currentStatus != 'present'
              ? ParentReportCard.errorColor
              : (uniformOk ? Colors.blue : ParentReportCard.errorColor)),
      onTap: () => setState(() => _selectedTab = 1),
    );
    final replyCard = _statusPill(
      icon: Icons.mail_rounded,
      label: context.t('Reply'),
      value: replied ? context.t('Sent') : context.t('Pending'),
      color: replied ? Colors.green : ParentReportCard.errorColor,
      onTap: () => setState(() => _selectedTab = 1),
    );

    final String ptmValue;
    final Color ptmColor;
    if (ptmJoined) {
      ptmValue = context.t('Joined');
      ptmColor = ParentReportCard.primaryColor;
    } else if (ptmClaimed) {
      ptmValue = context.t('Claim Pending');
      ptmColor = Colors.teal.shade700;
    } else if (isPtmToday) {
      ptmValue = context.t('Today');
      ptmColor = Colors.orange;
    } else if (hasPtmStatus) {
      ptmValue = context.t('Missed');
      ptmColor = ParentReportCard.errorColor;
    } else {
      ptmValue = context.t('Scheduled');
      ptmColor = ParentReportCard.primaryColor;
    }

    final ptmCard = _statusPill(
      icon: Icons.people_rounded,
      label: 'PTM',
      value: ptmValue,
      color: ptmColor,
      onTap: () => setState(() => _selectedTab = 1),
    );

    final bool isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: attCard),
              Expanded(child: uniformCard),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: replyCard),
              Expanded(child: ptmCard),
            ],
          ),
        ],
      );
    } else {
      return Row(
        children: [
          Expanded(child: attCard),
          Expanded(child: uniformCard),
          Expanded(child: replyCard),
          Expanded(child: ptmCard),
        ],
      );
    }
  }

  Widget _statusPill({required IconData icon, required String label, required String value, required Color color, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 10, color: ParentReportCard.textMutedColor, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherMessageCard({required bool needsReply, required String branchId, required String studentId, required String dateStr}) {
    if (!needsReply) return const SizedBox();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF7C3AED).withValues(alpha: 0.08), const Color(0xFF7C3AED).withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_rounded, color: Color(0xFF7C3AED), size: 20),
              const SizedBox(width: 10),
              Text(context.t('Teacher Message'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF7C3AED), fontFamily: context.isUrdu ? 'Noori' : null)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.isUrdu ? 'براہ کرم آج کی حاضری کے حوالے سے جواب دیں۔' : 'Please reply regarding today\'s attendance status.',
            style: TextStyle(fontSize: 13, color: const Color(0xFF7C3AED).withValues(alpha: 0.8), fontFamily: context.isUrdu ? 'Noori' : null),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _submitParentReply(context, branchId, dateStr, studentId),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.isUrdu ? 'ابھی جواب دیں' : 'Reply Now', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeSummaryCompact({required double due, required double totalSavings, required double baseFee, required Map<String, dynamic> fee}) {
    // Celebrate full waiver, notify if high
    String feeMessage;
    Color feeMessageColor;
    IconData feeIcon;
    if (due <= 0) {
      feeMessage = context.isUrdu ? 'ماشاء اللہ! اس مہینے فیس مکمل طور پر معاف ہے! 🎉' : 'MashaAllah! Fee is fully waived this month! 🎉';
      feeMessageColor = ParentReportCard.successColor;
      feeIcon = Icons.celebration_rounded;
    } else if (due >= 3000) {
      feeMessage = context.isUrdu 
          ? 'توجہ: فیس زیادہ ہے۔ روزانہ حاضری، یونیفارم اور جوابات سے اسے 0 روپے تک کم کیا جا سکتا ہے!' 
          : 'Notice: Fee is high. Daily attendance, uniform, and replies can reduce this to Rs. 0!';
      feeMessageColor = ParentReportCard.errorColor;
      feeIcon = Icons.warning_amber_rounded;
    } else if (totalSavings > baseFee * 0.5) {
      feeMessage = context.isUrdu ? 'بہت اچھا! آپ نے ${totalSavings.toStringAsFixed(0)} روپے بچائے 🌟' : 'Great! You saved Rs. ${totalSavings.toStringAsFixed(0)} 🌟';
      feeMessageColor = ParentReportCard.successColor;
      feeIcon = Icons.thumb_up_alt_rounded;
    } else if (totalSavings > 0) {
      feeMessage = context.isUrdu ? 'آپ نے ${totalSavings.toStringAsFixed(0)} روپے بچائے — حاضری و جواب سے مزید بچت ممکن ہے' : 'You saved Rs. ${totalSavings.toStringAsFixed(0)} — more attendance & replies = more savings';
      feeMessageColor = Colors.orange.shade700;
      feeIcon = Icons.trending_up_rounded;
    } else {
      feeMessage = context.isUrdu ? 'حاضری، یونیفارم اور جواب سے فیس میں چھوٹ حاصل کریں' : 'Attendance, uniform & replies earn fee discounts';
      feeMessageColor = Colors.grey;
      feeIcon = Icons.info_outline;
    }

    final String monthYearStr = DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth));

    // Get the details from the calculated fee variables
    final double attSavings = (fee['attSavings'] as num?)?.toDouble() ?? 0.0;
    final double uniSavings = (fee['uniSavings'] as num?)?.toDouble() ?? 0.0;
    final double msgSavings = (fee['msgSavings'] as num?)?.toDouble() ?? 0.0;
    final double ptmSavings = (fee['ptmSavings'] as num?)?.toDouble() ?? 0.0;
    final double proRatedBaseFee = (fee['proRatedBaseFee'] as num?)?.toDouble() ?? 0.0;
    final bool isProRated = proRatedBaseFee < baseFee;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: feeMessageColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: feeMessageColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(feeIcon, color: feeMessageColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(feeMessage, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: feeMessageColor, fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildPdfFormFeeBreakdown(
          baseFee: baseFee,
          proRatedBaseFee: proRatedBaseFee,
          attSavings: attSavings,
          uniSavings: uniSavings,
          msgSavings: msgSavings,
          ptmSavings: ptmSavings,
          totalSavings: totalSavings,
          due: due,
          isProRated: isProRated,
          monthYearStr: monthYearStr,
        ),
      ],
    );
  }

  Widget _buildPdfFormFeeBreakdown({
    required double baseFee,
    required double proRatedBaseFee,
    required double attSavings,
    required double uniSavings,
    required double msgSavings,
    required double ptmSavings,
    required double totalSavings,
    required double due,
    required bool isProRated,
    required String monthYearStr,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEF2F1)),
        boxShadow: const [
          BoxShadow(color: Color(0x1417232A), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.isUrdu ? 'فیس کی تفصیل اور بچت فارم' : 'Fee Statement Breakdown Form',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E5B48),
                  fontFamily: context.isUrdu ? 'Noori' : null,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDF4EA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  monthYearStr,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E5B48)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _formFeeRow(context.t('Standard Monthly Base Fee'), 'Rs. ${baseFee.toStringAsFixed(0)}', isHeader: true),
          if (isProRated)
            _formFeeRow(context.t('Pro-Rated Base Fee'), 'Rs. ${proRatedBaseFee.toStringAsFixed(0)}', isInfo: true),
          const SizedBox(height: 8),
          Text(
            context.isUrdu ? 'رعایات و بچت (Deductions & Rewards):' : 'Itemized Discounts & Rewards:',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          _formFeeRow(context.t('Attendance Reward'), '- Rs. ${attSavings.toStringAsFixed(0)}', color: Colors.green),
          _formFeeRow(context.t('Uniform Cleanliness Reward'), '- Rs. ${uniSavings.toStringAsFixed(0)}', color: Colors.blue),
          _formFeeRow(context.t('Teacher Reply Response Reward'), '- Rs. ${msgSavings.toStringAsFixed(0)}', color: Colors.purple),
          _formFeeRow(context.t('PTM Meeting Reward'), '- Rs. ${ptmSavings.toStringAsFixed(0)}', color: Colors.orange),
          const Divider(height: 20, thickness: 1),
          _formFeeRow(context.t('Total Discounts & Savings'), '- Rs. ${totalSavings.toStringAsFixed(0)}', isBold: true, color: Colors.green),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: due <= 0 ? const Color(0xFFDDF4EA) : const Color(0xFFFFF1F1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: due <= 0 ? const Color(0xFF22A861) : const Color(0xFFE84B4B)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.isUrdu ? 'قابل ادا رقم (NET AMOUNT DUE)' : 'NET PAYABLE AMOUNT DUE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: due <= 0 ? const Color(0xFF1E5B48) : const Color(0xFFE84B4B),
                    fontFamily: context.isUrdu ? 'Noori' : null,
                  ),
                ),
                Text(
                  context.isUrdu ? 'روپے ${due.toStringAsFixed(0)}' : 'Rs. ${due.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: due <= 0 ? const Color(0xFF1E5B48) : const Color(0xFFE84B4B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formFeeRow(String label, String value, {bool isHeader = false, bool isInfo = false, bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: (isHeader || isBold) ? FontWeight.bold : FontWeight.w500,
              color: isInfo ? Colors.blueGrey : (color ?? Colors.black87),
              fontFamily: context.isUrdu ? 'Noori' : null,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: (isHeader || isBold) ? FontWeight.bold : FontWeight.w600,
              color: color ?? (isInfo ? Colors.blueGrey : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuranProgressCard({
    required int currentTotalLines,
    required int monthGain,
    required double paceWeekly,
    required double overallPace,
    required double daysRemaining,
    required String estCompletionStr,
    required Map<String, dynamic> selectedDateLog,
  }) {
    final currentPara = (currentTotalLines / 288).floor() + 1;
    final linesInPara = currentTotalLines % 288;
    final pageInPara = (linesInPara / 16).floor() + 1;
    final juzPercentage = ((currentTotalLines / 8640) * 100).clamp(0.0, 100.0);

    final sabkiPara = selectedDateLog['sabkiPara'] ?? 0;
    final sabkiRatio = selectedDateLog['sabkiRatio']?.toString() ?? '—';
    final manzilPara = selectedDateLog['manzilPara'] ?? 0;
    final manzilRatio = selectedDateLog['manzilRatio']?.toString() ?? '—';

    final bool isSabkiDone = sabkiRatio != 'nahi_sunaya' && sabkiRatio != '—' && sabkiPara > 0;
    final bool isManzilDone = manzilRatio != 'nahi_sunaya' && manzilRatio != '—' && manzilPara > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ParentReportCard.accentColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.menu_book_rounded, color: ParentReportCard.accentColor),
                  const SizedBox(width: 8),
                  Text(
                    context.isUrdu ? 'قرآن مجید (Quran Majeed)' : 'Quran Majeed',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: ParentReportCard.textPrimaryColor,
                      fontFamily: context.isUrdu ? 'Noori' : null,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: juzPercentage / 100,
                      strokeWidth: 8,
                      backgroundColor: Colors.grey.shade100,
                      color: ParentReportCard.accentColor,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${juzPercentage.toStringAsFixed(0)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: ParentReportCard.primaryColor),
                      ),
                      Text(
                        'Juz $currentPara',
                        style: const TextStyle(fontSize: 10, color: ParentReportCard.textMutedColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.isUrdu ? 'کل محفوظ شدہ: $currentTotalLines / 8640 لائنیں' : 'Total Memorized: $currentTotalLines / 8640 lines',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: ParentReportCard.primaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.isUrdu ? 'موجودہ پارہ: $currentPara • صفحہ: $pageInPara' : 'Current Juz: Para $currentPara • Page $pageInPara',
                      style: TextStyle(fontSize: 12, color: ParentReportCard.textMutedColor, fontFamily: context.isUrdu ? 'Noori' : null),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ParentReportCard.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        context.isUrdu ? 'اس مہینے +$monthGain لائنیں مزید' : '+$monthGain lines gained this month',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ParentReportCard.accentColor, fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 1),
          Row(
            children: [
              Expanded(
                child: _quranTile(
                  icon: Icons.speed_rounded,
                  label: context.t('Weekly Pace'),
                  value: (selectedDateLog['attendance'] == 'leave' || selectedDateLog['attendance'] == 'leave_requested')
                      ? (context.isUrdu ? 'ترقی رکی ہوئی' : 'Paused')
                      : (paceWeekly > 0 ? '${paceWeekly.toStringAsFixed(1)} lines/wk' : (context.isUrdu ? 'شروعاتی رفتار' : 'Building Pace')),
                  sub: (selectedDateLog['attendance'] == 'leave' || selectedDateLog['attendance'] == 'leave_requested')
                      ? (context.isUrdu ? 'رخصت پر مطلع' : 'On Leave')
                      : (overallPace > 0 ? '${overallPace.toStringAsFixed(1)} lines/day avg' : (context.isUrdu ? 'روزانہ کارکردگی' : 'Daily Progress')),
                  color: ParentReportCard.primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _quranTile(
                  icon: Icons.event_repeat_rounded,
                  label: context.t('Est. Completion'),
                  value: (selectedDateLog['attendance'] == 'leave' || selectedDateLog['attendance'] == 'leave_requested')
                      ? (context.isUrdu ? 'روک دیا گیا' : 'Paused')
                      : (daysRemaining <= 0 || overallPace < 0.1
                          ? (context.isUrdu ? 'ابتدائی کارکردگی' : 'Building Pace')
                          : (daysRemaining > 1095
                              ? '~3.0 yrs'
                              : (daysRemaining < 365 ? '${(daysRemaining / 30).toStringAsFixed(1)} mos' : '${(daysRemaining / 365).toStringAsFixed(1)} yrs'))),
                  sub: (selectedDateLog['attendance'] == 'leave' || selectedDateLog['attendance'] == 'leave_requested')
                      ? (context.isUrdu ? 'رخصت (رفتار رکی ہوئی ہے)' : 'Paused (On Leave)')
                      : estCompletionStr,
                  color: ParentReportCard.accentColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quranTile({required IconData icon, required String label, required String value, required String sub, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: ParentReportCard.textMutedColor, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color, fontFamily: context.isUrdu ? 'Noori' : null)),
                Text(sub, style: TextStyle(fontSize: 10, color: ParentReportCard.textMutedColor, fontFamily: context.isUrdu ? 'Noori' : null)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab({
    required bool isDesktop,
    required bool isTablet,
    required Map<String, dynamic> todaySLog,
    required Map<String, dynamic> selectedDateLog,
    required bool isPtmForSelectedDate,
    required String currentStatus,
    required String leaveStatus,
    required bool isPtmToday,
    required bool needsReply,
    required List<QueryDocumentSnapshot> allLogs,
    required List<QueryDocumentSnapshot> monthLogs,
    required List<Map<String, dynamic>> holidaysData,
    required MadrassaConfig config,
    required double due,
    required double totalSavings,
    required double proRatedBaseFee,
    required int currentTotalLines,
    required int monthGain,
    required String estCompletionStr,
    required double paceWeekly,
    required double overallPace,
    required double daysRemaining,
    required Map<String, dynamic> fee,
    required Widget? congratsCard,
    required Widget nearingBanner,
  }) {
    final selectedDateStatus = selectedDateLog['attendance']?.toString() ?? 'unknown';
    final selectedDateLeaveStatus = selectedDateLog['leaveStatus'] ?? 'pending';
    final selectedDateUniform = selectedDateLog['uniform'] == true;
    final selectedDateReplied = selectedDateLog['parentReplied'] == true;
    
    // Check if PTM joined or claimed in selected date or anywhere in allLogs for the month
    final monthPtmJoined = allLogs.any((l) {
      final map = l.data() as Map<String, dynamic>?;
      final studentLog = map?[widget.studentId] as Map<String, dynamic>?;
      if (studentLog == null) return false;
      final p = studentLog['ptm'];
      final s = studentLog['ptmRequestStatus']?.toString().toLowerCase();
      return p == true || s == 'approved';
    });
    final selectedDatePtmClaimed = selectedDateLog['ptmRequestStatus'] == 'claimed';
    final selectedDatePtmJoined = selectedDateLog['ptm'] == true ||
        selectedDateLog['ptmRequestStatus'] == 'approved' ||
        selectedDateLog['ptmJoined'] == true ||
        studentData['ptmJoined'] == true ||
        monthPtmJoined;

    final selectedDatePtmRecorded = selectedDateLog.containsKey('ptm');
    final selectedDateNeedsReply = selectedDateLog['parentReplied'] != true && selectedDateStatus == 'present';
    final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final isSelectedToday = _selectedDate.year == DateTime.now().year && _selectedDate.month == DateTime.now().month && _selectedDate.day == DateTime.now().day;

    final heroBanner = _buildHeroBanner(
      isDesktop: isDesktop || isTablet,
      displayConfig: config,
      monthLogs: monthLogs,
      holidays: holidaysData.map((h) => h['date'] as DateTime).toList(),
    );

    final rawFeeSummary = _buildFeeSummaryCompact(due: due, totalSavings: totalSavings, baseFee: proRatedBaseFee, fee: fee);
    final feeSummary = InkWell(
      onTap: () => setState(() => _selectedTab = 3),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          rawFeeSummary,
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                context.isUrdu ? 'مکمل فیس کی تفصیلات دیکھیں ←' : 'View Detailed Fee Statement →',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ParentReportCard.primaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
            ],
          ),
        ],
      ),
    );

    final teacherMessage = isSelectedToday 
        ? _buildTeacherMessageCard(needsReply: selectedDateNeedsReply && !selectedDateReplied, branchId: widget.branchId, studentId: widget.studentId, dateStr: selectedDateStr)
        : const SizedBox();

    final statusPills = _buildStatusPills(
      currentStatus: selectedDateStatus,
      uniformOk: selectedDateUniform,
      replied: selectedDateReplied,
      ptmJoined: selectedDatePtmJoined,
      ptmClaimed: selectedDatePtmClaimed,
      isPtmToday: isPtmForSelectedDate,
      hasPtmStatus: selectedDatePtmRecorded,
    );

    final rawMonthGainWidget = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ParentReportCard.accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ParentReportCard.accentColor.withOpacity(0.2)),
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

    final rawForecastWidget = Row(
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



    final noticesList = config.auditLog.where((l) => l['type'] == 'ptm_reschedule' && l['month'] == config.month && l['year'] == config.year).toList();
    final hasRemindersOrNotices = isPtmForSelectedDate || selectedDateNeedsReply || (selectedDateStatus == 'absent' && selectedDateLeaveStatus == 'denied') || noticesList.isNotEmpty;

    final newsWidget = Container(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPtmForSelectedDate || selectedDateNeedsReply || (selectedDateStatus == 'absent' && selectedDateLeaveStatus == 'denied')) ...[
            _SectionTitle(label: context.t('Reminders'), icon: Icons.warning_amber_rounded),
            const SizedBox(height: 12),
            _buildReminders(isPtmForSelectedDate, selectedDateNeedsReply, selectedDateLeaveStatus),
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
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade700, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
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
                color: ParentReportCard.primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ParentReportCard.primaryColor.withOpacity(0.1)),
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

    final quickActions = _buildQuickActions(
      context: context,
      selectedDateLog: selectedDateLog,
      currentStatus: selectedDateStatus,
      isPtmToday: isPtmForSelectedDate,
      needsReply: selectedDateNeedsReply,
    );

    final embeddedQuranCard = _buildQuranProgressCard(
      currentTotalLines: currentTotalLines,
      monthGain: monthGain,
      paceWeekly: paceWeekly,
      overallPace: overallPace,
      daysRemaining: daysRemaining,
      estCompletionStr: estCompletionStr,
      selectedDateLog: selectedDateLog,
    );

    final embeddedCalendarCard = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionTitle(label: context.t('Attendance Calendar'), icon: Icons.calendar_month),
              TextButton.icon(
                onPressed: () => setState(() => _selectedTab = 1),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text(context.isUrdu ? 'تفصیل' : 'Details'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMonthSelector(),
          const SizedBox(height: 12),
          _AttendanceCalendar(
            studentId: widget.studentId,
            logs: allLogs,
            year: _selectedYear,
            month: _selectedMonth,
            config: config,
            selectedDate: _selectedDate,
            onDateSelected: (d) => setState(() => _selectedDate = d),
            holidaysData: holidaysData,
          ),
        ],
      ),
    );

    final clickableQuranCard = InkWell(
      onTap: () => setState(() => _selectedTab = 2),
      borderRadius: BorderRadius.circular(24),
      child: embeddedQuranCard,
    );

    final clickableFeeSummary = InkWell(
      onTap: () => setState(() => _selectedTab = 3),
      borderRadius: BorderRadius.circular(20),
      child: feeSummary,
    );

    if (isDesktop || isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heroBanner,
          const SizedBox(height: 20),
          newsWidget,
          const SizedBox(height: 20),
          quickActions,
          const SizedBox(height: 20),
          nearingBanner,
          if (congratsCard != null) congratsCard,
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    statusPills,
                    const SizedBox(height: 20),
                    teacherMessage,
                    if (selectedDateNeedsReply && !selectedDateReplied && isSelectedToday) const SizedBox(height: 20),
                    _buildDailyDetailsCard(allLogs, holidaysData, config),
                    const SizedBox(height: 20),
                    embeddedCalendarCard,
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    clickableQuranCard,
                    const SizedBox(height: 20),
                    clickableFeeSummary,
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      return Column(
        children: [
          heroBanner,
          const SizedBox(height: 16),
          newsWidget,
          const SizedBox(height: 16),
          quickActions,
          const SizedBox(height: 16),
          statusPills,
          const SizedBox(height: 16),
          teacherMessage,
          if (selectedDateNeedsReply && !selectedDateReplied && isSelectedToday) const SizedBox(height: 16),
          _buildDailyDetailsCard(allLogs, holidaysData, config),
          const SizedBox(height: 16),
          clickableQuranCard,
          const SizedBox(height: 16),
          embeddedCalendarCard,
          const SizedBox(height: 16),
          clickableFeeSummary,
          const SizedBox(height: 16),
          nearingBanner,
          if (congratsCard != null) congratsCard,
        ],
      );
    }
  }
  Widget _buildCombinedProgressTab({
    required bool isDesktop,
    required bool isTablet,
    required List<QueryDocumentSnapshot> allLogs,
    required List<Map<String, dynamic>> holidaysData,
    required MadrassaConfig config,
    required MadrassaConfig displayConfig,
    required int currentTotalLines,
    required int monthGain,
    required double paceWeekly,
    required double overallPace,
    required double daysRemaining,
    required String estCompletionStr,
    required Widget? congratsCard,
    required Widget nearingBanner,
  }) {
    const total = 8640;
    final pct = (currentTotalLines / total * 100).toStringAsFixed(1);
    final remainingLines = (total - currentTotalLines).clamp(0, total);

    // ── 2-Year Hifz Honor Gift Goal Calculation ──
    final joinDate = _parseDateTime(studentData['joinDate'], DateTime.now().subtract(const Duration(days: 1)));
    final deadline2Years = joinDate.add(const Duration(days: 730)); // 2 years = 730 days
    final now = DateTime.now();
    final daysLeftForGiftGoal = deadline2Years.difference(now).inDays;
    
    final linesRemainingForGift = (total - currentTotalLines).clamp(0, total);
    
    double requiredDailyForGift = 0.0;
    if (linesRemainingForGift > 0 && daysLeftForGiftGoal > 0) {
      requiredDailyForGift = linesRemainingForGift / daysLeftForGiftGoal;
    }
    final requiredWeeklyForGift = requiredDailyForGift * 7;
    
    final bool isCompletedHifz = linesRemainingForGift == 0;
    final bool isOnTrackForGift = (overallPace >= requiredDailyForGift) || isCompletedHifz;

    final giftGoalCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOnTrackForGift
              ? [const Color(0xFF14532D), const Color(0xFF15803D)]
              : [const Color(0xFF7C2D12), const Color(0xFF9A3412)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isOnTrackForGift ? const Color(0xFF15803D) : const Color(0xFF9A3412)).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Text('🎁', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.isUrdu ? '2 سالہ حفظ اونر گفٹ ہدف (Gift Goal)' : '2-Year Hifz Honor Gift & Goal',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.isUrdu 
                          ? 'شمولیت کے 2 سال کے اندر حفظ مکمل کرنے والے طلبا کے لیے خاص انعام!' 
                          : 'Special prize & honor gift for completing Hifz within 2 years of joining!',
                      style: TextStyle(fontSize: 11, color: Colors.white70, fontFamily: context.isUrdu ? 'Noori' : null),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white24),
          const SizedBox(height: 16),
          // Metrics Row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        context.isUrdu ? 'باقی دن' : 'Days Remaining',
                        style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        daysLeftForGiftGoal > 0 ? '$daysLeftForGiftGoal ${context.isUrdu ? "دن" : "days"}' : (context.isUrdu ? 'مکمل' : 'Passed'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        context.isUrdu ? 'مطلوبہ روزانہ رفتار' : 'Required Daily Pace',
                        style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCompletedHifz ? '0' : '${requiredDailyForGift.toStringAsFixed(1)} ${context.isUrdu ? "لائنیں" : "lines/day"}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        context.isUrdu ? 'مطلوبہ ہفتہ وار' : 'Required Weekly',
                        style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCompletedHifz ? '0' : '${requiredWeeklyForGift.toStringAsFixed(0)} ${context.isUrdu ? "لائنیں" : "lines/wk"}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Status Message Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  isOnTrackForGift ? Icons.emoji_events_rounded : Icons.track_changes_rounded,
                  color: isOnTrackForGift ? const Color(0xFFD4A017) : const Color(0xFFD97706),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCompletedHifz
                            ? (context.isUrdu ? '🎉 مبارک ہو! 2 سال کے اندر حفظ مکمل ہو گیا!' : '🎉 Congratulations! Hifz Completed within 2 Years!')
                            : (isOnTrackForGift
                                ? (context.isUrdu ? '🏆 انعام کا ہدف حاصل کرنے کے راستے پر ہیں!' : '🏆 On Track to Win the 2-Year Honor Gift!')
                                : (context.isUrdu ? '🎯 گفٹ ہدف حاصل کرنے کے لیے رفتار بڑھائیں' : '🎯 Target Needed to Win the Honor Gift')),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isOnTrackForGift ? const Color(0xFF14532D) : const Color(0xFF7C2D12),
                          fontFamily: context.isUrdu ? 'Noori' : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isCompletedHifz
                            ? (context.isUrdu ? 'طالب علم شاندار انعام کا حقدار ہے۔' : 'Student is eligible for the Grand Honor Prize!')
                            : (isOnTrackForGift
                                ? (context.isUrdu 
                                    ? 'موجودہ رفتار (${overallPace.toStringAsFixed(1)} لائنیں/دن) مطلوبہ رفتار سے بہتر ہے۔ شاندار!' 
                                    : 'Current pace (${overallPace.toStringAsFixed(1)} lines/day) meets required target (${requiredDailyForGift.toStringAsFixed(1)} lines/day)!')
                                : (context.isUrdu
                                    ? 'انعام جیتنے کے لیے روزانہ ${requiredDailyForGift.toStringAsFixed(1)} لائنیں (${requiredWeeklyForGift.toStringAsFixed(0)} لائنیں/ہفتہ) حفظ کرنا لازمی ہے۔'
                                    : 'Need ${requiredDailyForGift.toStringAsFixed(1)} lines/day (${requiredWeeklyForGift.toStringAsFixed(0)} lines/week) over the next $daysLeftForGiftGoal days to win the gift!')),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade800,
                          fontFamily: context.isUrdu ? 'Noori' : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

    final monthSelector = _buildMonthSelector();

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
            context.t('Overall Quran Majeed Memorization Progress'),
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
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, fontFamily: context.isUrdu ? 'Noori' : null),
          ),
        ],
      ),
    );

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

    if (isDesktop || isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('Quran Majeed Hifz Progress & Gift Goal'),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    progressCard,
                    const SizedBox(height: 16),
                    monthGainWidget,
                    const SizedBox(height: 16),
                    nearingBanner,
                    if (congratsCard != null) congratsCard,
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    giftGoalCard,
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      return Column(
        children: [
          progressCard,
          const SizedBox(height: 16),
          giftGoalCard,
          const SizedBox(height: 16),
          monthGainWidget,
          const SizedBox(height: 16),
          nearingBanner,
          if (congratsCard != null) congratsCard,
        ],
      );
    }
  }

  Widget _buildFeesTab({
    required bool isDesktop,
    required bool isTablet,
    required double due,
    required double totalSavings,
    required double proRatedBaseFee,
    required Widget monthSelector,
    required Widget headerRow,
    required Widget amountDueCard,
    required Widget savingsGrid,
    required Widget visualFlowCard,
    required Map<String, dynamic> fee,
    required List<QueryDocumentSnapshot> monthLogs,
    required List<DateTime> holidays,
    required MadrassaConfig displayConfig,
  }) {
    final feeSummary = _buildFeeSummaryCompact(due: due, totalSavings: totalSavings, baseFee: proRatedBaseFee, fee: fee);

    final ledgerCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEEF2F1)),
        boxShadow: const [
          BoxShadow(color: Color(0x1417232A), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.list_alt_rounded, color: Color(0xFF1E5B48)),
              const SizedBox(width: 10),
              Text(
                context.isUrdu ? 'روزانہ کی حاضری اور بچت کی تفصیل' : 'Daily Attendance & Savings Ledger',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E5B48),
                  fontFamily: context.isUrdu ? 'Noori' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.isUrdu 
                ? 'طالب علم کے ہر دن کے لیے حاضری، یونیفارم کی صفائی اور جوابات کی مکمل تفصیل:'
                : 'Day-by-day record of child attendance, uniform cleanliness, replies & rewards:',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          _buildDailySavingsLedger(
            monthLogs: monthLogs,
            holidays: holidays,
            displayConfig: displayConfig,
          ),
        ],
      ),
    );

    if (isDesktop || isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.t('Fee Statement & Breakdown'),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
              SizedBox(width: 300, child: monthSelector),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    feeSummary,
                    const SizedBox(height: 16),
                    headerRow,
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    visualFlowCard,
                    const SizedBox(height: 16),
                    ledgerCard,
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      return Column(
        children: [
          monthSelector,
          const SizedBox(height: 16),
          feeSummary,
          const SizedBox(height: 16),
          headerRow,
          const SizedBox(height: 16),
          visualFlowCard,
          const SizedBox(height: 20),
          ledgerCard,
        ],
      );
    }
  }

  Widget _buildDailySavingsLedger({
    required List<QueryDocumentSnapshot> monthLogs,
    required List<DateTime> holidays,
    required MadrassaConfig displayConfig,
  }) {
    final int daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final List<Widget> rows = [];

    for (int day = daysInMonth; day >= 1; day--) {
      final date = DateTime(_selectedYear, _selectedMonth, day);
      
      if (date.weekday == DateTime.sunday) continue;
      
      final isHoliday = holidays.any((h) => h.year == date.year && h.month == date.month && h.day == date.day);
      if (isHoliday) continue;

      final joinDateVal = studentData['joinDate'] != null ? _parseDateTime(studentData['joinDate']) : null;
      if (joinDateVal != null) {
        final dateOnly = DateTime(date.year, date.month, date.day);
        final joinOnly = DateTime(joinDateVal.year, joinDateVal.month, joinDateVal.day);
        if (dateOnly.isBefore(joinOnly)) {
          continue;
        }
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      QueryDocumentSnapshot? doc;
      for (final l in monthLogs) {
        if (l.id == dateStr) {
          doc = l;
          break;
        }
      }

      final logData = doc?.data() as Map<String, dynamic>?;
      final sLog = logData?[widget.studentId] as Map<String, dynamic>?;

      final now = DateTime.now();
      final todayOnly = DateTime(now.year, now.month, now.day);
      final dateOnly = DateTime(date.year, date.month, date.day);
      final isFuture = dateOnly.isAfter(todayOnly);

      String attText = '';
      Color attColor = Colors.grey;
      IconData attIcon = Icons.help_outline_rounded;
      
      String uniText = '';
      Color uniColor = Colors.grey;
      IconData uniIcon = Icons.help_outline_rounded;

      String replyText = '';
      Color replyColor = Colors.grey;
      IconData replyIcon = Icons.help_outline_rounded;

      double dailyEarned = 0.0;

      final workingDaysCount = MadrassaFeeLogic.getWorkingDaysCount(_selectedYear, _selectedMonth, holidays);
      final double dailyAttReward = workingDaysCount > 0 ? displayConfig.attendanceMaxDeduction / workingDaysCount : 0.0;
      final double dailyUniReward = workingDaysCount > 0 ? displayConfig.uniformMaxDeduction / workingDaysCount : 0.0;
      final double dailyMsgReward = workingDaysCount > 0 ? displayConfig.messageTotalDeduction / workingDaysCount : 0.0;

      if (isFuture) {
        attText = context.isUrdu ? 'مستقبل' : 'Future';
        attColor = Colors.blueGrey;
        attIcon = Icons.schedule_rounded;

        uniText = '—';
        uniColor = Colors.grey;
        uniIcon = Icons.remove;

        replyText = '—';
        replyColor = Colors.grey;
        replyIcon = Icons.remove;
      } else {
        final att = sLog?['attendance']?.toString();
        if (att == 'present') {
          attText = context.isUrdu ? 'حاضر' : 'Present';
          attColor = const Color(0xFF22A861);
          attIcon = Icons.check_circle_rounded;
          dailyEarned += dailyAttReward;
        } else if (att == 'leave') {
          attText = context.isUrdu ? 'رخصت' : 'Leave';
          attColor = Colors.amber.shade700;
          attIcon = Icons.offline_pin_rounded;
          dailyEarned += dailyAttReward;
        } else {
          attText = context.isUrdu ? 'غیر حاضر' : 'Absent';
          attColor = const Color(0xFFE84B4B);
          attIcon = Icons.cancel_rounded;
        }

        final isClean = sLog?['uniform'] == true;
        if (att == 'present') {
          if (isClean) {
            uniText = context.isUrdu ? 'صاف' : 'Clean';
            uniColor = const Color(0xFF3A8DFF);
            uniIcon = Icons.dry_cleaning_rounded;
            dailyEarned += dailyUniReward;
          } else {
            uniText = context.isUrdu ? 'غیر صاف' : 'Dirty';
            uniColor = const Color(0xFFE84B4B);
            uniIcon = Icons.warning_amber_rounded;
          }
        } else if (att == 'leave') {
          uniText = context.isUrdu ? 'رخصت' : 'Leave';
          uniColor = Colors.amber.shade700;
          uniIcon = Icons.offline_pin_rounded;
          dailyEarned += dailyUniReward;
        } else {
          uniText = context.isUrdu ? 'غیر حاضر' : 'Absent';
          uniColor = const Color(0xFFE84B4B);
          uniIcon = Icons.cancel_rounded;
        }

        final replied = sLog?['parentReplied'] == true;
        if (replied) {
          replyText = context.isUrdu ? 'جواب دیا' : 'Replied';
          replyColor = const Color(0xFF8A3FFC);
          replyIcon = Icons.chat_bubble_rounded;
          dailyEarned += dailyMsgReward;
        } else {
          replyText = context.isUrdu ? 'کوئی جواب نہیں' : 'No Reply';
          replyColor = const Color(0xFFE84B4B);
          replyIcon = Icons.speaker_notes_off_rounded;
        }
      }

      rows.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFCFCFA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEEF2F1)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat(context.isUrdu ? 'dd MMM' : 'dd MMMM').format(date),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E5B48)),
                    ),
                    Text(
                      DateFormat('EEEE').format(date),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(attIcon, color: attColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      attText,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: attColor, fontFamily: context.isUrdu ? 'Noori' : null),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(uniIcon, color: uniColor, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        uniText,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: uniColor, fontFamily: context.isUrdu ? 'Noori' : null),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(replyIcon, color: replyColor, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        replyText,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: replyColor, fontFamily: context.isUrdu ? 'Noori' : null),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  isFuture ? '—' : '+Rs. ${dailyEarned.toStringAsFixed(0)}',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: dailyEarned > 0 ? const Color(0xFF22A861) : Colors.red.shade400,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            context.isUrdu ? 'اس مہینے کے لیے کوئی فعال تعلیمی دن نہیں ہے' : 'No active working days for this month.',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      child: ListView(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        children: rows,
      ),
    );
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
        color: isFinal ? color.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isFinal ? color.withOpacity(0.2) : Colors.grey.shade200),
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
    final identityHero = _buildHeroBanner(
      isDesktop: isDesktop || isTablet,
      isAccountView: true,
    );

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
              const Icon(Icons.badge_outlined, color: Color(0xFF14532D)),
              const SizedBox(width: 12),
              Text(
                context.t('Personal Information'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.credit_card, context.t('Student CNIC'), studentData['studentCnic'] ?? context.t('Not Provided')),
          _buildDetailRow(
            Icons.calendar_today,
            context.t('Join Date'),
            studentData['joinDate'] != null
                ? (context.isUrdu 
                    ? DateFormat('dd-MM-yyyy').format(_parseDateTime(studentData['joinDate']))
                    : DateFormat('dd MMMM yyyy').format(_parseDateTime(studentData['joinDate'])))
                : context.t('Not Provided'),
          ),
          if (studentData['hasPrevMadrassa'] == true) ...[
            _buildDetailRow(Icons.school, context.t('Prev Madrassa'), studentData['prevMadrassaName'] ?? context.t('Not Provided')),
            _buildDetailRow(Icons.auto_stories, context.t('Prev Hifz Lines'), context.isUrdu ? '${studentData['prevHifzLines'] ?? 0} لائنیں' : '${studentData['prevHifzLines'] ?? 0} lines'),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.family_restroom, color: Color(0xFF14532D)),
                  const SizedBox(width: 12),
                  Text(
                    context.t('Guardian Details'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _showEditGuardianInfoDialog(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14532D).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF14532D).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF14532D)),
                      const SizedBox(width: 4),
                      Text(
                        context.isUrdu ? 'ترمیم کریں' : 'Edit',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF14532D), fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.person_outline, context.t('Guardian Name'), studentData['guardianName'] ?? context.t('Not Provided')),
          _buildDetailRow(Icons.credit_card_outlined, context.t('Guardian CNIC'), studentData['guardianCnic'] ?? context.t('Not Provided')),
          _buildDetailRow(Icons.phone_outlined, context.t('Phone'), studentData['contactPhone'] ?? context.t('Not Provided')),
        ],
      ),
    );

    final String? bFormUrl = studentData['bFormUrl'] ?? studentData['bFormBase64'];
    final String? guardianCnicUrl = studentData['guardianCnicUrl'] ?? studentData['guardianCnicBase64'];

    final documentsCard = Container(
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
              const Icon(Icons.folder_shared_outlined, color: Color(0xFF14532D)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.t('Student & Guardian Documents'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: ParentReportCard.textPrimaryColor,
                    fontFamily: context.isUrdu ? 'Noori' : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Read Only',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          ReadOnlyDocumentTile(
            label: context.t('Guardian CNIC Document'),
            icon: Icons.badge_outlined,
            documentUri: guardianCnicUrl,
          ),
          const SizedBox(height: 12),
          ReadOnlyDocumentTile(
            label: context.t('B-Form / Birth Certificate'),
            icon: Icons.assignment_ind_outlined,
            documentUri: bFormUrl,
          ),
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
              const Icon(Icons.language, color: Color(0xFF14532D)),
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
              const Icon(Icons.lock_reset_rounded, color: Color(0xFF14532D)),
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
                backgroundColor: const Color(0xFF14532D),
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

    if (isTablet || isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          identityHero,
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    if (status == 'left') ...[
                      rejoinWidget,
                      const SizedBox(height: 16),
                    ],
                    studentInfoCard,
                    const SizedBox(height: 16),
                    guardianInfoCard,
                    const SizedBox(height: 16),
                    documentsCard,
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    languageInfoCard,
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
          ),
        ],
      );
    } else {
      return Column(
        children: [
          identityHero,
          const SizedBox(height: 16),
          if (status == 'left') ...[
            rejoinWidget,
            const SizedBox(height: 16),
          ],
          studentInfoCard,
          const SizedBox(height: 16),
          guardianInfoCard,
          const SizedBox(height: 16),
          documentsCard,
          const SizedBox(height: 16),
          languageInfoCard,
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
    required Map<String, dynamic> selectedDateLog,
    required bool isPtmForSelectedDate,
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
    required double paceWeekly,
    required double overallPace,
    required double daysRemaining,
    required String estCompletionStr,
    required String status,
    required String? rejoinRequestStatus,
    required String? rejoinReason,
    required Timestamp? rejoinDate,
    required List<Map<String, dynamic>> auditList,
  }) {
    // ── Shared computed data (Student Management Estimation Logic) ──
    const total = 8640;
    final remainingLines = (total - currentTotalLines).clamp(0, total);
    final joinDate = _parseDateTime(studentData['joinDate'], DateTime.now().subtract(const Duration(days: 1)));
    final daysEnrolled = DateTime.now().difference(joinDate).inDays.clamp(1, 99999);
    final prevHifzLines = int.tryParse(studentData['prevHifzLines']?.toString() ?? '0') ?? 0;
    final totalMemorized = currentTotalLines;
    final avgPerDay = daysEnrolled > 0 ? totalMemorized / daysEnrolled : 0.0;

    // Month gain calculation
    final selectedMonthStart = DateTime(_selectedYear, _selectedMonth, 1);
    final monthKeyStr = DateFormat('yyyy-MM').format(DateTime(_selectedYear, _selectedMonth));
    final monthLogsFiltered = allLogs.where((l) => l.id.startsWith(monthKeyStr)).toList();

    int prevMonthLines = -1;
    final sortedAllDescLogs = [...allLogs]..sort((a, b) => b.id.compareTo(a.id));
    for (var logDoc in sortedAllDescLogs) {
      final logDate = DateTime.tryParse(logDoc.id);
      if (logDate != null && logDate.isBefore(selectedMonthStart)) {
        final logMap = logDoc.data() as Map<String, dynamic>?;
        final lines = logMap?[widget.studentId]?['currentLines'] as int?;
        if (lines != null && lines > 0) {
          prevMonthLines = lines;
          break;
        }
      }
    }

    int monthGain = 0;
    if (monthLogsFiltered.isNotEmpty) {
      final sortedMonthAsc = [...monthLogsFiltered]..sort((a, b) => a.id.compareTo(b.id));

      final firstMap = sortedMonthAsc.first.data() as Map<String, dynamic>?;
      final firstLogLines = firstMap?[widget.studentId]?['currentLines'] as int?;

      final lastMap = sortedMonthAsc.last.data() as Map<String, dynamic>?;
      final lastLogLines = lastMap?[widget.studentId]?['currentLines'] as int?;

      final int startLines = (prevMonthLines != -1)
          ? prevMonthLines
          : (firstLogLines ?? prevHifzLines);

      final int endLines = (lastLogLines != null) ? lastLogLines : currentTotalLines;

      monthGain = (endLines - startLines).clamp(0, 8640);
    }

    // Congrats & nearing completion
    final isHifzCompleted = currentTotalLines >= 8640 || studentData['status'] == 'hifz_completed';
    Widget? congratsCard;
    if (isHifzCompleted) {
      DateTime completionDate = DateTime.now();
      if (studentData['hifzCompletionDate'] != null) {
        completionDate = (studentData['hifzCompletionDate'] as Timestamp).toDate();
      } else {
        DateTime? earliest;
        for (var logDoc in allLogs) {
          final d = DateTime.tryParse(logDoc.id);
          if (d != null) {
            final log = logDoc.data() as Map<String, dynamic>?;
            final lines = log?[widget.studentId]?['currentLines'] as int?;
            if (lines != null && lines >= 8640 && (earliest == null || d.isBefore(earliest))) { earliest = d; }
          }
        }
        if (earliest != null) completionDate = earliest;
      }
      congratsCard = _buildCongratulatoryCard(joinDate: joinDate, completionDate: completionDate, studentName: studentData['name'] ?? 'the student');
    }
    final nearingBanner = _buildNearingCompletionBanner(currentTotalLines, studentData['name'] ?? '');

    // Fee data
    final due = (fee['amountDue'] as num?)?.toDouble() ?? 0.0;
    final attSavings = (fee['attSavings'] as num?)?.toDouble() ?? 0.0;
    final uniSavings = (fee['uniSavings'] as num?)?.toDouble() ?? 0.0;
    final msgSavings = (fee['msgSavings'] as num?)?.toDouble() ?? 0.0;
    final ptmSavings = (fee['ptmSavings'] as num?)?.toDouble() ?? 0.0;
    final proRatedBaseFee = (fee['proRatedBaseFee'] as num?)?.toDouble() ?? 0.0;
    final totalSavings = (fee['totalSavings'] as num?)?.toDouble() ?? 0.0;
    final activeWorkingDays = (fee['activeWorkingDays'] as num?)?.toInt() ?? 0;
    final joinDateVal = studentData['joinDate'] != null ? _parseDateTime(studentData['joinDate']) : null;
    final isProRated = proRatedBaseFee < displayConfig.baseFee;
    final joinDateStr = joinDateVal != null
        ? (context.isUrdu ? DateFormat('dd-MM-yyyy').format(joinDateVal) : DateFormat('dd MMMM yyyy').format(joinDateVal))
        : '';

    // Fee widgets (for tabs 0 and 3)
    Widget buildFeeMonthSelector() => _buildMonthSelector();

    Widget buildAmountDueCard() => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: due > 0 ? ParentReportCard.errorColor.withOpacity(0.08) : ParentReportCard.successColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: due > 0 ? ParentReportCard.errorColor.withOpacity(0.2) : ParentReportCard.successColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('Amount Due'), style: TextStyle(color: due > 0 ? ParentReportCard.errorColor : ParentReportCard.successColor, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: context.isUrdu ? 'Noori' : null)),
            const SizedBox(height: 4),
            Text(_formatMonthYear(DateTime(_selectedYear, _selectedMonth)), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null)),
          ]),
          Text(context.isUrdu ? 'روپے ${due.toStringAsFixed(0)}' : 'Rs. ${due.toStringAsFixed(0)}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: due > 0 ? ParentReportCard.errorColor : ParentReportCard.successColor, fontFamily: context.isUrdu ? 'Noori' : null)),
        ],
      ),
    );

    Widget buildSavingsTile(String label, double amount, Color color, IconData icon) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.12))),
        child: Row(children: [
          Icon(icon, size: 20, color: color), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t(label), style: TextStyle(fontSize: 11, color: ParentReportCard.textMutedColor, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
            const SizedBox(height: 4),
            Text(context.isUrdu ? 'روپے ${amount.toStringAsFixed(0)}-' : '-Rs. ${amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color, fontFamily: context.isUrdu ? 'Noori' : null)),
          ])),
        ]),
      );
    }

    Widget buildSavingsGrid() => Column(children: [
      Row(children: [
        Expanded(child: buildSavingsTile('Attendance', attSavings, Colors.green, Icons.calendar_today)),
        const SizedBox(width: 12),
        Expanded(child: buildSavingsTile('Uniform', uniSavings, Colors.blue, Icons.checkroom)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: buildSavingsTile('Teacher Response', msgSavings, Colors.purple, Icons.chat_bubble_outline)),
        const SizedBox(width: 12),
        Expanded(child: buildSavingsTile('PTM Meeting', ptmSavings, Colors.orange, Icons.people_outline)),
      ]),
    ]);

    Widget buildVisualFlowCard() => Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ParentReportCard.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.t('Fee Calculation Flow'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null)),
        const SizedBox(height: 20),
        _buildFlowStep(title: context.t('Pro-rated Base Fee'), subtitle: context.isUrdu ? 'سرگرم داخلہ: $activeWorkingDays تعلیمی دن' : 'Active enrollment: $activeWorkingDays working days', amount: context.isUrdu ? 'روپے ${proRatedBaseFee.toStringAsFixed(0)}' : 'Rs. ${proRatedBaseFee.toStringAsFixed(0)}', color: ParentReportCard.textPrimaryColor, icon: Icons.account_balance),
        if (isProRated && joinDateVal != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade200)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900), const SizedBox(width: 8),
              Expanded(child: Text(context.isUrdu ? 'بنیادی فیس (عام طور پر روپے ${displayConfig.baseFee.toStringAsFixed(0)}) تناسب کی بنیاد پر ہے کیونکہ طالب علم کی شمولیت کی تاریخ $joinDateStr ہے۔' : 'Base fee (Rs. ${displayConfig.baseFee.toStringAsFixed(0)} standard) is pro-rated because the student joined on $joinDateStr.', style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null))),
            ]),
          ),
        ],
        const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Icon(Icons.remove_circle_outline, color: ParentReportCard.errorColor, size: 20))),
        _buildFlowStep(title: context.t('Total Savings / Deductions'), subtitle: context.t('Combined rewards for attendance, behavior & PTM'), amount: context.isUrdu ? 'روپے ${totalSavings.toStringAsFixed(0)}-' : '-Rs. ${totalSavings.toStringAsFixed(0)}', color: Colors.green, icon: Icons.savings_outlined),
        const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Icon(Icons.drag_handle, color: ParentReportCard.textMutedColor, size: 20))),
        _buildFlowStep(
          title: context.t('Final Net Amount Due'),
          subtitle: context.isUrdu ? 'مہینہ برائے ${_formatMonth(DateTime(_selectedYear, _selectedMonth))} جمع کرائی گئی' : 'Submitted for the month of ${DateFormat('MMMM').format(DateTime(_selectedYear, _selectedMonth))}',
          amount: context.isUrdu ? 'روپے ${due.toStringAsFixed(0)}' : 'Rs. ${due.toStringAsFixed(0)}',
          color: due > 0 ? ParentReportCard.errorColor : ParentReportCard.successColor,
          icon: Icons.receipt,
          isFinal: true,
        ),
      ]),
    );

    Widget buildHeaderRow() => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(context.t('Monthly Statement'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ParentReportCard.textPrimaryColor, fontFamily: context.isUrdu ? 'Noori' : null)),
        ExportButton(
          onExcel: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('Preparing your Excel report...')), backgroundColor: ParentReportCard.primaryColor));
            MadrassaReportHelper.exportIndividualExcel(config: displayConfig, studentId: widget.studentId, studentData: studentData, logs: monthLogs, holidays: holidays);
          },
          onPdf: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('Preparing your PDF report...')), backgroundColor: ParentReportCard.primaryColor));
            MadrassaReportHelper.exportIndividualPdf(config: displayConfig, studentId: widget.studentId, studentData: studentData, logs: monthLogs, holidays: holidays);
          },
          isSmall: true,
        ),
      ],
    );

    Widget buildBackBar(String pageTitle) => Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: () => setState(() => _selectedTab = 0),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(
              context.isUrdu ? 'ڈیش بورڈ' : 'Back',
              style: TextStyle(fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: ParentReportCard.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              pageTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: ParentReportCard.textPrimaryColor,
                fontFamily: context.isUrdu ? 'Noori' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    switch (selectedTab) {
      case 0:
        return _buildDashboardTab(
          isDesktop: isDesktop,
          isTablet: isTablet,
          todaySLog: todaySLog,
          selectedDateLog: selectedDateLog,
          isPtmForSelectedDate: isPtmForSelectedDate,
          currentStatus: currentStatus,
          leaveStatus: leaveStatus,
          isPtmToday: isPtmToday,
          needsReply: needsReply,
          allLogs: allLogs,
          monthLogs: monthLogsFiltered,
          holidaysData: holidaysData,
          config: config,
          due: due,
          totalSavings: totalSavings,
          proRatedBaseFee: proRatedBaseFee,
          currentTotalLines: currentTotalLines,
          monthGain: monthGain,
          estCompletionStr: estCompletionStr,
          paceWeekly: paceWeekly,
          overallPace: overallPace,
          daysRemaining: daysRemaining,
          fee: fee,
          congratsCard: congratsCard,
          nearingBanner: nearingBanner,
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildBackBar(context.isUrdu ? 'حاضری' : 'Attendance'),
            Row(
              children: [
                Expanded(child: _buildMonthSelector()),
                const SizedBox(width: 12),
                ExportButton(
                  onExcel: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('Preparing your Excel report...')), backgroundColor: ParentReportCard.primaryColor));
                    MadrassaReportHelper.exportIndividualExcel(config: displayConfig, studentId: widget.studentId, studentData: studentData, logs: monthLogs, holidays: holidays);
                  },
                  onPdf: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('Preparing your PDF report...')), backgroundColor: ParentReportCard.primaryColor));
                    MadrassaReportHelper.exportIndividualPdf(config: displayConfig, studentId: widget.studentId, studentData: studentData, logs: monthLogs, holidays: holidays);
                  },
                  isSmall: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _AttendanceCalendar(
              studentId: widget.studentId,
              logs: allLogs,
              year: _selectedYear,
              month: _selectedMonth,
              config: config,
              selectedDate: _selectedDate,
              onDateSelected: (d) => setState(() => _selectedDate = d),
              holidaysData: holidaysData,
            ),
            const SizedBox(height: 16),
            _buildDailyDetailsCard(allLogs, holidaysData, config),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildBackBar(context.t('Quran Majeed Hifz Progress')),
            _buildQuranProgressCard(
              currentTotalLines: currentTotalLines,
              monthGain: monthGain,
              paceWeekly: paceWeekly,
              overallPace: overallPace,
              daysRemaining: daysRemaining,
              estCompletionStr: estCompletionStr,
              selectedDateLog: selectedDateLog,
            ),
            const SizedBox(height: 16),
            _buildCombinedProgressTab(
              isDesktop: isDesktop,
              isTablet: isTablet,
              allLogs: allLogs,
              holidaysData: holidaysData,
              config: config,
              displayConfig: displayConfig,
              currentTotalLines: currentTotalLines,
              monthGain: monthGain,
              paceWeekly: paceWeekly,
              overallPace: overallPace,
              daysRemaining: daysRemaining,
              estCompletionStr: estCompletionStr,
              congratsCard: congratsCard,
              nearingBanner: nearingBanner,
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildBackBar(context.t('Fee Statement & Breakdown')),
            _buildFeesTab(
              isDesktop: isDesktop,
              isTablet: isTablet,
              due: due,
              totalSavings: totalSavings,
              proRatedBaseFee: proRatedBaseFee,
              monthSelector: buildFeeMonthSelector(),
              headerRow: buildHeaderRow(),
              amountDueCard: buildAmountDueCard(),
              savingsGrid: buildSavingsGrid(),
              visualFlowCard: buildVisualFlowCard(),
              fee: fee,
              monthLogs: monthLogs,
              holidays: holidays,
              displayConfig: displayConfig,
            ),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildBackBar(context.t('Account & Guardian Profile')),
            _buildAccountTab(
              isDesktop: isDesktop,
              isTablet: isTablet,
              status: status,
              rejoinRequestStatus: rejoinRequestStatus,
              rejoinReason: rejoinReason,
              rejoinDate: rejoinDate,
              auditList: auditList,
            ),
          ],
        );
      case 5:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildBackBar(context.isUrdu ? 'رخصت اور جوابات کی درخواستیں' : 'Leave & Reply Requests'),
            _buildRequestsTab(
              allLogs: allLogs,
              isParentView: widget.isParentView,
              studentId: widget.studentId,
              branchId: widget.branchId,
            ),
          ],
        );
      default:
        return const SizedBox();
    }
  }

  Future<void> _approveLeaveRequest(String branchId, String dateStr, String targetStudentId) async {
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('madrassa_daily_logs')
        .doc(dateStr)
        .set({
      targetStudentId: {
        'attendance': 'leave',
        'leaveStatus': 'approved',
        'leaveApprovedBy': studentData['guardianName'] ?? 'Teacher',
        'leaveApprovalTime': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  Future<void> _denyLeaveRequest(String branchId, String dateStr, String targetStudentId) async {
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('madrassa_daily_logs')
        .doc(dateStr)
        .set({
      targetStudentId: {
        'attendance': 'absent',
        'leaveStatus': 'denied',
        'leaveDeniedBy': studentData['guardianName'] ?? 'Teacher',
        'leaveDenialTime': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  Widget _buildRequestsTab({
    required List<QueryDocumentSnapshot> allLogs,
    required bool isParentView,
    required String studentId,
    required String branchId,
  }) {
    final List<Map<String, dynamic>> requestsList = [];

    for (final logDoc in allLogs) {
      final dateStr = logDoc.id;
      final rawData = logDoc.data() as Map<String, dynamic>?;
      if (rawData == null) continue;

      rawData.forEach((stId, val) {
        if (val is Map) {
          final studentDataMap = Map<String, dynamic>.from(val);
          final attendance = studentDataMap['attendance']?.toString();
          final leaveStatus = studentDataMap['leaveStatus']?.toString() ?? (attendance == 'leave' ? 'approved' : 'pending');
          final hasLeaveRequest = attendance == 'leave_requested' || attendance == 'leave' || studentDataMap.containsKey('leaveReason');
          final parentReplied = studentDataMap['parentReplied'] == true || studentDataMap.containsKey('parentReplyText') || studentDataMap.containsKey('parentReplyMessage');

          if (isParentView && stId != studentId) return;

          final studentName = stId == widget.studentId
              ? (studentData['name'] ?? 'Student')
              : (studentDataMap['name'] ?? 'Student ($stId)');

          if (hasLeaveRequest) {
            DateTime reqDate;
            final ts = studentDataMap['timestamp'];
            if (ts is Timestamp) {
              reqDate = ts.toDate();
            } else {
              reqDate = DateTime.tryParse(dateStr) ?? DateTime.now();
            }

            requestsList.add({
              'id': '${dateStr}_leave_$stId',
              'type': 'leave',
              'dateStr': dateStr,
              'date': reqDate,
              'studentId': stId,
              'studentName': studentName,
              'reason': studentDataMap['leaveReason'] ?? (context.isUrdu ? 'رخصت کی درخواست' : 'Leave Request'),
              'status': leaveStatus,
            });
          }

          if (parentReplied) {
            DateTime reqDate;
            final ts = studentDataMap['parentReplyTime'] ?? studentDataMap['timestamp'];
            if (ts is Timestamp) {
              reqDate = ts.toDate();
            } else {
              reqDate = DateTime.tryParse(dateStr) ?? DateTime.now();
            }

            requestsList.add({
              'id': '${dateStr}_reply_$stId',
              'type': 'reply',
              'dateStr': dateStr,
              'date': reqDate,
              'studentId': stId,
              'studentName': studentName,
              'reason': studentDataMap['parentReplyText'] ?? studentDataMap['parentReplyMessage'] ?? (context.isUrdu ? 'استاد کو جواب بھیجا گیا' : 'Reply sent to teacher'),
              'status': 'approved',
            });
          }
        }
      });
    }

    requestsList.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

    final filtered = requestsList.where((r) {
      if (_requestStatusFilter == 'all') return true;
      return r['status'] == _requestStatusFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('all', context.isUrdu ? 'تمام (${requestsList.length})' : 'All (${requestsList.length})'),
              const SizedBox(width: 8),
              _filterChip('pending', context.isUrdu ? 'زیر التوا (Pending)' : 'Pending'),
              const SizedBox(width: 8),
              _filterChip('approved', context.isUrdu ? 'منظور شدہ (Approved)' : 'Approved'),
              const SizedBox(width: 8),
              _filterChip('denied', context.isUrdu ? 'مسترد شدہ (Denied)' : 'Denied'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                const Icon(Icons.inbox_rounded, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  context.isUrdu ? 'کوئی درخواست نہیں ملی' : 'No requests found',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final req = filtered[i];
              final isLeave = req['type'] == 'leave';
              final status = req['status'] as String;
              final reqDate = req['date'] as DateTime;
              final dateFormatted = DateFormat('dd MMM yyyy, hh:mm a').format(reqDate);

              Color statusColor;
              String statusLabel;
              if (status == 'approved') {
                statusColor = ParentReportCard.successColor;
                statusLabel = context.isUrdu ? 'منظور شدہ' : 'Approved';
              } else if (status == 'denied') {
                statusColor = ParentReportCard.errorColor;
                statusLabel = context.isUrdu ? 'مسترد' : 'Denied';
              } else {
                statusColor = Colors.orange;
                statusLabel = context.isUrdu ? 'زیر التوا' : 'Pending';
              }

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isLeave ? Icons.email_rounded : Icons.reply_rounded,
                            color: statusColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isLeave
                                    ? (context.isUrdu ? 'رخصت کی درخواست' : 'Leave Request')
                                    : (context.isUrdu ? 'جواب کی تصدیق' : 'Reply Verification'),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: ParentReportCard.textPrimaryColor,
                                  fontFamily: context.isUrdu ? 'Noori' : null,
                                ),
                              ),
                              Text(
                                '${req['studentName']} • ${req['dateStr']}',
                                style: const TextStyle(fontSize: 12, color: ParentReportCard.textMutedColor),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      req['reason'],
                      style: TextStyle(
                        fontSize: 13,
                        color: ParentReportCard.textPrimaryColor,
                        fontFamily: context.isUrdu ? 'Noori' : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          dateFormatted,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        if (!isParentView && status == 'pending' && isLeave)
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _approveLeaveRequest(branchId, req['dateStr'], req['studentId']),
                                icon: const Icon(Icons.check, size: 14, color: Colors.green),
                                label: Text(context.isUrdu ? 'منظور کریں' : 'Approve', style: const TextStyle(color: Colors.green, fontSize: 12)),
                              ),
                              TextButton.icon(
                                onPressed: () => _denyLeaveRequest(branchId, req['dateStr'], req['studentId']),
                                icon: const Icon(Icons.close, size: 14, color: Colors.red),
                                label: Text(context.isUrdu ? 'مسترد کریں' : 'Deny', style: const TextStyle(color: Colors.red, fontSize: 12)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _filterChip(String filterVal, String label) {
    final selected = _requestStatusFilter == filterVal;
    return ChoiceChip(
      selected: selected,
      selectedColor: ParentReportCard.primaryColor,
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : ParentReportCard.textPrimaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      onSelected: (_) => setState(() => _requestStatusFilter = filterVal),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('madrassa_students')
          .doc(widget.studentId)
          .snapshots(),
      builder: (context, studentSnap) {
        // Update live student data when stream emits
        if (studentSnap.hasData && studentSnap.data != null && studentSnap.data!.exists) {
          final data = studentSnap.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            _liveStudentData = data;
          }
        }

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
                  studentData: studentData,
                  logs: monthLogs,
                  config: displayConfig,
                  totalWorkingDays: workingDays,
                  holidays: holidays,
                );


                final estData = _calculateEstimationData(allLogs);
                final int currentTotalLines = estData['totalMemorized'] as int;
                final double paceWeekly = estData['paceWeekly'] as double;
                final double overallPace = estData['recentDailyRate'] as double;
                final double daysRemaining = estData['daysRemaining'] as double;
                final String estCompletionStr = estData['estCompletionStr'] as String;

                final status = studentData['status'] ?? 'active';
                final rejoinRequestStatus = studentData['rejoinRequestStatus'];
                final rejoinReason = studentData['rejoinRequestReason'];
                final rejoinDate = studentData['rejoinRequestDate'] as Timestamp?;


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

                // ── NEW: selected-date log, used by Hero Banner + Status Pills ──
                final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
                Map<String, dynamic> selectedDateLog = {};
                try {
                  final selDoc = allLogs.firstWhere((l) => l.id == selectedDateStr);
                  final sData = selDoc.data() as Map<String, dynamic>?;
                  selectedDateLog = (sData?[widget.studentId] is Map ? sData![widget.studentId] as Map<String, dynamic> : {});
                } catch (_) {}

                final isPtmForSelectedDate = _selectedDate.year == ptmDate.year &&
                    _selectedDate.month == ptmDate.month &&
                    _selectedDate.day == ptmDate.day;
                // needsReply should reflect the SELECTED date's reply state,
                // so that when a teacher unmarks a reply, the parent sees
                // "Reply to Teacher" appear again for that date.
                final selectedDateParentReplied = selectedDateLog['parentReplied'] == true;
                final needsReply = status == 'active' && !selectedDateParentReplied && (selectedDateLog['attendance']?.toString() ?? currentStatus) == 'present';
                final leaveStatus = todaySLog['leaveStatus'] ?? 'pending';

                final holidaysData = (holidaySnap.data!.docs).map((d) {
                  final date = (d['date'] as Timestamp).toDate();
                  final name = d.data() is Map && (d.data() as Map).containsKey('name') ? d['name']?.toString() ?? 'Holiday' : 'Holiday';
                  return {'date': date, 'name': name};
                }).toList();

                final rawAudit = studentData['auditLog'];
                final auditListRaw = rawAudit is List ? rawAudit : [];
                final auditList = List<Map<String, dynamic>>.from(
                  auditListRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
                );

                final currentUser = FirebaseAuth.instance.currentUser;
                final guardianUsername = currentUser?.email ??
                    studentData['guardianEmail']?.toString() ??
                    studentData['contactPhone']?.toString() ??
                    studentData['guardianName']?.toString() ?? '';

                return Scaffold(
                  backgroundColor: ParentReportCard.surfaceColor,
                  appBar: AppBar(
                    backgroundColor: ParentReportCard.primaryColor,
                    elevation: 0,
                    iconTheme: const IconThemeData(color: Colors.white),
                    leading: widget.onBackToSummary != null
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            tooltip: context.t('Back to Family Summary'),
                            onPressed: widget.onBackToSummary,
                          )
                        : Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Image.asset('assets/logo/gmwf-1.webp', fit: BoxFit.contain),
                          ),
                    title: widget.allDocs.length <= 1
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.isUrdu ? 'پورٹل سرپرست' : 'Guardian Portal',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontFamily: context.isUrdu ? 'Noori' : null,
                                ),
                              ),
                              if (guardianUsername.isNotEmpty)
                                Text(
                                  guardianUsername,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: widget.selectedIndex,
                              dropdownColor: ParentReportCard.primaryColor,
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                              isExpanded: true,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              selectedItemBuilder: (BuildContext context) {
                                return widget.allDocs.map<Widget>((doc) {
                                  final d = doc.data() as Map<String, dynamic>? ?? {};
                                  final name = d['name'] ?? 'Student';
                                  return Text(
                                    name,
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: context.isUrdu ? 'Noori' : null),
                                    overflow: TextOverflow.ellipsis,
                                  );
                                }).toList();
                              },
                              items: List.generate(widget.allDocs.length, (index) {
                                final d = widget.allDocs[index];
                                final dData = d.data() as Map<String, dynamic>? ?? {};
                                final name = dData['name'] ?? 'Student';
                                return DropdownMenuItem<int>(
                                  value: index,
                                  child: Text(name, style: const TextStyle(color: Colors.white)),
                                );
                              }),
                              onChanged: (val) {
                                if (val != null) {
                                  widget.onStudentChanged(val);
                                }
                              },
                            ),
                          ),
                    actions: [
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedTab = _selectedTab == 4 ? 0 : 4;
                          });
                        },
                        icon: Icon(
                          _selectedTab == 4 ? Icons.home_rounded : Icons.account_circle_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _selectedTab == 4
                              ? (context.isUrdu ? 'ہوم' : 'Home')
                              : (context.isUrdu ? 'اکاؤنٹ' : 'Accounts'),
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: context.isUrdu ? 'Noori' : null),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedTab == 4 ? ParentReportCard.accentColor : Colors.white.withValues(alpha: 0.2),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                  body: LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth > 900;
                      final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth <= 900;

                      return SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 32 : (isTablet ? 24 : 16),
                          vertical: 20,
                        ),
                        child: Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: _buildTabContent(
                              _selectedTab,
                              isDesktop: isDesktop,
                              isTablet: isTablet,
                              todaySLog: todaySLog,
                              selectedDateLog: selectedDateLog,
                              isPtmForSelectedDate: isPtmForSelectedDate,
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
                              paceWeekly: paceWeekly,
                              overallPace: overallPace,
                              daysRemaining: daysRemaining,
                              estCompletionStr: estCompletionStr,
                              status: status,
                              rejoinRequestStatus: rejoinRequestStatus,
                              rejoinReason: rejoinReason,
                              rejoinDate: rejoinDate,
                              auditList: auditList,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
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
      (const Color(0xFFECEFF1), 'Sunday', null, false, false),
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
  final int year;
  final int month;
  final MadrassaConfig config;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final List<Map<String, dynamic>> holidaysData;

  const _AttendanceCalendar({
    super.key,
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
                if (rawData is Map && rawData[studentId] is Map) {
                  statusData = Map<String, dynamic>.from(rawData[studentId] as Map);
                }
              } catch (_) {}

              Color bg = const Color(0xFFF1F4F9);
              Color textCol = Colors.grey.shade400;
              bool ptmAttended = statusData?['ptm'] == true;
              final isSunday = date.weekday == DateTime.sunday;
              bool isAbsent = false;

              final att = statusData?['attendance']?.toString();
              if (isHoliday) {
                bg = const Color(0xFFE0F2F1);
                textCol = const Color(0xFF00796B);
              } else if (att == 'present') {
                bg = const Color(0xFFE8F5E9);
                textCol = const Color(0xFF2E7D32);
              } else if (att == 'leave' || att == 'leave_requested') {
                bg = const Color(0xFFFFF3E0);
                textCol = const Color(0xFFEF6C00);
              } else if (att == 'absent') {
                bg = const Color(0xFFFFEBEE);
                textCol = const Color(0xFFDC2626);
                isAbsent = true;
              } else if (isPast && !isSunday) {
                bg = const Color(0xFFFFEBEE);
                textCol = const Color(0xFFDC2626);
                isAbsent = true;
              } else if (isSunday) {
                bg = const Color(0xFFECEFF1);
                textCol = Colors.grey.shade500;
              }

              BoxDecoration decoration = BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: isSelectedDate
                    ? Border.all(color: ParentReportCard.primaryColor, width: 2.5)
                    : (isAbsent
                        ? Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.5), width: 1.2)
                        : (isToday ? Border.all(color: ParentReportCard.accentColor.withValues(alpha: 0.5), width: 1.5) : null)),
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
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$day', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textCol)),
                          if (isAbsent) ...[
                            const SizedBox(height: 1),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                context.isUrdu ? 'غائب' : 'ABSENT',
                                style: const TextStyle(fontSize: 6.5, fontWeight: FontWeight.w900, color: Color(0xFFDC2626)),
                              ),
                            ),
                          ],
                        ],
                      ),
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