// lib/widgets/gmwf_loading_view.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

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

  static const _darkBg = Color(0xFF0A0F1A);
  static const _accent = Color(0xFF2E7D32);
  static const _accentLight = Color(0xFF4CAF50);
  static const _gold = Color(0xFFD4A94C);

  final List<String> _defaultMessages = [
    "Initializing system...",
    "Syncing branch data...",
    "Preparing your dashboard...",
  ];

  @override
  void initState() {
    super.initState();

    // Gentle pulse glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Entry animation
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

    // Shimmer for the progress bar
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

    _emergencyTimer = Timer(const Duration(seconds: 15), () {
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
    final logoSize = (size.shortestSide * 0.16).clamp(80.0, 150.0);

    final displayMessage =
        widget.message ?? _defaultMessages[_messageIndex];

    final content = FadeTransition(
      opacity: _fadeIn,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Logo with glow ring ──────────────────────────────
            AnimatedBuilder(
              animation: Listenable.merge([_pulseController, _entryController]),
              builder: (_, child) {
                return Transform.scale(
                  scale: _logoScale.value,
                  child: Container(
                    width: logoSize + 36,
                    height: logoSize + 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.15 * _pulseAnim.value),
                          blurRadius: 40 * _pulseAnim.value,
                          spreadRadius: 8 * _pulseAnim.value,
                        ),
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.08 * _pulseAnim.value),
                          blurRadius: 60 * _pulseAnim.value,
                          spreadRadius: 4 * _pulseAnim.value,
                        ),
                      ],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF131B2E),
                        border: Border.all(
                          color: _accent.withValues(alpha: 0.3 + 0.2 * _pulseAnim.value),
                          width: 2,
                        ),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: child,
                    ),
                  ),
                );
              },
              child: ClipOval(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: Image.asset(
                      'assets/logo/gmwf-1.webp',
                      width: logoSize,
                      height: logoSize,
                      cacheWidth: 400,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.local_pharmacy,
                        size: logoSize * 0.6,
                        color: _accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Title ────────────────────────────────────────────
            Text(
              'GMWF',
              style: TextStyle(
                fontSize: isTablet ? 26 : 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 4,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Management System',
              style: TextStyle(
                fontSize: isTablet ? 13 : 11,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 2,
              ),
            ),

            const SizedBox(height: 28),

            // ── Shimmer progress bar ─────────────────────────────
            SizedBox(
              width: isTablet ? 200 : 160,
              child: AnimatedBuilder(
                animation: _shimmerController,
                builder: (_, _) {
                  return Container(
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: CustomPaint(
                        painter: _ShimmerBarPainter(
                          progress: _shimmerAnim.value,
                          color: _accent,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // ── Status message ───────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: Text(
                displayMessage,
                key: ValueKey(displayMessage),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isTablet ? 14 : 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.45),
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
                  fontSize: isTablet ? 12 : 10,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ],

            // ── Emergency button ─────────────────────────────────
            if (_showEmergencyButton) ...[
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Taking longer than usual?",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "The system might be offline or blocked.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/');
                      },
                      icon: const Icon(Icons.flash_on, size: 16),
                      label: const Text("Force Start Offline", style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
    );

    if (widget.isFullPage) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 1.2,
              colors: [
                Color(0xFF0F1A2E),
                _darkBg,
                Color(0xFF060A12),
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(child: content),
        ),
      );
    }

    return Container(
      color: _darkBg,
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
    final barWidth = size.width * 0.4;
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
