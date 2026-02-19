// lib/pages/fix_patients.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/local_storage_service.dart' as lss;
import '../services/sync_service.dart';

class FixPatientsScreen extends StatefulWidget {
  final String branchId;

  const FixPatientsScreen({super.key, required this.branchId});

  @override
  State<FixPatientsScreen> createState() => _FixPatientsScreenState();
}

class _FixPatientsScreenState extends State<FixPatientsScreen> {
  bool isRunning = false;
  bool isMigrating = false;
  bool isClearingLocal = false;

  int totalPatients = 0;
  int processed = 0;
  int globalAdults = 0;
  int globalChildren = 0;
  int globalNeedsReview = 0;
  int globalMissingIsAdult = 0;

  Map<String, Map<String, int>> branchStats = {};
  Map<String, String> branchNames = {};

  List<QueryDocumentSnapshot> allPatients = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Future<void> _processData({required bool doUpdate}) async {
    setState(() {
      isRunning = true;
      totalPatients = processed = globalAdults = globalChildren = globalNeedsReview = 0;
      globalMissingIsAdult = 0;
      branchStats.clear();
      branchNames.clear();
      allPatients.clear();
    });

    final branchesSnap = await FirebaseFirestore.instance.collection('branches').get();
    for (var doc in branchesSnap.docs) {
      final data = doc.data();
      branchNames[doc.id] = data['name'] as String? ?? doc.id;
    }
    branchNames['unknown'] = 'Unknown / Missing BranchId';

    final patientsSnap = await FirebaseFirestore.instance.collection('patients').get();
    totalPatients = patientsSnap.docs.length;
    allPatients = patientsSnap.docs;

    if (totalPatients == 0) {
      setState(() => isRunning = false);
      return;
    }

    WriteBatch? batch;
    int batchCount = 0;

    for (var doc in patientsSnap.docs) {
      final data = doc.data();
      final String? rawBranchId = data['branchId'] as String?;
      final String branchId = rawBranchId?.trim().isNotEmpty == true ? rawBranchId! : 'unknown';

      final String? cnic = data['cnic'] as String?;
      final String? guardianCnic = data['guardianCnic'] as String?;
      final bool? existingIsAdult = data['isAdult'] as bool?;

      final bool hasOwnCnic = cnic != null && cnic.trim().isNotEmpty;
      final bool isAdult = hasOwnCnic;
      final bool needsReview = !isAdult && (guardianCnic == null || guardianCnic.trim().isEmpty);

      if (existingIsAdult == null) globalMissingIsAdult++;

      if (isAdult) {
        globalAdults++;
      } else {
        globalChildren++;
        if (needsReview) globalNeedsReview++;
      }

      final stats = branchStats.putIfAbsent(branchId, () => {
            'total': 0,
            'adults': 0,
            'children': 0,
            'needsReview': 0,
            'missingIsAdult': 0,
          });
      stats['total'] = (stats['total'] ?? 0) + 1;
      if (isAdult) {
        stats['adults'] = (stats['adults'] ?? 0) + 1;
      } else {
        stats['children'] = (stats['children'] ?? 0) + 1;
        if (needsReview) stats['needsReview'] = (stats['needsReview'] ?? 0) + 1;
      }
      if (existingIsAdult == null) stats['missingIsAdult'] = (stats['missingIsAdult'] ?? 0) + 1;

      processed++;
      setState(() {});

      if (doUpdate) {
        final updates = <String, dynamic>{
          'isAdult': isAdult,
          'needsReview': needsReview,
        };
        if (isAdult) updates['guardianCnic'] = null;

        batch ??= FirebaseFirestore.instance.batch();
        batch.update(doc.reference, updates);
        batchCount++;

        if (batchCount >= 500) {
          await batch.commit();
          batch = null;
          batchCount = 0;
        }
      }
    }

    if (doUpdate && batch != null && batchCount > 0) {
      await batch.commit();
    }

    setState(() => isRunning = false);
  }

  Future<void> _clearLocalAndRefresh() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear All Local Data?"),
        content: const Text(
          "This will:\n"
          "• Delete ALL local patients, tokens, stock, etc.\n"
          "• Re-download fresh data from server\n"
          "• Permanently remove all duplicates\n\n"
          "Are you sure? This action cannot be undone.",
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Yes, Clear Everything"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => isClearingLocal = true);

    try {
      // Clear all local data
      await lss.LocalStorageService.clearAllData();

      // Directly call full download with safe 'all' branchId
      await lss.LocalStorageService.fullDownloadOnce('all');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Success! All local data cleared and fresh data downloaded."),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 8),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint("ERROR in clearLocalAndRefresh: $e");
      debugPrint(stackTrace.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed: $e"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 10),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isClearingLocal = false);
      }
    }
  }

  List<Map<String, dynamic>> get sortedBranchList {
    return branchStats.entries.map((e) {
      return {
        'branchId': e.key,
        'branchName': branchNames[e.key] ?? e.key,
        'total': e.value['total'] ?? 0,
        'adults': e.value['adults'] ?? 0,
        'children': e.value['children'] ?? 0,
        'needsReview': e.value['needsReview'] ?? 0,
        'missingIsAdult': e.value['missingIsAdult'] ?? 0,
      };
    }).toList()
      ..sort((a, b) => (a['branchName'] as String).compareTo(b['branchName'] as String));
  }

  List<QueryDocumentSnapshot> get filteredPatients {
    if (_searchQuery.isEmpty) return allPatients;
    final query = _searchQuery.toLowerCase();
    return allPatients.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] as String?)?.toLowerCase() ?? '';
      final cnic = (data['cnic'] as String?)?.toLowerCase() ?? '';
      final guardian = (data['guardianCnic'] as String?)?.toLowerCase() ?? '';
      final phone = (data['phone'] as String?)?.toLowerCase() ?? '';
      return name.contains(query) || cnic.contains(query) || guardian.contains(query) || phone.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasData = allPatients.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fix & Review Patients'),
        backgroundColor: const Color(0xFF006D5B),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Patient Data Tool', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    '• Has any CNIC → Adult\n'
                    '• No CNIC → True Child\n'
                    '• Child without guardian CNIC → Needs Review',
                    style: TextStyle(fontSize: 15, color: Colors.grey[700], height: 1.4),
                  ),
                  const SizedBox(height: 24),

                  Card(
                    elevation: 6,
                    color: Colors.red[50],
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.red),
                          const SizedBox(height: 12),
                          const Text(
                            'Clear All Local Data',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Permanently deletes all local patients, tokens, stock, etc.\n'
                            'Then re-downloads fresh data from server.\n'
                            'Use this to fix duplicates once and for all.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15),
                          ),
                          const SizedBox(height: 16),
                          if (isClearingLocal)
                            const Column(
                              children: [
                                CircularProgressIndicator(color: Colors.red),
                                SizedBox(height: 12),
                                Text('Clearing and re-downloading...'),
                              ],
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: isRunning || isMigrating ? null : _clearLocalAndRefresh,
                              icon: const Icon(Icons.delete_forever, color: Colors.white),
                              label: const Text('Clear Local & Re-Download'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[700],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                elevation: 4,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Global Summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const Divider(),
                          _buildStatRow('Total Patients', totalPatients),
                          _buildStatRow('Adults (has own CNIC)', globalAdults, color: Colors.blue),
                          _buildStatRow('True Children (no CNIC)', globalChildren, color: Colors.purple),
                          _buildStatRow('Needs Review', globalNeedsReview, color: Colors.red, bold: true),
                          _buildStatRow('Missing isAdult Field', globalMissingIsAdult, color: Colors.orange[800], bold: true),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: totalPatients > 0 ? processed / totalPatients : 0,
                            minHeight: 10,
                          ),
                          const SizedBox(height: 8),
                          Text('Processed: $processed / $totalPatients', textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  const Text('Branch-wise Summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 180,
                    child: hasData
                        ? ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: sortedBranchList.length,
                            itemBuilder: (context, i) {
                              final b = sortedBranchList[i];
                              final hasIssues = b['needsReview'] > 0 || b['branchId'] == 'unknown' || b['missingIsAdult'] > 0;
                              return SizedBox(
                                width: 240,
                                child: Card(
                                  color: hasIssues ? Colors.red[50] : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          b['branchName'],
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: b['branchId'] == 'unknown' ? Colors.orange[800] : const Color(0xFF006D5B),
                                          ),
                                        ),
                                        if (b['branchId'] == 'unknown')
                                          const Text('Missing branchId', style: TextStyle(color: Colors.orange, fontSize: 12)),
                                        const SizedBox(height: 8),
                                        _buildStatRow('Total', b['total']),
                                        _buildStatRow('Adults', b['adults'], color: Colors.blue),
                                        _buildStatRow('Children', b['children'], color: Colors.purple),
                                        _buildStatRow('Review', b['needsReview'], color: Colors.red, bold: true),
                                        _buildStatRow('Missing isAdult', b['missingIsAdult'], color: Colors.orange[800], bold: true),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : const Center(child: Text('No data yet')),
                  ),

                  const SizedBox(height: 24),

                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search by Name, CNIC, Guardian CNIC, Phone',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                    enabled: hasData,
                  ),

                  const SizedBox(height: 16),
                  const Text('All Patients', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),

                  hasData
                      ? ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredPatients.length,
                          itemBuilder: (context, index) {
                            final doc = filteredPatients[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final String patientId = doc.id;
                            final String? name = data['name'] as String?;
                            final String? cnic = (data['cnic'] as String?)?.trim();
                            final String? guardianCnic = (data['guardianCnic'] as String?)?.trim();
                            final String? phone = data['phone'] as String?;
                            final bool? existingIsAdult = data['isAdult'] as bool?;
                            final bool hasCnic = cnic != null && cnic.isNotEmpty;
                            final bool needsReview = data['needsReview'] == true;
                            final bool missingIsAdult = existingIsAdult == null;
                            final bool cnicIsPatientId = patientId == cnic && cnic != null;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: needsReview ? Colors.red[50] : (missingIsAdult ? Colors.yellow[50] : null),
                              child: ListTile(
                                title: Text(name ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (cnic != null && cnic.isNotEmpty)
                                      Text('CNIC: $cnic ${cnicIsPatientId ? '(Used as Patient ID)' : ''}'),
                                    if (guardianCnic != null && guardianCnic.isNotEmpty)
                                      Text('Guardian CNIC: $guardianCnic', style: const TextStyle(color: Colors.green)),
                                    if (!hasCnic)
                                      const Text('No Own CNIC → True Child', style: const TextStyle(color: Colors.purple)),
                                    if (phone != null) Text('Phone: $phone'),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.person, size: 16, color: hasCnic ? Colors.blue : Colors.purple),
                                        const SizedBox(width: 4),
                                        Text(hasCnic ? 'Adult' : 'Child',
                                            style: TextStyle(color: hasCnic ? Colors.blue : Colors.purple)),
                                        if (needsReview) ...[
                                          const SizedBox(width: 12),
                                          const Icon(Icons.warning, size: 16, color: Colors.red),
                                          const Text(' Needs Review', style: TextStyle(color: Colors.red)),
                                        ],
                                        if (missingIsAdult) ...[
                                          const SizedBox(width: 12),
                                          const Icon(Icons.help_outline, size: 16, color: Colors.orange),
                                          const Text(' Missing isAdult', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                                        ],
                                        if (cnicIsPatientId) ...[
                                          const SizedBox(width: 12),
                                          const Icon(Icons.key, size: 16, color: Colors.orange),
                                          const Text(' CNIC = ID', style: TextStyle(color: Colors.orange)),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      : const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'No data loaded yet.\nPress "Dry Run" below to scan all patients.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
            ),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: isRunning || isMigrating || isClearingLocal ? null : () => _processData(doUpdate: false),
                    icon: const Icon(Icons.visibility),
                    label: const Text('Dry Run (Scan Only)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[700],
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: isRunning || isMigrating || isClearingLocal ? null : () => _processData(doUpdate: true),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Fix Data'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (isRunning || isMigrating || isClearingLocal)
            const LinearProgressIndicator(minHeight: 4, backgroundColor: Colors.transparent),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          const Spacer(),
          Text(
            value.toString(),
            style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}