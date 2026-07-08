import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DashboardStatCard extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final Color barColor;

  const DashboardStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.barColor,
  });

  @override
  State<DashboardStatCard> createState() => _DashboardStatCardState();
}

class _DashboardStatCardState extends State<DashboardStatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cleanLabel = widget.label.toUpperCase();
    final Color bgColor;
    final Color indicatorColor;
    final Color labelColor;
    final Color valueColor = Colors.white;
    final String footerText;

    if (cleanLabel.contains('TOTAL')) {
      bgColor = const Color(0xFF1D4ED8); // Vibrant Royal Blue / Blue 700
      indicatorColor = const Color(0xFF93C5FD); // Soft Sky Blue
      labelColor = const Color(0xFFEFF6FF); // Crisp Light Blue
      footerText = 'All-time volume tracked';
    } else if (cleanLabel.contains('RECEIVED')) {
      bgColor = const Color(0xFF047857); // Vibrant Emerald / Green 700
      indicatorColor = const Color(0xFF6EE7B7); // Soft Mint Green
      labelColor = const Color(0xFFECFDF5); // Crisp Light Green
      footerText = 'Successfully received';
    } else {
      bgColor = const Color(0xFFB45309); // Vibrant Warm Amber / Amber 700
      indicatorColor = const Color(0xFFFDE68A); // Soft Gold
      labelColor = const Color(0xFFFFFBEB); // Crisp Light Amber
      footerText = 'Awaiting verification';
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? Colors.white.withOpacity(0.24)
                : Colors.white.withOpacity(0.12),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_isHovered ? 0.20 : 0.12),
              blurRadius: _isHovered ? 20 : 12,
              offset: Offset(0, _isHovered ? 8 : 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Subtle Top-Right Sheen Gradient
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(_isHovered ? 0.08 : 0.04),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Left Vertical Accent Bar (replaces the vintage bottom bar)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isHovered ? 6 : 4,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
            ),
            // Content with uniform padding and breathing space
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: labelColor.withOpacity(0.8),
                          letterSpacing: 0.8,
                        ),
                      ),
                      AnimatedScale(
                        scale: _isHovered ? 1.15 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(_isHovered ? 0.20 : 0.12),
                            border: Border.all(
                              color: Colors.white.withOpacity(_isHovered ? 0.25 : 0.15),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            widget.icon,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'PKR ',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: labelColor.withOpacity(0.6),
                            letterSpacing: 0.5,
                          ),
                        ),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.value,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: valueColor,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Descriptive footer context subtitle replacing progress bar
                    Text(
                      footerText,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: labelColor.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }
}
