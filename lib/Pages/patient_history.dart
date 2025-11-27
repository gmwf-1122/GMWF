// lib/pages/patient_history.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class PatientHistory extends StatefulWidget {
  final String branchId;
  final String patientCNIC;
  final double maxCardHeight;
  final Function(Map<String, dynamic> visit)? onRepeatLast;
  final bool showAll;

  const PatientHistory({
    super.key,
    required this.branchId,
    required this.patientCNIC,
    this.maxCardHeight = 120,
    this.onRepeatLast,
    this.showAll = false,
  });

  @override
  State<PatientHistory> createState() => _PatientHistoryState();
}

class _PatientHistoryState extends State<PatientHistory> {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _lightGreen = Color(0xFFF1F8E9);

  Map<String, dynamic>? _latestVisit;
  List<Map<String, dynamic>> _allVisits = [];
  Map<String, dynamic>? _patientData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPatientData();
    if (widget.showAll) {
      _fetchAllVisits();
    } else {
      _fetchLatestVisit();
    }
  }

  Future<void> _fetchPatientData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('patients')
          .doc(widget.patientCNIC)
          .get();

      if (doc.exists) {
        _patientData = doc.data();
      }
    } catch (e) {
      debugPrint('Error fetching patient data: $e');
    }
  }

  Future<void> _fetchLatestVisit() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('prescriptions')
          .doc(widget.patientCNIC)
          .collection('prescriptions')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        _latestVisit = query.docs.first.data();
      }
    } catch (e) {
      debugPrint('Error fetching latest visit: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchAllVisits() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('prescriptions')
          .doc(widget.patientCNIC)
          .collection('prescriptions')
          .orderBy('createdAt', descending: true)
          .get();

      _allVisits = query.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('Error fetching all visits: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  int _calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  Widget _buildPatientHeader() {
    if (_patientData == null) return const SizedBox.shrink();

    final name = _patientData!['name'] ?? 'Unknown';
    final gender = _patientData!['gender'] ?? 'Unknown';
    final dobTimestamp = _patientData!['dob'] as Timestamp?;
    final dob = dobTimestamp?.toDate();
    final age = dob != null ? _calculateAge(dob) : null;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: _green,
            child: Icon(
              FontAwesomeIcons.user,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _green,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$gender${age != null ? ', $age years' : ''}',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(
          title,
          style: TextStyle(
            color: _green,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      );

  Widget _buildVitals(Map<String, dynamic>? vitals) {
    if (vitals == null || vitals.isEmpty) {
      return Text("No vitals recorded.",
          style: TextStyle(color: Colors.black54, fontSize: 13));
    }

    final List<Map<String, dynamic>> vitalList = [
      {
        'icon': Icons.favorite,
        'color': Colors.pink.shade500,
        'label': 'BP',
        'value': vitals['bp'] ?? '-'
      },
      {
        'icon': Icons.thermostat,
        'color': Colors.orange.shade500,
        'label': 'Temp',
        'value': '${vitals['temp'] ?? '-'} ${vitals['tempUnit'] ?? ''}'
      },
      {
        'icon': Icons.water_drop,
        'color': Colors.purple.shade500,
        'label': 'Sugar',
        'value': vitals['sugar'] ?? '-'
      },
      {
        'icon': Icons.fitness_center,
        'color': Colors.teal.shade500,
        'label': 'Weight',
        'value': vitals['weight'] ?? '-'
      },
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: vitalList
          .map((v) => Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: v['color'],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(v['icon'], size: 16, color: Colors.white),
                    SizedBox(width: 4),
                    Text('${v['label']}: ${v['value']}',
                        style: TextStyle(fontSize: 14, color: Colors.white)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  bool _isInjectable(Map<String, dynamic> med) {
    final name = (med['name'] ?? med['displayName'] ?? '').toLowerCase();
    return name.contains('inj') || name.contains('injection');
  }

  Widget _buildMedicineChip(Map<String, dynamic> med) {
    final name = med['displayName'] ?? med['name'] ?? 'Unknown Med';
    final dose = med['dose'] ?? '';
    final freq = med['frequency'] ?? '';
    final timing = med['timing'] ?? '';

    final parts = <String>[];
    if (dose.isNotEmpty) parts.add(dose);
    if (freq.isNotEmpty) parts.add(freq);
    if (timing.isNotEmpty) parts.add(timing);

    final subtitle = parts.isNotEmpty ? parts.join(' • ') : '';

    return Chip(
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white)),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                style: TextStyle(fontSize: 14, color: Colors.white70)),
        ],
      ),
      backgroundColor: _green,
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildInjectableChip(Map<String, dynamic> med) {
    final name = med['displayName'] ?? med['name'] ?? 'Unknown Injectable';
    final quantity = med['quantity']?.toString() ?? '1';
    final dose = med['dose'] ?? '';
    final freq = med['frequency'] ?? '';
    final timing = med['timing'] ?? '';

    final parts = <String>[];
    if (dose.isNotEmpty) parts.add(dose);
    if (freq.isNotEmpty) parts.add(freq);
    if (timing.isNotEmpty) parts.add(timing);

    final subtitle = parts.isNotEmpty ? parts.join(' • ') : '';

    return Chip(
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$name (Qty: $quantity)',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white)),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                style: TextStyle(fontSize: 14, color: Colors.white70)),
        ],
      ),
      backgroundColor: Colors.blue.shade500,
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildLabChip(Map<String, dynamic> lab) {
    final test = lab['name'] ?? lab['testName'] ?? 'Unknown Test';
    final result = lab['result'] ?? '';

    return Chip(
      label: Text(
        result.isNotEmpty ? "$test ($result)" : test,
        style: TextStyle(fontSize: 14, color: Colors.white),
      ),
      backgroundColor: Colors.green.shade500,
      padding: EdgeInsets.symmetric(horizontal: 6),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  void _repeatVisit(Map<String, dynamic> visit) {
    if (widget.onRepeatLast == null) return;

    final updated = Map<String, dynamic>.from(visit);

    final pres = (visit['prescriptions'] as List<dynamic>?) ?? [];
    updated['inventoryMed'] = pres
        .where((m) =>
            m is Map &&
            m['inventoryId'] != null &&
            m['inventoryId'].toString().isNotEmpty)
        .cast<Map<String, dynamic>>()
        .toList();
    updated['customMed'] = pres
        .where((m) =>
            m is Map &&
            (m['inventoryId'] == null || m['inventoryId'].toString().isEmpty))
        .cast<Map<String, dynamic>>()
        .toList();
    updated['injectables'] = pres
        .where((m) => m is Map && _isInjectable(m as Map<String, dynamic>))
        .cast<Map<String, dynamic>>()
        .toList();
    updated['vitals'] =
        (visit['vitals'] as Map?)?.cast<String, dynamic>() ?? {};
    updated['labResults'] = (visit['labResults'] as List?) ?? [];

    widget.onRepeatLast!(updated);

    if (widget.showAll) {
      Navigator.pop(context);
    }
  }

  Widget _buildVisitCard(Map<String, dynamic> visit, {bool isLatest = false}) {
    final timestamp = visit['createdAt'] as Timestamp?;
    final date = timestamp != null
        ? DateFormat('dd MMM yyyy • hh:mm a').format(timestamp.toDate())
        : 'Unknown Date';

    final patientName =
        visit['patientName']?.toString().trim() ?? 'Unknown Patient';
    final serial = visit['serial']?.toString() ?? '-';

    final prescriptions = (visit['prescriptions'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        <Map<String, dynamic>>[];
    final oralMeds = prescriptions.where((med) => !_isInjectable(med)).toList();
    final injectables =
        prescriptions.where((med) => _isInjectable(med)).toList();
    final labs =
        (visit['labResults'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[];
    final vitals = (visit['vitals'] as Map?)?.cast<String, dynamic>() ?? {};

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _green,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      Text(
                        "Serial: $serial",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  date,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                if (isLatest)
                  Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Chip(
                      label: Text("Latest",
                          style: TextStyle(fontSize: 10, color: _green)),
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle("Condition"),
                Text(
                  visit['complaint'] ?? '-',
                  style: TextStyle(fontSize: 14.5, color: Colors.black87),
                ),
                SizedBox(height: 8),
                _buildSectionTitle("Diagnosis"),
                Text(
                  visit['diagnosis'] ?? '-',
                  style: TextStyle(fontSize: 14.5, color: Colors.black87),
                ),
                SizedBox(height: 12),
                _buildSectionTitle("Vitals"),
                _buildVitals(vitals),
                SizedBox(height: 12),
                _buildSectionTitle("Medicines"),
                oralMeds.isEmpty
                    ? Text("No medicines prescribed.",
                        style: TextStyle(color: Colors.black54, fontSize: 13))
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children:
                            oralMeds.map<Widget>(_buildMedicineChip).toList(),
                      ),
                SizedBox(height: 12),
                _buildSectionTitle("Injectables"),
                injectables.isEmpty
                    ? Text("No injectables prescribed.",
                        style: TextStyle(color: Colors.black54, fontSize: 13))
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: injectables
                            .map<Widget>(_buildInjectableChip)
                            .toList(),
                      ),
                SizedBox(height: 12),
                _buildSectionTitle("Lab Tests"),
                labs.isEmpty
                    ? Text("No lab tests ordered.",
                        style: TextStyle(color: Colors.black54, fontSize: 13))
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: labs.map<Widget>(_buildLabChip).toList(),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: _green, strokeWidth: 2.5));
    }

    if (widget.showAll) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _green,
          title: Text("Visit History",
              style: TextStyle(color: Colors.white, fontSize: 18)),
          iconTheme: IconThemeData(color: Colors.white),
          elevation: 2,
        ),
        body: Column(
          children: [
            _buildPatientHeader(),
            Expanded(
              child: _allVisits.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 48, color: Colors.black26),
                          SizedBox(height: 16),
                          Text("No previous visits found.",
                              style: TextStyle(color: Colors.black54)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(12),
                      itemCount: _allVisits.length,
                      itemBuilder: (_, i) => _buildVisitCard(_allVisits[i]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _repeatVisit(_allVisits.first),
                    icon: Icon(Icons.repeat, color: Colors.white),
                    label: Text("Repeat Last Visit"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_latestVisit == null) {
      return Center(
        child: Text("No last visit found.",
            style: TextStyle(color: Colors.black54)),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: _green, size: 20),
              SizedBox(width: 6),
              Text("Last Visit",
                  style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
          SizedBox(height: 10),
          _buildVisitCard(_latestVisit!, isLatest: true),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () => _repeatVisit(_latestVisit!),
                icon: Icon(Icons.repeat, color: Colors.white),
                label: Text("Repeat Last Visit"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PatientHistory(
                        branchId: widget.branchId,
                        patientCNIC: widget.patientCNIC,
                        showAll: true,
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.list_alt, color: _green),
                label: Text("View Full History"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _green,
                  side: BorderSide(color: _green),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
