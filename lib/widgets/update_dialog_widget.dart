// lib/widgets/update_dialog_widget.dart

import 'dart:math' as math;
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

  static bool _isShowingDialog = false;

  /// Primary entry-point to trigger update checking and display dialog.
  /// Fully protected against uncaught exceptions and overlapping dialogs.
  static Future<void> showUpdateDialogIfNeeded(
    BuildContext context, {
    bool isServerMode = false,
    bool manualCheck = false,
  }) async {
    if (_isShowingDialog && !manualCheck) {
      debugPrint('[UpdateDialogWidget] Update dialog already showing. Skipping redundant check.');
      return;
    }

    try {
      final updateInfo = await AutoUpdateService.checkForUpdates();
      if (updateInfo == null || !updateInfo.hasUpdate) {
        if (manualCheck && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Your application is up to date!'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Check version-specific snooze for non-mandatory updates
      if (!manualCheck && !updateInfo.forceUpdate) {
        try {
          final box = Hive.isBoxOpen('app_settings')
              ? Hive.box('app_settings')
              : await Hive.openBox('app_settings');
          final snoozedVersion = box.get('update_snoozed_version') as String?;
          final snoozedUntilStr = box.get('update_snoozed_until') as String?;

          if (snoozedUntilStr != null && snoozedVersion == updateInfo.latestVersion) {
            final snoozedUntil = DateTime.tryParse(snoozedUntilStr);
            if (snoozedUntil != null && DateTime.now().isBefore(snoozedUntil)) {
              debugPrint('[UpdateDialogWidget] Update prompt for v${updateInfo.latestVersion} snoozed until $snoozedUntil');
              return;
            }
          }
        } catch (e) {
          debugPrint('[UpdateDialogWidget] Error reading snooze setting: $e');
        }
      }

      if (isServerMode) {
        debugPrint('[UpdateDialogWidget] Headless server mode detected. Executing silent background auto-update...');
        await AutoUpdateService.performSilentHeadlessUpdate(updateInfo.downloadUrl);
        return;
      }

      if (!context.mounted) return;

      _isShowingDialog = true;
      await showDialog(
        context: context,
        barrierDismissible: !updateInfo.forceUpdate,
        barrierColor: Colors.black.withValues(alpha: 0.65),
        builder: (ctx) => UpdateDialogWidget(updateInfo: updateInfo),
      );
    } catch (e) {
      debugPrint('[UpdateDialogWidget] Exception in showUpdateDialogIfNeeded: $e');
    } finally {
      _isShowingDialog = false;
    }
  }

  @override
  State<UpdateDialogWidget> createState() => _UpdateDialogWidgetState();
}

class _UpdateDialogWidgetState extends State<UpdateDialogWidget> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';

  // ── GMWF Brand Identity Colors ──────────────────────────────────────────────
  // Locked to organization teal regardless of user role, so the update dialog
  // always presents consistent brand identity.
  static const Color _brandTeal       = Color(0xFF0E6E63);
  static const Color _brandTealLight  = Color(0xFF16897A);
  static const Color _brandTealDark   = Color(0xFF0A4F47);
  static const Color _brandTealMuted  = Color(0xFFD3EDEA);
  static const Color _brandGold       = Color(0xFFB07C2C);

  Future<void> _startInAppDownload() async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.01;
      _statusMessage = 'Connecting to update server...';
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

    if (mounted) {
      if (success) {
        // Always reset _isDownloading so the dialog is not stuck in "Installing..." state.
        // The APK installer runs as a separate Android activity; our job is done.
        setState(() {
          _isDownloading = false;
        });

        if (!widget.updateInfo.forceUpdate) {
          // Auto close dialog after installer launches if non-mandatory
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              Navigator.of(context, rootNavigator: true).maybePop();
            }
          });
        }
      } else {
        // Download or install failed — reset so the user can retry or dismiss
        setState(() {
          _isDownloading = false;
          if (_statusMessage.isEmpty ||
              _statusMessage.startsWith('Downloading') ||
              _statusMessage.startsWith('Connecting')) {
            _statusMessage = 'Download failed. Please check your network connection or download via browser.';
          }
        });
      }
    }
  }

  void _snoozeUpdate() {
    try {
      final snoozeUntil = DateTime.now().add(const Duration(hours: 24));
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        box.put('update_snoozed_until', snoozeUntil.toIso8601String());
        box.put('update_snoozed_version', widget.updateInfo.latestVersion);
      }
    } catch (e) {
      debugPrint('[UpdateDialogWidget] Error saving snooze setting: $e');
    }
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    final media = MediaQuery.sizeOf(context);
    final maxCardWidth = math.min(480.0, media.width * 0.92);
    final maxCardHeight = math.min(620.0, media.height * 0.86);

    return PopScope(
      canPop: !widget.updateInfo.forceUpdate && !_isDownloading,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Container(
          width: maxCardWidth,
          constraints: BoxConstraints(
            maxWidth: maxCardWidth,
            maxHeight: maxCardHeight,
          ),
          decoration: BoxDecoration(
            color: t.bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _brandTeal.withValues(alpha: 0.28), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 36,
                spreadRadius: 4,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: _brandTeal.withValues(alpha: 0.12),
                blurRadius: 42,
                spreadRadius: 6,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. FIXED HEADER — GMWF Brand Identity
              _buildFixedHeader(t),

              // 2. SCROLLABLE CONTENT BODY (Release notes + Status/Progress)
              Flexible(
                child: Scrollbar(
                  thumbVisibility: true,
                  radius: const Radius.circular(8),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Mandatory update banner if required
                        if (widget.updateInfo.forceUpdate) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: _brandGold.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _brandGold.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 18, color: _brandGold),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'This is a required update to ensure continued database sync and system security.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: t.isDarkCanvas ? _brandGold : const Color(0xFF7A5A1E),
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Release Notes Section
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: t.isDarkCanvas
                                ? _brandTeal.withValues(alpha: 0.06)
                                : _brandTealMuted.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: t.isDarkCanvas
                                  ? _brandTeal.withValues(alpha: 0.18)
                                  : _brandTeal.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 16,
                                    color: _brandTeal,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    'What\'s New in this Release:',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: t.textSecondary,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                widget.updateInfo.releaseNotes.trim().isNotEmpty
                                    ? widget.updateInfo.releaseNotes.trim()
                                    : 'Performance optimizations, database sync enhancements, and general user experience improvements.',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: t.textPrimary,
                                  height: 1.48,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Progress bar or Error hints when active
                        if (_isDownloading || _statusMessage.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildProgressOrErrorView(t),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // 3. FIXED BOTTOM ACTION BUTTONS FOOTER
              _buildFixedFooter(t),
            ],
          ),
        ),
      ),
    );
  }

  /// Fixed Top Header with GMWF brand identity, logo, title, and version transition pill.
  Widget _buildFixedHeader(dynamic t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _brandTeal.withValues(alpha: 0.14),
            _brandTealLight.withValues(alpha: 0.05),
            t.bgCard as Color,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          bottom: BorderSide(color: _brandTeal.withValues(alpha: 0.15), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Logo Header with Branded Glow Ring
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _brandTeal.withValues(alpha: 0.22),
                      _brandTeal.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              Container(
                width: 66,
                height: 66,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: t.bgCard as Color,
                  shape: BoxShape.circle,
                  border: Border.all(color: _brandTeal.withValues(alpha: 0.40), width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: _brandTeal.withValues(alpha: 0.20),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/logo/gmwf-1.webp',
                  fit: BoxFit.contain,
                  errorBuilder: (_, e, s) => const Icon(Icons.system_update_rounded, color: _brandTeal, size: 30),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_brandTeal, _brandTealLight],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: t.bgCard as Color, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: _brandTeal.withValues(alpha: 0.45),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // GMWF Brand Name
          Text(
            'GMWF',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.5,
              color: _brandTeal.withValues(alpha: t.isDarkCanvas ? 0.85 : 1.0),
            ),
          ),
          const SizedBox(height: 4),

          // Title
          Text(
            widget.updateInfo.forceUpdate ? 'Mandatory Update Required' : 'New Version Available!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: t.textPrimary as Color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Version Transition Pill — teal branded
          FutureBuilder<String>(
            future: AutoUpdateService.getAppVersion(),
            builder: (context, snapshot) {
              final currentVer = snapshot.data ?? AutoUpdateService.currentVersion;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _brandTeal.withValues(alpha: 0.12),
                      _brandTealLight.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _brandTeal.withValues(alpha: 0.25), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'v$currentVer',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.textSecondary as Color,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 7),
                      child: Icon(
                        Icons.east_rounded,
                        size: 13,
                        color: _brandTeal,
                      ),
                    ),
                    Text(
                      'v${widget.updateInfo.latestVersion}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _brandTeal,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Live Download Progress or Error State View — brand teal themed
  Widget _buildProgressOrErrorView(dynamic t) {
    if (_isDownloading) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _brandTeal.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _brandTeal.withValues(alpha: 0.18)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _downloadProgress >= 1.0 ? 'Finalizing Setup...' : 'Downloading Assets...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.textSecondary as Color,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _brandTeal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(_downloadProgress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _brandTeal,
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
                backgroundColor: _brandTeal.withValues(alpha: 0.12),
                color: _brandTeal,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: t.isDarkCanvas ? _brandTealLight : _brandTeal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else if (_statusMessage.contains('Failed') ||
        _statusMessage.contains('Error') ||
        _statusMessage.contains('Denied') ||
        _statusMessage.contains('Timeout') ||
        _statusMessage.contains('Could not open installer')) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF7F1D1D).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.35), width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 17),
                SizedBox(width: 8),
                Text(
                  'Installation Notice',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 11.5,
                color: t.isDarkCanvas ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InkWell(
                  onTap: _startInAppDownload,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _brandTeal,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, color: Colors.white, size: 15),
                        SizedBox(width: 6),
                        Text(
                          'Retry',
                          style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => AutoUpdateService.launchUpdateUrl(widget.updateInfo.downloadUrl),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _brandTealDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_browser_rounded, color: Colors.white, size: 15),
                        SizedBox(width: 6),
                        Text(
                          'Download via Browser',
                          style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      return Text(
        _statusMessage,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: t.isDarkCanvas ? _brandTealLight : _brandTeal,
        ),
        textAlign: TextAlign.center,
      );
    }
  }

  /// Fixed Bottom Footer with Action Buttons — brand teal themed
  Widget _buildFixedFooter(dynamic t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(
        color: t.bgCard as Color,
        border: Border(
          top: BorderSide(color: _brandTeal.withValues(alpha: 0.12), width: 1),
        ),
      ),
      child: Row(
        children: [
          if (!widget.updateInfo.forceUpdate && !_isDownloading) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _snoozeUpdate,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: BorderSide(color: t.bgRule as Color, width: 1.2),
                ),
                child: Text(
                  'Remind Later',
                  style: TextStyle(color: t.textSecondary as Color, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: _isDownloading
                    ? []
                    : [
                        BoxShadow(
                          color: _brandTeal.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: ElevatedButton(
                onPressed: _isDownloading ? null : _startInAppDownload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandTeal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _brandTeal.withValues(alpha: 0.5),
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isDownloading ? Icons.hourglass_top_rounded : Icons.system_update_alt_rounded,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isDownloading
                          ? (_downloadProgress >= 1.0 ? 'Installing...' : 'Downloading...')
                          : 'Update Now',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, letterSpacing: 0.2),
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
}
