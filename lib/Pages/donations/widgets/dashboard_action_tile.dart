import 'package:flutter/material.dart';
import '../../../constants/colors.dart';
import '../donations_shared.dart';

class DashboardActionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isActive;

  const DashboardActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isActive = false,
  });

  @override
  State<DashboardActionTile> createState() => _DashboardActionTileState();
}

class _DashboardActionTileState extends State<DashboardActionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: ScaleButton(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? widget.color.withValues(alpha: _isHovered ? 0.08 : 0.06)
                  : (_isHovered ? widget.color.withValues(alpha: 0.03) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.isActive
                    ? widget.color.withValues(alpha: _isHovered ? 0.6 : 0.4)
                    : (_isHovered ? widget.color.withValues(alpha: 0.3) : const Color(0x0A000000)),
                width: widget.isActive || _isHovered ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isHovered ? 0.04 : 0.02),
                  blurRadius: _isHovered ? 12 : 10,
                  offset: _isHovered ? const Offset(0, 6) : const Offset(0, 4),
                ),
                if (widget.isActive || _isHovered)
                  BoxShadow(
                    color: widget.color.withValues(alpha: _isHovered ? 0.16 : 0.1),
                    blurRadius: _isHovered ? 16 : 12,
                    offset: _isHovered ? const Offset(0, 8) : const Offset(0, 6),
                  ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        widget.color.withValues(alpha: _isHovered ? 0.22 : 0.15),
                        widget.color.withValues(alpha: _isHovered ? 0.08 : 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: AnimatedScale(
                    scale: _isHovered ? 1.25 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: Icon(widget.icon, size: 16, color: widget.color),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: widget.isActive
                          ? widget.color
                          : (_isHovered ? widget.color : AppColors.gray800),
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
