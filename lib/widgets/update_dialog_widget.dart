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
    final primaryColor = t.accent;

    return PopScope(
      canPop: !widget.updateInfo.forceUpdate && !_isDownloading,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
            color: t.bgCard,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: primaryColor.withValues(alpha: 0.15), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 32,
                spreadRadius: 4,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.08),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Ambient Banner Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withValues(alpha: 0.12),
                      primaryColor.withValues(alpha: 0.03),
                      t.bgCard,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    // Logo Header with Pulsing Glow Ring
                    Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                primaryColor.withValues(alpha: 0.25),
                                primaryColor.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: 74,
                          height: 74,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: t.bgCard,
                            shape: BoxShape.circle,
                            border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.15),
                                blurRadius: 16,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/logo/gmwf-1.webp',
                            fit: BoxFit.contain,
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [primaryColor, primaryColor.withValues(alpha: 0.85)],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(color: t.bgCard, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Text(
                      'New Version Available!',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: t.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Version Transition Pill
                    FutureBuilder<String>(
                      future: AutoUpdateService.getAppVersion(),
                      builder: (context, snapshot) {
                        final currentVer = snapshot.data ?? AutoUpdateService.currentVersion;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                primaryColor.withValues(alpha: 0.1),
                                primaryColor.withValues(alpha: 0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: primaryColor.withValues(alpha: 0.25), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'v$currentVer',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: t.textSecondary,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.east_rounded,
                                  size: 14,
                                  color: primaryColor,
                                ),
                              ),
                              Text(
                                'v${widget.updateInfo.latestVersion}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Content Body
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Release Notes Section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: t.bg.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.bgRule.withValues(alpha: 0.7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.stars_rounded,
                                size: 16,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'What\'s New in this Update:',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: t.textSecondary,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.updateInfo.releaseNotes,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: t.textPrimary,
                              height: 1.45,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Mandatory Warning if forced
                    if (widget.updateInfo.forceUpdate) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.amber.shade300, width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade900),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'This is a required update to maintain server sync & functionality.',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Live Download Progress Bar & Status Text
                    if (_isDownloading || _statusMessage.isNotEmpty) ...[
                      if (_isDownloading) ...[
                        Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _downloadProgress >= 1.0 ? 'Finalizing Setup...' : 'Downloading Assets...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: t.textSecondary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${(_downloadProgress * 100).toInt()}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _downloadProgress > 0 ? _downloadProgress : null,
                                backgroundColor: primaryColor.withValues(alpha: 0.12),
                                color: primaryColor,
                                minHeight: 9,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _statusMessage,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: primaryColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ] else if (_statusMessage.contains('Failed') || _statusMessage.contains('Error') || _statusMessage.contains('Denied') || _statusMessage.contains('Timeout')) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.red.shade600.withValues(alpha: 0.5), width: 1.0),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Installation Hint',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _statusMessage,
                                style: TextStyle(fontSize: 12, color: Colors.red.shade300, height: 1.35),
                              ),
                              const SizedBox(height: 12),
                              InkWell(
                                onTap: () => AutoUpdateService.launchUpdateUrl(widget.updateInfo.downloadUrl),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade800,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.open_in_browser_rounded, color: Colors.white, size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'Download File via Browser',
                                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 18),
                    ],

                    // Bottom Action Buttons
                    Row(
                      children: [
                        if (!widget.updateInfo.forceUpdate && !_isDownloading) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _snoozeUpdate,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                side: BorderSide(color: t.bgRule, width: 1.2),
                              ),
                              child: Text(
                                'Remind Later',
                                style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: _isDownloading
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: primaryColor.withValues(alpha: 0.3),
                                        blurRadius: 14,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isDownloading ? null : _startInAppDownload,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isDownloading ? Icons.hourglass_top_rounded : Icons.system_update_alt_rounded,
                                    size: 19,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isDownloading
                                        ? (_downloadProgress >= 1.0 ? 'Installing...' : 'Downloading...')
                                        : 'Update Now',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

