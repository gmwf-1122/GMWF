import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../models/madrassa_config.dart';
import '../models/madrassa_fee_logic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../utils/photo_upload_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../utils/madrassa_local_storage.dart';
import '../../../services/sync_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../services/local_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/madrassa_providers.dart';

import 'package:image_picker/image_picker.dart';
import 'dart:async';

import '../madrassa_strings.dart';

class DailyLogView extends ConsumerStatefulWidget {
  final String branchId;
  final String editorName;
  final String editorRole;
  const DailyLogView({
    super.key,
    required this.branchId,
    this.editorName = 'Unknown',
    this.editorRole = 'Madrassa Teacher',
  });

  @override
  ConsumerState<DailyLogView> createState() => _DailyLogViewState();
}

class _DailyLogViewState extends ConsumerState<DailyLogView> {
  DateTime _selectedDate = DateTime.now();
  Map<String, Map<String, dynamic>> _localChanges = {};
  bool _isSaving = false;
  final Map<String, PhotoUploadStatus> _uploadStates = {};
  bool _allPresentToggled = false;
  bool _allUniformToggled = false;
  bool _allRepliedToggled = false;
  // Student notifiers to allow isolated rebuilding of student cards
  final Map<String, ValueNotifier<Map<String, dynamic>>> _studentNotifiers = {};
  // Counter to trigger legend and save button rebuilds
  final ValueNotifier<int> _changeNotifier = ValueNotifier(0);
  final ScrollController _calendarScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final GlobalKey _calendarKey = GlobalKey();
  bool _hasInitialScrollDone = false;
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _verticalScrollController.addListener(() {
      final show = _verticalScrollController.offset > 300;
      if (show != _showBackToTop) {
        setState(() {
          _showBackToTop = show;
        });
      }
    });
    _calendarScrollController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedDate(animate: false);
    });

    // Initialise streams/downloads for the initially selected date
    _updateDateStreams();
  }

  @override
  void dispose() {
    _calendarScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  // Initialise streams/downloads for the selected date
  void _updateDateStreams() {
    MadrassaLocalStorage.downloadStudents(widget.branchId);
    MadrassaLocalStorage.downloadLogsForMonth(
        widget.branchId, _selectedDate.year, _selectedDate.month);
    MadrassaLocalStorage.downloadHolidays(widget.branchId);
  }

  bool _isFutureDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final compareDate = DateTime(date.year, date.month, date.day);
    return compareDate.isAfter(today);
  }

  bool _canSaveData() {
    final now = DateTime.now();
    final selY = _selectedDate.year;
    final selM = _selectedDate.month;
    final curY = now.year;
    final curM = now.month;

    final prevMonthDate = DateTime(curY, curM - 1, 1);
    final prevY = prevMonthDate.year;
    final prevM = prevMonthDate.month;

    return (selY == curY && selM == curM) || (selY == prevY && selM == prevM);
  }

  DateTime getPtmDateFor(int targetYear, int targetMonth, MadrassaConfig config) {
    final reschedule = config.auditLog.firstWhereOrNull((log) =>
        log['type'] == 'ptm_reschedule' &&
        log['year'] == targetYear &&
        log['month'] == targetMonth);
        
    if (reschedule != null) {
      final newVal = int.tryParse(reschedule['newValue']?.toString() ?? '');
      if (newVal != null && newVal > 0) {
        return DateTime(targetYear, targetMonth, newVal);
      }
    }

    if (config.ptmDay > 0) {
      return DateTime(targetYear, targetMonth, config.ptmDay);
    }

    DateTime date = DateTime(targetYear, targetMonth, 1);
    while (date.weekday != DateTime.friday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  void _scrollToSelectedDate({bool animate = true}) {
    if (!_calendarScrollController.hasClients) return;
    final context = _calendarKey.currentContext;
    if (context == null) return;

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final viewportWidth = renderBox.size.width;
    if (viewportWidth <= 0) return;

    final daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    const itemWidth = 68.0; // 60 width + 8 horizontal margin (4 each side)
    const listPadding = 16.0; // padding at start of list

    final index = _selectedDate.day - 1;
    final itemCenter = listPadding + (index * itemWidth) + (itemWidth / 2);
    final targetOffset = itemCenter - (viewportWidth / 2);

    final maxScroll = (listPadding * 2) + (daysInMonth * itemWidth) - viewportWidth;
    final clampedOffset = targetOffset.clamp(0.0, maxScroll < 0 ? 0.0 : maxScroll);

    if (animate) {
      _calendarScrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _calendarScrollController.jumpTo(clampedOffset);
    }
  }

  Future<void> _saveChanges() async {
    if (_localChanges.isEmpty) return;
    setState(() => _isSaving = true);

    // Validation for sabki and manzil fields: both Para and Ratio must be provided together.
    for (var entry in _localChanges.entries) {
      final data = entry.value;
      
      // Sabki validation
      final int sabkiPara = data['sabkiPara'] is int ? data['sabkiPara'] : 0;
      final String? sabkiRatio = data['sabkiRatio']?.toString();
      final bool hasSabkiRatio = sabkiRatio != null && sabkiRatio.isNotEmpty && sabkiRatio != '-';
      
      if (hasSabkiRatio && sabkiRatio != 'nahi_sunaya' && sabkiPara == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sabki: Para must be selected for ratio $sabkiRatio.')),
        );
        setState(() => _isSaving = false);
        return;
      }
      if (sabkiPara > 0 && !hasSabkiRatio) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sabki: Ratio must be selected for Para $sabkiPara.')),
        );
        setState(() => _isSaving = false);
        return;
      }

      // Manzil validation
      final int manzilPara = data['manzilPara'] is int ? data['manzilPara'] : 0;
      final String? manzilRatio = data['manzilRatio']?.toString();
      final bool hasManzilRatio = manzilRatio != null && manzilRatio.isNotEmpty && manzilRatio != '-';
      
      if (hasManzilRatio && manzilRatio != 'nahi_sunaya' && manzilPara == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Manzil: Para must be selected for ratio $manzilRatio.')),
        );
        setState(() => _isSaving = false);
        return;
      }
      if (manzilPara > 0 && !hasManzilRatio) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Manzil: Ratio must be selected for Para $manzilPara.')),
        );
        setState(() => _isSaving = false);
        return;
      }
    }

    try {
      final String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // Save locally (updates cached student currentLines, enqueues sync tasks, enqueues audit logs)
      await MadrassaLocalStorage.saveLogRecordLocal(
        branchId: widget.branchId,
        dateKey: dateKey,
        logData: _localChanges,
        editorName: widget.editorName,
        editorRole: widget.editorRole,
      );

      // Trigger background upload if online
      SyncService().triggerUpload();

      setState(() {
  _localChanges = {};
  _isSaving = false;
  _allPresentToggled = false;
  _allUniformToggled = false;
  _allRepliedToggled = false;
  _studentNotifiers.clear();
});
_changeNotifier.value++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l.savedSuccess)),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }





  Map<String, dynamic> _safeMap(dynamic val) {
    if (val is Map) {
      return Map<String, dynamic>.from(val);
    }
    return {};
  }

  // Update local changes silently (isolated rebuilds)
  void _updateLocalSilent(String sId, String key, dynamic value) {
    if (!_localChanges.containsKey(sId)) {
      final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final logData = ref.read(madrassaDailyLogProvider((branchId: widget.branchId, dateKey: dateKey))).value ?? {};
      final dbLog = _safeMap(logData[sId]);
      _localChanges[sId] = Map<String, dynamic>.from(dbLog);
    }
    _localChanges[sId]![key] = value;
    if (_studentNotifiers.containsKey(sId)) {
      _studentNotifiers[sId]!.value =
          Map<String, dynamic>.from(_localChanges[sId]!);
    }
    _changeNotifier.value++;
  }

  void _updateAttendanceSilent(String sId, String value) {
    _updateLocalSilent(sId, 'attendance', value);
    if (value != 'present') {
      _updateLocalSilent(sId, 'uniform', false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    
    final configAsyncValue = ref.watch(madrassaConfigProvider(widget.branchId));
    final holidaysAsyncValue = ref.watch(madrassaHolidaysProvider(widget.branchId));
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final filteredStudentsAsyncValue = ref.watch(madrassaFilteredStudentsProvider((branchId: widget.branchId, selectedDate: _selectedDate)));
    final logAsyncValue = ref.watch(madrassaDailyLogProvider((branchId: widget.branchId, dateKey: dateKey)));

    return configAsyncValue.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error loading config: $e'))),
      data: (config) {
        final ptmDate = getPtmDateFor(_selectedDate.year, _selectedDate.month, config);
        final isPtmDay = _selectedDate.year == ptmDate.year && _selectedDate.month == ptmDate.month && _selectedDate.day == ptmDate.day;
        final isReadOnly = !_canSaveData();

        // Read holidays from cache
        final cachedHolidays = holidaysAsyncValue.value ?? [];
        String? holidayName;
        for (final h in cachedHolidays) {
          final dateVal = h['date'];
          DateTime? d;
          if (dateVal is String) {
            d = DateTime.tryParse(dateVal);
          } else if (dateVal is Timestamp) {
            d = dateVal.toDate();
          }
          if (d != null && d.year == _selectedDate.year && d.month == _selectedDate.month && d.day == _selectedDate.day) {
            holidayName = h['name'] as String? ?? 'Holiday';
            break;
          }
        }
        final isHoliday = holidayName != null;
        final isSunday = _selectedDate.weekday == DateTime.sunday;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FD),
          floatingActionButton: ValueListenableBuilder<int>(
            valueListenable: _changeNotifier,
            builder: (context, _, __) {
              return _buildFabArea(isDesktop) ?? const SizedBox.shrink();
            },
          ),
          body: CustomScrollView(
            key: const PageStorageKey('daily_log_scroll'),
            controller: _verticalScrollController,
            slivers: [
              SliverToBoxAdapter(
                child: _buildHeader(config),
              ),
              // Holiday summary for the selected month
              SliverToBoxAdapter(
                child: _buildHorizontalCalendar(config, cachedHolidays),
              ),
              if (!_canSaveData())
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.isUrdu
                                ? 'صرف پڑھنے کی حد: آپ صرف موجودہ یا پچھلے مہینے کا ڈیٹا تبدیل اور محفوظ کر سکتے ہیں۔'
                                : 'Read-Only Mode: You can only edit and save daily log data for the current or previous month.',
                            style: context.urduStyle(
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (isHoliday)
                SliverToBoxAdapter(
                  child: Container(
                    height: MediaQuery.of(context).size.height - 250,
                    alignment: Alignment.center,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.green.shade200, width: 2),
                            ),
                            child: Icon(Icons.flag_rounded, size: 64, color: Colors.green.shade700),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            holidayName!,
                            style: context.urduStyle(
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              () {
                                final now = DateTime.now();
                                final isToday = _selectedDate.year == now.year &&
                                    _selectedDate.month == now.month &&
                                    _selectedDate.day == now.day;
                                if (isToday) {
                                  return context.isUrdu
                                      ? 'آج مدرسہ بند ہے'
                                      : 'Madrassa is Closed Today';
                                } else {
                                  return context.isUrdu
                                      ? 'اس دن مدرسہ بند ہے'
                                      : 'Madrassa is Closed on this Day';
                                }
                              }(),
                              style: context.urduStyle(
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (isSunday)
                SliverToBoxAdapter(
                  child: Container(
                    height: MediaQuery.of(context).size.height - 250,
                    alignment: Alignment.center,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.blue.shade200, width: 2),
                            ),
                            child: Icon(Icons.weekend_rounded, size: 64, color: Colors.blue.shade700),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            context.isUrdu ? 'اتوار کی چھٹی' : 'Weekly Holiday (Sunday)',
                            style: context.urduStyle(
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0D47A1),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_isFutureDate(_selectedDate))
                SliverToBoxAdapter(
                  child: Container(
                    height: MediaQuery.of(context).size.height - 250,
                    alignment: Alignment.center,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isPtmDay ? Icons.people_outline : Icons.calendar_today_outlined,
                            size: 64,
                            color: isPtmDay ? Colors.orange : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isPtmDay
                                ? (context.isUrdu ? 'پی ٹی ایم میٹنگ شیڈول ہے' : 'PTM Meeting Scheduled')
                                : context.l.futureDateTitle,
                            style: context.urduStyle(
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isPtmDay ? Colors.orange.shade800 : Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32.0),
                            child: Text(
                              isPtmDay
                                  ? (context.isUrdu
                                      ? 'اس تاریخ کو پیرنٹ ٹیچر میٹنگ (PTM) شیڈول ہے۔'
                                      : 'At this date, the Parent Teacher Meeting is scheduled.')
                                  : context.l.futureDateSubtitle,
                              textAlign: TextAlign.center,
                              style: context.urduStyle(
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                filteredStudentsAsyncValue.when(
                  loading: () => const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, st) => SliverToBoxAdapter(
                    child: Center(child: Text('Error: $e')),
                  ),
                  data: (students) {
                    return logAsyncValue.when(
                      loading: () => const SliverToBoxAdapter(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, st) => SliverToBoxAdapter(
                        child: Center(child: Text('Error: $e')),
                      ),
                      data: (logData) {
                        final double paddingVal = MediaQuery.of(context).size.width < 600 ? 16 : 24;

                        return SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: paddingVal),
                          sliver: SliverList(
                            key: const PageStorageKey('daily_log_student_list'),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index == 0) {
                                  return Column(
                                    children: [
                                      if (isReadOnly)
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(8),
                                          width: double.infinity,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade50,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.amber.shade200),
                                          ),
                                          child: Text(
                                            context.isUrdu ? 'صرف پڑھنے کی اجازت ہے (پرانی تاریخ)' : 'Read Only Mode (Past Date)',
                                            style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ValueListenableBuilder<int>(
                                        valueListenable: _changeNotifier,
                                        builder: (context, _, __) =>
                                            _buildStatusLegend(context, students, logData),
                                      ),
                                    ],
                                  );
                                }
                                final s = students[index - 1];
                                final sId = s['id'] ?? '';
                                final sLog = _localChanges[sId] ?? _safeMap(logData[sId]);
                                final notifier = _studentNotifiers.putIfAbsent(
                                    sId, () => ValueNotifier(sLog));
                                return _StudentLogCard(
                                  key: ValueKey('${sId}_${_selectedDate.toIso8601String()}'),
                                  student: s,
                                  logNotifier: notifier,
                                  isPtmDay: isPtmDay,
                                  isReadOnly: isReadOnly,
                                  branchId: widget.branchId,
                                  uploadStatus: _uploadStates[sId],
                                  onUpdateLocal: _updateLocalSilent,
                                  onPickPhoto: _pickAndUploadPhoto,
                                  onSendWhatsApp: _sendDailyWhatsApp,
                                  onShowCustomLines: _showCustomLinesDialog,
                                  buildParaDropdown: _buildParaDropdown,
                                  buildRatioDropdown: _buildRatioDropdown,
                                );
                              },
                              childCount: students.length + 1,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
            ],
          ),
        );
      },
    );
  }



  // Builds the status legend based on students and log data


  Widget _buildHeader(MadrassaConfig config) {
    final ptmDate = config.getPtmDate();
    final workingDays = MadrassaFeeLogic.getWorkingDaysCount(config.year, config.month);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 16 : 24, isMobile ? 16 : 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${DateFormat('MMMM yyyy').format(_selectedDate)} — ${context.l.dailyLog}',
                  style: context.urduStyle(
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isMobile ? 18 : 22,
                      color: const Color(0xFF1A1C1E),
                    ),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.today, size: 16, color: Color(0xFF008080)),
                label: Text(
                  context.isUrdu ? 'آج' : 'Today',
                  style: const TextStyle(
                    color: Color(0xFF008080),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime.now();
                    _localChanges.clear();
                    _studentNotifiers.clear();
                  });
                  _changeNotifier.value++;
                  _updateDateStreams();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToSelectedDate(animate: true);
                  });
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 16, color: Color(0xFF008080)),
                tooltip: 'Previous Month',
                onPressed: () {
                  setState(() {
                    final prevMonth = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
                    final lastDayOfPrevMonth = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
                    final targetDay = _selectedDate.day.clamp(1, lastDayOfPrevMonth);
                    _selectedDate = DateTime(prevMonth.year, prevMonth.month, targetDay);
                    _localChanges.clear();
                    _studentNotifiers.clear();
                  });
                  _changeNotifier.value++;
                  _updateDateStreams();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToSelectedDate(animate: true);
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF008080)),
                tooltip: 'Next Month',
                onPressed: () {
                  setState(() {
                    final nextMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
                    final lastDayOfNextMonth = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
                    final targetDay = _selectedDate.day.clamp(1, lastDayOfNextMonth);
                    _selectedDate = DateTime(nextMonth.year, nextMonth.month, targetDay);
                    _localChanges.clear();
                    _studentNotifiers.clear();
                  });
                  _changeNotifier.value++;
                  _updateDateStreams();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToSelectedDate(animate: true);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$workingDays working days • Sundays excluded • PTM: ${DateFormat('EEE, MMM d').format(ptmDate)}',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalCalendar(MadrassaConfig config, List<Map<String, dynamic>> holidays) {
    final daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    final ptmDate = config.getPtmDate();
    final now = DateTime.now();

    if (!_hasInitialScrollDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_calendarScrollController.hasClients) {
          _scrollToSelectedDate(animate: false);
          _hasInitialScrollDone = true;
        }
      });
    }

    final showLeftGrey = !_calendarScrollController.hasClients || _calendarScrollController.offset <= 0;
    final showRightGrey = !_calendarScrollController.hasClients || 
        (_calendarScrollController.position.hasContentDimensions &&
         _calendarScrollController.offset >= _calendarScrollController.position.maxScrollExtent);
    final leftColor = showLeftGrey ? Colors.grey : const Color(0xFF008080);
    final rightColor = showRightGrey ? Colors.grey : const Color(0xFF008080);

    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.chevron_left, color: leftColor),
          onPressed: showLeftGrey
              ? null
              : () {
                  if (_calendarScrollController.hasClients) {
                    final target = (_calendarScrollController.offset - 204.0).clamp(0.0, _calendarScrollController.position.maxScrollExtent);
                    _calendarScrollController.animateTo(
                      target,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                },
        ),
        Expanded(
          child: SizedBox(
            key: _calendarKey,
            height: 100,
            child: Listener(
              onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent && _calendarScrollController.hasClients) {
                  final newOffset = _calendarScrollController.offset + pointerSignal.scrollDelta.dy;
                  _calendarScrollController.jumpTo(
                    newOffset.clamp(
                      0.0,
                      _calendarScrollController.position.maxScrollExtent,
                    ),
                  );
                }
              },
              child: ListView.builder(
                controller: _calendarScrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: daysInMonth,
                itemBuilder: (context, i) {
                  final date = DateTime(_selectedDate.year, _selectedDate.month, i + 1);
                  final isSelected = date.day == _selectedDate.day;
                  final isSunday = date.weekday == DateTime.sunday;
                  final ptmDateForCell = getPtmDateFor(date.year, date.month, config);
                  final isPtm = date.year == ptmDateForCell.year && date.month == ptmDateForCell.month && date.day == ptmDateForCell.day;
                  final isToday = date.year == now.year && date.month == now.month && date.day == now.day;

                  String? holidayName;
                  for (var h in holidays) {
                    final dateVal = h['date'];
                    DateTime? hDate;
                    if (dateVal is String) {
                      hDate = DateTime.tryParse(dateVal);
                    } else if (dateVal is Timestamp) {
                      hDate = dateVal.toDate();
                    }
                    if (hDate != null && hDate.year == date.year && hDate.month == date.month && hDate.day == date.day) {
                      holidayName = h['name'] as String? ?? 'Holiday';
                      break;
                    }
                  }
                  final isHoliday = holidayName != null;

                  Color cardColor = Colors.white;
                  if (isSelected) {
                    cardColor = isHoliday ? const Color(0xFF2E7D32) : const Color(0xFF4C4DDC);
                  } else if (isHoliday) {
                    cardColor = const Color(0xFFE8F5E9);
                  }

                  Border border;
                  if (isSelected) {
                    border = Border.all(color: cardColor, width: 1.0);
                  } else if (isToday) {
                    border = Border.all(color: const Color(0xFF008080), width: 2.0);
                  } else if (isHoliday) {
                    border = Border.all(color: const Color(0xFF81C784), width: 1.0);
                  } else {
                    border = Border.all(color: const Color(0xFFE0E2E7), width: 1.0);
                  }

                  Color dayAbbrevColor = isSelected ? Colors.white70 : (isHoliday ? const Color(0xFF2E7D32) : Colors.grey);
                  Color dayNumColor = isSelected ? Colors.white : (isHoliday ? const Color(0xFF1B5E20) : const Color(0xFF1A1C1E));

                  return GestureDetector(
                    onTap: isSunday ? null : () {
  setState(() {
    _selectedDate = date;
    _localChanges.clear();
    _allPresentToggled = false;
    _allUniformToggled = false;
    _allRepliedToggled = false;
    _studentNotifiers.clear();
  });
  _changeNotifier.value++;
  _updateDateStreams(); // this calls _subscribeToLog() which resets _logNotifier
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _scrollToSelectedDate(animate: true);
  });
},
                    child: Opacity(
                      opacity: isSunday ? 0.3 : 1.0,
                      child: Container(
                        width: 60,
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: border,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('E').format(date).toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: dayAbbrevColor),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${date.day}',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: dayNumColor),
                            ),
                            if (isHoliday)
                              Padding(
                                padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
                                child: Text(
                                  holidayName,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: isSelected ? Colors.white : const Color(0xFF2E7D32),
                                  ),
                                ),
                              )
                            else if (isPtm)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'PTM',
                                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : const Color(0xFFD32F2F)),
                                ),
                              ),
                            if (isToday)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.white : (isHoliday ? const Color(0xFF2E7D32) : const Color(0xFF008080)),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.chevron_right, color: rightColor),
          onPressed: showRightGrey
              ? null
              : () {
                  if (_calendarScrollController.hasClients) {
                    final target = (_calendarScrollController.offset + 204.0).clamp(0.0, _calendarScrollController.position.maxScrollExtent);
                    _calendarScrollController.animateTo(
                      target,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                },
        ),
      ],
    );
  }

  Widget _buildStatusLegend(BuildContext context, List<Map<String, dynamic>> students, Map<String, dynamic> logData) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isReadOnly = !_canSaveData();
    int present = 0, leave = 0, absent = 0, replied = 0;
    for (var s in students) {
      final sId = s['id'] ?? '';
      final log = _localChanges[sId] ?? _safeMap(logData[sId]);
      final att = log['attendance'] ?? 'absent';
      if (att == 'present') {
        present++;
      } else if (att == 'leave') {
        leave++;
      } else {
        absent++;
      }
      if (log['parentReplied'] == true) replied++;
    }

    final dateText = DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate);

    // Date & stats section
    Widget dateAndStatsWidget;
    if (isMobile) {
      dateAndStatsWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateText,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A1C1E)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _statText('${context.l.present}: $present', const Color(0xFF4CAF50)),
              _statText('${context.l.leave}: $leave', const Color(0xFFF5A623)),
              _statText('${context.l.absent}: $absent', const Color(0xFFE53935)),
              _statText(context.isUrdu ? 'جوابات: $replied' : 'Replied: $replied', const Color(0xFFFFA726)),
            ],
          ),
        ],
      );
    } else {
      dateAndStatsWidget = Row(
        children: [
          Expanded(
            child: Text(
              dateText,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A1C1E)),
            ),
          ),
          _statText('${context.l.present}: $present', const Color(0xFF4CAF50)),
          const SizedBox(width: 12),
          _statText('${context.l.leave}: $leave', const Color(0xFFF5A623)),
          const SizedBox(width: 12),
          _statText('${context.l.absent}: $absent', const Color(0xFFE53935)),
          const SizedBox(width: 12),
          _statText(context.isUrdu ? 'جوابات: $replied' : 'Replied: $replied', const Color(0xFFFFA726)),
        ],
      );
    }

    // Actions & Legends section
    Widget actionsAndLegendsWidget;
    if (isDesktop) {
      actionsAndLegendsWidget = Row(
        children: [
          _efficiencyButton(
            label: context.l.allPresent,
            icon: Icons.done_all,
            color: const Color(0xFF4CAF50),
            isSelected: _allPresentToggled,
            onTap: isReadOnly ? null : () {
              setState(() {
                _allPresentToggled = !_allPresentToggled;
                for (var s in students) {
                  final sId = s['id'] ?? '';
                  final log = _safeMap(logData[sId]);
                  final currentAtt = _localChanges[sId]?['attendance'] ?? log['attendance'];
                  if (currentAtt != 'leave') {
                    _updateAttendanceSilent(sId, _allPresentToggled ? 'present' : 'absent');
                  }
                }
              });
            },
          ),
          const SizedBox(width: 8),
          _efficiencyButton(
            label: context.l.allUniform,
            icon: Icons.check_circle_outline,
            color: const Color(0xFF5B9BD5),
            isSelected: _allUniformToggled,
            onTap: isReadOnly ? null : () {
              setState(() {
                _allUniformToggled = !_allUniformToggled;
                for (var s in students) {
                  final sId = s['id'] ?? '';
                  final log = _safeMap(logData[sId]);
                  final currentAtt = _localChanges[sId]?['attendance'] ?? log['attendance'];
                  if (currentAtt == 'present') {
                    _updateLocalSilent(sId, 'uniform', _allUniformToggled);
                  }
                }
              });
            },
          ),
          const SizedBox(width: 8),
          _efficiencyButton(
            label: context.isUrdu ? 'سب نے جواب دیا' : 'All Replied',
            icon: Icons.message_outlined,
            color: const Color(0xFFFFA726),
            isSelected: _allRepliedToggled,
            onTap: isReadOnly ? null : () {
              setState(() {
                _allRepliedToggled = !_allRepliedToggled;
                for (var s in students) {
                  final sId = s['id'] ?? '';
                  _updateLocalSilent(sId, 'parentReplied', _allRepliedToggled);
                }
              });
            },
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _localChanges.isEmpty || _isSaving || isReadOnly ? null : _saveChanges,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5),
                  )
                : const Icon(Icons.save, size: 16),
            label: Text(context.l.saveChanges, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF008080), // Teal
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),

        ],
      );
    } else {
      actionsAndLegendsWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _efficiencyButton(
                label: context.l.allPresent,
                icon: Icons.done_all,
                color: const Color(0xFF4CAF50),
                isSelected: _allPresentToggled,
                onTap: isReadOnly ? null : () {
                  setState(() {
                    _allPresentToggled = !_allPresentToggled;
                    for (var s in students) {
                      final sId = s['id'] ?? '';
                      final log = _safeMap(logData[sId]);
                      final currentAtt = _localChanges[sId]?['attendance'] ?? log['attendance'];
                      if (currentAtt != 'leave') {
                        _updateAttendanceSilent(sId, _allPresentToggled ? 'present' : 'absent');
                      }
                    }
                  });
                },
              ),
              _efficiencyButton(
                label: context.l.allUniform,
                icon: Icons.check_circle_outline,
                color: const Color(0xFF5B9BD5),
                isSelected: _allUniformToggled,
                onTap: isReadOnly ? null : () {
                  setState(() {
                    _allUniformToggled = !_allUniformToggled;
                    for (var s in students) {
                      final sId = s['id'] ?? '';
                      final log = _safeMap(logData[sId]);
                      final currentAtt = _localChanges[sId]?['attendance'] ?? log['attendance'];
                      if (currentAtt == 'present') {
                        _updateLocalSilent(sId, 'uniform', _allUniformToggled);
                      }
                    }
                  });
                },
              ),
              _efficiencyButton(
                label: context.isUrdu ? 'سب نے جواب دیا' : 'All Replied',
                icon: Icons.message_outlined,
                color: const Color(0xFFFFA726),
                isSelected: _allRepliedToggled,
                onTap: isReadOnly ? null : () {
                  setState(() {
                    _allRepliedToggled = !_allRepliedToggled;
                    for (var s in students) {
                      final sId = s['id'] ?? '';
                      _updateLocalSilent(sId, 'parentReplied', _allRepliedToggled);
                    }
                  });
                },
              ),
            ],
          ),

        ],
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 0,
        vertical: isMobile ? 12 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dateAndStatsWidget,
          SizedBox(height: isMobile ? 12 : 16),
          actionsAndLegendsWidget,
        ],
      ),
    );
  }

  Widget _efficiencyButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDisabled 
              ? Colors.grey.shade200 
              : (isSelected ? color : color.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDisabled 
                ? Colors.grey.shade300 
                : (isSelected ? color : color.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isDisabled ? Colors.grey : (isSelected ? Colors.white : color)),
            const SizedBox(width: 8),
            Text(
              label,
              style: context.urduStyle(
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDisabled ? Colors.grey : (isSelected ? Colors.white : color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statText(String label, Color color) {
    return Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14));
  }



  Widget _buildParaDropdown(BuildContext context, int? selectedValue, bool isEnabled, ValueChanged<int?>? onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E2E7)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: (selectedValue == null || selectedValue == 0) ? null : selectedValue,
          hint: Text('-', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          icon: const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF008080)),
          isDense: true,
          isExpanded: true,
          style: const TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold),
          items: [
            for (int i = 1; i <= 30; i++)
              DropdownMenuItem(
                value: i,
                child: Text('$i', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
          onChanged: isEnabled ? onChanged : null,
        ),
      ),
    );
  }

  Widget _buildRatioDropdown(BuildContext context, String? selectedValue, bool isEnabled, ValueChanged<String?>? onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E2E7)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: (selectedValue == null || selectedValue.isEmpty || selectedValue == '-') ? null : selectedValue,
          hint: Text('-', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          icon: const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF008080)),
          isDense: true,
          isExpanded: true,
          style: const TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold),
          items: [
            DropdownMenuItem(value: '1/4', child: Text(context.isUrdu ? 'پاؤ' : 'Pao')),
            DropdownMenuItem(value: '1/2', child: Text(context.isUrdu ? 'نصف' : 'Nisf')),
            DropdownMenuItem(value: '3/4', child: Text(context.isUrdu ? 'ثلاثہ' : 'Salasa')),
            DropdownMenuItem(value: '1', child: Text(context.isUrdu ? 'پارہ' : 'Para')),
            DropdownMenuItem(value: 'nahi_sunaya', child: Text(context.isUrdu ? 'نہیں سنایا' : 'Nahi Sunaya')),
          ],
          onChanged: isEnabled ? onChanged : null,
        ),
      ),
    );
  }



  Future<void> _pickAndUploadPhoto(String studentId) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      if (!mounted) return;
      setState(() => _uploadStates[studentId] = PhotoUploadStatus.uploading);

      final bytes = await picked.readAsBytes();
      
      final uploadStream = PhotoUploadHelper.upload(
        bytes: bytes,
        branchId: widget.branchId,
        studentId: studentId,
      );

      await for (final state in uploadStream) {
        if (!mounted) return;
        setState(() {
          _uploadStates[studentId] = state.status;
        });

        if (state.status == PhotoUploadStatus.success) {
          final downloadUrl = state.downloadUrl;
          if (downloadUrl != null && downloadUrl.isNotEmpty) {
            await FirebaseFirestore.instance
                .collection('branches')
                .doc(widget.branchId)
                .collection('madrassa_students')
                .doc(studentId)
                .update({'photoUrl': downloadUrl});

            // Update local student cache instantly
            final studentCache = MadrassaLocalStorage.getStudentCached(widget.branchId, studentId);
            if (studentCache != null) {
              studentCache['photoUrl'] = downloadUrl;
              await MadrassaLocalStorage.cacheStudent(widget.branchId, studentId, studentCache);
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Photo updated')),
              );
            }
          }
        } else if (state.status == PhotoUploadStatus.error) {
          throw Exception(state.error ?? 'Upload error');
        }
      }
    } catch (e) {
      debugPrint('Error picking or uploading image: $e');
      if (!mounted) return;
      setState(() => _uploadStates[studentId] = PhotoUploadStatus.error);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo upload failed, try again.')),
      );
    }
  }

  void _showCustomLinesDialog(BuildContext context, String studentId, int currentLines) {
    final textCtrl = TextEditingController(text: currentLines.toString());
    // Auto-select text so user can just type a number to replace it immediately.
    textCtrl.selection = TextSelection(baseOffset: 0, extentOffset: textCtrl.text.length);

    showDialog(
      context: context,
      builder: (dContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            context.isUrdu ? 'سبق کی لائنیں درج کریں' : 'Enter Custom Sabak Lines',
            style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          content: TextField(
            controller: textCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'e.g. 15',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF008080), width: 2),
              ),
            ),
            onSubmitted: (val) {
              final newLines = int.tryParse(val.trim());
              if (newLines != null && newLines >= 0) {
                _updateLocalSilent(studentId, 'currentLines', newLines);
                Navigator.of(dContext).pop();
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dContext).pop(),
              child: Text(
                context.l.cancel,
                style: context.urduStyle(style: const TextStyle(color: Colors.grey)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF008080),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final newLines = int.tryParse(textCtrl.text.trim());
                if (newLines != null && newLines >= 0) {
                  _updateLocalSilent(studentId, 'currentLines', newLines);
                  Navigator.of(dContext).pop();
                }
              },
              child: Text(
                context.l.save,
                style: context.urduStyle(),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendDailyWhatsApp(Map<String, dynamic> s, Map<String, dynamic> log) async {
    final studentData = s;
    final sId = s['id'] ?? '';

    // Get parent phone
    final String rawPhone = studentData['contactPhone']?.toString() ?? studentData['phone']?.toString() ?? '';
    if (rawPhone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Parent contact phone number not provided.')),
      );
      return;
    }

    // Clean phone number
    String phone = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.startsWith('0')) {
      phone = '92${phone.substring(1)}';
    }
    phone = phone.replaceAll('+', '');
    if (!phone.startsWith('92') && phone.length == 10) {
      phone = '92$phone';
    }

    // Load actual log data combining local changes and DB log
    final currentLog = _localChanges[sId] ?? log;
    final att = currentLog['attendance']?.toString() ?? 'absent';
    final uni = currentLog['uniform'] == true;
    
    final int lines = currentLog['currentLines'] is int ? currentLog['currentLines'] as int : (int.tryParse(currentLog['currentLines']?.toString() ?? '') ?? 0);
    final int sabkiParaVal = currentLog['sabkiPara'] is int ? currentLog['sabkiPara'] as int : (int.tryParse(currentLog['sabkiPara']?.toString() ?? '') ?? 0);
    final String? sabkiRatioVal = currentLog['sabkiRatio']?.toString();
    final int manzilParaVal = currentLog['manzilPara'] is int ? currentLog['manzilPara'] as int : (int.tryParse(currentLog['manzilPara']?.toString() ?? '') ?? 0);
    final String? manzilRatioVal = currentLog['manzilRatio']?.toString();

    String formatRatio(String? ratio) {
      if (ratio == '1/4') return '1/4';
      if (ratio == '1/2') return '1/2';
      if (ratio == '3/4') return '3/4';
      if (ratio == '1') return '1';
      if (ratio == 'nahi_sunaya') return ' نہیں سنایا';
      return ratio ?? '-';
    }

    // Attendance label formatting
    String attTextEn = 'Absent';
    String attTextUr = 'غیر حاضر';
    if (att == 'present') {
      attTextEn = 'Present';
      attTextUr = 'حاضر';
    } else if (att == 'leave') {
      attTextEn = 'On Leave';
      attTextUr = 'رخصت';
    }

    final dateStr = DateFormat('dd-MM-yyyy').format(_selectedDate);
    final studentName = studentData['name'] ?? '—';
    final rollNumber = studentData['rollNumber'] ?? '?';

    // Format Sabak/Sabki/Manzil strings for message
    String sabakMsg = 'Lines: $lines';
    
    String sabkiMsg = 'No test today';
    if (sabkiParaVal > 0 && sabkiRatioVal != null && sabkiRatioVal.isNotEmpty && sabkiRatioVal != '-') {
      sabkiMsg = 'Para $sabkiParaVal (${formatRatio(sabkiRatioVal)})';
    } else if (sabkiRatioVal == 'nahi_sunaya') {
      sabkiMsg = 'نہیں سنایا';
    }

    String manzilMsg = 'No test today';
    if (manzilParaVal > 0 && manzilRatioVal != null && manzilRatioVal.isNotEmpty && manzilRatioVal != '-') {
      manzilMsg = 'Para $manzilParaVal (${formatRatio(manzilRatioVal)})';
    } else if (manzilRatioVal == 'nahi_sunaya') {
      manzilMsg = 'نہیں سنایا';
    }

    final String uniformMsg = uni ? 'Clean / صاف' : 'Incomplete / Not Clean / نامکمل یا صاف نہیں';

    final String message = 
        '*Gulzar Madina Welfare Foundation (Madrassa)*\n'
        '*Daily Progress Report | روزانہ کارکردگی رپورٹ*\n'
        '--------------------------------------------\n'
        '*Date / تاریخ:* $dateStr\n'
        '*Student / طالب علم:*          $studentName (Roll: $rollNumber)\n'
        '*Attendance / حاضری:*     $attTextEn / $attTextUr\n'
        '${att == 'present' ? '*Uniform / لباس:*               $uniformMsg\n' : ''}'
        '\n'
        '${att == 'present' ? '*Daily Progress / روزانہ کارکردگی:*\n'
        '• *Sabak:* $sabakMsg\n'
        '• *Sabki:* $sabkiMsg\n'
        '• *Manzil:* $manzilMsg\n' : ''}'
        '--------------------------------------------\n'
        'JazakAllah Khair! / جزاک اللہ خیر!';

    final waUri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');

    try {
      final success = await launchUrl(waUri, mode: LaunchMode.externalApplication);
      if (!success) {
        throw 'Could not launch URL';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch WhatsApp.')),
        );
      }
    }
  }



  Widget? _buildFabArea(bool isDesktop) {
    final showSave = _localChanges.isNotEmpty && !isDesktop;
    final showTop = _showBackToTop;

    if (!showSave && !showTop) return null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTop) ...[
            FloatingActionButton(
              heroTag: 'btn_back_to_top',
              mini: true,
              backgroundColor: const Color(0xFF008080).withValues(alpha: 0.8),
              foregroundColor: Colors.white,
              onPressed: () {
                _verticalScrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              },
              child: const Icon(Icons.arrow_upward),
            ),
            const SizedBox(width: 12),
          ],
          if (showSave)
            ElevatedButton.icon(
              onPressed: _isSaving || !_canSaveData() ? null : _saveChanges,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(context.l.saveChanges),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF008080), // Teal
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }
}


class SegmentedAttendanceToggle extends StatelessWidget {
  final String value; // 'present', 'leave', 'absent'
  final ValueChanged<String>? onChanged;
  final bool showLabel;

  const SegmentedAttendanceToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget toggle = Container(
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFEDF0F5),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegment(
            context: context,
            label: 'P',
            isSelected: value == 'present',
            activeColor: const Color(0xFF10B981), // Emerald green
            onTap: onChanged == null ? null : () => onChanged!('present'),
          ),
          const SizedBox(width: 4),
          _buildSegment(
            context: context,
            label: 'L',
            isSelected: value == 'leave',
            activeColor: const Color(0xFFF59E0B), // Orange/yellow
            onTap: onChanged == null ? null : () => onChanged!('leave'),
          ),
          const SizedBox(width: 4),
          _buildSegment(
            context: context,
            label: 'A',
            isSelected: value == 'absent',
            activeColor: const Color(0xFFEF4444), // Red
            onTap: onChanged == null ? null : () => onChanged!('absent'),
          ),
        ],
      ),
    );

    if (showLabel) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            context.l.attendance,
            style: context.urduStyle(
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF78909C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 2),
          toggle,
        ],
      );
    }
    return toggle;
  }

  Widget _buildSegment({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 32,
        height: 30,
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF64748B),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _StudentLogCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final ValueNotifier<Map<String, dynamic>> logNotifier;
  final bool isPtmDay;
  final bool isReadOnly;
  final String branchId;
  final PhotoUploadStatus? uploadStatus;
  final Function(String sId, String key, dynamic value) onUpdateLocal;
  final Function(String sId) onPickPhoto;
  final Function(Map<String, dynamic> s, Map<String, dynamic> log) onSendWhatsApp;
  final Function(BuildContext context, String sId, int currentLines) onShowCustomLines;
  final Widget Function(BuildContext context, int? selectedValue, bool isEnabled, ValueChanged<int?>? onChanged) buildParaDropdown;
  final Widget Function(BuildContext context, String? selectedValue, bool isEnabled, ValueChanged<String?>? onChanged) buildRatioDropdown;

  const _StudentLogCard({
    super.key,
    required this.student,
    required this.logNotifier,
    required this.isPtmDay,
    required this.isReadOnly,
    required this.branchId,
    this.uploadStatus,
    required this.onUpdateLocal,
    required this.onPickPhoto,
    required this.onSendWhatsApp,
    required this.onShowCustomLines,
    required this.buildParaDropdown,
    required this.buildRatioDropdown,
  });

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _attButton(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: active ? color : const Color(0xFFE8EAED),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF9E9E9E),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _switchCol(BuildContext context, String label, bool val, ValueChanged<bool>? onChanged, {Color? activeColor, Color? trackColor}) {
    return Column(
      children: [
        Text(
          label,
          style: context.urduStyle(style: const TextStyle(fontSize: 10, color: Color(0xFF78909C), fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 2),
        Switch(
          value: val,
          onChanged: onChanged,
          activeColor: activeColor ?? const Color(0xFF5B9BD5),
          activeTrackColor: trackColor ?? (activeColor ?? const Color(0xFF5B9BD5)).withValues(alpha: 0.4),
          inactiveThumbColor: const Color(0xFFBDBDBD),
          inactiveTrackColor: const Color(0xFFE0E0E0),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  Widget _buildSabakField(BuildContext context, String sId, int lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.isUrdu ? 'سبق (لائنیں)' : 'Sabak (Lines)',
          style: context.urduStyle(style: const TextStyle(fontSize: 11, color: Color(0xFF495057), fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFE53935), size: 20),
              onPressed: (isReadOnly || lines == 0)
                  ? null
                  : () {
                      onUpdateLocal(sId, 'currentLines', lines - 1);
                    },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: isReadOnly ? null : () => onShowCustomLines(context, sId, lines),
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE0E2E7)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$lines',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Color(0xFF2E7D32), size: 20),
              onPressed: isReadOnly
                  ? null
                  : () {
                      onUpdateLocal(sId, 'currentLines', lines + 1);
                    },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSabkiField(BuildContext context, int sabkiPara, String? sabkiRatio) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.isUrdu ? 'سبکی (پارہ / تناسب)' : 'Sabki (Para / Ratio)',
          style: context.urduStyle(style: const TextStyle(fontSize: 11, color: Color(0xFF495057), fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              flex: 5,
               child: buildParaDropdown(context, sabkiPara, !isReadOnly, isReadOnly ? null : (val) {
                onUpdateLocal(student['id'] ?? '', 'sabkiPara', val ?? 0);
              }),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 6,
              child: buildRatioDropdown(context, sabkiRatio, !isReadOnly, isReadOnly ? null : (val) {
                onUpdateLocal(student['id'] ?? '', 'sabkiRatio', val ?? '-');
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildManzilField(BuildContext context, int manzilPara, String? manzilRatio) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.isUrdu ? 'منزل (پارہ / تناسب)' : 'Manzil (Para / Ratio)',
          style: context.urduStyle(style: const TextStyle(fontSize: 11, color: Color(0xFF495057), fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: buildParaDropdown(context, manzilPara, !isReadOnly, isReadOnly ? null : (val) {
                onUpdateLocal(student['id'] ?? '', 'manzilPara', val ?? 0);
              }),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 6,
              child: buildRatioDropdown(context, manzilRatio, !isReadOnly, isReadOnly ? null : (val) {
                onUpdateLocal(student['id'] ?? '', 'manzilRatio', val ?? '-');
              }),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: logNotifier,
      builder: (context, log, child) {
        final studentData = student;
        final sId = student['id'] ?? '';

        final name = studentData['name'] ?? '—';
        final rollNumber = studentData['rollNumber']?.toString() ?? '?';
        final photoUrl = studentData['photoUrl'] ?? studentData['photo_url'];

        final att = log['attendance'] ?? 'absent';
        final uni = log['uniform'] ?? false;
        final msg = log['parentReplied'] ?? false;
        final isParentRequested = log['isParentRequested'] == true;
        final parentRepliedRequested = log['parentRepliedRequested'] == true;
        final leaveStatus = log['leaveStatus'] ?? 'pending';

        final int lines = log['currentLines'] is int ? log['currentLines'] as int : (int.tryParse(log['currentLines']?.toString() ?? '') ?? 0);
        final int sabkiPara = log['sabkiPara'] is int ? log['sabkiPara'] as int : (int.tryParse(log['sabkiPara']?.toString() ?? '') ?? 0);
        final String? sabkiRatio = log['sabkiRatio']?.toString();
        final int manzilPara = log['manzilPara'] is int ? log['manzilPara'] as int : (int.tryParse(log['manzilPara']?.toString() ?? '') ?? 0);
        final String? manzilRatio = log['manzilRatio']?.toString();

        Widget avatarWidget;
        if (uploadStatus == PhotoUploadStatus.uploading) {
          avatarWidget = const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF008080)),
          );
        } else if (photoUrl != null && photoUrl.isNotEmpty) {
          avatarWidget = ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              photoUrl,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 32,
                height: 32,
                color: const Color(0xFFE0F2F1),
                alignment: Alignment.center,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Color(0xFF008080), fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          );
        } else {
          avatarWidget = Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2F1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Color(0xFF008080), fontWeight: FontWeight.bold, fontSize: 13),
            ),
          );
        }

        avatarWidget = GestureDetector(
          onTap: isReadOnly ? null : () {
            if (photoUrl != null && photoUrl.isNotEmpty) {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 28),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: InteractiveViewer(
                          maxScale: 4.0,
                          child: Image.network(
                            photoUrl,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.black.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          onPickPhoto(sId);
                        },
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Change Photo'),
                      ),
                    ],
                  ),
                ),
              );
            } else {
              onPickPhoto(sId);
            }
          },
          child: avatarWidget,
        );

        Widget topRow = Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                rollNumber,
                style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            avatarWidget,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            IconButton(
              icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366), size: 20),
              onPressed: () => onSendWhatsApp(student, log),
              tooltip: 'Send WhatsApp report',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            if (isPtmDay) ...[
              const SizedBox(width: 8),
              _attButton('J', log['ptm'] == true, const Color(0xFF2E7D32), isReadOnly ? () {} : () => onUpdateLocal(sId, 'ptm', true)),
              const SizedBox(width: 4),
              _attButton('M', log['ptm'] == false, const Color(0xFFD32F2F), isReadOnly ? () {} : () => onUpdateLocal(sId, 'ptm', false)),
            ],
          ],
        );

        Widget middleRow = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (isParentRequested && leaveStatus == 'pending')
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _actionButton('Approve', Colors.green, () {
                      onUpdateLocal(sId, 'attendance', 'leave');
                      onUpdateLocal(sId, 'leaveStatus', 'approved');
                    }),
                    const SizedBox(width: 8),
                    _actionButton('Deny', Colors.red, () {
                      onUpdateLocal(sId, 'attendance', 'absent');
                      onUpdateLocal(sId, 'leaveStatus', 'denied');
                    }),
                  ],
                ),
              )
            else ...[
              SegmentedAttendanceToggle(
                value: att,
                onChanged: isReadOnly ? null : (newAtt) {
                  onUpdateLocal(sId, 'attendance', newAtt);
                  if (newAtt != 'present') {
                    onUpdateLocal(sId, 'uniform', false);
                  }
                },
                showLabel: false,
              ),
              _switchCol(
                context,
                context.l.uniform,
                uni,
                (att == 'present' && !isReadOnly) ? (v) => onUpdateLocal(sId, 'uniform', v) : null,
              ),
              _switchCol(
                context,
                context.l.parentReplied,
                msg,
                isReadOnly ? null : (v) => onUpdateLocal(sId, 'parentReplied', v),
                activeColor: const Color(0xFFFFA726),
                trackColor: const Color(0xFFFFCC80),
              ),
            ]
          ],
        );

        Widget desktopRow = Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                rollNumber,
                style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ),
            avatarWidget,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (isParentRequested && leaveStatus == 'pending')
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        'Parent requested a leave: ${log['leaveReason'] ?? "No reason"}',
                        style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                      ),
                    ),
                  if (parentRepliedRequested && msg != true)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Parent requested reply verification',
                            style: TextStyle(fontSize: 11, color: Colors.purple.shade900, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          _actionButton('Approve Reply', Colors.purple, () {
                            onUpdateLocal(sId, 'parentReplied', true);
                            onUpdateLocal(sId, 'parentRepliedRequested', false);
                          }),
                          const SizedBox(width: 8),
                          _actionButton('Deny', Colors.red, () {
                            onUpdateLocal(sId, 'parentRepliedRequested', false);
                          }),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isParentRequested && leaveStatus == 'pending')
              Row(
                children: [
                  _actionButton('Approve', Colors.green, isReadOnly ? () {} : () {
                    onUpdateLocal(sId, 'attendance', 'leave');
                    onUpdateLocal(sId, 'leaveStatus', 'approved');
                  }),
                  const SizedBox(width: 8),
                  _actionButton('Deny', Colors.red, isReadOnly ? () {} : () {
                    onUpdateLocal(sId, 'attendance', 'absent');
                    onUpdateLocal(sId, 'leaveStatus', 'denied');
                  }),
                ],
              )
            else
              SegmentedAttendanceToggle(
                value: att,
                onChanged: isReadOnly ? null : (newAtt) {
                  onUpdateLocal(sId, 'attendance', newAtt);
                  if (newAtt != 'present') {
                    onUpdateLocal(sId, 'uniform', false);
                  }
                },
                showLabel: true,
              ),
            const SizedBox(width: 24),
            _switchCol(
              context,
              context.l.uniform,
              uni,
              (att == 'present' && !isReadOnly) ? (v) => onUpdateLocal(sId, 'uniform', v) : null,
            ),
            const SizedBox(width: 24),
            _switchCol(
              context,
              context.l.parentReplied,
              msg,
              isReadOnly ? null : (v) => onUpdateLocal(sId, 'parentReplied', v),
              activeColor: const Color(0xFFFFA726),
              trackColor: const Color(0xFFFFCC80),
            ),
            const SizedBox(width: 24),
            IconButton(
              icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366), size: 20),
              onPressed: () => onSendWhatsApp(student, log),
              tooltip: 'Send WhatsApp report',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            if (isPtmDay) ...[
              const SizedBox(width: 24),
              Column(
                children: [
                  Text(
                    context.l.ptm,
                    style: context.urduStyle(style: const TextStyle(fontSize: 10, color: Color(0xFF78909C), fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _attButton('J', log['ptm'] == true, const Color(0xFF2E7D32), isReadOnly ? () {} : () => onUpdateLocal(sId, 'ptm', true)),
                      const SizedBox(width: 4),
                      _attButton('M', log['ptm'] == false, const Color(0xFFD32F2F), isReadOnly ? () {} : () => onUpdateLocal(sId, 'ptm', false)),
                    ],
                  ),
                ],
              ),
            ],
          ],
        );

        Widget progressSection = const SizedBox.shrink();
        if (att == 'present') {
          progressSection = Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE9ECEF)),
            ),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSabakField(context, sId, lines),
                      const SizedBox(height: 12),
                      _buildSabkiField(context, sabkiPara, sabkiRatio),
                      const SizedBox(height: 12),
                      _buildManzilField(context, manzilPara, manzilRatio),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildSabakField(context, sId, lines)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildSabkiField(context, sabkiPara, sabkiRatio)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildManzilField(context, manzilPara, manzilRatio)),
                    ],
                  ),
          );
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E2E7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              isMobile
                  ? Column(
                      children: [
                        topRow,
                        const SizedBox(height: 8),
                        if (isParentRequested && leaveStatus == 'pending') ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4)),
                            width: double.infinity,
                            child: Text(
                              'Parent requested a leave: ${log['leaveReason'] ?? "No reason"}',
                              style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                        if (parentRepliedRequested && msg != true) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.purple.shade200),
                            ),
                            width: double.infinity,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Parent requested reply verification',
                                    style: TextStyle(fontSize: 11, color: Colors.purple.shade900, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                _actionButton('Approve Reply', Colors.purple, isReadOnly ? () {} : () {
                                  onUpdateLocal(sId, 'parentReplied', true);
                                  onUpdateLocal(sId, 'parentRepliedRequested', false);
                                }),
                                const SizedBox(width: 8),
                                _actionButton('Deny', Colors.red, isReadOnly ? () {} : () {
                                  onUpdateLocal(sId, 'parentRepliedRequested', false);
                                }),
                              ],
                            ),
                          ),
                        ],
                        middleRow,
                      ],
                    )
                  : desktopRow,
              progressSection,
            ],
          ),
        );
      },
    );
  }
}