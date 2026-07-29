// lib/widgets/update_dialog_widget.dart

import 'package:flutter/material.dart';
import '../services/auto_update_service.dart';
import '../theme/role_theme_provider.dart';

class UpdateDialogWidget extends StatelessWidget {
  final UpdateInfo updateInfo;

  const UpdateDialogWidget({
    super.key,
    required this.updateInfo,
  });

  static Future<void> showUpdateDialogIfNeeded(BuildContext context, {bool isServerMode = false}) async {
    final updateInfo = await AutoUpdateService.checkForUpdates();
    if (updateInfo != null && updateInfo.hasUpdate) {
      if (isServerMode) {
        debugPrint('[UpdateDialogWidget] Headless server mode detected. Executing silent background auto-update...');
        await AutoUpdateService.performSilentHeadlessUpdate(updateInfo.downloadUrl);
        return;
      }

      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: !updateInfo.forceUpdate,
          builder: (ctx) => UpdateDialogWidget(updateInfo: updateInfo),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    return PopScope(
      canPop: !updateInfo.forceUpdate,
      child: Dialog(
        backgroundColor: t.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo Header with Update Badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(color: t.accent.withValues(alpha: 0.2), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: t.accent.withValues(alpha: 0.1),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/logo/gmwf-1.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: t.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.bgCard, width: 2),
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'New Update Available!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 6),

              // Version Chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200, width: 0.8),
                ),
                child: Text(
                  'v${AutoUpdateService.currentVersion}  ➔  v${updateInfo.latestVersion}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.blue.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Release Notes Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.bgRule),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What\'s New:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: t.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      updateInfo.releaseNotes,
                      style: TextStyle(
                        fontSize: 13,
                        color: t.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Mandatory warning if required
              if (updateInfo.forceUpdate) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This update is required to continue using the application.',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Buttons
              Row(
                children: [
                  if (!updateInfo.forceUpdate) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          side: BorderSide(color: t.bgRule),
                        ),
                        child: Text(
                          'Later',
                          style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        AutoUpdateService.launchUpdateUrl(updateInfo.downloadUrl);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_rounded, size: 18),
                          SizedBox(width: 6),
                          Text('Update Now', style: TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
