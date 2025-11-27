// patient_detail_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

enum SearchMode { inline, popup }

class PatientDetailScreen extends StatefulWidget {
  final String patientId;
  final Map<String, dynamic> patientData;
  final bool isOnline;
  final Box localBox;
  final String branchId;
  final String doctorId;
  final SearchMode initialSearchMode;

  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.patientData,
    required this.isOnline,
    required this.localBox,
    required this.branchId,
    required this.doctorId,
    this.initialSearchMode = SearchMode.inline,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _diagnosisController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  SearchMode _mode = SearchMode.inline;

  List<Map<String, dynamic>> _prescription =
      []; // {code, name, qty, stockAtTime}
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialSearchMode;
    _loadLastPrescriptionPreview();
    _searchController.addListener(_onSearchChanged);
  }

  void _loadLastPrescriptionPreview() {
    final notes = widget.patientData['doctorNotes'];
    if (notes is List && notes.isNotEmpty) {
      final last = notes.last;
      final diag = last['diagnosis'];
      final meds = last['medicines'];
      if (diag != null && diag is String) _diagnosisController.text = diag;
      if (meds is List) {
        _prescription = meds.map((m) => Map<String, dynamic>.from(m)).toList();
      }
    }
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchInventory(q);
    });
  }

  Future<void> _searchInventory(String q) async {
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }

    setState(() {
      _searching = true;
    });

    try {
      // Use prefix queries for name and code (Firestore)
      // name range: q -> q + \uf8ff
      final nameQuery = await _firestore
          .collection('inventory')
          .where('branchId', isEqualTo: widget.branchId)
          .where('medName', isGreaterThanOrEqualTo: q)
          .where('medName', isLessThanOrEqualTo: '$q\uf8ff')
          .limit(50)
          .get();

      final codeQuery = await _firestore
          .collection('inventory')
          .where('branchId', isEqualTo: widget.branchId)
          .where('medCode', isGreaterThanOrEqualTo: q)
          .where('medCode', isLessThanOrEqualTo: '$q\uf8ff')
          .limit(50)
          .get();

      final Map<String, Map<String, dynamic>> merged = {};
      for (var d in nameQuery.docs) {
        final m = d.data();
        merged[d.id] = {'id': d.id, ...m};
      }
      for (var d in codeQuery.docs) {
        final m = d.data();
        merged[d.id] = {'id': d.id, ...m};
      }

      setState(() {
        _searchResults =
            merged.values.map((m) => Map<String, dynamic>.from(m)).toList();
      });
    } catch (e) {
      debugPrint("Search inventory failed: $e");
      // fallback: try a simple fetch (limited) and filter client-side
      try {
        final snap = await _firestore
            .collection('inventory')
            .where('branchId', isEqualTo: widget.branchId)
            .limit(100)
            .get();
        final ql = q.toLowerCase();
        final filtered = snap.docs
            .where((d) {
              final m = d.data();
              final name = (m['medName'] ?? '').toString().toLowerCase();
              final code = (m['medCode'] ?? '').toString().toLowerCase();
              return name.contains(ql) || code.contains(ql);
            })
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
        setState(() {
          _searchResults =
              filtered.map((m) => Map<String, dynamic>.from(m)).toList();
        });
      } catch (_) {
        setState(() => _searchResults = []);
      }
    }

    setState(() => _searching = false);
  }

  Future<void> _openPopupSearch() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search medicine by name or code',
                        ),
                        autofocus: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    )
                  ]),
                ),
                Expanded(
                  child: _buildSearchResultsList(),
                ),
              ],
            ),
          ),
        );
      },
    );
    // Clear search after popup closes
    _searchController.clear();
    setState(() => _searchResults = []);
  }

  Widget _buildSearchResultsList() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return const Center(child: Text("No medicines found"));
    }
    return ListView.separated(
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, idx) {
        final med = _searchResults[idx];
        final name = med['medName'] ?? 'Unknown';
        final code = med['medCode'] ?? '';
        final stock = med['stock'] ?? 0;
        return ListTile(
          title: Text("$name (${code.toString()})"),
          subtitle: Text("Stock: $stock"),
          trailing: IconButton(
            icon: const Icon(FontAwesomeIcons.plusCircle),
            onPressed: () => _askQtyAndAdd(med),
          ),
        );
      },
    );
  }

  void _askQtyAndAdd(Map<String, dynamic> med) async {
    final qtyCtrl = TextEditingController(text: '1');
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text("Add ${med['medName'] ?? 'medicine'}"),
          content: TextField(
            controller: qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                final q = int.tryParse(qtyCtrl.text) ?? 1;
                Navigator.pop(ctx, q);
              },
              child: const Text("Add"),
            )
          ],
        );
      },
    );

    if (res != null && res > 0) {
      setState(() {
        _prescription.add({
          'id': med['id'],
          'medCode': med['medCode'],
          'medName': med['medName'],
          'qty': res,
          'stockAtTime': med['stock'] ?? 0,
        });
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Added to prescription")));
    }
  }

  void _removeFromPrescription(int idx) {
    setState(() {
      _prescription.removeAt(idx);
    });
  }

  Future<void> _repeatLast() async {
    // attempt to fetch last from Firestore (fresh) or fallback to provided data
    try {
      final doc =
          await _firestore.collection('patients').doc(widget.patientId).get();
      final data = doc.data();
      if (data != null &&
          data['doctorNotes'] is List &&
          (data['doctorNotes'] as List).isNotEmpty) {
        final last = (data['doctorNotes'] as List).last;
        if (last['medicines'] is List) {
          setState(() {
            _prescription = (last['medicines'] as List)
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
            if (last['diagnosis'] is String) {
              _diagnosisController.text = last['diagnosis'];
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Loaded last prescription")));
          return;
        }
      }
    } catch (e) {
      debugPrint("Repeat fetch failed: $e");
    }

    // Fallback: from passed patientData
    final notes = widget.patientData['doctorNotes'];
    if (notes is List && notes.isNotEmpty) {
      final last = notes.last;
      setState(() {
        if (last['diagnosis'] is String) {
          _diagnosisController.text = last['diagnosis'];
        }
        if (last['medicines'] is List) {
          _prescription = (last['medicines'] as List)
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Loaded last prescription (cached)")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No previous prescription found")));
    }
  }

  Future<void> _savePrescription() async {
    if (_prescription.isEmpty && _diagnosisController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Add diagnosis or medicines first")));
      return;
    }

    final payload = {
      'date': DateTime.now().toIso8601String(),
      'diagnosis': _diagnosisController.text.trim(),
      'medicines':
          _prescription.map((m) => Map<String, dynamic>.from(m)).toList(),
      'doctorId': widget.doctorId,
      'doctorEmail': null,
    };

    setState(() => _saving = true);

    try {
      payload['doctorEmail'] = 'unknown';
      // try to get current doctor email
      try {
        final docUser =
            await _firestore.collection('doctors').doc(widget.doctorId).get();
        if (docUser.exists && docUser.data()?['email'] != null) {
          payload['doctorEmail'] = docUser.data()?['email'];
        }
      } catch (_) {}

      if (widget.isOnline) {
        await _firestore.collection('patients').doc(widget.patientId).set({
          'doctorNotes': FieldValue.arrayUnion([payload]),
        }, SetOptions(merge: true));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Prescription saved online")));
      } else {
        // store in Hive pending list
        final list = widget.localBox
            .get('pendingPrescriptions', defaultValue: []) as List;
        final newList = List.from(list)
          ..add({'patientId': widget.patientId, ...payload});
        await widget.localBox.put('pendingPrescriptions', newList);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Offline: saved to local cache")));
      }
      // optionally clear after save:
      setState(() {
        _prescription = [];
        _diagnosisController.clear();
      });
    } catch (e) {
      debugPrint("Save failed: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to save: $e")));
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _diagnosisController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Widget _prescriptionPreview() {
    if (_prescription.isEmpty) {
      return const Text("No medicines added yet");
    }
    return Column(
      children: [
        ..._prescription.asMap().entries.map((entry) {
          final i = entry.key;
          final med = entry.value;
          return ListTile(
            title: Text("${med['medName'] ?? ''} (${med['medCode'] ?? ''})"),
            subtitle:
                Text("Qty: ${med['qty']} | Stock (ref): ${med['stockAtTime']}"),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _removeFromPrescription(i),
            ),
          );
        })
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patientData;
    return Scaffold(
      appBar: AppBar(
        title: Text(p['name'] ?? 'Patient',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
              icon: const Icon(FontAwesomeIcons.repeat),
              onPressed: _repeatLast,
              tooltip: "Repeat last"),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F9D58), Color(0xFFE8F5E9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: ListView(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Name: ${p['name'] ?? 'Unknown'}",
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text("Age: ${p['age'] ?? 'N/A'}"),
                      Text("Gender: ${p['gender'] ?? 'N/A'}"),
                      Text("Serial: ${p['serial'] ?? 'N/A'}"),
                    ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Diagnosis / Notes",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _diagnosisController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: "Write diagnosis, tests, observations",
                        ),
                      ),
                    ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text("Prescription",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          // Toggle modes
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _mode = SearchMode.inline;
                              });
                            },
                            child: Text("Inline",
                                style: TextStyle(
                                    color: _mode == SearchMode.inline
                                        ? Colors.green
                                        : Colors.black54)),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _mode = SearchMode.popup;
                              });
                            },
                            child: Text("Popup",
                                style: TextStyle(
                                    color: _mode == SearchMode.popup
                                        ? Colors.green
                                        : Colors.black54)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_mode == SearchMode.inline) ...[
                        TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search med by name/code'),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(height: 180, child: _buildSearchResultsList()),
                      ] else ...[
                        ElevatedButton.icon(
                          icon: const Icon(FontAwesomeIcons.search),
                          label: const Text("Open Medicine Search (Popup)"),
                          onPressed: _openPopupSearch,
                        ),
                      ],
                      const Divider(),
                      const Text("Prescription Preview:",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      _prescriptionPreview(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _repeatLast,
                            icon: const Icon(FontAwesomeIcons.repeat),
                            label: const Text("Repeat Last"),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _savePrescription,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(FontAwesomeIcons.save),
                              label: const Text("Save Prescription"),
                            ),
                          ),
                        ],
                      )
                    ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
