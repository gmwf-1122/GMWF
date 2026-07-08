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

  @override
  void initState() {
    super.initState();
    _selectedDateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
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
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box(LocalStorageService.entriesBox).listenable(),
        builder: (context, Box box, _) {
          final allEntries = LocalStorageService.getLocalEntries(widget.branchId);

          // Group by dateKey
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (final entry in allEntries) {
            final dk = entry['dateKey']?.toString() ?? 'unknown';
            grouped.putIfAbsent(dk, () => []).add(entry);
          }

          final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

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

          final currentList = grouped[_selectedDateKey] ?? [];
          currentList.sort((a, b) => (b['createdAt'] ?? '').toString().compareTo((a['createdAt'] ?? '').toString()));

          return Row(
            children: [
              // Sidebar for Dates
              Container(
                width: 250,
                color: const Color(0xFF1F2937).withValues(alpha: 0.5),
                child: ListView.builder(
                  itemCount: sortedDates.length,
                  itemBuilder: (context, index) {
                    final date = sortedDates[index];
                    final count = grouped[date]?.length ?? 0;
                    final isSelected = date == _selectedDateKey;

                    return ListTile(
                      title: Text(
                        date,
                        style: TextStyle(
                          color: isSelected ? Colors.blueAccent : Colors.white70,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: isSelected ? Colors.blueAccent : Colors.white54,
                            fontSize: 12,
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
              // Main Content for Selected Date
              Expanded(
                child: currentList.isEmpty
                    ? const Center(child: Text('No entries for this date.', style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(24),
                        itemCount: currentList.length,
                        itemBuilder: (context, index) {
                          final entry = currentList[index];
                          final serial = entry['serial']?.toString() ?? 'N/A';
                          final name = entry['patientName'] ?? entry['name'] ?? 'Unknown';
                          final status = entry['status']?.toString() ?? 'waiting';
                          final by = entry['performedBy'] ?? 'Unknown';
                          final timeStr = entry['createdAt']?.toString() ?? '';
                          String displayTime = '';
                          if (timeStr.isNotEmpty) {
                            try {
                              final dt = DateTime.parse(timeStr);
                              displayTime = DateFormat('hh:mm a').format(dt);
                            } catch (_) {}
                          }

                          Color statusColor = Colors.orangeAccent;
                          if (status == 'completed') statusColor = Colors.greenAccent;

                          return Card(
                            color: const Color(0xFF1F2937).withValues(alpha: 0.8),
                            margin: const EdgeInsets.only(bottom: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          '#$serial',
                                          style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  const Divider(color: Colors.white10),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Added By: $by', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                      Text(displayTime, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
