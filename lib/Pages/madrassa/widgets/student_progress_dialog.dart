import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StudentProgressDialog extends StatefulWidget {
  final String studentName;
  final String? photoUrl;
  final String className;
  final String rollNumber;
  final DateTime? joinDate;
  final int totalLines;
  final int currentLines;
  final int prevHifzLines;
  final String percentage;
  final int? estimatedDays;

  const StudentProgressDialog({
    Key? key,
    required this.studentName,
    this.photoUrl,
    required this.className,
    required this.rollNumber,
    this.joinDate,
    required this.totalLines,
    required this.currentLines,
    this.prevHifzLines = 0,
    required this.percentage,
    this.estimatedDays,
  }) : super(key: key);

  @override
  State<StudentProgressDialog> createState() => _StudentProgressDialogState();
}

class _StudentProgressDialogState extends State<StudentProgressDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Total memorized = lines here + prior hifz
    final totalMemorized = widget.currentLines + widget.prevHifzLines;
    final pct = widget.totalLines > 0
        ? (totalMemorized / widget.totalLines * 100).clamp(0.0, 100.0)
        : 0.0;
    _progressAnim = Tween<double>(begin: 0, end: pct / 100).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatEstimate(int days) {
    final y = days ~/ 365;
    final rem = days % 365;
    final m = rem ~/ 30;
    final d = rem % 30;
    final parts = <String>[];
    if (y > 0) parts.add('$y yr${y > 1 ? 's' : ''}');
    if (m > 0) parts.add('$m mo');
    if (d > 0 || parts.isEmpty) parts.add('$d day${d != 1 ? 's' : ''}');
    return parts.join(' ');
  }

  String _timeWithOrg() {
    if (widget.joinDate == null) return '—';
    final diff = DateTime.now().difference(widget.joinDate!);
    final y = diff.inDays ~/ 365;
    final m = (diff.inDays % 365) ~/ 30;
    final d = diff.inDays % 30;
    final parts = <String>[];
    if (y > 0) parts.add('$y yr${y > 1 ? 's' : ''}');
    if (m > 0) parts.add('$m mo');
    if (d > 0 || parts.isEmpty) parts.add('$d day${d != 1 ? 's' : ''}');
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final totalMemorized = widget.currentLines + widget.prevHifzLines;
    final pct = widget.totalLines > 0
        ? (totalMemorized / widget.totalLines * 100).clamp(0.0, 100.0)
        : 0.0;
    final remaining = (widget.totalLines - totalMemorized).clamp(0, widget.totalLines);
    const teal = Color(0xFF008080);
    const tealLight = Color(0xFFE0F2F1);
    const cardBg = Color(0xFFF8FFFE);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      backgroundColor: Colors.transparent,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 480,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.14),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header gradient banner ──
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF005f5f), teal, Color(0xFF00a896)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 36,
                            backgroundColor: const Color(0xFF006666),
                            backgroundImage: (widget.photoUrl != null &&
                                    widget.photoUrl!.isNotEmpty)
                                ? NetworkImage(widget.photoUrl!)
                                : null,
                            child: (widget.photoUrl == null ||
                                    widget.photoUrl!.isEmpty)
                                ? Text(
                                    widget.studentName.isNotEmpty
                                        ? widget.studentName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.studentName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _chip(Icons.school_outlined,
                                      widget.className),
                                  const SizedBox(width: 8),
                                  _chip(Icons.tag, 'Roll ${widget.rollNumber}'),
                                ],
                              ),
                              if (widget.joinDate != null) ...[
                                const SizedBox(height: 6),
                                _chip(
                                  Icons.calendar_today_outlined,
                                  'Joined ${DateFormat('d MMM yyyy').format(widget.joinDate!)}',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Body ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Circular + bar progress
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Circular gauge
                            AnimatedBuilder(
                              animation: _progressAnim,
                              builder: (_, __) => SizedBox(
                                width: 90,
                                height: 90,
                                child: CustomPaint(
                                  painter: _ArcPainter(
                                    progress: _progressAnim.value,
                                    color: teal,
                                    bg: tealLight,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${(pct).toStringAsFixed(1)}%',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: teal,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Memorization Progress',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6B7280),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  AnimatedBuilder(
                                    animation: _progressAnim,
                                    builder: (_, __) => ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: _progressAnim.value,
                                        minHeight: 10,
                                        backgroundColor: tealLight,
                                        valueColor:
                                            const AlwaysStoppedAnimation(teal),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '$totalMemorized lines memorized',
                                        // ignore: dead_code
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF374151),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        '$remaining left',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // ── Stat cards row ──
                        Row(
                          children: [
                            _statCard(
                              icon: Icons.menu_book_rounded,
                              label: 'Total Verses',
                              value: '${widget.totalLines}',
                              color: const Color(0xFF6366F1),
                              bg: const Color(0xFFEEF2FF),
                            ),
                            const SizedBox(width: 10),
                            _statCard(
                              icon: Icons.check_circle_outline,
                              label: 'Memorized',
                              value: '$totalMemorized',
                              color: teal,
                              bg: tealLight,
                            ),
                            const SizedBox(width: 10),
                            _statCard(
                              icon: Icons.timelapse_rounded,
                              label: 'Time with Org',
                              value: _timeWithOrg(),
                              color: const Color(0xFFF59E0B),
                              bg: const Color(0xFFFFFBEB),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ── Estimate banner ──
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: widget.estimatedDays != null
                                ? cardBg
                                : const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: widget.estimatedDays != null
                                  ? tealLight
                                  : const Color(0xFFFED7AA),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: widget.estimatedDays != null
                                      ? tealLight
                                      : const Color(0xFFFED7AA),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.flag_rounded,
                                  color: widget.estimatedDays != null
                                      ? teal
                                      : const Color(0xFFEA580C),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Estimated Completion',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.estimatedDays != null
                                          ? _formatEstimate(widget.estimatedDays!)
                                          : 'Not enough data yet',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: widget.estimatedDays != null
                                            ? const Color(0xFF065F46)
                                            : const Color(0xFF9A3412),
                                      ),
                                    ),
                                    if (widget.estimatedDays != null)
                                      Text(
                                        'Based on daily memorization rate',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── Close button ──
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: teal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(color: teal),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'Close',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color bg,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Circular arc progress painter ──
class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color bg;
  const _ArcPainter({
    required this.progress,
    required this.color,
    required this.bg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final strokeW = 8.0;
    final bgPaint = Paint()
      ..color = bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;
    final start = -math.pi / 2;
    final sweep = 2 * math.pi * progress;
    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.color != color;
}
