// lib/widgets/gmwf_loading_view.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../constants/navigator_key.dart';

class GmwfLoadingView extends StatefulWidget {
  final String? message;
  final String? subMessage;
  final bool isFullPage;

  const GmwfLoadingView({
    super.key,
    this.message,
    this.subMessage,
    this.isFullPage = true,
  });

  @override
  State<GmwfLoadingView> createState() => _GmwfLoadingViewState();
}

class _GmwfLoadingViewState extends State<GmwfLoadingView>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _entryController;
  late AnimationController _shimmerController;

  late Animation<double> _pulseAnim;
  late Animation<double> _fadeIn;
  late Animation<double> _logoScale;
  late Animation<double> _shimmerAnim;

  Timer? _messageTimer;
  Timer? _emergencyTimer;
  bool _showEmergencyButton = false;
  int _messageIndex = 0;

  final List<String> _defaultMessages = [
    "Initializing system...",
    "Syncing branch data...",
    "Preparing your dashboard...",
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeIn = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _shimmerAnim = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _entryController.forward();

    if (widget.message == null) {
      _messageTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) {
          setState(() {
            _messageIndex = (_messageIndex + 1) % _defaultMessages.length;
          });
        }
      });
    }

    _emergencyTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) {
        setState(() => _showEmergencyButton = true);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entryController.dispose();
    _shimmerController.dispose();
    _messageTimer?.cancel();
    _emergencyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;
    final logoSize = (size.shortestSide * 0.16).clamp(80.0, 130.0);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme Tokens matching LoginPage exactly
    final bgColor = isDark ? const Color(0xFF031611) : const Color(0xFFEFF6F0);
    final cardBg = isDark ? const Color(0xFF041C16).withValues(alpha: 0.92) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF10B981).withValues(alpha: 0.3) : Colors.white;
    final cardShadow = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : const Color(0xFF047857).withValues(alpha: 0.08);
    final badgeColor = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final badgeDivider = isDark ? const Color(0xFF047857) : const Color(0xFFA7F3D0);
    final titleMain = isDark ? Colors.white : const Color(0xFF064E3B);
    final titleAccent = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final subtitleColor = isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF4B5563);
    final shimmerColor = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final shimmerTrack = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFF059669).withValues(alpha: 0.12);
    final glowColor = isDark ? const Color(0xFF10B981) : const Color(0xFF059669);

    final displayMessage = widget.message ?? _defaultMessages[_messageIndex];

    final content = FadeTransition(
      opacity: _fadeIn,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cardBorder,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: cardShadow,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: glowColor.withValues(alpha: isDark ? 0.08 : 0.04),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Logo with Glowing Ring & Shared-Element Hero Tag ────────
                AnimatedBuilder(
                  animation: Listenable.merge([_pulseController, _entryController]),
                  builder: (_, child) {
                    return Transform.scale(
                      scale: _logoScale.value,
                      child: Container(
                        width: logoSize + 28,
                        height: logoSize + 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: glowColor.withValues(alpha: 0.25 * _pulseAnim.value),
                              blurRadius: 40 * _pulseAnim.value,
                              spreadRadius: 6 * _pulseAnim.value,
                            ),
                          ],
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? const Color(0xFF02140F) : Colors.white,
                            border: Border.all(
                              color: glowColor.withValues(alpha: 0.4 + 0.3 * _pulseAnim.value),
                              width: 2,
                            ),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: Hero(
                    tag: 'gmwf_app_logo',
                    child: Image.asset(
                      'assets/logo/gmwf-1.webp',
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.local_pharmacy,
                        size: logoSize * 0.6,
                        color: glowColor,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Tagline Badge ─────────────────────────────────────────
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 16, child: Divider(color: badgeDivider, thickness: 1.5)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        "GMWF SYSTEM INITIALIZATION",
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    SizedBox(width: 16, child: Divider(color: badgeDivider, thickness: 1.5)),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Title ─────────────────────────────────────────────────
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'Roboto'),
                    children: [
                      TextSpan(text: "Gulzar ", style: TextStyle(color: titleMain)),
                      TextSpan(text: "Madina", style: TextStyle(color: titleAccent)),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  'Welfare Foundation Management System',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: subtitleColor,
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 12),

                // ── Lottie Animation Loading Bar ───────────────────────────
                SizedBox(
                  width: isTablet ? 260 : 220,
                  height: 64,
                  child: Lottie.asset(
                    'assets/animations/loading (2).json',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Lottie.asset(
                      'assets/animations/loading (1).json',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: SizedBox(
                          width: isTablet ? 220 : 180,
                          child: AnimatedBuilder(
                            animation: _shimmerController,
                            builder: (_, _) {
                              return Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  color: shimmerTrack,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: CustomPaint(
                                    painter: _ShimmerBarPainter(
                                      progress: _shimmerAnim.value,
                                      color: shimmerColor,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Status Message ────────────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Text(
                    displayMessage,
                    key: ValueKey(displayMessage),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: badgeColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),

                if (widget.subMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.subMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: subtitleColor,
                    ),
                  ),
                ],

                // ── Emergency Action Card ─────────────────────────────────
                if (_showEmergencyButton) ...[
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: isDark ? 0.1 : 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Taking longer than expected?",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orangeAccent,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Initializing local database & sync engine...",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: subtitleColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () {
                            if (navigatorKey.currentState != null) {
                              navigatorKey.currentState!.pushReplacementNamed('/home');
                            } else {
                              Navigator.pushReplacementNamed(context, '/home');
                            }
                          },
                          icon: const Icon(Icons.bolt, size: 16),
                          label: const Text("Launch Main Dashboard", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.isFullPage) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Stack(
          children: [
            // ── Islamic Arch Backdrop (assets/images/2.webp) ────────────────
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: 500,
              child: Opacity(
                opacity: isDark ? 0.25 : 0.18,
                child: Image.asset(
                  'assets/images/2.webp',
                  fit: BoxFit.fitHeight,
                  alignment: Alignment.topLeft,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),

            // ── Ambient Glows ───────────────────────────────────────────────
            Positioned(
              top: -80,
              left: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowColor.withValues(alpha: isDark ? 0.12 : 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              right: -80,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowColor.withValues(alpha: isDark ? 0.15 : 0.08),
                ),
              ),
            ),

            // ── Main Centered Glass Card Content ─────────────────────────────
            SafeArea(child: content),
          ],
        ),
      );
    }

    return Container(
      color: bgColor,
      child: content,
    );
  }
}

// ── Shimmer bar painter ───────────────────────────────────────────────────────

class _ShimmerBarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ShimmerBarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width * 0.45;
    final x = (progress * size.width) - barWidth / 2;

    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.7),
          color,
          color.withValues(alpha: 0.7),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(x, 0, barWidth, size.height));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(max(0, x), 0, min(barWidth, size.width - max(0, x)), size.height),
        const Radius.circular(2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ShimmerBarPainter old) =>
      old.progress != progress;
}


