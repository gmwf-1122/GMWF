// lib/pages/branches.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'inventory_doc.dart';
import 'assets.dart';
import 'branches_register.dart';

class PatientSummaryCard extends StatelessWidget {
  final String title;
  final Future<Map<String, int>> dataFuture;
  final Color color;
  final IconData titleIcon;
  final bool showRevenue;
  final Map<String, IconData> valueIcons;
  final Map<String, String> valueLabels;

  // No 'const' keyword → fixes hot reload error
  PatientSummaryCard({
    super.key,
    required this.title,
    required this.dataFuture,
    required this.color,
    required this.titleIcon,
    this.showRevenue = false,
    required this.valueIcons,
    required this.valueLabels,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return const Center(child: Text("Error", style: TextStyle(color: Colors.white)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No data", style: TextStyle(color: Colors.white70)));
        }

        final d = snapshot.data!;
        final revenue = d['revenue'] ?? 0;
        final minis = <Widget>[];

        for (final key in valueLabels.keys.where((k) => k.startsWith('v'))) {
          minis.add(_mini(valueLabels[key]!, d[key] ?? 0, valueIcons[key] ?? Icons.help_outline));
        }
        minis.add(_mini("Total", d['total'] ?? 0, valueIcons['total'] ?? Icons.people));

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: color,
          child: SizedBox(
            height: 180,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(titleIcon, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: minis),
                  if (showRevenue)
                    Row(
                      children: [
                        const Icon(Icons.attach_money, size: 20, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          "Rs. $revenue",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _mini(String label, int value, IconData icon) => Expanded(
        child: Column(
          children: [
            Icon(icon, size: 24, color: Colors.white),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text(
              "$value",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      );
}

class Branches extends StatefulWidget {
  final String? branchId;

  const Branches({super.key, this.branchId});

  @override
  State<Branches> createState() => _BranchesState();
}

class _BranchesState extends State<Branches> with AutomaticKeepAliveClientMixin {
  String? selectedTypeFilter;
  DateTime? selectedStartDate;
  DateTime? selectedEndDate;

  @override
  bool get wantKeepAlive => true;

  DateTime get effectiveStart {
    if (selectedStartDate != null && selectedEndDate != null) return selectedStartDate!;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get effectiveEnd {
    if (selectedStartDate != null && selectedEndDate != null) return selectedEndDate!.add(const Duration(days: 1));
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1);
  }

  Future<Map<String, int>> _tokensFuture(String branchId) async {
    try {
      int zakat = 0, nonZakat = 0, gmwf = 0;
      final df = DateFormat('ddMMyy');
      final start = effectiveStart;
      final end = effectiveEnd;

      for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
        final ds = df.format(d);
        final base = FirebaseFirestore.instance.collection('branches').doc(branchId).collection('serials').doc(ds);
        final countFutures = ['zakat', 'non-zakat', 'gmwf'].map((c) => base.collection(c).count().get());
        final snaps = await Future.wait(countFutures);
        zakat += snaps[0].count ?? 0;
        nonZakat += snaps[1].count ?? 0;
        gmwf += snaps[2].count ?? 0;
      }
      final total = zakat + nonZakat + gmwf;
      final revenue = zakat * 20 + nonZakat * 100;
      return {'v1': zakat, 'v2': nonZakat, 'v3': gmwf, 'total': total, 'revenue': revenue};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, int>> _prescriptionsFuture(String branchId) async {
    try {
      int waiting = 0;
      int prescribed = 0;
      final df = DateFormat('ddMMyy');
      final start = effectiveStart;
      final end = effectiveEnd;

      for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
        final ds = df.format(d);
        final base = FirebaseFirestore.instance.collection('branches').doc(branchId).collection('serials').doc(ds);

        final futures = ['zakat', 'non-zakat', 'gmwf'].map((c) => base.collection(c).get());
        final snaps = await Future.wait(futures);

        final serialToIdentifier = <String, String>{};

        for (final snap in snaps) {
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final serial = data['serial']?.toString();

            // CRITICAL FIX: Prefer cnic → guardianCnic → patientId
            // (your prescriptions are saved under CNIC or guardianCNIC as parent doc)
            String identifier = data['cnic']?.toString()?.trim() ?? '';
            if (identifier.isEmpty) {
              identifier = data['guardianCnic']?.toString()?.trim() ?? '';
            }
            if (identifier.isEmpty) {
              identifier = data['patientId']?.toString()?.trim() ?? '';
            }

            if (serial != null && identifier.isNotEmpty) {
              serialToIdentifier[serial] = identifier;
              debugPrint('Serial $serial linked to identifier: $identifier');
            } else {
              debugPrint('Serial $serial has no usable identifier');
            }
          }
        }

        final presRoot = FirebaseFirestore.instance.collection('branches').doc(branchId).collection('prescriptions');
        for (final entry in serialToIdentifier.entries) {
          final serial = entry.key;
          final identifier = entry.value;
          final presSnap = await presRoot.doc(identifier).collection('prescriptions').doc(serial).get();
          if (presSnap.exists) {
            prescribed++;
            debugPrint('Prescription FOUND for serial $serial (identifier: $identifier)');
          } else {
            waiting++;
            debugPrint('Prescription MISSING for serial $serial (identifier: $identifier)');
          }
        }
      }

      final total = waiting + prescribed;
      debugPrint('Prescriptions summary: Waiting=$waiting, Prescribed=$prescribed, Total=$total');
      return {'v1': waiting, 'v2': prescribed, 'total': total};
    } catch (e) {
      debugPrint("Prescriptions error: $e");
      return {'v1': 0, 'v2': 0, 'total': 0};
    }
  }

  Future<Map<String, int>> _dispensaryCountFuture(String branchId) async {
    try {
      final df = DateFormat('ddMMyy');
      final start = effectiveStart;
      final end = effectiveEnd;
      int count = 0;
      for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
        final ds = df.format(d);
        final snap = await FirebaseFirestore.instance.collection('branches/$branchId/dispensary/$ds/$ds').count().get();
        count += snap.count ?? 0;
      }
      return {'v1': 0, 'v2': count, 'total': count};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _dispensaryFuture(String branchId) async {
    try {
      final df = DateFormat('ddMMyy');
      final displayFormat = DateFormat('dd MMM yyyy');
      final start = effectiveStart;
      final end = effectiveEnd;

      final List<Map<String, dynamic>> list = [];
      Map<String, String> serialToType = {};

      for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
        final ds = df.format(d);
        final base = FirebaseFirestore.instance.collection('branches').doc(branchId).collection('serials').doc(ds);
        final futures = ['zakat', 'non-zakat', 'gmwf'].map((c) => base.collection(c).get());
        final snaps = await Future.wait(futures);

        for (int i = 0; i < 3; i++) {
          final coll = ['zakat', 'non-zakat', 'gmwf'][i];
          for (final doc in snaps[i].docs) {
            final data = doc.data() as Map<String, dynamic>;
            final serial = data['serial']?.toString();
            if (serial != null && serial.isNotEmpty) {
              serialToType[serial] = coll;
            }
          }
        }
      }

      for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
        final ds = df.format(d);
        final snap = await FirebaseFirestore.instance.collection('branches/$branchId/dispensary/$ds/$ds').get();

        for (final doc in snap.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          final serial = data['serial']?.toString() ?? '';
          if (serial.isEmpty) continue;

          data['name'] = data['patientName'] ?? 'Unknown';
          data['phone'] = (data['phone']?.toString().isNotEmpty ?? false) ? data['phone'] : 'N/A';
          data['doctorName'] = data['prescribedBy'] ?? 'Unknown';
          data['dispenserName'] = data['dispenserName'] ?? 'Unknown';
          data['tokenBy'] = data['tokenBy'] ?? 'Unknown';
          data['type'] = serialToType[serial] ?? _queueTypeToType(data['queueType']);
          data['serial'] = serial;
          data['dispenseDate'] = data['dispensedAt'] != null
              ? displayFormat.format((data['dispensedAt'] as Timestamp).toDate())
              : displayFormat.format(DateFormat('ddMMyy').parse(ds));

          final pid = data['patientId']?.toString() ?? '';
          if (pid.isNotEmpty) {
            try {
              final psnap = await FirebaseFirestore.instance.collection('branches/$branchId/patients').doc(pid).get();
              if (psnap.exists) {
                final p = psnap.data()!;
                if (data['name'] == 'Unknown') data['name'] = p['name'] ?? 'Unknown';
                if (data['phone'] == 'N/A') data['phone'] = p['phone'] ?? 'N/A';
                data['age'] = p['age']?.toString() ?? 'N/A';
                data['gender'] = p['gender'] ?? 'N/A';
                data['bloodGroup'] = p['bloodGroup'] ?? 'N/A';

                final cnic = p['cnic']?.toString()?.trim() ?? '';
                if (cnic.isNotEmpty) {
                  data['displayCnic'] = cnic;
                  data['isChild'] = false;
                } else {
                  final gcnic = p['guardianCnic']?.toString()?.trim() ?? '';
                  data['displayCnic'] = gcnic.isNotEmpty ? gcnic : 'N/A';
                  data['isChild'] = true;
                  if (gcnic.isNotEmpty) {
                    final gq = await FirebaseFirestore.instance
                        .collection('branches/$branchId/patients')
                        .where('cnic', isEqualTo: gcnic)
                        .limit(1)
                        .get();
                    if (gq.docs.isNotEmpty) data['guardianName'] = gq.docs.first['name'] ?? 'N/A';
                  }
                }
              }
            } catch (_) {}
          }

          list.add(data);
        }
      }

      return {
        'v1': 0,
        'v2': list.length,
        'total': list.length,
        'dispensed': list,
      };
    } catch (e) {
      debugPrint("Dispensary error: $e");
      return {};
    }
  }

  String _queueTypeToType(String? qt) {
    switch (qt?.toLowerCase()) {
      case 'zakat':     return 'zakat';
      case 'non-zakat': return 'non-zakat';
      case 'gmwf':      return 'gmwf';
      default:          return 'Unknown';
    }
  }

  Widget _dateRangeSelector() {
    final isToday = selectedStartDate == null && selectedEndDate == null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("From:", style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedStartDate ?? DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => selectedStartDate = picked);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: const Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(
                selectedStartDate != null ? DateFormat('dd MMM yyyy').format(selectedStartDate!) : "Select date",
                style: TextStyle(color: selectedStartDate != null ? Colors.black87 : Colors.grey[600]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        const Text("To:", style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedEndDate ?? DateTime.now(),
                firstDate: selectedStartDate ?? DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => selectedEndDate = picked);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: const Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(
                selectedEndDate != null ? DateFormat('dd MMM yyyy').format(selectedEndDate!) : "Select date",
                style: TextStyle(color: selectedEndDate != null ? Colors.black87 : Colors.grey[600]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: () => setState(() {}),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
          child: const Text("Apply"),
        ),
        if (!isToday)
          IconButton(
            icon: const Icon(Icons.clear, color: Colors.redAccent),
            tooltip: "Clear range (back to today)",
            onPressed: () => setState(() {
              selectedStartDate = null;
              selectedEndDate = null;
            }),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              "(Today)",
              style: TextStyle(color: Colors.blueGrey[700], fontStyle: FontStyle.italic, fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _typeFilter() {
    final isWide = MediaQuery.of(context).size.width > 600;

    if (isWide) {
      return Wrap(
        spacing: 8,
        children: [
          _filterChip("All", null),
          _filterChip("Zakat", "zakat"),
          _filterChip("Non-Zakat", "non-zakat"),
          _filterChip("GMWF", "gmwf"),
        ],
      );
    } else {
      return DropdownButton<String>(
        value: selectedTypeFilter ?? 'all',
        underline: const SizedBox(),
        items: const [
          DropdownMenuItem(value: 'all', child: Text('All')),
          DropdownMenuItem(value: 'zakat', child: Text('Zakat')),
          DropdownMenuItem(value: 'non-zakat', child: Text('Non-Zakat')),
          DropdownMenuItem(value: 'gmwf', child: Text('GMWF')),
        ],
        onChanged: (v) => setState(() => selectedTypeFilter = v == 'all' ? null : v),
      );
    }
  }

  Widget _filterChip(String label, String? type) {
    final selected = selectedTypeFilter == type;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (sel) => setState(() => selectedTypeFilter = sel ? type : null),
      selectedColor: Colors.blue.shade700,
      backgroundColor: Colors.grey.shade200,
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
      checkmarkColor: Colors.white,
    );
  }

  Widget _infoRow(IconData icon, String text, {String? copy}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
          if (copy != null && copy.isNotEmpty && copy != 'N/A')
            IconButton(
              icon: const Icon(Icons.content_copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copy));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: $copy')));
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBranchDetails(String branchName, String branchId) {
    final isSupervisor = widget.branchId != null;
    final isWide = MediaQuery.of(context).size.width > 900;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(isWide ? 32 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  branchName,
                  style: TextStyle(fontSize: isWide ? 32 : 26, fontWeight: FontWeight.bold),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isSupervisor)
                      Row(
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.inventory, color: Colors.white),
                            label: const Text(
                              "Inventory",
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => InventoryDocPage(branchId: branchId)),
                              );
                            },
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.account_balance_wallet, color: Colors.white),
                            label: const Text(
                              "Assets",
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple.shade700,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => AssetsPage(branchId: branchId, isAdmin: true)),
                              );
                            },
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    _dateRangeSelector(),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Summary Cards – no const
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: PatientSummaryCard(
                          title: "Tokens",
                          dataFuture: _tokensFuture(branchId),
                          color: Colors.green.shade600,
                          titleIcon: Icons.people_alt,
                          showRevenue: true,
                          valueIcons: {'v1': Icons.favorite, 'v2': Icons.group, 'v3': Icons.handshake, 'total': Icons.people_alt},
                          valueLabels: {'v1': 'Zakat', 'v2': 'Non-Zakat', 'v3': 'GMWF'},
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: PatientSummaryCard(
                          title: "Prescriptions",
                          dataFuture: _prescriptionsFuture(branchId),
                          color: Colors.blue.shade600,
                          titleIcon: Icons.medical_information,
                          valueIcons: {'v1': Icons.timer, 'v2': Icons.check_circle, 'total': Icons.medical_information},
                          valueLabels: {'v1': 'Waiting', 'v2': 'Prescribed'},
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: PatientSummaryCard(
                          title: "Dispensary",
                          dataFuture: _dispensaryCountFuture(branchId),
                          color: Colors.orange.shade600,
                          titleIcon: Icons.local_pharmacy,
                          valueIcons: {'v1': Icons.access_time, 'v2': Icons.done_all, 'total': Icons.local_pharmacy},
                          valueLabels: {'v1': 'Pending', 'v2': 'Dispensed'},
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    PatientSummaryCard(
                      title: "Tokens",
                      dataFuture: _tokensFuture(branchId),
                      color: Colors.green.shade600,
                      titleIcon: Icons.people_alt,
                      showRevenue: true,
                      valueIcons: {'v1': Icons.favorite, 'v2': Icons.group, 'v3': Icons.handshake, 'total': Icons.people_alt},
                      valueLabels: {'v1': 'Zakat', 'v2': 'Non-Zakat', 'v3': 'GMWF'},
                    ),
                    const SizedBox(height: 20),
                    PatientSummaryCard(
                      title: "Prescriptions",
                      dataFuture: _prescriptionsFuture(branchId),
                      color: Colors.blue.shade600,
                      titleIcon: Icons.medical_information,
                      valueIcons: {'v1': Icons.timer, 'v2': Icons.check_circle, 'total': Icons.medical_information},
                      valueLabels: {'v1': 'Waiting', 'v2': 'Prescribed'},
                    ),
                    const SizedBox(height: 20),
                    PatientSummaryCard(
                      title: "Dispensary",
                      dataFuture: _dispensaryCountFuture(branchId),
                      color: Colors.orange.shade600,
                      titleIcon: Icons.local_pharmacy,
                      valueIcons: {'v1': Icons.access_time, 'v2': Icons.done_all, 'total': Icons.local_pharmacy},
                      valueLabels: {'v1': 'Pending', 'v2': 'Dispensed'},
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 40),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text("Dispensed Patients", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                _typeFilter(),
              ],
            ),

            const SizedBox(height: 24),

            FutureBuilder<Map<String, dynamic>>(
              key: ValueKey('dispensed-$branchId-$selectedStartDate-$selectedEndDate-$selectedTypeFilter'),
              future: _dispensaryFuture(branchId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("No dispensed records found for selected period"));
                }

                final all = snapshot.data!['dispensed'] as List<dynamic>;
                final filtered = all
                    .where((p) => selectedTypeFilter == null || p['type']?.toString().toLowerCase() == selectedTypeFilter)
                    .cast<Map<String, dynamic>>()
                    .toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text("No patients match the selected type filter"));
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    final isChild = p['isChild'] == true;
                    final typeColor = {
                      'zakat': Colors.green.shade600,
                      'non-zakat': Colors.blue.shade600,
                      'gmwf': Colors.orange.shade600,
                    }[p['type']?.toLowerCase()] ?? Colors.grey.shade600;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(isChild ? Icons.child_care : Icons.person, color: Colors.green.shade700, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    p['name'] ?? 'Unknown',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: typeColor, borderRadius: BorderRadius.circular(20)),
                                  child: Text(
                                    (p['type'] ?? 'Unknown').toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            _infoRow(Icons.calendar_today, 'Date: ${p['dispenseDate'] ?? 'N/A'}'),
                            _infoRow(Icons.badge, '${isChild ? "Guardian CNIC" : "CNIC"}: ${p['displayCnic'] ?? 'N/A'}', copy: p['displayCnic']),
                            if (isChild) _infoRow(Icons.family_restroom, 'Guardian: ${p['guardianName'] ?? 'N/A'}'),
                            _infoRow(Icons.phone, 'Phone: ${p['phone'] ?? 'N/A'}', copy: p['phone']),
                            _infoRow(Icons.cake, 'Age: ${p['age'] ?? 'N/A'} • Gender: ${p['gender'] ?? 'N/A'}'),
                            _infoRow(Icons.bloodtype, 'Blood Group: ${p['bloodGroup'] ?? 'N/A'}'),
                            _infoRow(Icons.medical_services, 'Prescribed by: ${p['doctorName'] ?? 'Unknown'}'),
                            _infoRow(Icons.token, 'Token by: ${p['tokenBy'] ?? 'Unknown'}'),
                            _infoRow(Icons.local_pharmacy, 'Dispensed by: ${p['dispenserName'] ?? 'Unknown'}'),
                            _infoRow(Icons.numbers, 'Serial: ${p['serial'] ?? 'N/A'}'),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isSupervisorMode = widget.branchId != null;

    if (isSupervisorMode) {
      final branchName = widget.branchId![0].toUpperCase() + widget.branchId!.substring(1).replaceAll('-', ' ');
      return Scaffold(
        appBar: AppBar(
          title: Text("Branch: $branchName"),
          backgroundColor: const Color(0xFF006D5B),
          foregroundColor: Colors.white,
        ),
        body: _buildBranchDetails(branchName, widget.branchId!),
      );
    }

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('branches').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No branches found"));
          }

          final branches = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            final name = data?['name'] as String? ?? doc.id;
            return MapEntry(name, doc.id);
          }).toList()..sort((a, b) => a.key.compareTo(b.key));

          return DefaultTabController(
            length: branches.length,
            child: Column(
              children: [
                Container(
                  color: const Color(0xFF006D5B),
                  child: TabBar(
                    isScrollable: true,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    indicatorColor: Colors.white,
                    tabs: branches.map((e) => Tab(text: e.key)).toList(),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: branches.map((e) => _buildBranchDetails(e.key, e.value)).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}