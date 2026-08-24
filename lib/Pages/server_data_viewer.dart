import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../services/local_storage_service.dart';

class ServerDataViewer extends StatefulWidget {
  final String branchId;

  const ServerDataViewer({super.key, required this.branchId});

  @override
  State<ServerDataViewer> createState() => _ServerDataViewerState();
}

class _ServerDataViewerState extends State<ServerDataViewer> {
  String _selectedDateKey = '';
  String _selectedCategory = 'all';
  String _searchQuery = '';
  bool _sortNewestFirst = true;

  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, String>> _categories = const [
    {'id': 'all', 'label': 'All Categories', 'icon': '📂'},
    {'id': 'dispensary', 'label': 'Dispensary & OPD', 'icon': '🏥'},
    {'id': 'madrassa', 'label': 'Madrassa & Education', 'icon': '🎓'},
    {'id': 'school', 'label': 'School & Library', 'icon': '🏫'},
    {'id': 'finance', 'label': 'Finance & Donations', 'icon': '💰'},
    {'id': 'dasterkhwaan', 'label': 'Dasterkhwaan & Welfare', 'icon': '🍲'},
    {'id': 'system', 'label': 'System & Sync Logs', 'icon': '⚙️'},
    {'id': 'failed_outbox', 'label': 'Failed Outbox (Errors)', 'icon': '🚨'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedDateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _detectCategory(Map<String, dynamic> entry) {
    final qt = (entry['queueType'] ?? entry['category'] ?? entry['type'] ?? '').toString().toLowerCase();
    final dataStr = jsonEncode(entry).toLowerCase();

    if (qt.contains('madrassa') || dataStr.contains('madrassa') || dataStr.contains('hafiz') || dataStr.contains('tajweed')) {
      return 'madrassa';
    }
    if (qt.contains('school') || dataStr.contains('school') || qt.contains('library')) {
      return 'school';
    }
    if (qt.contains('donation') || qt.contains('finance') || qt.contains('expense') || qt.contains('loan') || dataStr.contains('amount_paid')) {
      return 'finance';
    }
    if (qt.contains('food') || qt.contains('dasterkhwaan') || qt.contains('ration')) {
      return 'dasterkhwaan';
    }
    if (qt.contains('sync') || qt.contains('heartbeat') || qt.contains('system')) {
      return 'system';
    }
    // Default fallback to dispensary/OPD for patient entries
    return 'dispensary';
  }

  void _showEntryDetails(BuildContext context, Map<String, dynamic> entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2937),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final category = _detectCategory(entry);
        final serial = entry['serial']?.toString() ?? 'N/A';
        final name = entry['patientName'] ?? entry['name'] ?? entry['title'] ?? 'Record Payload';
        final status = (entry['status'] ?? 'waiting').toString();
        final prettyJson = const JsonEncoder.withIndent('  ').convert(entry);

        return Container(
          height: MediaQuery.of(ctx).size.height * 0.75,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '#$serial - $name',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Chip(
                    avatar: Text(_categories.firstWhere((c) => c['id'] == category)['icon'] ?? '📁'),
                    label: Text(category.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
                    side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.4)),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    backgroundColor: status == 'completed' ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                    side: BorderSide(color: status == 'completed' ? Colors.green : Colors.orange),
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 24),
              const Text('RAW RECORD PAYLOAD:', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0F19),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      prettyJson,
                      style: const TextStyle(color: Color(0xFF10B981), fontFamily: 'monospace', fontSize: 13, height: 1.4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2937),
        elevation: 0,
        title: const Text('Server Data Archive', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_sortNewestFirst ? Icons.sort_rounded : Icons.history_rounded, color: Colors.white70),
            tooltip: _sortNewestFirst ? 'Sorting: Newest First' : 'Sorting: Oldest First',
            onPressed: () {
              setState(() {
                _sortNewestFirst = !_sortNewestFirst;
              });
            },
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box(LocalStorageService.entriesBox).listenable(),
        builder: (context, Box box, _) {
          List<Map<String, dynamic>> allEntries = LocalStorageService.getLocalEntries(widget.branchId);
          if (_selectedCategory == 'failed_outbox') {
            try {
              if (Hive.isBoxOpen('realtime_failed_outbox')) {
                final failedBox = Hive.box('realtime_failed_outbox');
                allEntries = failedBox.values
                    .whereType<Map>()
                    .map((m) => Map<String, dynamic>.from(m))
                    .toList();
              }
            } catch (_) {}
          }

          // Group by dateKey
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (final entry in allEntries) {
            final dk = entry['dateKey']?.toString() ?? 'unknown';
            grouped.putIfAbsent(dk, () => []).add(entry);
          }

          final sortedDates = grouped.keys.toList()..sort((a, b) => _sortNewestFirst ? b.compareTo(a) : a.compareTo(b));

          if (sortedDates.isEmpty) {
            return const Center(
              child: Text(
                'No data saved on this server yet.',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            );
          }

          if (!sortedDates.contains(_selectedDateKey) && sortedDates.isNotEmpty) {
            _selectedDateKey = sortedDates.first;
          }

          final rawCurrentList = grouped[_selectedDateKey] ?? [];

          // Filter by category and search query
          final filteredList = rawCurrentList.where((entry) {
            if (_selectedCategory != 'all') {
              final cat = _detectCategory(entry);
              if (cat != _selectedCategory) return false;
            }
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final serial = (entry['serial'] ?? '').toString().toLowerCase();
              final name = (entry['patientName'] ?? entry['name'] ?? '').toString().toLowerCase();
              final by = (entry['performedBy'] ?? '').toString().toLowerCase();
              final qt = (entry['queueType'] ?? '').toString().toLowerCase();

              return serial.contains(q) || name.contains(q) || by.contains(q) || qt.contains(q);
            }
            return true;
          }).toList();

          filteredList.sort((a, b) {
            final tA = (a['createdAt'] ?? '').toString();
            final tB = (b['createdAt'] ?? '').toString();
            return _sortNewestFirst ? tB.compareTo(tA) : tA.compareTo(tB);
          });

          return Column(
            children: [
              // Top Bar Filters: Category Chips + Search Bar
              Container(
                color: const Color(0xFF1F2937),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    // Search Bar
                    TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search by serial #, patient, staff, or category...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF0B0F19),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onChanged: (val) {
                        setState(() => _searchQuery = val.trim());
                      },
                    ),
                    const SizedBox(height: 10),
                    // Category Chips Scroll
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (ctx, idx) {
                          final cat = _categories[idx];
                          final isSelected = cat['id'] == _selectedCategory;
                          return ChoiceChip(
                            avatar: Text(cat['icon']!),
                            label: Text(
                              cat['label']!,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: Colors.blueAccent,
                            backgroundColor: const Color(0xFF0B0F19),
                            onSelected: (_) {
                              setState(() => _selectedCategory = cat['id']!);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Main Layout: Dates Sidebar + Categorized Entries Grid/List
              Expanded(
                child: Row(
                  children: [
                    // Sidebar for Dates
                    Container(
                      width: 230,
                      color: const Color(0xFF1F2937).withValues(alpha: 0.5),
                      child: ListView.builder(
                        itemCount: sortedDates.length,
                        itemBuilder: (context, index) {
                          final date = sortedDates[index];
                          final count = grouped[date]?.length ?? 0;
                          final isSelected = date == _selectedDateKey;

                          return ListTile(
                            dense: true,
                            title: Text(
                              date,
                              style: TextStyle(
                                color: isSelected ? Colors.blueAccent : Colors.white70,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.white10,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  color: isSelected ? Colors.blueAccent : Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            selected: isSelected,
                            selectedTileColor: Colors.blueAccent.withValues(alpha: 0.1),
                            onTap: () {
                              setState(() {
                                _selectedDateKey = date;
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const VerticalDivider(width: 1, color: Colors.white10),

                    // Content Area for Selected Date & Filters
                    Expanded(
                      child: filteredList.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.folder_open_rounded, size: 48, color: Colors.white24),
                                  const SizedBox(height: 12),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'No records matching "$_searchQuery"'
                                        : 'No records found for this category/date.',
                                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(20),
                              itemCount: filteredList.length,
                              itemBuilder: (context, index) {
                                final entry = filteredList[index];
                                final category = _detectCategory(entry);
                                final serial = entry['serial']?.toString() ?? 'N/A';
                                final name = entry['patientName'] ?? entry['name'] ?? entry['title'] ?? 'Record Payload';
                                final byRaw = entry['performedBy'] ??
                                              entry['createdByName'] ??
                                              entry['createdBy'] ??
                                              entry['doctorName'] ??
                                              entry['receptionistName'] ??
                                              entry['_senderUsername'] ??
                                              entry['userId'];
                                final by = (byRaw != null && byRaw.toString().trim().isNotEmpty)
                                    ? byRaw.toString().trim()
                                    : 'Unknown Staff';
                                final status = (entry['status'] ?? 'waiting').toString();
                                final timeStr = entry['createdAt']?.toString() ?? '';

                                String displayTime = '';
                                if (timeStr.isNotEmpty) {
                                  try {
                                    final dt = DateTime.parse(timeStr);
                                    displayTime = DateFormat('hh:mm:ss a').format(dt);
                                  } catch (_) {}
                                }

                                Color statusColor = Colors.orangeAccent;
                                if (status == 'completed') statusColor = Colors.greenAccent;

                                final catIcon = _categories.firstWhere((c) => c['id'] == category, orElse: () => _categories.first)['icon']!;

                                return InkWell(
                                  onTap: () => _showEntryDetails(context, entry),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Card(
                                    color: const Color(0xFF1F2937).withValues(alpha: 0.8),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(catIcon, style: const TextStyle(fontSize: 18)),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.blueAccent.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                                                ),
                                                child: Text(
                                                  '#$serial',
                                                  style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: statusColor.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                                ),
                                                child: Text(
                                                  status.toUpperCase(),
                                                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          const Divider(color: Colors.white10, height: 1),
                                          const SizedBox(height: 10),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.person_outline_rounded, size: 14, color: Colors.white54),
                                                  const SizedBox(width: 4),
                                                  Text('By: $by', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                                ],
                                              ),
                                              Row(
                                                children: [
                                                  const Icon(Icons.access_time_rounded, size: 14, color: Colors.white54),
                                                  const SizedBox(width: 4),
                                                  Text(displayTime, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
