// lib/widgets/firestore_quota_monitor_widget.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../services/local_storage_service.dart';
import '../services/donations_local_storage.dart';
import '../services/quota_service.dart';
import '../realtime/realtime_manager.dart';

class FirestoreQuotaMonitorWidget extends StatelessWidget {
  final String branchId;
  const FirestoreQuotaMonitorWidget({super.key, this.branchId = 'all'});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!Hive.isBoxOpen(LocalStorageService.entriesBox)) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: QuotaService.isQuotaExhaustedNotifier,
      builder: (context, isQuotaExhausted, _) {
        return ValueListenableBuilder<Box>(
          valueListenable: Hive.box(LocalStorageService.entriesBox).listenable(),
          builder: (context, Box entriesBox, _) {
            final totalTokensToday = _countTodayTokens(entriesBox);
            final pendingSync = Hive.isBoxOpen(LocalStorageService.syncBox)
                ? Hive.box(LocalStorageService.syncBox).length
                : 0;
            final onLan = RealtimeManager().isConnected;

            // Estimated daily Firestore writes & reads
            final estimatedWrites = onLan ? pendingSync : totalTokensToday;
            final estimatedReads = isQuotaExhausted
                ? 50000
                : (onLan ? 50 : (totalTokensToday * 2) + 120);
            final lanSavedOps = onLan ? (totalTokensToday * 4) : 0;

            // Cloud Storage estimation (Firestore Spark Free Tier = 1,024 MB / 1 GiB)
            final totalDocs = entriesBox.length +
                (Hive.isBoxOpen(LocalStorageService.patientsBox) ? Hive.box(LocalStorageService.patientsBox).length : 0) +
                (Hive.isBoxOpen(LocalStorageService.stockBox) ? Hive.box(LocalStorageService.stockBox).length : 0) +
                (Hive.isBoxOpen(LocalStorageService.usersBox) ? Hive.box(LocalStorageService.usersBox).length : 0) +
                (Hive.isBoxOpen(DonationsLocalStorage.donationsBox) ? Hive.box(DonationsLocalStorage.donationsBox).length : 0);

            // Average Firestore doc with metadata & indices is ~1.8 KB
            final estimatedStorageMb = (totalDocs * 1.8 / 1024).clamp(0.1, 1024.0);
            const maxFreeStorageMb = 1024.0; // 1 GiB

            const maxFreeReads = 50000;
            const maxFreeWrites = 20000;

            final readPercent = isQuotaExhausted ? 1.0 : (estimatedReads / maxFreeReads).clamp(0.0, 1.0);
            final writePercent = (estimatedWrites / maxFreeWrites).clamp(0.0, 1.0);
            final storagePercent = (estimatedStorageMb / maxFreeStorageMb).clamp(0.0, 1.0);

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161B22) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isQuotaExhausted
                      ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                      : (isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
                  width: isQuotaExhausted ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isQuotaExhausted ? Colors.red : Colors.black).withValues(alpha: isDark ? 0.2 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quota Limit Warning Banner if exhausted
                  if (isQuotaExhausted) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Firebase Cloud Quota Limit Reached (50,000 Reads Exceeded)",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF991B1B),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Daily free quota was consumed by global queries/devices. App is operating in 100% Offline Local Hive & LAN Zero-Quota Mode until midnight UTC reset.",
                                  style: TextStyle(fontSize: 11.5, color: Colors.red.shade800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (isQuotaExhausted ? const Color(0xFFEF4444) : const Color(0xFF00695C)).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isQuotaExhausted ? Icons.cloud_off_rounded : Icons.speed_rounded,
                              color: isQuotaExhausted ? const Color(0xFFDC2626) : const Color(0xFF00897B),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Firestore Quota & Cloud Storage Monitor',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                'Firebase Free Tier Limits (50k Reads • 20k Writes • 1 GB Storage)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isQuotaExhausted
                              ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                              : (onLan
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                  : const Color(0xFFF59E0B).withValues(alpha: 0.15)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isQuotaExhausted
                                ? const Color(0xFFEF4444)
                                : (onLan ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isQuotaExhausted
                                  ? Icons.error_outline_rounded
                                  : (onLan ? Icons.wifi_tethering_rounded : Icons.cloud_queue_rounded),
                              size: 14,
                              color: isQuotaExhausted
                                  ? const Color(0xFFEF4444)
                                  : (onLan ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isQuotaExhausted
                                  ? 'Quota Exceeded (Local Active)'
                                  : (onLan ? 'LAN Zero-Quota Mode' : 'Cloud Fallback Mode'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isQuotaExhausted
                                    ? const Color(0xFFEF4444)
                                    : (onLan ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

              // Responsive Metric Cards Layout (2x2 on mobile, 4 columns on desktop)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 650;

                  final cardReads = _buildQuotaCard(
                    title: 'Reads Today',
                    countStr: NumberFormat('#,###').format(estimatedReads),
                    maxStr: '/ 50,000',
                    percent: readPercent,
                    color: const Color(0xFF3B82F6),
                    icon: Icons.download_rounded,
                    isDark: isDark,
                  );

                  final cardWrites = _buildQuotaCard(
                    title: 'Writes Today',
                    countStr: NumberFormat('#,###').format(estimatedWrites),
                    maxStr: '/ 20,000',
                    percent: writePercent,
                    color: const Color(0xFF8B5CF6),
                    icon: Icons.upload_rounded,
                    isDark: isDark,
                  );

                  final cardStorage = _buildQuotaCard(
                    title: 'Total Cloud Storage',
                    countStr: '${estimatedStorageMb.toStringAsFixed(1)} MB',
                    maxStr: '/ 1,024 MB (1 GB)',
                    percent: storagePercent,
                    color: const Color(0xFF0284C7),
                    icon: Icons.cloud_done_rounded,
                    isDark: isDark,
                    subtitle: '${NumberFormat('#,###').format(totalDocs)} total cloud documents',
                  );

                  final cardLan = Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 16),
                            SizedBox(width: 6),
                            Text(
                              'LAN Ops Saved',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '+$lanSavedOps',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Served via WebSocket',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );

                  if (isNarrow) {
                    return Column(
                      children: [
                        Row(children: [
                          Expanded(child: cardReads),
                          const SizedBox(width: 10),
                          Expanded(child: cardWrites),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: cardStorage),
                          const SizedBox(width: 10),
                          Expanded(child: cardLan),
                        ]),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: cardReads),
                      const SizedBox(width: 12),
                      Expanded(child: cardWrites),
                      const SizedBox(width: 12),
                      Expanded(child: cardStorage),
                      const SizedBox(width: 12),
                      Expanded(child: cardLan),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  },
);
  }

  Widget _buildQuotaCard({
    required String title,
    required String countStr,
    required String maxStr,
    required double percent,
    required Color color,
    required IconData icon,
    required bool isDark,
    String? subtitle,
  }) {
    final pctLabel = (percent * 100).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Text(
                '$pctLabel%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                countStr,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  maxStr,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  int _countTodayTokens(Box? box) {
    if (box == null || box.isEmpty) return 0;
    final todayKey = DateFormat('ddMMyy').format(DateTime.now());
    final todayYmd = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int count = 0;
    final values = box.values.toList();
    for (int i = values.length - 1; i >= 0; i--) {
      final item = values[i];
      if (item is Map) {
        final dKey = item['dateKey']?.toString() ?? item['date']?.toString();
        if (dKey == todayKey || dKey == todayYmd) {
          count++;
        } else if (count > 0 && dKey != null && dKey.isNotEmpty) {
          // Reached before today's cluster in the sequential log
          break;
        }
      }
    }
    return count;
  }
}
