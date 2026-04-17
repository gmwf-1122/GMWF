// lib/widgets/gmwf_loading_view.dart
import 'dart:async';
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
  late AnimationController _loopController;
  late AnimationController _entryController;

  late Animation<double> _floatAnimation;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideIn;

  Timer? _messageTimer;
  int _messageIndex = 0;

  final List<String> _defaultMessages = [
    "Connecting to system...",
    "Syncing branch data...",
    "Preparing dashboard...",
  ];

  @override
  void initState() {
    super.initState();

    // Subtle floating animation
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _loopController, curve: Curves.easeInOut),
    );

    // Entry animation
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeIn = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    _slideIn = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOut),
    );

    _entryController.forward();

    // Dynamic message rotation (only if no custom message provided)
    if (widget.message == null) {
      _messageTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        setState(() {
          _messageIndex =
              (_messageIndex + 1) % _defaultMessages.length;
        });
      });
    }
  }

  @override
  void dispose() {
    _loopController.dispose();
    _entryController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;

    final logoSize =
        (size.width * (isTablet ? 0.22 : 0.35)).clamp(110.0, 220.0);

    final displayMessage =
        widget.message ?? _defaultMessages[_messageIndex];

    final content = FadeTransition(
      opacity: _fadeIn,
      child: SlideTransition(
        position: _slideIn,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 64 : 28,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Floating logo
                AnimatedBuilder(
                  animation: _loopController,
                  builder: (_, child) {
                    return Transform.translate(
                      offset: Offset(0, _floatAnimation.value),
                      child: child,
                    );
                  },
                  child: Image.asset(
                    'assets/logo/gmwf.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.local_pharmacy,
                      size: logoSize,
                      color: const Color(0xFF00695C),
                    ),
                  ),
                ),

                const SizedBox(height: 48),

                // Branded loader
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    strokeCap: StrokeCap.round,
                    valueColor: const AlwaysStoppedAnimation(
                      Color(0xFF1B5E20),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Main message
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    displayMessage,
                    key: ValueKey(displayMessage),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isTablet ? 22 : 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1B5E20),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Sub message
                if (widget.subMessage != null)
                  Text(
                    widget.subMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isTablet ? 16 : 14,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.isFullPage) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFF1F8E9),
                Color(0xFFE8F5E9),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(child: content),
        ),
      );
    }

    return content;
  }
}