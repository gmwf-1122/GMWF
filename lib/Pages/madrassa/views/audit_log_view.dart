import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:gmwf/design/tokens/comfort_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/madrassa_common_widgets.dart';
import '../madrassa_strings.dart';

class AuditLogView extends StatefulWidget {
  final String branchId;
  const AuditLogView({super.key, required this.branchId});

  @override
  State<AuditLogView> createState() => _AuditLogViewState();
}

class _AuditLogViewState extends State<AuditLogView> {
  final List<DocumentSnapshot> _logs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMoreLogs();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMoreLogs();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMoreLogs() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Query query = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('madrassa_audit_logs')
          .orderBy('timestamp', descending: true)
          .limit(20);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final querySnapshot = await query.get();

      if (querySnapshot.docs.length < 20) {
        _hasMore = false;
      }

      if (querySnapshot.docs.isNotEmpty) {
        _lastDocument = querySnapshot.docs.last;
        setState(() {
          _logs.addAll(querySnapshot.docs);
        });
      }
    } catch (e) {
      debugPrint('Error loading audit logs: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes minute${minutes == 1 ? '' : 's'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hour${hours == 1 ? '' : 's'} ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days day${days == 1 ? '' : 's'} ago';
    } else {
      return DateFormat('yyyy-MM-dd').format(dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.adapt(SoftPalette.gray50),
      appBar: AppBar(
        title: Text(
          context.l.auditLog,
          style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        backgroundColor: context.adapt(SoftPalette.gray50),
        foregroundColor: context.adapt(SoftPalette.gray900),
        elevation: 0.5,
      ),
      body: _logs.isEmpty && _isLoading
          ? Center(child: CircularProgressIndicator(color: context.adapt(SoftPalette.indigo550)))
          : _logs.isEmpty
              ? Center(
                  child: Text(
                    context.l.noData,
                    style: context.urduStyle(style: TextStyle(color: context.adapt(SoftPalette.gray350))),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _logs.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _logs.length) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(child: CircularProgressIndicator(color: context.adapt(SoftPalette.indigo550))),
                      );
                    }

                    final doc = _logs[index];
                    final log = doc.data() as Map<String, dynamic>? ?? {};
                    final editor = log['editor'] ?? 'System';
                    final role = log['role'] ?? '';
                    final message = log['message'] ?? '';
                    final timestampObj = log['timestamp'];

                    DateTime? timestamp;
                    if (timestampObj is Timestamp) {
                      timestamp = timestampObj.toDate();
                    } else if (timestampObj is String) {
                      timestamp = DateTime.tryParse(timestampObj);
                    }

                    final timeStr = timestamp != null ? _formatRelativeTime(timestamp) : '';
                    String title = editor;
                    IconData icon = Icons.info_outline;
                    Color color = context.adapt(SoftPalette.blue400);

                    final type = log['type'] ?? '';
                    if (type == 'ptm_reschedule') {
                      icon = Icons.notification_important_rounded;
                      color = context.adapt(SoftPalette.red400);
                    } else if (type == 'daily_log_edit') {
                      icon = Icons.edit_calendar_rounded;
                      color = context.adapt(SoftPalette.indigo600);
                    } else if (type == 'status_change') {
                      icon = Icons.swap_horiz_rounded;
                      color = context.adapt(SoftPalette.amber300);
                    } else if (type == 'config_change') {
                      icon = Icons.settings_rounded;
                      color = context.adapt(SoftPalette.teal500);
                    } else if (type == 'student_enrollment') {
                      icon = Icons.person_add_rounded;
                      color = context.adapt(SoftPalette.green400);
                    } else if (type == 'student_edit') {
                      icon = Icons.edit_note_rounded;
                      color = context.adapt(SoftPalette.slate500);
                    }

                    return buildActivityItem(context, title, message, timeStr, icon, color, role: role);
                  },
                ),
    );
  }
}
