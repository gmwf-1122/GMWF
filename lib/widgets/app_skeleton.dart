// lib/widgets/app_skeleton.dart

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hive/hive.dart';

class AppSkeleton extends StatelessWidget {
  final Widget child;
  final bool? isDark;

  const AppSkeleton({super.key, required this.child, this.isDark});

  static bool getIsDarkMode(BuildContext context) {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final dark = Hive.box('app_settings').get('is_dark_mode');
        if (dark != null) return dark == true;
      }
    } catch (_) {}
    return Theme.of(context).brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark ?? getIsDarkMode(context);

    final baseColor = dark ? const Color(0xFF1E293B) : Colors.grey.shade200;
    final highlightColor = dark ? const Color(0xFF334155) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

class AppSkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Color? color;

  const AppSkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Shimmer skeleton for Patient History visit cards
class PatientHistorySkeleton extends StatelessWidget {
  final int count;
  const PatientHistorySkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    final isDark = AppSkeleton.getIsDarkMode(context);

    return AppSkeleton(
      isDark: isDark,
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: count,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade300,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                ),
                child: const Row(
                  children: [
                    AppSkeletonBox(width: 140, height: 12),
                    Spacer(),
                    AppSkeletonBox(width: 50, height: 12),
                  ],
                ),
              ),
              // Body
              const Padding(
                padding: EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: AppSkeletonBox(width: double.infinity, height: 28)),
                        SizedBox(width: 8),
                        Expanded(child: AppSkeletonBox(width: double.infinity, height: 28)),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        AppSkeletonBox(width: 70, height: 20),
                        SizedBox(width: 6),
                        AppSkeletonBox(width: 70, height: 20),
                        SizedBox(width: 6),
                        AppSkeletonBox(width: 70, height: 20),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        AppSkeletonBox(width: 130, height: 24),
                        SizedBox(width: 6),
                        AppSkeletonBox(width: 110, height: 24),
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

/// Shimmer skeleton for Patient Detail Profile & Info panels
class PatientDetailSkeleton extends StatelessWidget {
  const PatientDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = AppSkeleton.getIsDarkMode(context);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
      body: AppSkeleton(
        isDark: isDark,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Skeleton
              Row(
                children: [
                  const AppSkeletonBox(width: 44, height: 44, borderRadius: 22),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      AppSkeletonBox(width: 160, height: 16),
                      SizedBox(height: 6),
                      AppSkeletonBox(width: 100, height: 12),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Main content split
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Info Card Skeleton
                        SizedBox(
                          width: 340,
                          child: _buildInfoCardSkeleton(isDark),
                        ),
                        const SizedBox(width: 16),
                        // Right History Skeleton
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AppSkeletonBox(width: 150, height: 18),
                              const SizedBox(height: 12),
                              const PatientHistorySkeleton(count: 3),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _buildInfoCardSkeleton(isDark),
                      const SizedBox(height: 16),
                      const PatientHistorySkeleton(count: 2),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildInfoCardSkeleton(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSkeletonBox(width: 120, height: 16),
          const SizedBox(height: 14),
          for (int i = 0; i < 6; i++) ...[
            Row(
              children: const [
                AppSkeletonBox(width: 80, height: 12),
                SizedBox(width: 12),
                Expanded(child: AppSkeletonBox(width: double.infinity, height: 12)),
              ],
            ),
            if (i < 5) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Standalone pulsating logo loading indicator
class AppLogoLoadingIndicator extends StatefulWidget {
  final double size;
  final String? message;
  final bool? isDark;

  const AppLogoLoadingIndicator({
    super.key,
    this.size = 56,
    this.message,
    this.isDark,
  });

  @override
  State<AppLogoLoadingIndicator> createState() => _AppLogoLoadingIndicatorState();
}

class _AppLogoLoadingIndicatorState extends State<AppLogoLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.9, end: 1.05).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark ?? AppSkeleton.getIsDarkMode(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _pulse,
          child: Container(
            width: widget.size + 16,
            height: widget.size + 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark ? const Color(0xFF0F172A) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Image.asset(
              'assets/logo/gmwf-1.webp',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.local_pharmacy, color: Color(0xFF0D9488)),
            ),
          ),
        ),
        if (widget.message != null && widget.message!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            widget.message!,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      ],
    );
  }
}
