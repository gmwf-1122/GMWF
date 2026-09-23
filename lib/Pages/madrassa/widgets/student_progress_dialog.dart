import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/image_upload_service.dart';
import '../madrassa_strings.dart';

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
  final double? recentDailyRate;
  final bool? isNazra;
  final bool? qaidaCompleted;
  final String? qaidaSabak;
  final int? rukuPara;
  final dynamic ruku;

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
    this.recentDailyRate,
    this.isNazra,
    this.qaidaCompleted,
    this.qaidaSabak,
    this.rukuPara,
    this.ruku,
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

    final isNazra = widget.isNazra == true ||
        widget.className.toLowerCase().contains('nazra') ||
        widget.className.contains('ناظرہ');
    final isQComp = widget.qaidaCompleted == true || widget.qaidaSabak == 'completed';
    final int qLessonNum = int.tryParse(widget.qaidaSabak ?? '1') ?? 1;

    double progressVal = 0.0;
    if (isNazra) {
      progressVal = isQComp ? 1.0 : (qLessonNum / 21).clamp(0.0, 1.0);
    } else {
      final totalMemorized = widget.currentLines + widget.prevHifzLines;
      progressVal = widget.totalLines > 0
          ? (totalMemorized / widget.totalLines).clamp(0.0, 1.0)
          : 0.0;
    }

    _progressAnim = Tween<double>(begin: 0, end: progressVal).animate(
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

  String _formatDays(int days) {
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

    final isNazra = widget.isNazra == true ||
        widget.className.toLowerCase().contains('nazra') ||
        widget.className.contains('ناظرہ');
    final isQComp = widget.qaidaCompleted == true || widget.qaidaSabak == 'completed';
    final qLesson = widget.qaidaSabak ?? '1';
    final int qLessonNum = int.tryParse(qLesson) ?? 1;
    final double qaidaPct = isQComp ? 100.0 : ((qLessonNum / 21) * 100).clamp(0.0, 100.0);

    final isHifz = !isNazra && (widget.className.toLowerCase().contains('hifz') ||
                   widget.className.contains('حفظ') ||
                   widget.className.isEmpty);
    final daysSinceJoin = widget.joinDate != null
        ? DateTime.now().difference(widget.joinDate!).inDays
        : 0;
    final int targetDays = 1095; // 3 years
    final int daysLeftIn3Years = targetDays - daysSinceJoin;
    final double linesPerDayRequired = daysLeftIn3Years > 0
        ? remaining / daysLeftIn3Years
        : 0.0;

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
                            child: ClipOval(
                              child: () {
                                final photoStr = widget.photoUrl?.trim();
                                final bytes = ImageUploadService.decodeBase64ToBytes(photoStr);
                                if (bytes != null) {
                                  return Image.memory(bytes, fit: BoxFit.cover, width: 72, height: 72);
                                } else if (photoStr != null && photoStr.startsWith('http')) {
                                  return Image.network(
                                    photoStr,
                                    fit: BoxFit.cover,
                                    width: 72,
                                    height: 72,
                                    errorBuilder: (_, __, ___) => Text(
                                      widget.studentName.isNotEmpty ? widget.studentName[0].toUpperCase() : '?',
                                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  );
                                }
                                return Text(
                                  widget.studentName.isNotEmpty ? widget.studentName[0].toUpperCase() : '?',
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                                );
                              }(),
                            ),
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
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  _chip(
                                    isNazra ? Icons.auto_stories : Icons.school_outlined,
                                    isNazra ? (context.isUrdu ? 'ناظرہ' : 'Nazra') : widget.className,
                                  ),
                                  _chip(Icons.tag, 'Roll ${widget.rollNumber}'),
                                  if (isNazra)
                                    _chip(
                                      Icons.auto_stories_rounded,
                                      isQComp ? 'قاعدہ مکمل ✅' : 'قاعدہ سبق $qLessonNum/21',
                                    ),
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
                                    color: isNazra && isQComp ? const Color(0xFF10B981) : teal,
                                    bg: tealLight,
                                  ),
                                  child: Center(
                                    child: Text(
                                      isNazra
                                          ? (isQComp ? '100%' : '${qaidaPct.toStringAsFixed(0)}%')
                                          : '${(pct).toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isNazra && isQComp ? const Color(0xFF10B981) : teal,
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
                                  Text(
                                    isNazra
                                        ? (context.isUrdu ? 'قاعدہ کی پیش رفت' : 'Qaida Progress')
                                        : 'Memorization Progress',
                                    style: const TextStyle(
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
                                        valueColor: AlwaysStoppedAnimation(
                                          isNazra && isQComp ? const Color(0xFF10B981) : teal,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        isNazra
                                            ? (isQComp
                                                ? (context.isUrdu ? 'قاعدہ مکمل (21 اسباق)' : 'Qaida Completed (21 Lessons)')
                                                : (context.isUrdu ? 'سبق نمبر $qLessonNum / ۲۱ زیرِ تعلیم' : 'Lesson $qLessonNum of 21 in progress'))
                                            : '$totalMemorized lines memorized',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF374151),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        isNazra
                                            ? (isQComp
                                                ? '✅ 100%'
                                                : (context.isUrdu ? '${21 - qLessonNum} اسباق باقی' : '${21 - qLessonNum} left'))
                                            : '$remaining left',
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
                        if (isNazra) ...[
                          Row(
                            children: [
                              _statCard(
                                icon: Icons.auto_stories_rounded,
                                label: context.isUrdu ? 'قاعدہ اسباق' : 'Qaida Lessons',
                                value: isQComp ? '21 / 21 ✅' : '$qLessonNum / 21',
                                color: isQComp ? const Color(0xFF059669) : teal,
                                bg: isQComp ? const Color(0xFFECFDF5) : tealLight,
                              ),
                              const SizedBox(width: 10),
                              _statCard(
                                icon: Icons.bookmark_added_rounded,
                                label: context.isUrdu ? 'ناظرہ کیفیت' : 'Nazra Status',
                                value: isQComp
                                    ? (context.isUrdu ? 'ناظرہ قرآن' : 'Nazra Quran')
                                    : (context.isUrdu ? 'قاعدہ جاری' : 'Qaida Active'),
                                color: const Color(0xFF6366F1),
                                bg: const Color(0xFFEEF2FF),
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
                        ] else ...[
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
                        ],

                        const SizedBox(height: 16),

                        // ── Estimate / Detail banner ──
                        if (isNazra) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isQComp ? const Color(0xFFF0FDF4) : const Color(0xFFF0FDFA),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isQComp ? const Color(0xFFBBF7D0) : const Color(0xFFCCFBF1),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isQComp ? const Color(0xFFDCFCE7) : const Color(0xFFCCFBF1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isQComp ? Icons.verified_rounded : Icons.auto_stories_rounded,
                                    color: isQComp ? const Color(0xFF16A34A) : teal,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isQComp
                                            ? (context.isUrdu ? 'قاعدہ مرحلہ: مکمل ✅' : 'Qaida Stage: Completed ✅')
                                            : (context.isUrdu ? 'قاعدہ مرحلہ: جاری' : 'Qaida Stage: In Progress'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isQComp ? const Color(0xFF15803D) : const Color(0xFF0F766E),
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isQComp
                                            ? (context.isUrdu ? 'قاعدہ مکمل — ناظرہ قرآن پاک جاری' : 'Qaida Completed — Reading Nazra Quran')
                                            : (context.isUrdu ? 'سبق نمبر $qLessonNum / ۲۱ زیرِ تعلیم' : 'Lesson $qLessonNum of 21 active'),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: isQComp ? const Color(0xFF166534) : const Color(0xFF115E59),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isQComp
                                            ? (widget.ruku != null && widget.ruku.toString().isNotEmpty && widget.ruku.toString() != '-'
                                                ? (context.isUrdu ? 'موجودہ رُكوع: پارہ ${widget.rukuPara ?? 1} • ${widget.ruku} رُكوع' : 'Current Ruku: Para ${widget.rukuPara ?? 1} • Ruku ${widget.ruku}')
                                                : (context.isUrdu ? 'طالب علم ناظرہ قرآن کی تلاوت کر رہا ہے' : 'Student has advanced to Nazra Quran reading.'))
                                            : (context.isUrdu ? 'باقی اسباق: ${21 - qLessonNum} (کل 21 اسباق)' : '${21 - qLessonNum} lessons remaining out of 21'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isQComp ? const Color(0xFF15803D) : Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
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
                      ],

                        if (isHifz) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFDCFCE7)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.insights_rounded,
                                    color: Color(0xFF16A34A),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '3-Year Hifz Target (36 Months)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF15803D),
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (daysLeftIn3Years > 0) ...[
                                        Text(
                                          'Requires min. ${linesPerDayRequired.toStringAsFixed(1)} lines/day to finish on time',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF166534),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Target Time Left: ${_formatDays(daysLeftIn3Years)} • Current pace: ${(widget.recentDailyRate ?? 0.0).toStringAsFixed(1)} lines/day',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ] else ...[
                                        const Text(
                                          'Target completion timeframe exceeded (3 years passed)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF991B1B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Current pace: ${(widget.recentDailyRate ?? 0.0).toStringAsFixed(1)} lines/day',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

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
