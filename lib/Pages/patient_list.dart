// lib/pages/patient_list.dart
import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PatientList extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic>? selectedPatient;
  final Function(Map<String, dynamic>) onPatientSelected;

  const PatientList({
    super.key,
    required this.branchId,
    required this.selectedPatient,
    required this.onPatientSelected,
  });

  @override
  State<PatientList> createState() => _PatientListState();
}

class _PatientListState extends State<PatientList>
    with SingleTickerProviderStateMixin {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _blue = Color(0xFF1976D2);
  static const Color _purple = Color(0xFF9C27B0);

  late final AnimationController _pulse;
  final ScrollController _scroll = ScrollController();

  List<Map<String, dynamic>> _all = [];
  int _selected = -1;

  @override
  void initState() {
    super.initState();
    _pulse =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _stream() {
    final today = DateFormat('ddMMyy').format(DateTime.now());
    final ref = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('serials')
        .doc(today);

    return StreamZip([
      ref.collection('zakat').snapshots(),
      ref.collection('non-zakat').snapshots(),
    ]).map((snaps) {
      List<Map<String, dynamic>> ready = [];
      List<Map<String, dynamic>> done = [];

      for (var snap in snaps) {
        for (var doc in snap.docs) {
          final d = doc.data();
          final status = d['status'] ?? '';
          final map = {
            ...d,
            'id': doc.id,
            'serial': d['serial'] ?? '000000-999',
          };
          if (status == 'completed') ready.add(map);
          if (status == 'dispensed') done.add(map);
        }
      }

      ready.sort((a, b) => _num(a['serial']).compareTo(_num(b['serial'])));
      done.sort((a, b) => _num(a['serial']).compareTo(_num(b['serial'])));

      return [...ready, ...done];
    });
  }

  int _num(String s) => int.tryParse(s.split('-').last) ?? 999;

  void _next() {
    final idx = _all.indexWhere((p) => p['status'] == 'completed');
    if (idx == -1) return;

    setState(() => _selected = idx);
    widget.onPatientSelected(_all[idx]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scroll.animateTo(idx * 76,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      color: Colors.white,
      child: Column(
        children: [
          // TITLE – PERFECT
          Container(
            color: _green,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.list_alt, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text(
                  "Dispense Queue",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // SUMMARY CARDS – SOFT & CLEAN
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _stream(),
            builder: (context, snap) {
              _all = snap.data ?? [];
              final ready =
                  _all.where((p) => p['status'] == 'completed').length;
              final done = _all.length - ready;

              if (_selected == -1 && ready > 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _next());
              }

              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _card("Ready", ready, _green),
                    _card("Done", done, _blue),
                    _card("Total", _all.length, _purple),
                  ],
                ),
              );
            },
          ),

          // LIST
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream(),
              builder: (context, snap) {
                if (!snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                _all = snap.data!;

                if (_all.isEmpty) {
                  return const Center(
                      child: Text("Queue empty",
                          style: TextStyle(color: Colors.grey)));
                }

                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 80),
                  itemCount: _all.length,
                  itemBuilder: (context, i) {
                    final p = _all[i];
                    final ready = p['status'] == 'completed';
                    final done = p['status'] == 'dispensed';
                    final sel = i == _selected;

                    final firstReady =
                        _all.indexWhere((x) => x['status'] == 'completed');
                    final canTap = ready && i == firstReady;

                    return Card(
                      elevation: 0,
                      color: sel ? _green.withOpacity(0.07) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: sel ? _green : Colors.grey.shade300,
                          width: sel ? 1.8 : 1,
                        ),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        enabled: canTap,
                        onTap: canTap
                            ? () {
                                setState(() => _selected = i);
                                widget.onPatientSelected(p);
                              }
                            : null,
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: done ? Colors.grey.shade400 : _green,
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          p['patientName'] ?? 'Unknown',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: done ? Colors.grey[600] : Colors.black87,
                          ),
                        ),
                        subtitle: Text("Serial: ${p['serial']}",
                            style: const TextStyle(fontSize: 12)),
                        trailing: done
                            ? const Icon(Icons.check_circle,
                                color: _blue, size: 26)
                            : (ready ? _dot() : null),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // CLEAN SUMMARY CARD
  Widget _card(String label, int count, Color c) {
    return Container(
      width: 88,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: c, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(count.toString(),
              style: TextStyle(
                  fontSize: 18, color: c, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // CLEAN PULSING DOT – NO SHADOW
  Widget _dot() => ScaleTransition(
        scale: Tween(begin: 0.9, end: 1.3).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        ),
        child: Container(
          width: 11,
          height: 11,
          decoration:
              const BoxDecoration(color: _green, shape: BoxShape.circle),
        ),
      );
}
