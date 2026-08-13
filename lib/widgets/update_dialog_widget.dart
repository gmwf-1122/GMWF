// lib/widgets/update_dialog_widget.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/auto_update_service.dart';
import '../theme/role_theme_provider.dart';

class UpdateDialogWidget extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialogWidget({
    super.key,
    required this.updateInfo,
  });

  static Future<void> showUpdateDialogIfNeeded(
    BuildContext context, {
    bool isServerMode = false,
    bool manualCheck = false,
  }) async {
    if (!manualCheck) {
      try {
        final box = Hive.isBoxOpen('app_settings') ? Hive.box('app_settings') : await Hive.openBox('app_settings');
        final snoozedUntilStr = box.get('update_snoozed_until') as String?;
        if (snoozedUntilStr != null) {
          final snoozedUntil = DateTime.parse(snoozedUntilStr);
          if (DateTime.now().isBefore(snoozedUntil)) {
            debugPrint('[UpdateDialogWidget] Update prompt snoozed until $snoozedUntil');
            return;
          }
        }
      } catch (e) {
        debugPrint('[UpdateDialogWidget] Error reading snooze setting: $e');
      }
    }

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
  State<UpdateDialogWidget> createState() => _UpdateDialogWidgetState();
}

class _UpdateDialogWidgetState extends State<UpdateDialogWidget> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';

  Future<void> _startInAppDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.01;
      _statusMessage = 'Connecting...';
    });

    final success = await AutoUpdateService.downloadAndInstallUpdate(
      widget.updateInfo.downloadUrl,
      onProgress: (progress, statusMessage) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            _statusMessage = statusMessage;
          });
        }
      },
    );

    if (!success && mounted) {
      setState(() {
        _isDownloading = false;
        if (_statusMessage.isEmpty || _statusMessage.startsWith('Downloading') || _statusMessage.startsWith('Connecting')) {
          _statusMessage = 'Download failed. Please check internet connection and try again.';
        }
      });
    }

    if (mounted && success && !widget.updateInfo.forceUpdate) {
      // Auto close dialog after installer launches if non-mandatory
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.maybePop(context);
      });
    }
  }

  void _snoozeUpdate() {
    try {
      final snoozeUntil = DateTime.now().add(const Duration(hours: 24));
      if (Hive.isBoxOpen('app_settings')) {
        Hive.box('app_settings').put('update_snoozed_until', snoozeUntil.toIso8601String());
      }
    } catch (e) {
      debugPrint('[UpdateDialogWidget] Error saving snooze timestamp: $e');
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    return PopScope(
      canPop: !widget.updateInfo.forceUpdate && !_isDownloading,
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
                      'assets/logo/gmwf-1.webp',
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
                  'v${AutoUpdateService.currentVersion}  ➔  v${widget.updateInfo.latestVersion}',
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
                      widget.updateInfo.releaseNotes,
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
              if (widget.updateInfo.forceUpdate) ...[
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

              // Live Download Progress Bar when active or status message present
              if (_isDownloading || _statusMessage.isNotEmpty) ...[
                if (_isDownloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                      backgroundColor: t.accent.withValues(alpha: 0.12),
                      color: t.accent,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t.accent,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else if (_statusMessage.contains('Failed') || _statusMessage.contains('Error') || _statusMessage.contains('Denied') || _statusMessage.contains('Timeout')) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade700, width: 1.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Update Warning',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _statusMessage,
                          style: TextStyle(fontSize: 12, color: Colors.red.shade200, height: 1.35),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => AutoUpdateService.launchUpdateUrl(widget.updateInfo.downloadUrl),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.shade800,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_browser_rounded, color: Colors.white, size: 15),
                                SizedBox(width: 6),
                                Text(
                                  'Download File via Browser',
                                  style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t.accent,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
              ],

              // Buttons
              Row(
                children: [
                  if (!widget.updateInfo.forceUpdate && !_isDownloading) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _snoozeUpdate,
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
                      onPressed: _isDownloading ? null : _startInAppDownload,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isDownloading ? Icons.hourglass_top_rounded : Icons.download_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isDownloading
                                ? (_downloadProgress >= 1.0 ? 'Installing...' : 'Downloading...')
                                : 'Update Now',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
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
