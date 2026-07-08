import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/madrassa_config.dart';
import 'audit_log_view.dart';
import '../madrassa_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/madrassa_providers.dart';

// Breakpoints for responsive dashboard sizing
const double kMobileBreakpoint = 600.0;
const double kTabletBreakpoint = 900.0;

class MadrassaOverviewView extends ConsumerWidget {
  final String branchId;
  final Function(int)? onAction;
  final bool isAdmin;

  const MadrassaOverviewView({
    super.key,
    required this.branchId,
    required this.isAdmin,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: Full dark mode theme support integration
    final configAsync = ref.watch(madrassaConfigProvider(branchId));
    final studentsAsync = ref.watch(madrassaStudentsProvider(branchId));

    return configAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFF4C4DDC)),
      ),
      error: (e, st) => Center(child: Text('Error loading config: $e')),
      data: (config) {
        return studentsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF4C4DDC)),
          ),
          error: (e, st) => Center(child: Text('Error loading students: $e')),
          data: (allStudents) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWelcomeHeader(context),
                  const SizedBox(height: 32),
                  _buildRealtimeStatGrid(context, ref),
                  const SizedBox(height: 32),
                  _buildQuickActions(context),
                  const SizedBox(height: 32),
                  _buildRecentActivity(context),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWelcomeHeader(BuildContext context) {
    // Localized formatted current date with safe fallback
    String formattedDate;
    try {
      formattedDate = DateFormat.yMMMMEEEEd(context.isUrdu ? 'ur' : 'en').format(DateTime.now());
    } catch (_) {
      formattedDate = DateFormat.yMMMMEEEEd().format(DateTime.now());
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < kMobileBreakpoint;

          final mosqueBadge = Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mosque,
              color: Colors.white,
              size: 28,
            ),
          );

          final titleText = Text(
            context.l.overviewTitle,
            style: context.urduStyle(
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          );

          final subtitleText = Text(
            context.l.appSubtitle,
            style: context.urduStyle(
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.85),
              ),
            ),
          );

          final dateChip = Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  formattedDate,
                  style: context.urduStyle(
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );

          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    mosqueBadge,
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
                const SizedBox(height: 16),
                dateChip,
              ],
            );
          } else {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      mosqueBadge,
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
                dateChip,
              ],
            );
          }
        },
      ),
    );
  } // End of _buildWelcomeHeader

  // Rewritten realtime stat grid with individual StreamBuilders and placeholders
   Widget _buildRealtimeStatGrid(BuildContext context, WidgetRef ref) {
     final theme = Theme.of(context);

     // Helper placeholder card
     Widget placeholderCard(String label) {
       return Container(
         padding: const EdgeInsets.all(16),
         decoration: BoxDecoration(
           color: theme.cardColor,
           borderRadius: BorderRadius.circular(20),
           boxShadow: [
             BoxShadow(
               color: const Color(0xFF1A1C1E).withOpacity(0.06),
               blurRadius: 12,
               offset: const Offset(0, 4),
             ),
           ],
         ),
         child: Center(
           child: SizedBox(
             width: 24,
             height: 24,
             child: CircularProgressIndicator(strokeWidth: 2, color: theme.primaryColor),
           ),
         ),
       );
     }

     // Determine grid layout
     return LayoutBuilder(
       builder: (context, constraints) {
         final width = constraints.maxWidth;
         final int crossAxisCount;
         final double childAspectRatio;

         if (width < kMobileBreakpoint) {
           crossAxisCount = 2;
           childAspectRatio = 1.4;
         } else if (width < kTabletBreakpoint) {
           crossAxisCount = 3;
           childAspectRatio = 1.3;
         } else {
           crossAxisCount = 4;
           childAspectRatio = 1.2;
         }

         final studentsAsync = ref.watch(madrassaStudentsProvider(branchId));
         final configAsync = ref.watch(madrassaConfigProvider(branchId));
         final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
         final dailyLogAsync = ref.watch(madrassaDailyLogProvider((branchId: branchId, dateKey: dateKey)));

         return GridView.count(
           crossAxisCount: crossAxisCount,
           shrinkWrap: true,
           physics: const NeverScrollableScrollPhysics(),
           mainAxisSpacing: 16,
           crossAxisSpacing: 16,
           childAspectRatio: childAspectRatio,
           children: [
             // Students Card
             studentsAsync.when(
               loading: () => placeholderCard(context.l.totalStudents),
               error: (_, __) => _statCard(context, context.l.totalStudents, '0', Icons.people_alt_rounded, 210),
               data: (students) {
                 final activeCount = students.where((d) {
                   final statusVal = d['status'];
                   return (statusVal == null || statusVal == '')
                       ? (d['active'] == true)
                       : (statusVal == 'active');
                 }).length;
                 return _statCard(
                   context,
                   context.l.totalStudents,
                   '$activeCount',
                   Icons.people_alt_rounded,
                   210,
                 );
               },
             ),
             // Attendance/Daily Log Card
             dailyLogAsync.when(
               loading: () => placeholderCard(context.l.dailyLogTitle),
               error: (_, __) => _statCard(context, context.l.dailyLogTitle, '0 / 0', Icons.edit_calendar_rounded, 160),
               data: (logData) {
                 final totalActive = studentsAsync.value?.where((d) {
                   final statusVal = d['status'];
                   return (statusVal == null || statusVal == '')
                       ? (d['active'] == true)
                       : (statusVal == 'active');
                 }).length ?? 0;
                 
                 int present = 0;
                 logData.forEach((k, v) {
                   if (v is Map && v['attendance'] == 'present') present++;
                 });
                 return _statCard(context, context.l.dailyLogTitle, '$present / $totalActive', Icons.edit_calendar_rounded, 160);
               },
             ),
             // PTM Card
             configAsync.when(
               loading: () => placeholderCard(context.l.ptmDay),
               error: (_, __) => _statCard(context, context.l.ptmDay, '-', Icons.event_available_rounded, 280),
               data: (config) => _statCard(context, context.l.ptmDay, DateFormat('MMM d').format(config.getPtmDate()), Icons.event_available_rounded, 280),
             ),
             // Fees Card
             configAsync.when(
               loading: () => placeholderCard(context.l.baseFeeLabel),
               error: (_, __) => _statCard(context, context.l.baseFeeLabel, '-', Icons.account_balance_wallet_rounded, 35),
               data: (config) => _statCard(context, context.l.baseFeeLabel, 'Rs. ${config.baseFee.toInt()}', Icons.account_balance_wallet_rounded, 35),
             ),
           ],
         );
       },
     );
   }

  Widget _statCard(BuildContext context, String label, String value, IconData icon, double hue) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Derived HSL colors
    final accentColor = HSLColor.fromAHSL(1.0, hue, 0.65, 0.45).toColor();
    final bgTint = HSLColor.fromAHSL(1.0, hue, 0.65, 0.94).toColor();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1C1E).withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bgTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A1C1E),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.urduStyle(
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Enumerate quick actions and their navigation destinations
    final actions = [
      // 1. Daily Log -> attendance/lesson tab (indexes correspond to _selectedIndex in MadrassaDashboard)
      _QuickActionItem(
        title: context.l.dailyLog,
        subtitle: context.isUrdu
            ? "حاضری اور اسباق کی روزانہ رپورٹ درج کریں"
            : "Track attendance and lesson progress",
        icon: Icons.checklist_rounded,
        hue: 220, // Indigo
        onTap: () => onAction?.call(1),
      ),
      if (isAdmin) ...[
        // 2. Monthly Report -> analytical summary/exports (index 3)
        _QuickActionItem(
          title: context.l.monthlyReport,
          subtitle: context.isUrdu
              ? "ماہانہ حاضری، فیس اور کارکردگی کی رپورٹ اور ڈاؤن لوڈ"
              : "Analyze monthly metrics and export PDF/Excel files",
          icon: Icons.analytics_rounded,
          hue: 170, // Teal
          onTap: () => onAction?.call(3),
        ),
        // 3. Configuration -> settings parameters (index 4)
        _QuickActionItem(
          title: context.l.config,
          subtitle: context.isUrdu
              ? "بنیادی فیس، چھٹیوں اور پی ٹی ایم کی تاریخوں کی ترتیبات"
              : "Manage base fees, holiday dates, and PTM timings",
          icon: Icons.settings_suggest_rounded,
          hue: 35, // Orange/Gold
          onTap: () => onAction?.call(4),
        ),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l.todayActions,
          style: context.urduStyle(
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.indigo.shade900,
            ),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < kMobileBreakpoint;
            if (isMobile) {
              return Column(
                children: actions
                    .map((act) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _quickActionCard(context, act),
                        ))
                    .toList(),
              );
            } else {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  mainAxisExtent: 84,
                ),
                itemCount: actions.length,
                itemBuilder: (context, idx) {
                  return _quickActionCard(context, actions[idx]);
                },
              );
            }
          },
        ),
      ],
    );
  }

  Widget _quickActionCard(BuildContext context, _QuickActionItem item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final accentColor = HSLColor.fromAHSL(1.0, item.hue, 0.65, 0.45).toColor();
    final bgTint = HSLColor.fromAHSL(1.0, item.hue, 0.65, 0.94).toColor();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withOpacity(0.12), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A1C1E).withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: bgTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: context.urduStyle(
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A1C1E),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.urduStyle(
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white.withOpacity(0.5) : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('madrassa_audit_logs')
          .orderBy('timestamp', descending: true)
          .limit(10) // Capped at 10 items for comprehensive audit tracking
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.withOpacity(0.12)),
            ),
            child: Text(
              'Error loading activity: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.withOpacity(0.12)),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFF4C4DDC)),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A1C1E).withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.l.auditLog,
                    style: context.urduStyle(
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.indigo.shade900,
                      ),
                    ),
                  ),
                  Icon(Icons.more_horiz, color: isDark ? Colors.white.withOpacity(0.5) : Colors.grey),
                ],
              ),
              const SizedBox(height: 24),
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text(
                      context.l.noData,
                      style: context.urduStyle(style: const TextStyle(color: Colors.grey, fontSize: 14)),
                    ),
                  ),
                )
              else ...[
                ...List.generate(docs.length, (index) {
                  final doc = docs[index];
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
                  Color color = Colors.blue;

                  final type = log['type'] ?? '';
                  if (type == 'ptm_reschedule') {
                    icon = Icons.notification_important_rounded;
                    color = Colors.red;
                  } else if (type == 'daily_log_edit') {
                    icon = Icons.edit_calendar_rounded;
                    color = Colors.indigo;
                  } else if (type == 'status_change') {
                    icon = Icons.swap_horiz_rounded;
                    color = Colors.orange;
                  } else if (type == 'config_change') {
                    icon = Icons.settings_rounded;
                    color = Colors.teal;
                  } else if (type == 'student_enrollment') {
                    icon = Icons.person_add_rounded;
                    color = Colors.green;
                  } else if (type == 'student_edit') {
                    icon = Icons.edit_note_rounded;
                    color = Colors.blueGrey;
                  }

                  final isLast = index == docs.length - 1;

                  return _buildActivityTimelineItem(
                    context: context,
                    title: title,
                    message: message,
                    timeStr: timeStr,
                    timestamp: timestamp,
                    icon: icon,
                    color: color,
                    isLast: isLast,
                    role: role,
                  );
                }),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => AuditLogView(branchId: branchId),
                        ),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                    label: const Text('View All Logs', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF4C4DDC),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivityTimelineItem({
    required BuildContext context,
    required String title,
    required String message,
    required String timeStr,
    required DateTime? timestamp,
    required IconData icon,
    required Color color,
    required bool isLast,
    required String role,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Column: Dot Icon + Vertical Connector Line (via Stack to prevent unbounded constraints)
          SizedBox(
            width: 32,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!isLast)
                  Positioned(
                    top: 16, // middle of the 32x32 dot
                    bottom: 0,
                    width: 2,
                    child: Container(
                      color: isDark ? Colors.white24 : Colors.grey.shade200,
                    ),
                  ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right Column: Timeline Event Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                  border: Border(
                    left: BorderSide(color: color, width: 4),
                    top: BorderSide(color: Colors.grey.withOpacity(0.1)),
                    bottom: BorderSide(color: Colors.grey.withOpacity(0.1)),
                    right: BorderSide(color: Colors.grey.withOpacity(0.1)),
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.urduStyle(
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isDark ? Colors.white : const Color(0xFF1A1C1E),
                                    ),
                                  ),
                                ),
                              ),
                              if (role.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    role,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: timestamp != null
                              ? DateFormat('dd MMMM yyyy, hh:mm a').format(timestamp)
                              : '',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 12,
                                color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.grey.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timeStr,
                                style: TextStyle(
                                  color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.grey.shade400,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: context.urduStyle(
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
}

class _QuickActionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final double hue;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.hue,
    required this.onTap,
  });
}
