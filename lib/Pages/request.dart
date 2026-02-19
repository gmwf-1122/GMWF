import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import '../services/sync_service.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_events.dart';

class RequestUtils {
  static String getTitle(String type, String patient) {
    return switch (type) {
      'dispense' => 'Patient: $patient',
      'add_stock' => 'Stock Request',
      'change_prescription' => 'Prescription Change',
      'token_reversal' => 'Token Reversal',
      'edit_medicine' => 'Edit Medicine Request',
      'delete_medicine' => 'Delete Medicine Request',
      'patient_edit' => 'Patient Edit: $patient',
      _ => 'Request',
    };
  }

  static Color getBadgeColor(String type) => switch (type) {
        'dispense' => Colors.teal.shade100,
        'add_stock' => Colors.teal.shade100,
        'change_prescription' => Colors.teal.shade100,
        'token_reversal' => Colors.red.shade100,
        'edit_medicine' => Colors.teal.shade100,
        'delete_medicine' => Colors.red.shade100,
        'patient_edit' => Colors.yellow.shade100,
        _ => Colors.grey.shade300,
      };

  static Color getTextColor(String type) => switch (type) {
        'dispense' => Colors.teal.shade800,
        'add_stock' => Colors.teal.shade800,
        'change_prescription' => Colors.teal.shade800,
        'token_reversal' => Colors.red.shade800,
        'edit_medicine' => Colors.teal.shade800,
        'delete_medicine' => Colors.red.shade800,
        'patient_edit' => Colors.yellow.shade800,
        _ => Colors.grey.shade800,
      };

  static String generateDocId(
    String name,
    String type,
    String doseOrVariant,
    String expiry, {
    int? distilledWater,
    int? drops,
  }) {
    String clean(String s) => s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '');
    final cleanExpiry = clean(expiry);
    if (type == 'Nebulization' && distilledWater != null && drops != null) {
      return '${clean(name)}--${clean(type)}--water${distilledWater}ml-drops$drops--$cleanExpiry';
    }
    return '${clean(name)}--${clean(type)}--${clean(doseOrVariant)}--$cleanExpiry';
  }
}

class RequestPage extends StatefulWidget {
  final String branchId;
  const RequestPage({super.key, required this.branchId});

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);

    _realtimeSub = RealtimeManager().messageStream.listen((event) {
      final type = event['event_type'] as String?;
      final data = event['data'] as Map<String, dynamic>?;

      if (!mounted) return;

      if (type == 'request_approved' ||
          type == 'request_rejected' ||
          type == 'token_reversal_approved' ||
          type == 'token_reversal_rejected') {
        if (data == null || data['branchId'] == widget.branchId) {
          if (mounted) setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Requests', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Pending', icon: Icon(Icons.pending_actions)),
            Tab(text: 'Approved', icon: Icon(Icons.check_circle)),
            Tab(text: 'Rejected', icon: Icon(Icons.cancel)),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            _StableRequestTab(branchId: widget.branchId, status: 'pending'),
            _StableRequestTab(branchId: widget.branchId, status: 'approved'),
            _StableRequestTab(branchId: widget.branchId, status: 'rejected'),
          ],
        ),
      ),
    );
  }
}

class _StableRequestTab extends StatefulWidget {
  final String branchId;
  final String status;

  const _StableRequestTab({required this.branchId, required this.status});

  @override
  State<_StableRequestTab> createState() => _StableRequestTabState();
}

class _StableRequestTabState extends State<_StableRequestTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final Stream<QuerySnapshot> _editStream;
  late final Stream<QuerySnapshot> _dispenseStream;

  @override
  void initState() {
    super.initState();

    // No orderBy → instant loading without index
    _editStream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('edit_requests')
        .where('status', isEqualTo: widget.status)
        .snapshots();

    _dispenseStream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('dispense_requests')
        .where('status', isEqualTo: widget.status)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<List<QuerySnapshot>>(
      stream: CombineLatestStream.list([_editStream, _dispenseStream]),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error loading requests:\n${snapshot.error.toString().split('\n').first}',
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.teal));
        }

        final editDocs = snapshot.data![0].docs;
        final dispenseDocs = snapshot.data![1].docs;
        final allDocs = [...editDocs, ...dispenseDocs];

        if (allDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.status == 'pending'
                      ? Icons.pending_actions_outlined
                      : widget.status == 'approved'
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                  size: 80,
                  color: Colors.teal.shade600,
                ),
                const SizedBox(height: 16),
                Text(
                  widget.status == 'pending'
                      ? 'No Pending Requests'
                      : widget.status == 'approved'
                          ? 'No Approved Requests'
                          : 'No Rejected Requests',
                  style: const TextStyle(color: Colors.teal, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 300));
            if (mounted) setState(() {});
          },
          color: Colors.teal,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: allDocs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _buildRequestCard(context, allDocs[i]),
          ),
        );
      },
    );
  }

  Widget _buildRequestCard(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final requestType = data['requestType']?.toString() ?? data['type']?.toString() ?? 'unknown';
    final collection = doc.reference.parent.id;

    final patientName = data['patientName']?.toString() ?? '—';
    final requesterId = data['requestedBy']?.toString();
    final ts = data['requestedAt'] as Timestamp?;
    final reason = data['reason']?.toString() ?? '';

    String amountText = '';
    if (requestType == 'token_reversal') {
      final queueType = (data['queueType'] as String?)?.toLowerCase() ?? 'zakat';
      if (queueType.contains('non')) {
        amountText = 'Rs. 100';
      } else if (queueType.contains('gmwf')) {
        amountText = 'Rs. 0';
      } else {
        amountText = 'Rs. 20';
      }
    }

    final Future<String> requesterNameFuture = requesterId == null
        ? Future.value('Unknown')
        : FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('users')
            .doc(requesterId)
            .get()
            .then((snap) => snap.data()?['username']?.toString() ?? 'User')
            .timeout(const Duration(seconds: 5), onTimeout: () => 'User')
            .catchError((_) => 'User');

    return FutureBuilder<String>(
      future: requesterNameFuture,
      builder: (context, snap) {
        final name = snap.data ?? 'Loading...';

        return Card(
          color: Colors.teal.shade50,
          elevation: widget.status == 'pending' ? 6 : 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        RequestUtils.getTitle(requestType, patientName),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: RequestUtils.getBadgeColor(requestType),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        requestType.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: RequestUtils.getTextColor(requestType),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: Colors.teal.shade800),
                    const SizedBox(width: 8),
                    Text('By: $name', style: const TextStyle(fontSize: 14)),
                  ],
                ),
                if (ts != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Requested: ${DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate())}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                if (amountText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Amount: $amountText',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade800,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (requestType == 'patient_edit')
                  _buildPatientChanges(data, doc.id, collection)
                else if (requestType == 'token_reversal')
                  _buildTokenReversalView(data)
                else if (data['items'] != null || data['draftItems'] != null)
                  _buildItemsView(data, doc.id, requestType),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Reason: $reason', style: const TextStyle(fontSize: 14)),
                ],
                const SizedBox(height: 16),
                if (widget.status == 'pending')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _updateStatus(context, doc.id, 'rejected', requestType, collection),
                        child: const Text('Reject', style: TextStyle(color: Colors.red)),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
                        onPressed: () => _updateStatus(context, doc.id, 'approved', requestType, collection),
                        child: const Text('Approve', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  )
                else
                  Align(
                    alignment: Alignment.centerRight,
                    child: Chip(
                      label: Text(widget.status.toUpperCase()),
                      backgroundColor: Colors.teal.withOpacity(0.2),
                      labelStyle: TextStyle(color: Colors.teal.shade800, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemsView(Map<String, dynamic> data, String requestId, String requestType) {
    final rawItems = widget.status == 'pending'
        ? (data['draftItems'] as List?) ?? (data['items'] as List?) ?? []
        : (data['items'] as List?) ?? [];
    final items = rawItems.cast<Map<String, dynamic>>();

    final isWide = MediaQuery.of(context).size.width > 600;

    return isWide ? _buildTable(items, requestId, requestType) : _buildCompactItems(items, requestId, requestType);
  }

  Widget _buildTable(List<Map<String, dynamic>> items, String requestId, String requestType) {
    final canEdit = widget.status == 'pending';
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Dose', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Price', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Expiry', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Edit', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: List<DataRow>.generate(items.length, (index) {
          final m = items[index];
          return DataRow(
            cells: [
              DataCell(Text(m['name']?.toString() ?? '')),
              DataCell(Row(children: [_typeIcon(m['type']), const SizedBox(width: 6), Text(m['type'] ?? '')])),
              DataCell(Text(m['dose']?.toString() ?? '')),
              DataCell(Text('${m['quantity'] ?? 0}')),
              DataCell(Text('PKR ${m['price'] ?? 0}')),
              DataCell(Text(_formatDate(m['expiryDate']))),
              DataCell(
                canEdit
                    ? IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _showEditItemDialog(requestId, index, m),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildCompactItems(List<Map<String, dynamic>> items, String requestId, String requestType) {
    final canEdit = widget.status == 'pending';
    return Column(
      children: List<Widget>.generate(items.length, (index) {
        final m = items[index];
        final name = m['name']?.toString() ?? '';
        final type = m['type']?.toString() ?? '';
        final dose = (m['dose']?.toString().isNotEmpty == true) ? ' ${m['dose']}' : '';
        final qty = m['quantity'] ?? 0;
        final price = m['price'] ?? 0;
        final expiry = _formatDate(m['expiryDate']);
        return InkWell(
          onTap: canEdit ? () => _showEditItemDialog(requestId, index, m) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                _typeIcon(type),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black87),
                      children: [
                        TextSpan(text: '$name ($type$dose) × $qty', style: const TextStyle(fontWeight: FontWeight.w500)),
                        TextSpan(text: '\nPKR $price | $expiry', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                ),
                canEdit
                    ? IconButton(
                        icon: Icon(Icons.edit_outlined, size: 18, color: Colors.teal.shade800),
                        onPressed: () => _showEditItemDialog(requestId, index, m),
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _typeIcon(String? type) {
    final t = type ?? 'Others';
    final icon = switch (t) {
      'Tablet' => FontAwesomeIcons.tablets,
      'Capsule' => FontAwesomeIcons.capsules,
      'Syrup' => FontAwesomeIcons.bottleDroplet,
      'Injection' => FontAwesomeIcons.syringe,
      'Big Bottle' => FontAwesomeIcons.prescriptionBottleAlt,
      'Nebulization' => FontAwesomeIcons.cloud,
      _ => FontAwesomeIcons.pills,
    };
    return Icon(icon, size: 16, color: Colors.teal.shade800);
  }

  Widget _buildPatientChanges(Map<String, dynamic> data, String requestId, String collection) {
    final originalData = data['originalData'] as Map<String, dynamic>? ?? {};
    final proposedRaw = widget.status == 'pending'
        ? (data['draftData'] ?? data['proposedData'])
        : data['proposedData'];
    final proposedData = proposedRaw as Map<String, dynamic>? ?? {};

    final fields = ['name', 'phone', 'status', 'bloodGroup', 'gender', 'dob'];

    String getValue(Map<String, dynamic> m, String key) {
      final v = m[key];
      if (key == 'dob' && v is Timestamp?) {
        return v == null ? '—' : DateFormat('dd-MM-yyyy').format(v.toDate());
      }
      return v?.toString() ?? '—';
    }

    String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

    final isWide = MediaQuery.of(context).size.width > 600;

    if (isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Field', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('Original', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('Proposed', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: fields.map((f) {
                return DataRow(
                  cells: [
                    DataCell(Text(capitalize(f))),
                    DataCell(Text(getValue(originalData, f))),
                    DataCell(Text(getValue(proposedData, f))),
                  ],
                );
              }).toList(),
            ),
          ),
          if (widget.status == 'pending') ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _showEditPatientDialog(requestId, proposedData, originalData),
                icon: const Icon(Icons.edit),
                label: const Text('Edit Proposed'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
              ),
            ),
          ],
        ],
      );
    } else {
      return Column(
        children: [
          ...fields.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('${capitalize(f)}:')),
                    Text(getValue(originalData, f)),
                    const Icon(Icons.arrow_forward, size: 16),
                    const SizedBox(width: 8),
                    Text(getValue(proposedData, f)),
                  ],
                ),
              )),
          if (widget.status == 'pending') ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _showEditPatientDialog(requestId, proposedData, originalData),
                icon: const Icon(Icons.edit),
                label: const Text('Edit Proposed'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
              ),
            ),
          ],
        ],
      );
    }
  }

  Widget _buildTokenReversalView(Map<String, dynamic> data) {
    final tokenSerial = data['tokenSerial']?.toString() ?? data['tokenId']?.toString() ?? '—';
    final patientId = data['patientId']?.toString() ?? '—';
    final amountText = ''; // We now use the pre-calculated amountText from above
    final queueType = data['queueType']?.toString() ?? 'unknown';

    // Only show amount if it's a token reversal
    String displayAmount = '';
    if (amountText.isNotEmpty) {
      displayAmount = amountText;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Token Details:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
        const SizedBox(height: 8),
        Text("Token Serial: $tokenSerial"),
        Text("Patient ID: $patientId"),
        Text("Queue: $queueType"),
        if (displayAmount.isNotEmpty)
          Text(
            "Amount: $displayAmount",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800),
          ),
      ],
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '—';
    if (raw is String) {
      final parsed = _tryParseDateString(raw);
      if (parsed != null) return DateFormat('dd-MM-yyyy').format(parsed);
      return raw;
    }
    if (raw is Timestamp) {
      return DateFormat('dd-MM-yyyy').format(raw.toDate());
    }
    return raw.toString();
  }

  DateTime? _tryParseDateString(String s) {
    final ddmmyyyy = RegExp(r'^(\d{2})[-\/](\d{2})[-\/](\d{4})$');
    final yyyymmdd = RegExp(r'^(\d{4})[-\/](\d{2})[-\/](\d{2})$');
    var m = ddmmyyyy.firstMatch(s);
    if (m != null) {
      return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
    }
    m = yyyymmdd.firstMatch(s);
    if (m != null) {
      return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    }
    return null;
  }

  Future<void> _showEditPatientDialog(String requestId, Map<String, dynamic> proposed, Map<String, dynamic> original) async {
    bool isChild = original['isAdult'] == false;

    final cnicCtrl = TextEditingController(
      text: isChild ? (original['guardianCnic']?.toString() ?? '') : (original['cnic']?.toString() ?? ''),
    );
    final nameCtrl = TextEditingController(text: proposed['name']?.toString() ?? original['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: proposed['phone']?.toString() ?? original['phone']?.toString() ?? '');
    final dobCtrl = TextEditingController();
    final bloodGroupCtrl = TextEditingController(text: proposed['bloodGroup']?.toString() ?? original['bloodGroup']?.toString() ?? 'N/A');

    String selectedStatus = proposed['status']?.toString() ?? original['status']?.toString() ?? 'Zakat';
    String selectedGender = proposed['gender']?.toString() ?? original['gender']?.toString() ?? 'Male';

    if (proposed['dob'] != null || original['dob'] != null) {
      final date = (proposed['dob'] as Timestamp?)?.toDate() ?? (original['dob'] as Timestamp?)?.toDate();
      if (date != null) dobCtrl.text = DateFormat('dd-MM-yyyy').format(date);
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Colors.teal.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.edit_note, color: Colors.teal.shade800),
              const SizedBox(width: 8),
              Text("Edit Proposed Changes", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade800),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Patient Type", style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text("Adult"),
                              value: false,
                              groupValue: isChild,
                              activeColor: Colors.teal.shade700,
                              onChanged: (v) => setState(() => isChild = v!),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text("Child"),
                              value: true,
                              groupValue: isChild,
                              activeColor: Colors.teal.shade700,
                              onChanged: (v) => setState(() => isChild = v!),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: cnicCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: isChild ? "Guardian CNIC" : "CNIC",
                    prefixIcon: Icon(Icons.badge, color: Colors.teal.shade800),
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: "Full Name",
                    prefixIcon: Icon(Icons.person, color: Colors.teal.shade800),
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration: InputDecoration(
                    labelText: "Phone (optional)",
                    prefixIcon: Icon(Icons.phone, color: Colors.teal.shade800),
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dobCtrl,
                  decoration: InputDecoration(
                    labelText: "DOB (dd-MM-yyyy)",
                    prefixIcon: Icon(Icons.cake, color: Colors.teal.shade800),
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bloodGroupCtrl,
                  decoration: InputDecoration(
                    labelText: "Blood Group",
                    prefixIcon: Icon(Icons.bloodtype, color: Colors.teal.shade800),
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("Status", style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(child: RadioListTile<String>(title: const Text("Zakat"), value: "Zakat", groupValue: selectedStatus, onChanged: (v) => setState(() => selectedStatus = v!))),
                    Expanded(child: RadioListTile<String>(title: const Text("Non-Zakat"), value: "Non-Zakat", groupValue: selectedStatus, onChanged: (v) => setState(() => selectedStatus = v!))),
                    Expanded(child: RadioListTile<String>(title: const Text("GMWF"), value: "GMWF", groupValue: selectedStatus, onChanged: (v) => setState(() => selectedStatus = v!))),
                  ],
                ),
                const SizedBox(height: 20),
                const Text("Gender", style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(child: RadioListTile<String>(title: const Text("Male"), value: "Male", groupValue: selectedGender, onChanged: (v) => setState(() => selectedGender = v!))),
                    Expanded(child: RadioListTile<String>(title: const Text("Female"), value: "Female", groupValue: selectedGender, onChanged: (v) => setState(() => selectedGender = v!))),
                    Expanded(child: RadioListTile<String>(title: const Text("Other"), value: "Other", groupValue: selectedGender, onChanged: (v) => setState(() => selectedGender = v!))),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancel", style: TextStyle(color: Colors.teal.shade800)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
              onPressed: () async {
                DateTime? dob;
                if (dobCtrl.text.isNotEmpty && RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(dobCtrl.text)) {
                  final p = dobCtrl.text.split('-');
                  dob = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
                }

                final newProposed = <String, dynamic>{
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                  'status': selectedStatus,
                  'bloodGroup': bloodGroupCtrl.text.trim().isNotEmpty ? bloodGroupCtrl.text.trim() : 'N/A',
                  'gender': selectedGender,
                  'isAdult': !isChild,
                  if (dob != null) 'dob': Timestamp.fromDate(dob),
                  if (isChild) 'guardianCnic': cnicCtrl.text.trim(),
                  if (!isChild) 'cnic': cnicCtrl.text.trim(),
                };

                await FirebaseFirestore.instance
                    .collection('branches')
                    .doc(widget.branchId)
                    .collection('edit_requests')
                    .doc(requestId)
                    .update({'draftData': newProposed});

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draft updated')));
              },
              child: const Text("Save Draft", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(
    BuildContext context,
    String docId,
    String newStatus,
    String requestType,
    String collection,
  ) async {
    final ref = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection(collection)
        .doc(docId);

    try {
      await ref.update({
        'status': newStatus,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      if (newStatus == 'approved') {
        final snap = await ref.get();
        final data = snap.data() as Map<String, dynamic>;

        if (requestType == 'patient_edit') {
          final patientId = data['patientId'] as String?;
          final toApply = (data['draftData'] as Map<String, dynamic>?) ?? (data['proposedData'] as Map<String, dynamic>?);

          if (toApply == null || toApply.isEmpty || patientId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Invalid request data"), backgroundColor: Colors.red),
            );
            return;
          }

          final patientsRef = FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('patients');

          var patientDoc = await patientsRef.doc(patientId).get();

          if (!patientDoc.exists) {
            final original = data['originalData'] as Map<String, dynamic>? ?? {};
            final proposed = toApply;

            final cnic = proposed['cnic']?.toString() ?? original['cnic']?.toString() ?? data['cnic']?.toString();
            final guardianCnic = proposed['guardianCnic']?.toString() ?? original['guardianCnic']?.toString() ?? data['guardianCnic']?.toString();

            Query query = patientsRef.limit(1);

            if (cnic != null && cnic.isNotEmpty) {
              query = query.where('cnic', isEqualTo: cnic);
            } else if (guardianCnic != null && guardianCnic.isNotEmpty) {
              query = query.where('guardianCnic', isEqualTo: guardianCnic);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Could not find patient in Firestore"), backgroundColor: Colors.red),
              );
              return;
            }

            final querySnap = await query.get();
            if (querySnap.docs.isNotEmpty) {
              patientDoc = querySnap.docs.first as QueryDocumentSnapshot<Map<String, dynamic>>;
            }
          }

          if (!patientDoc.exists) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Patient not found in Firestore"), backgroundColor: Colors.red),
            );
            return;
          }

          await patientDoc.reference.update(toApply);

          await SyncService().forceFullRefresh(widget.branchId);
        } else if (requestType == 'token_reversal') {
          final tokenSerial = data['tokenSerial'] as String? ?? data['tokenId'] as String?;
          if (tokenSerial == null || tokenSerial.isEmpty) return;

          final queueTypeRaw = (data['queueType'] as String?)?.toLowerCase() ?? 'zakat';
          final queueCollection = queueTypeRaw.contains('non')
              ? 'non-zakat'
              : queueTypeRaw.contains('gmwf') || queueTypeRaw.contains('gm wf')
                  ? 'gmwf'
                  : 'zakat';

          final dateKey = tokenSerial.split('-').first;

          await FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('serials')
              .doc(dateKey)
              .collection(queueCollection)
              .doc(tokenSerial)
              .delete();

          await SyncService().forceFullRefresh(widget.branchId);
        } else if (requestType == 'add_stock') {
          final itemsToUse = (data['draftItems'] as List?)?.cast<Map<String, dynamic>>() ?? (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          await _handleAddStock({'items': itemsToUse});
        } else if (requestType == 'edit_medicine') {
          final itemsToUse = (data['draftItems'] as List?)?.cast<Map<String, dynamic>>() ?? (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          await _handleEditMedicine({'items': itemsToUse});
        } else if (requestType == 'delete_medicine') {
          final itemsToUse = (data['draftItems'] as List?)?.cast<Map<String, dynamic>>() ?? (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          await _handleDeleteMedicine({'items': itemsToUse});
        } else if (requestType == 'change_prescription') {
          final itemsToUse = (data['draftItems'] as List?)?.cast<Map<String, dynamic>>() ?? (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          await _handleChangePrescription(data, itemsToUse);
        }
      }

      if (mounted) setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Request ${newStatus.toUpperCase()}"),
          backgroundColor: newStatus == 'approved' ? Colors.teal.shade700 : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _handleAddStock(Map<String, dynamic> data) async {
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final branchRef = FirebaseFirestore.instance.collection('branches').doc(widget.branchId);
    final inventory = branchRef.collection('inventory');
    final warehouse = branchRef.collection('warehouse');
    final batch = FirebaseFirestore.instance.batch();

    for (final item in items) {
      final name = item['name']?.toString();
      final type = item['type']?.toString();
      final classification = item['classification']?.toString() ?? '';
      final dose = item['dose']?.toString() ?? '';
      final distilledWater = (item['distilledWater'] as num?)?.toInt();
      final drops = (item['drops'] as num?)?.toInt();
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      final price = (item['price'] as num?)?.toInt() ?? 0;
      final expiry = item['expiryDate']?.toString() ?? '';
      final isBigBottle = item['isBigBottle'] == true;

      if (name == null || type == null || qty <= 0) continue;
      final nameLower = name.toLowerCase();

      final variantForId = (type == 'Nebulization') ? 'neb${distilledWater ?? 0}-${drops ?? 0}' : dose;

      final warehouseId = RequestUtils.generateDocId(
        name,
        type,
        variantForId,
        expiry,
        distilledWater: distilledWater,
        drops: drops,
      );
      final warehouseSnap = await warehouse.doc(warehouseId).get();

      final commonFields = {
        'name': name,
        'name_lower': nameLower,
        'classification': classification,
        'type': type,
        'price': price,
        'quantity': qty,
        'expiryDate': expiry,
      };

      Map<String, dynamic> fullWarehouseData = Map.from(commonFields);
      if (type == 'Nebulization') {
        fullWarehouseData['distilledWater'] = distilledWater ?? 0;
        fullWarehouseData['drops'] = drops ?? 0;
      } else {
        fullWarehouseData['dose'] = dose;
      }

      if (warehouseSnap.exists) {
        final cur = (warehouseSnap['quantity'] ?? 0).toInt();
        batch.update(warehouse.doc(warehouseId), {'quantity': cur + qty});
      } else {
        fullWarehouseData['addedAt'] = FieldValue.serverTimestamp();
        batch.set(warehouse.doc(warehouseId), fullWarehouseData);
      }

      if (isBigBottle) {
        final smallName = "$name (Small)";
        final smallDoseNum = (int.tryParse(dose.replaceAll(RegExp(r'\D'), '')) ?? 100) ~/ 10;
        final smallDose = "$smallDoseNum ml";

        final inventoryId = RequestUtils.generateDocId(
          smallName,
          'Syrup',
          smallDose,
          expiry,
        );
        final invSnap = await inventory.doc(inventoryId).get();

        final totalSmallQty = qty * 10;

        if (invSnap.exists) {
          final cur = (invSnap['quantity'] ?? 0).toInt();
          batch.update(inventory.doc(inventoryId), {'quantity': cur + totalSmallQty});
        } else {
          batch.set(inventory.doc(inventoryId), {
            'name': smallName,
            'name_lower': smallName.toLowerCase(),
            'classification': classification,
            'type': 'Syrup',
            'dose': smallDose,
            'price': price ~/ 10,
            'quantity': totalSmallQty,
            'expiryDate': expiry,
            'addedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        final inventoryId = RequestUtils.generateDocId(
          name,
          type,
          variantForId,
          expiry,
          distilledWater: distilledWater,
          drops: drops,
        );
        final invSnap = await inventory.doc(inventoryId).get();

        Map<String, dynamic> fullInventoryData = Map.from(commonFields);
        if (type == 'Nebulization') {
          fullInventoryData['distilledWater'] = distilledWater ?? 0;
          fullInventoryData['drops'] = drops ?? 0;
        } else {
          fullInventoryData['dose'] = dose;
        }

        if (invSnap.exists) {
          final cur = (invSnap['quantity'] ?? 0).toInt();
          batch.update(inventory.doc(inventoryId), {
            'quantity': cur + qty,
            'classification': classification,
            'price': price,
          });
        } else {
          fullInventoryData['addedAt'] = FieldValue.serverTimestamp();
          batch.set(inventory.doc(inventoryId), fullInventoryData);
        }
      }
    }

    await batch.commit();
  }

  Future<void> _handleEditMedicine(Map<String, dynamic> data) async {
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final inventory = FirebaseFirestore.instance.collection('branches').doc(widget.branchId).collection('inventory');
    final batch = FirebaseFirestore.instance.batch();

    for (final item in items) {
      final oldId = item['oldId']?.toString();
      if (oldId == null) continue;

      final name = item['name']?.toString() ?? '';
      final type = item['type']?.toString() ?? '';
      final dose = item['dose']?.toString() ?? '';
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      final price = (item['price'] as num?)?.toInt() ?? 0;
      final expiry = item['expiryDate']?.toString() ?? '';
      final classification = item['classification']?.toString() ?? '';
      final distilledWater = (item['distilledWater'] as num?)?.toInt();
      final drops = (item['drops'] as num?)?.toInt();

      final newData = <String, dynamic>{
        'name': name,
        'name_lower': name.toLowerCase(),
        'type': type,
        'dose': type == 'Nebulization' ? '' : dose,
        'quantity': qty,
        'price': price,
        'expiryDate': expiry,
        'classification': classification,
      };

      if (type == 'Nebulization') {
        newData['distilledWater'] = distilledWater ?? 0;
        newData['drops'] = drops ?? 0;
      }

      final newId = RequestUtils.generateDocId(
        name,
        type,
        type == 'Nebulization' ? '' : dose,
        expiry,
        distilledWater: distilledWater,
        drops: drops,
      );

      if (oldId == newId) {
        batch.update(inventory.doc(oldId), newData);
      } else {
        batch.delete(inventory.doc(oldId));
        newData['addedAt'] = FieldValue.serverTimestamp();
        batch.set(inventory.doc(newId), newData);
      }
    }
    await batch.commit();
  }

  Future<void> _handleDeleteMedicine(Map<String, dynamic> data) async {
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final inventory = FirebaseFirestore.instance.collection('branches').doc(widget.branchId).collection('inventory');
    final batch = FirebaseFirestore.instance.batch();

    for (final item in items) {
      final name = item['name']?.toString();
      final type = item['type']?.toString();
      final dose = item['dose']?.toString() ?? '';
      final expiry = item['expiryDate']?.toString() ?? '';
      final distilledWater = (item['distilledWater'] as num?)?.toInt();
      final drops = (item['drops'] as num?)?.toInt();

      if (name == null || type == null) continue;

      final id = RequestUtils.generateDocId(
        name,
        type,
        dose,
        expiry,
        distilledWater: distilledWater,
        drops: drops,
      );

      batch.delete(inventory.doc(id));
    }
    await batch.commit();
  }

  Future<void> _handleChangePrescription(Map<String, dynamic> data, List<Map<String, dynamic>> items) async {
    final patientId = data['patientId']?.toString();
    if (patientId == null) return;

    final patientRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('patients')
        .doc(patientId);

    await patientRef.update({
      'prescription': items,
    });
  }

  Future<void> _showEditItemDialog(String requestId, int itemIndex, Map<String, dynamic> item) async {
    final reqRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('edit_requests')
        .doc(requestId);
    final reqSnap = await reqRef.get();
    final reqData = reqSnap.data();
    final status = reqData?['status']?.toString() ?? '';
    if (status != 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot edit — request is not pending'), backgroundColor: Colors.orange),
      );
      return;
    }

    final nameCtrl = TextEditingController(text: item['name']?.toString() ?? '');
    final qtyCtrl = TextEditingController(text: (item['quantity'] ?? 0).toString());
    final priceCtrl = TextEditingController(text: (item['price'] ?? 0).toString());
    DateTime? pickedDate = _tryParseDateString(item['expiryDate']?.toString() ?? '');
    String expiryStr = pickedDate != null ? DateFormat('dd-MM-yyyy').format(pickedDate) : (item['expiryDate']?.toString() ?? '');

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          Future<void> pickDate() async {
            final initial = pickedDate ?? DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d != null) {
              setState(() {
                pickedDate = d;
                expiryStr = DateFormat('dd-MM-yyyy').format(d);
              });
            }
          }

          return AlertDialog(
            backgroundColor: Colors.teal.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Edit Item', style: TextStyle(color: Colors.teal.shade800)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.medication, color: Colors.teal.shade800),
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      prefixIcon: Icon(Icons.inventory, color: Colors.teal.shade800),
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Price (PKR)',
                      prefixIcon: Icon(Icons.attach_money, color: Colors.teal.shade800),
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          readOnly: true,
                          controller: TextEditingController(text: expiryStr),
                          decoration: InputDecoration(
                            labelText: 'Expiry',
                            prefixIcon: Icon(Icons.calendar_month, color: Colors.teal.shade800),
                            filled: true,
                            fillColor: Colors.white,
                            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                          ),
                        ),
                      ),
                      IconButton(onPressed: pickDate, icon: Icon(Icons.calendar_today, color: Colors.teal.shade800)),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: Colors.teal.shade800))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
                onPressed: () async {
                  final newName = nameCtrl.text.trim();
                  final newQty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                  final newPrice = int.tryParse(priceCtrl.text.trim()) ?? 0;
                  final newExpiry = expiryStr;

                  if (newName.isEmpty || newQty <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid input')));
                    return;
                  }

                  final updatedItem = Map<String, dynamic>.from(item);
                  updatedItem['name'] = newName;
                  updatedItem['quantity'] = newQty;
                  updatedItem['price'] = newPrice;
                  updatedItem['expiryDate'] = newExpiry;

                  await _editItemInRequestAsDraft(requestId, itemIndex, updatedItem);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item updated in draft')));
                },
                child: const Text("Save", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _editItemInRequestAsDraft(String requestId, int itemIndex, Map<String, dynamic> newItem) async {
    final ref = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('edit_requests')
        .doc(requestId);

    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data() as Map<String, dynamic>? ?? {};
    if (data['status'] != 'pending') return;

    final originalItems = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    var draftItems = (data['draftItems'] as List?)?.cast<Map<String, dynamic>>()?.toList() ??
        originalItems.map((e) => Map<String, dynamic>.from(e)).toList();

    if (itemIndex >= 0 && itemIndex < draftItems.length) {
      draftItems[itemIndex] = newItem;
    }

    await ref.update({
      'draftItems': draftItems,
      'lastEditedAt': FieldValue.serverTimestamp(),
      'lastEditedBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }
}