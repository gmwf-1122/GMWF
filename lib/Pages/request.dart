import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import '../services/sync_service.dart';
import '../services/local_storage_service.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_events.dart';

class RequestUtils {
  static String getTitle(String type, String patient) {
    return switch (type) {
      'dispense'            => 'Patient: $patient',
      'add_stock'           => 'Stock Request',
      'change_prescription' => 'Prescription Change',
      'token_reversal'      => 'Token Reversal',
      'edit_medicine'       => 'Edit Medicine Request',
      'delete_medicine'     => 'Delete Medicine Request',
      'patient_edit'        => 'Patient Edit: $patient',
      'token_exception'     => 'Token Exception: $patient',
      _                     => 'Request',
    };
  }

  static Color getBadgeColor(String type) => switch (type) {
        'dispense'            => Colors.teal.shade100,
        'add_stock'           => Colors.teal.shade100,
        'change_prescription' => Colors.teal.shade100,
        'token_reversal'      => Colors.red.shade100,
        'edit_medicine'       => Colors.teal.shade100,
        'delete_medicine'     => Colors.red.shade100,
        'patient_edit'        => Colors.yellow.shade100,
        'token_exception'     => Colors.orange.shade100,
        _                     => Colors.grey.shade300,
      };

  static Color getTextColor(String type) => switch (type) {
        'dispense'            => Colors.teal.shade800,
        'add_stock'           => Colors.teal.shade800,
        'change_prescription' => Colors.teal.shade800,
        'token_reversal'      => Colors.red.shade800,
        'edit_medicine'       => Colors.teal.shade800,
        'delete_medicine'     => Colors.red.shade800,
        'patient_edit'        => Colors.yellow.shade800,
        'token_exception'     => Colors.orange.shade800,
        _                     => Colors.grey.shade800,
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

List<Map<String, dynamic>> _safeItemList(dynamic raw) {
  if (raw == null) return [];
  if (raw is! List) return [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

int _safeInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) {
    return int.tryParse(v) ?? (double.tryParse(v)?.toInt() ?? 0);
  }
  return 0;
}

class RequestPage extends StatefulWidget {
  final String branchId;
  final bool isSupervisor;
  const RequestPage({super.key, required this.branchId, this.isSupervisor = false});

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage>
    with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  String? _currentUserRole;
  String? _username;
  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);

    // Fetch current user details
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(uid)
          .get()
          .then((snap) {
        if (mounted) {
          setState(() {
            _currentUserRole = snap.data()?['role']?.toString().toLowerCase();
            _username = snap.data()?['username']?.toString();
          });
        }
      });
    }

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
        title: const Text('Requests',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
            _StableRequestTab(
              branchId: widget.branchId, 
              status: 'pending', 
              isSupervisor: widget.isSupervisor,
              currentUserRole: _currentUserRole,
              username: _username,
            ),
            _StableRequestTab(
              branchId: widget.branchId, 
              status: 'approved', 
              isSupervisor: widget.isSupervisor,
              currentUserRole: _currentUserRole,
              username: _username,
            ),
            _StableRequestTab(
              branchId: widget.branchId, 
              status: 'rejected', 
              isSupervisor: widget.isSupervisor,
              currentUserRole: _currentUserRole,
              username: _username,
            ),
          ],
        ),
      ),
    );
  }
}

class _StableRequestTab extends StatefulWidget {
  final String branchId;
  final String status;
  final bool isSupervisor;
  final String? currentUserRole;
  final String? username;
  const _StableRequestTab({
    required this.branchId, 
    required this.status,
    this.isSupervisor = false,
    this.currentUserRole,
    this.username,
  });

  @override
  State<_StableRequestTab> createState() => _StableRequestTabState();
}

class _StableRequestTabState extends State<_StableRequestTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final Stream<QuerySnapshot> _editStream;
  late final Stream<QuerySnapshot> _dispenseStream;

  final Map<String, String> _nameCache = {};

  @override
  void initState() {
    super.initState();
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

  String _resolveRequesterName(String docId, Map<String, dynamic> data) {
    if (_nameCache.containsKey(docId)) return _nameCache[docId]!;

    final cached = (data['requesterName']?.toString() ?? '').trim();
    if (cached.isNotEmpty) {
      _nameCache[docId] = cached;
      return cached;
    }

    final requesterId = (data['requestedBy']?.toString() ??
            data['requester']?.toString() ??
            '')
        .trim();
    if (requesterId.isEmpty) {
      _nameCache[docId] = 'Unknown';
      return 'Unknown';
    }

    _nameCache[docId] = '…';

    FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('users')
        .doc(requesterId)
        .get()
        .then((snap) {
      final name = snap.data()?['username']?.toString() ?? 'User';
      if (mounted) setState(() => _nameCache[docId] = name);
    }).catchError((_) {
      if (mounted) setState(() => _nameCache[docId] = 'User');
    });

    return '…';
  }

  int _safeInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  List<Map<String, dynamic>> _safeItemList(dynamic list) {
    if (list == null || list is! List) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
          return const Center(
              child: CircularProgressIndicator(color: Colors.teal));
        }

        final editDocs    = snapshot.data![0].docs;
        final dispenseDocs = snapshot.data![1].docs;
        var allDocs = [...editDocs, ...dispenseDocs];

        final seen = <String>{};
        allDocs = allDocs.where((d) => seen.add(d.id)).toList();

        allDocs.sort((a, b) {
          final aTime = (a.data() as Map)['requestedAt'] as Timestamp?;
          final bTime = (b.data() as Map)['requestedAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });

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
                  style: const TextStyle(
                      color: Colors.teal,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            _nameCache.clear();
            await Future.delayed(const Duration(milliseconds: 300));
            if (mounted) setState(() {});
          },
          color: Colors.teal,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: allDocs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) =>
                _buildRequestCard(context, allDocs[i]),
          ),
        );
      },
    );
  }

  Widget _buildRequestCard(
      BuildContext context, QueryDocumentSnapshot doc) {
    final data        = doc.data() as Map<String, dynamic>;
    final requestType = data['requestType']?.toString() ??
        data['type']?.toString() ??
        'unknown';
    final collection  = doc.reference.parent.id;
    final patientName = data['patientName']?.toString() ?? '—';
    final ts          = data['requestedAt'] as Timestamp?;
    final reason      = data['reason']?.toString() ?? '';
    final name        = _resolveRequesterName(doc.id, data);
    final approverName = data['reviewedByName'] ?? data['approvedByName'];
    final docReason   = data['doctorReason']?.toString() ?? '';

    String amountText = '';
    if (requestType == 'token_reversal') {
      final queueType =
          (data['queueType'] as String?)?.toLowerCase() ?? 'zakat';
      if (queueType.contains('non')) {
        amountText = 'Rs. 100';
      } else if (queueType.contains('gmwf')) {
        amountText = 'PKR 0';
      } else {
        amountText = 'Rs. 20';
      }
    }

    final isDoctor = widget.currentUserRole == 'doctor';
    final canApproveAsSupervisor = widget.isSupervisor && requestType != 'token_exception';
    final canApproveAsDoctor = isDoctor && requestType == 'token_exception';

    return Card(
      color: Colors.teal.shade50,
      elevation: widget.status == 'pending' ? 6 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
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
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.person, size: 16, color: Colors.teal.shade800),
              const SizedBox(width: 8),
              Text('By: $name', style: const TextStyle(fontSize: 14)),
            ]),
            if (ts != null) ...[
              const SizedBox(height: 4),
              Text(
                'Requested: ${DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate())}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            if (widget.status == 'approved') ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.verified_user, size: 14, color: Colors.teal.shade700),
                const SizedBox(width: 6),
                Text(
                  'Approved by: ${approverName ?? 'Doctor'}',
                  style: TextStyle(
                    fontSize: 12, 
                    color: Colors.teal.shade700, 
                    fontWeight: FontWeight.bold
                  ),
                ),
              ]),
            ],
            if (widget.status == 'rejected') ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.remove_circle, size: 14, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Text(
                  'Rejected by: ${approverName ?? 'Doctor'}',
                  style: TextStyle(
                    fontSize: 12, 
                    color: Colors.red.shade700, 
                    fontWeight: FontWeight.bold
                  ),
                ),
              ]),
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
            else if (requestType == 'edit_medicine')
              _buildMedicineEditChanges(data)
            else if (requestType == 'token_reversal')
              _buildTokenReversalView(data)
            else if (requestType == 'token_exception')
              _buildTokenExceptionView(data)
            else if (data['items'] != null || data['draftItems'] != null)
              _buildItemsView(data, doc.id, requestType),

            if (reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Requester Reason: $reason',
                  style: const TextStyle(fontSize: 14)),
            ],
            if (docReason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Approval Reason: $docReason',
                  style: TextStyle(
                    fontSize: 14, 
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade900,
                  )),
            ],
            const SizedBox(height: 16),
            if (widget.status == 'pending')
              if (canApproveAsSupervisor || canApproveAsDoctor)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _updateStatus(context, doc.id,
                          'rejected', requestType, collection),
                      child: const Text('Reject',
                          style: TextStyle(color: Colors.red)),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _updateStatus(context, doc.id,
                          'approved', requestType, collection),
                      child: const Text('Approve'),
                    ),
                  ],
                )
              else if (widget.isSupervisor && requestType == 'token_exception')
                _buildDoctorOnlyNotice()
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: Chip(
                    label: const Text('PENDING APPROVAL'),
                    backgroundColor: Colors.orange.withValues(alpha: 0.1),
                    labelStyle: TextStyle(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 10),
                  ),
                )
            else
              Align(
                alignment: Alignment.centerRight,
                child: Chip(
                  label: Text(widget.status.toUpperCase()),
                  backgroundColor: widget.status == 'approved' 
                      ? Colors.teal.withValues(alpha: 0.15) 
                      : Colors.red.withValues(alpha: 0.1),
                  labelStyle: TextStyle(
                      color: widget.status == 'approved' 
                          ? Colors.teal.shade800 
                          : Colors.red.shade800,
                      fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsView(
      Map<String, dynamic> data, String requestId, String requestType) {
    final items = widget.status == 'pending'
        ? (_safeItemList(data['draftItems']).isNotEmpty
            ? _safeItemList(data['draftItems'])
            : _safeItemList(data['items']))
        : _safeItemList(data['items']);

    final isWide = MediaQuery.of(context).size.width > 600;
    return isWide
        ? _buildTable(items, requestId, requestType)
        : _buildCompactItems(items, requestId, requestType);
  }

  Widget _buildTable(List<Map<String, dynamic>> items, String requestId,
      String requestType) {
    final canEdit = widget.status == 'pending';
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(
              label: Text('Formula',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(
              label: Text('Type',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(
              label: Text('Dose',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(
              label: Text('Qty',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(
              label: Text('Price',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(
              label: Text('Expiry',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(
              label: Text('Edit',
                  style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: List<DataRow>.generate(items.length, (index) {
          final m       = items[index];
          final formula = (m['formula'] ?? '').toString();
          return DataRow(cells: [
            DataCell(Text(m['name']?.toString() ?? '')),
            DataCell(Row(children: [
              _typeIcon(m['type']),
              const SizedBox(width: 6),
              Text(m['type'] ?? '')
            ])),
            DataCell(Text(m['dose']?.toString() ?? '')),
            DataCell(Text('${m['quantity'] ?? 0}')),
            DataCell(Text('PKR ${m['price'] ?? 0}')),
            DataCell(Text(_formatDate(m['expiryDate']))),
            DataCell(
              canEdit
                  ? IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () =>
                          _showEditItemDialog(requestId, index, m),
                    )
                  : const SizedBox.shrink(),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _buildCompactItems(List<Map<String, dynamic>> items,
      String requestId, String requestType) {
    final canEdit = widget.status == 'pending';
    return Column(
      children: List<Widget>.generate(items.length, (index) {
        final m       = items[index];
        final name    = m['name']?.toString() ?? '';
        final type    = m['type']?.toString() ?? '';
        final dose    = (m['dose']?.toString().isNotEmpty == true)
            ? ' ${m['dose']}'
            : '';
        final qty    = m['quantity'] ?? 0;
        final price  = m['price'] ?? 0;
        final expiry = _formatDate(m['expiryDate']);
        final formula = (m['formula'] ?? '').toString();
        return InkWell(
          onTap: canEdit
              ? () => _showEditItemDialog(requestId, index, m)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              _typeIcon(type),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black87),
                    children: [
                      TextSpan(
                          text: '$name ($type$dose) × $qty',
                          style: const TextStyle(
                              fontWeight: FontWeight.w500)),
                      TextSpan(
                          text: '\nPKR $price | $expiry',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
              ),
              canEdit
                  ? IconButton(
                      icon: Icon(Icons.edit_outlined,
                          size: 18, color: Colors.teal.shade800),
                      onPressed: () =>
                          _showEditItemDialog(requestId, index, m),
                    )
                  : const SizedBox.shrink(),
            ]),
          ),
        );
      }),
    );
  }

  Widget _typeIcon(String? type) {
    final t    = type ?? 'Others';
    final icon = switch (t) {
      'Tablet'      => FontAwesomeIcons.tablets,
      'Capsule'     => FontAwesomeIcons.capsules,
      'Syrup'       => FontAwesomeIcons.bottleDroplet,
      'Injection'   => FontAwesomeIcons.syringe,
      'Big Bottle'  => FontAwesomeIcons.prescriptionBottleAlt,
      'Nebulization' => FontAwesomeIcons.cloud,
      _             => FontAwesomeIcons.pills,
    };
    return Icon(icon, size: 16, color: Colors.teal.shade800);
  }

  Widget _buildPatientChanges(
      Map<String, dynamic> data, String requestId, String collection) {
    final originalData = data['originalData'] as Map<String, dynamic>? ?? {};
    final proposedRaw  = widget.status == 'pending'
        ? (data['draftData'] ?? data['proposedData'])
        : data['proposedData'];
    final proposedData = proposedRaw as Map<String, dynamic>? ?? {};

    final fields = [
      'name', 'phone', 'status', 'bloodGroup', 'gender', 'dob'
    ];

    String getValue(Map<String, dynamic> m, String key) {
      final v = m[key];
      if (key == 'dob' && v is Timestamp?) {
        return v == null
            ? '—'
            : DateFormat('dd-MM-yyyy').format(v.toDate());
      }
      return v?.toString() ?? '—';
    }

    String capitalize(String s) =>
        s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

    final isWide = MediaQuery.of(context).size.width > 600;

    if (isWide) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(
                      label: Text('Field',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('Original',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('Proposed',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: fields
                    .map((f) => DataRow(cells: [
                          DataCell(Text(capitalize(f))),
                          DataCell(Text(getValue(originalData, f))),
                          DataCell(Text(getValue(proposedData, f))),
                        ]))
                    .toList(),
              ),
            ),
            if (widget.status == 'pending') ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () => _showEditPatientDialog(
                      requestId, proposedData, originalData),
                  icon: const Icon(Icons.edit, color: Colors.white),
                  label: const Text('Edit Proposed'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ]);
    } else {
      return Column(children: [
        ...fields.map((f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text('${capitalize(f)}:')),
                Text(getValue(originalData, f)),
                const Icon(Icons.arrow_forward, size: 16),
                const SizedBox(width: 8),
                Text(getValue(proposedData, f)),
              ]),
            )),
        if (widget.status == 'pending') ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () => _showEditPatientDialog(
                  requestId, proposedData, originalData),
              icon: const Icon(Icons.edit, color: Colors.white),
              label: const Text('Edit Proposed'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ]);
    }
  }

  Widget _buildMedicineEditChanges(Map<String, dynamic> data) {
    final originalData = data['originalData'] as Map<String, dynamic>? ?? {};
    final items = widget.status == 'pending'
        ? (_safeItemList(data['draftItems']).isNotEmpty
            ? _safeItemList(data['draftItems'])
            : _safeItemList(data['items']))
        : _safeItemList(data['items']);
    
    if (items.isEmpty) return const SizedBox.shrink();
    final proposedData = items[0];

    final fields = [
      {'key': 'name', 'label': 'Formula'},
      {'key': 'type', 'label': 'Type'},
      {'key': 'dose', 'label': 'Dose'},
      {'key': 'quantity', 'label': 'Qty'},
      {'key': 'price', 'label': 'Price'},
      {'key': 'expiryDate', 'label': 'Expiry'},
    ];

    String getValue(Map<String, dynamic> m, String key) {
      final v = m[key];
      if (key == 'price' && v != null && v.toString().isNotEmpty) {
        return 'PKR ${v.toString()}';
      }
      return v?.toString() ?? '—';
    }

    final isWide = MediaQuery.of(context).size.width > 600;

    if (isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Medicine Comparison', 
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal.shade900)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 48,
              columns: const [
                DataColumn(label: Text('Field', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Original', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Proposed', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: fields.map((f) {
                final key = f['key']!;
                final label = f['label']!;
                final oldVal = getValue(originalData, key);
                final newVal = getValue(proposedData, key);
                final isChanged = oldVal != newVal && newVal != '—';
                
                return DataRow(cells: [
                  DataCell(Text(label, style: const TextStyle(fontSize: 13))),
                  DataCell(Text(oldVal, style: const TextStyle(fontSize: 13))),
                  DataCell(Text(newVal, style: TextStyle(
                    fontSize: 13,
                    color: isChanged ? Colors.blue.shade900 : null,
                    fontWeight: isChanged ? FontWeight.bold : null,
                  ))),
                ]);
              }).toList(),
            ),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Changes:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade900, fontSize: 13)),
          const SizedBox(height: 6),
          ...fields.map((f) {
            final key = f['key']!;
            final label = f['label']!;
            final oldVal = getValue(originalData, key);
            final newVal = getValue(proposedData, key);
            if (oldVal == newVal || newVal == '—') return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(flex: 3, child: Text(oldVal, style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.red, fontSize: 12))),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.arrow_forward, size: 12, color: Colors.teal),
                  ),
                  Expanded(flex: 4, child: Text(newVal, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 12))),
                ],
              ),
            );
          }),
        ],
      );
    }
  }

  Widget _buildTokenReversalView(Map<String, dynamic> data) {
    final tokenSerial = data['tokenSerial']?.toString() ??
        data['tokenId']?.toString() ??
        '—';
    final patientId = data['patientId']?.toString() ?? '—';
    final queueType = data['queueType']?.toString() ?? 'unknown';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Token Details:",
          style: TextStyle(
              fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
      const SizedBox(height: 8),
      Text("Token Serial: $tokenSerial"),
      Text("Patient ID: $patientId"),
      Text("Queue: $queueType"),
    ]);
  }

  Widget _buildTokenExceptionView(Map<String, dynamic> data) {
    final restriction = data['restriction'] as Map<String, dynamic>?;
    final patientId  = data['patientId']?.toString() ?? '—';
    final remDays    = restriction?['remainingDays'] ?? '—';
    final isLastDay  = restriction?['isLastDay'] == true;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
          const SizedBox(width: 8),
          const Text("Restriction Details:", style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        Text("Patient ID: $patientId"),
        Text(isLastDay 
          ? "Status: Medicine expires TODAY"
          : "Status: Medicine expires in $remDays days"),
      ]),
    );
  }

  Widget _buildDoctorOnlyNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, size: 16, color: Colors.blue.shade800),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "This request must be reviewed by a Doctor.",
            style: TextStyle(
              fontSize: 12, 
              color: Colors.blue.shade800, 
              fontWeight: FontWeight.bold
            ),
          ),
        ),
      ]),
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
      return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!),
          int.parse(m.group(1)!));
    }
    m = yyyymmdd.firstMatch(s);
    if (m != null) {
      return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
          int.parse(m.group(3)!));
    }
    return null;
  }

  Future<void> _showEditPatientDialog(String requestId,
      Map<String, dynamic> proposed, Map<String, dynamic> original) async {
    bool isChild = original['isAdult'] == false;
    final cnicCtrl = TextEditingController(
      text: isChild
          ? (original['guardianCnic']?.toString() ?? '')
          : (original['cnic']?.toString() ?? ''),
    );
    final nameCtrl = TextEditingController(
        text: proposed['name']?.toString() ??
            original['name']?.toString() ??
            '');
    final phoneCtrl = TextEditingController(
        text: proposed['phone']?.toString() ??
            original['phone']?.toString() ??
            '');
    final dobCtrl        = TextEditingController();
    final bloodGroupCtrl = TextEditingController(
        text: proposed['bloodGroup']?.toString() ??
            original['bloodGroup']?.toString() ??
            'N/A');
    String selectedStatus = proposed['status']?.toString() ??
        original['status']?.toString() ??
        'Zakat';
    String selectedGender = proposed['gender']?.toString() ??
        original['gender']?.toString() ??
        'Male';

    if (proposed['dob'] != null || original['dob'] != null) {
      final date = (proposed['dob'] as Timestamp?)?.toDate() ??
          (original['dob'] as Timestamp?)?.toDate();
      if (date != null)
        dobCtrl.text = DateFormat('dd-MM-yyyy').format(date);
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Colors.teal.shade50,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.edit_note, color: Colors.teal.shade800),
            const SizedBox(width: 8),
            Text("Edit Proposed Changes",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade800)),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                      const Text("Patient Type",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(children: [
                        Expanded(
                            child: RadioListTile<bool>(
                                title: const Text("Adult"),
                                value: false,
                                groupValue: isChild,
                                activeColor: Colors.teal.shade700,
                                onChanged: (v) =>
                                    setState(() => isChild = v!))),
                        Expanded(
                            child: RadioListTile<bool>(
                                title: const Text("Child"),
                                value: true,
                                groupValue: isChild,
                                activeColor: Colors.teal.shade700,
                                onChanged: (v) =>
                                    setState(() => isChild = v!))),
                      ]),
                    ]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: cnicCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: isChild ? "Guardian CNIC" : "CNIC",
                  prefixIcon:
                      Icon(Icons.badge, color: Colors.teal.shade800),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: "Full Name",
                  prefixIcon:
                      Icon(Icons.person, color: Colors.teal.shade800),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(
                  labelText: "Phone (optional)",
                  prefixIcon:
                      Icon(Icons.phone, color: Colors.teal.shade800),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dobCtrl,
                decoration: InputDecoration(
                  labelText: "DOB (dd-MM-yyyy)",
                  prefixIcon:
                      Icon(Icons.cake, color: Colors.teal.shade800),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bloodGroupCtrl,
                decoration: InputDecoration(
                  labelText: "Blood Group",
                  prefixIcon: Icon(Icons.bloodtype,
                      color: Colors.teal.shade800),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 20),
              const Text("Status",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(child: RadioListTile<String>(
                    title: const Text("Zakat"),
                    value: "Zakat",
                    groupValue: selectedStatus,
                    onChanged: (v) =>
                        setState(() => selectedStatus = v!))),
                Expanded(child: RadioListTile<String>(
                    title: const Text("Non-Zakat"),
                    value: "Non-Zakat",
                    groupValue: selectedStatus,
                    onChanged: (v) =>
                        setState(() => selectedStatus = v!))),
                Expanded(child: RadioListTile<String>(
                    title: const Text("GMWF"),
                    value: "GMWF",
                    groupValue: selectedStatus,
                    onChanged: (v) =>
                        setState(() => selectedStatus = v!))),
              ]),
              const SizedBox(height: 20),
              const Text("Gender",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(child: RadioListTile<String>(
                    title: const Text("Male"),
                    value: "Male",
                    groupValue: selectedGender,
                    onChanged: (v) =>
                        setState(() => selectedGender = v!))),
                Expanded(child: RadioListTile<String>(
                    title: const Text("Female"),
                    value: "Female",
                    groupValue: selectedGender,
                    onChanged: (v) =>
                        setState(() => selectedGender = v!))),
                Expanded(child: RadioListTile<String>(
                    title: const Text("Other"),
                    value: "Other",
                    groupValue: selectedGender,
                    onChanged: (v) =>
                        setState(() => selectedGender = v!))),
              ]),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancel",
                  style: TextStyle(color: Colors.teal.shade800)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                DateTime? dob;
                if (dobCtrl.text.isNotEmpty &&
                    RegExp(r'^\d{2}-\d{2}-\d{4}$')
                        .hasMatch(dobCtrl.text)) {
                  final p = dobCtrl.text.split('-');
                  dob = DateTime(
                      int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
                }
                final newProposed = <String, dynamic>{
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim().isNotEmpty
                      ? phoneCtrl.text.trim()
                      : null,
                  'status': selectedStatus,
                  'bloodGroup': bloodGroupCtrl.text.trim().isNotEmpty
                      ? bloodGroupCtrl.text.trim()
                      : 'N/A',
                  'gender': selectedGender,
                  'isAdult': !isChild,
                  if (dob != null) 'dob': Timestamp.fromDate(dob),
                  if (isChild)  'guardianCnic': cnicCtrl.text.trim(),
                  if (!isChild) 'cnic': cnicCtrl.text.trim(),
                };
                await FirebaseFirestore.instance
                    .collection('branches')
                    .doc(widget.branchId)
                    .collection('edit_requests')
                    .doc(requestId)
                    .update({'draftData': newProposed});
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Draft updated')));
              },
              child: const Text("Save Draft"),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showReasonPrompt(BuildContext context, String action) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${action == 'approved' ? 'Approval' : 'Rejection'} Reason'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: 'Enter reason for $action...',
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: action == 'approved' ? Colors.teal : Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (ctrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reason is required'))
                );
                return;
              }
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(action.toUpperCase()),
          ),
        ],
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
    // If it's a token exception, prompt for a reason first
    String? docReason;
    if (requestType == 'token_exception') {
      docReason = await _showReasonPrompt(context, newStatus);
      if (docReason == null) return; // User cancelled
    }

    final ref = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection(collection)
        .doc(docId);

    try {
      String? reviewerName;
      final reviewerUid = FirebaseAuth.instance.currentUser?.uid;
      if (reviewerUid != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('users')
            .doc(reviewerUid)
            .get();
        reviewerName = userDoc.data()?['username']?.toString();
      }

      await ref.update({
        'status':     newStatus,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': reviewerUid,
        if (reviewerName != null) 'reviewedByName': reviewerName,
        if (docReason != null) 'doctorReason': docReason,
      });

      if (newStatus == 'approved') {
        final snap = await ref.get();
        final data = snap.data() as Map<String, dynamic>;

        debugPrint('=== APPROVAL DEBUG ===');
        debugPrint('Request Type: $requestType');
        debugPrint('Collection: $collection');
        debugPrint('Document ID: $docId');

        if (requestType == 'patient_edit') {
          final patientId = data['patientId'] as String?;
          final toApply   = (data['draftData']    as Map<String, dynamic>?) ??
                            (data['proposedData'] as Map<String, dynamic>?);

          if (toApply == null ||
              toApply.isEmpty ||
              patientId == null ||
              patientId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Invalid patient edit request data"),
                backgroundColor: Colors.red));
            return;
          }

          debugPrint('Patient ID to update: $patientId');
          debugPrint('Changes to apply: $toApply');

          final patientsRef = FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('patients');

          await patientsRef.doc(patientId).update(toApply);
          debugPrint('✅ Patient $patientId updated in Firestore');

          await SyncService().forceFullRefresh(widget.branchId);

          // ── Broadcast to receptionist screens ────────────────────────────
          try {
            final sanitizedChanges = LocalStorageService.sanitize(toApply);
            RealtimeManager().sendMessage({
              'event_type': 'patient_edit_approved',
              'data': {
                'branchId': widget.branchId,
                'patientId': patientId,
                'changes': sanitizedChanges,
              },
            });
            debugPrint('✅ patient_edit_approved broadcast sent');
          } catch (e) {
            debugPrint('Failed to broadcast patient edit: $e');
          }
        }
        else if (requestType == 'token_reversal') {
          final tokenSerial = data['tokenSerial'] as String? ??
              data['tokenId']     as String?;
          if (tokenSerial == null || tokenSerial.isEmpty) {
            debugPrint('❌ Token reversal: missing tokenSerial');
            return;
          }

          final queueTypeRaw    =
              (data['queueType'] as String?)?.toLowerCase() ?? 'zakat';
          final queueCollection = queueTypeRaw.contains('non')
              ? 'non-zakat'
              : (queueTypeRaw.contains('gmwf') ||
                      queueTypeRaw.contains('gm wf'))
                  ? 'gmwf'
                  : 'zakat';

          final dateKey = tokenSerial.split('-').first;

          debugPrint('Deleting token: $tokenSerial from $queueCollection');

          // Delete from Firestore
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('serials')
              .doc(dateKey)
              .collection(queueCollection)
              .doc(tokenSerial)
              .delete();

          debugPrint('✅ Token deleted from Firestore');

          // Delete from local Hive on the supervisor device
          await LocalStorageService.deleteLocalEntry(
              widget.branchId, tokenSerial);

          debugPrint('✅ Token deleted from local storage');

          await SyncService().forceFullRefresh(widget.branchId);

          // ── Broadcast to receptionist screens ────────────────────────────
          try {
            RealtimeManager().sendMessage({
              'event_type': 'token_reversal_approved',
              'data': {
                'branchId':    widget.branchId,
                'tokenSerial': tokenSerial,
                'queueType':   queueCollection,
                'dateKey':     dateKey,
              },
            });
            debugPrint('✅ token_reversal_approved broadcast sent');
          } catch (e) {
            debugPrint('Failed to broadcast token reversal: $e');
          }
        }
        else if (requestType == 'add_stock') {
          final itemsToUse = _safeItemList(data['draftItems']).isNotEmpty
              ? _safeItemList(data['draftItems'])
              : _safeItemList(data['items']);

          if (itemsToUse.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No items found in stock request'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }

          try {
            await _handleAddStock(itemsToUse);
            await SyncService().forceFullRefresh(widget.branchId);
            debugPrint('✅ Add stock completed successfully');
          } catch (e, stack) {
            debugPrint('❌ Add stock failed: $e');
            debugPrint(stack.toString());
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to update inventory: $e'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }
        else if (requestType == 'edit_medicine') {
          final itemsToUse = _safeItemList(data['draftItems']).isNotEmpty
              ? _safeItemList(data['draftItems'])
              : _safeItemList(data['items']);
          await _handleEditMedicine(itemsToUse, reviewerUid ?? '', reviewerName);
          await SyncService().forceFullRefresh(widget.branchId);
        }
        else if (requestType == 'delete_medicine') {
          final itemsToUse = _safeItemList(data['draftItems']).isNotEmpty
              ? _safeItemList(data['draftItems'])
              : _safeItemList(data['items']);
          await _handleDeleteMedicine(itemsToUse);
          await SyncService().forceFullRefresh(widget.branchId);
        }
        else if (requestType == 'change_prescription') {
          final itemsToUse = _safeItemList(data['draftItems']).isNotEmpty
              ? _safeItemList(data['draftItems'])
              : _safeItemList(data['items']);
          await _handleChangePrescription(data, itemsToUse);
        }
        else if (requestType == 'token_exception') {
          // Find the patientId/restictId from the request data
          final patientId = data['patientId']?.toString();
          final medicineName = data['medicineName']?.toString();
          
          if (patientId != null) {
             // 1. Delete restriction from Firestore
             final restrictionsRef = FirebaseFirestore.instance
                 .collection('branches')
                 .doc(widget.branchId)
                 .collection('medicine_restrictions');
             
             await restrictionsRef.doc(patientId).delete().catchError((e) {
               debugPrint('Note: Restriction doc $patientId already gone or error: $e');
             });

             // 2. Broadcast to all LAN devices so the UI updates instantly everywhere
             RealtimeManager().sendMessage({
               'event_type': 'restriction_removed',
               'data': {
                 'branchId': widget.branchId,
                 'patientId': patientId,
                 'medicineName': medicineName,
               },
             });
             
             debugPrint('✅ Token exception approved: Restriction removed for $patientId');
          }
        }
        else if (requestType == 'register_medicine') {
          final itemsToUse = _safeItemList(data['draftItems']).isNotEmpty
              ? _safeItemList(data['draftItems'])
              : _safeItemList(data['items']);
          
          if (itemsToUse.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No items found in registration request'))
            );
            return;
          }

          final inventory = FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('inventory');
          
          for (final item in itemsToUse) {
            final name = item['name']?.toString() ?? '';
            final type = item['type'] ?? '';
            final dose = item['dose'] ?? '';
            final exp  = item['expiryDate'] ?? '';
            
            final id = RequestUtils.generateDocId(name, type, dose, exp);
            
            await inventory.doc(id).set({
              ...item,
              'addedAt': FieldValue.serverTimestamp(),
              'isVerified': true,
              'createdBy': data['requestedBy'],
              'createdByName': data['requesterName'],
              'approvedBy': reviewerUid,
              'approvedByName': reviewerName ?? 'Supervisor',
            });
            
            // Add to log
            await FirebaseFirestore.instance
                .collection('branches')
                .doc(widget.branchId)
                .collection('inventory_log')
                .add({
              'action': 'medicine_registered',
              'medicineName': name,
              'medicineType': type,
              'dose': dose,
              'quantityAdded': _safeInt(item['quantity']),
              'price': item['price'],
              'expiryDate': exp,
              'performedBy': reviewerUid,
              'performedByName': reviewerName ?? 'Supervisor',
              'timestamp': FieldValue.serverTimestamp(),
              'docId': id,
              'approvedRequestId': docId,
            });
          }
          await SyncService().forceFullRefresh(widget.branchId);
        }
      }

      // ✅ FIX: Use microtask so the Firestore stream has one event-loop turn
      // to re-emit the updated document before we force a rebuild. Without
      // this the card still briefly shows the old status after approval.
      if (mounted) {
        Future.microtask(() {
          if (mounted) setState(() {});
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Request ${newStatus.toUpperCase()}"),
        backgroundColor: newStatus == 'approved'
            ? Colors.teal.shade700
            : Colors.red,
      ));
    } catch (e, stack) {
      debugPrint('❌ _updateStatus error: $e');
      debugPrint(stack.toString());
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleAddStock(List<Map<String, dynamic>> items) async {
    debugPrint('handleAddStock started with ${items.length} items');

    if (items.isEmpty) {
      debugPrint('handleAddStock: items list is empty - returning');
      return;
    }

    final branchRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId);
    final inventory = branchRef.collection('inventory');
    final warehouse  = branchRef.collection('warehouse');
    final batch      = FirebaseFirestore.instance.batch();

    int operationCount = 0;

    for (final item in items) {
      final name = item['name']?.toString()?.trim();
      final type = item['type']?.toString()?.trim();

      if (name == null || name.isEmpty || type == null || type.isEmpty) {
        debugPrint('Skipping item: missing name or type');
        continue;
      }

      final formula        = (item['formula'] ?? '').toString().trim();
      final formulaLower   = formula.toLowerCase();
      final classification = item['classification']?.toString() ?? '';
      final dose           = item['dose']?.toString() ?? '';
      final distilledWater = (item['distilledWater'] as num?)?.toInt();
      final drops          = (item['drops']          as num?)?.toInt();

      final qty   = _safeInt(item['quantity']);
      final price = _safeInt(item['price']);
      final expiry = item['expiryDate']?.toString() ?? '';

      if (qty <= 0) {
        debugPrint('Skipping item "$name" - quantity <= 0');
        continue;
      }

      final nameLower    = name.toLowerCase();
      final variantForId = type == 'Nebulization'
          ? 'neb${distilledWater ?? 0}-${drops ?? 0}'
          : dose;

      final warehouseId = RequestUtils.generateDocId(
        name, type, variantForId, expiry,
        distilledWater: distilledWater, drops: drops,
      );

      final warehouseSnap = await warehouse.doc(warehouseId).get();

      final commonFields = <String, dynamic>{
        'name':           name,
        'name_lower':     nameLower,
        'formula':        formula,
        'formula_lower':  formulaLower,
        'classification': classification,
        'type':           type,
        'price':          price,
        'quantity':       qty,
        'expiryDate':     expiry,
      };

      final Map<String, dynamic> fullWarehouseData = Map.from(commonFields);
      if (type == 'Nebulization') {
        fullWarehouseData['distilledWater'] = distilledWater ?? 0;
        fullWarehouseData['drops']          = drops ?? 0;
      } else {
        fullWarehouseData['dose'] = dose;
      }

      if (warehouseSnap.exists) {
        final dataMap = warehouseSnap.data() as Map<String, dynamic>? ?? {};
        final curQty  = _safeInt(dataMap['quantity']);
        batch.update(warehouse.doc(warehouseId), {
          'quantity':      curQty + qty,
          'formula':       formula,
          'formula_lower': formulaLower,
        });
      } else {
        fullWarehouseData['addedAt'] = FieldValue.serverTimestamp();
        batch.set(warehouse.doc(warehouseId), fullWarehouseData);
      }

      Query invQuery = inventory
          .where('name_lower', isEqualTo: nameLower)
          .where('type',       isEqualTo: type);

      if (type != 'Nebulization' && dose.isNotEmpty) {
        invQuery = invQuery.where('dose', isEqualTo: dose);
      }
      if (expiry.isNotEmpty) {
        invQuery = invQuery.where('expiryDate', isEqualTo: expiry);
      }

      final existingQuery = await invQuery.limit(1).get();

      final Map<String, dynamic> fullInventoryData = Map.from(commonFields);
      if (type == 'Nebulization') {
        fullInventoryData['distilledWater'] = distilledWater ?? 0;
        fullInventoryData['drops']          = drops ?? 0;
      } else {
        fullInventoryData['dose'] = dose;
      }

      if (existingQuery.docs.isNotEmpty) {
        final existingDoc = existingQuery.docs.first;
        final dataMap     = existingDoc.data() as Map<String, dynamic>? ?? {};
        final curQty      = _safeInt(dataMap['quantity']);
        batch.update(existingDoc.reference, {
          'quantity':       curQty + qty,
          'formula':        formula,
          'formula_lower':  formulaLower,
          'classification': classification,
          'price':          price,
        });
      } else {
        final inventoryId = RequestUtils.generateDocId(
          name, type, variantForId, expiry,
          distilledWater: distilledWater, drops: drops,
        );
        fullInventoryData['addedAt'] = FieldValue.serverTimestamp();
        batch.set(inventory.doc(inventoryId), fullInventoryData);
      }

      operationCount++;
    }

    if (operationCount == 0) {
      debugPrint('No valid operations to commit');
      return;
    }

    debugPrint('Committing batch with $operationCount operations...');
    await batch.commit();
    debugPrint('✅ Batch commit successful for add_stock');
  }

  Future<void> _handleEditMedicine(
      List<Map<String, dynamic>> items, String reviewerUid, String? reviewerName) async {
    if (items.isEmpty) return;

    final inventory = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('inventory');
    final batch = FirebaseFirestore.instance.batch();

    for (final item in items) {
      final oldId = item['oldId']?.toString();
      if (oldId == null) continue;

      final name           = item['name']?.toString() ?? '';
      final type           = item['type']?.toString() ?? '';
      final formula        = (item['formula'] ?? '').toString().trim();
      final dose           = item['dose']?.toString() ?? '';
      final qty            = _safeInt(item['quantity']);
      final price          = _safeInt(item['price']);
      final expiry         = item['expiryDate']?.toString() ?? '';
      final classification = item['classification']?.toString() ?? '';
      final distilledWater = (item['distilledWater'] as num?)?.toInt();
      final drops          = (item['drops']          as num?)?.toInt();

      final newData = <String, dynamic>{
        'name':           name,
        'name_lower':     name.toLowerCase(),
        'formula':        formula,
        'formula_lower':  formula.toLowerCase(),
        'type':           type,
        'dose':           type == 'Nebulization' ? '' : dose,
        'quantity':       qty,
        'price':          price,
        'expiryDate':     expiry,
        'classification': classification,
        'approvedBy':     reviewerUid,
        'approvedByName': reviewerName ?? 'Supervisor',
        'updatedAt':      FieldValue.serverTimestamp(),
      };
      if (type == 'Nebulization') {
        newData['distilledWater'] = distilledWater ?? 0;
        newData['drops']          = drops ?? 0;
      }

      final newId = RequestUtils.generateDocId(
        name, type, type == 'Nebulization' ? '' : dose, expiry,
        distilledWater: distilledWater, drops: drops,
      );

      if (oldId == newId) {
        batch.update(inventory.doc(oldId), newData);
      } else {
        batch.delete(inventory.doc(oldId));
        
        // Broadcast delete to LAN so others remove the old ghost record immediately
        RealtimeManager().sendMessage({
          'event_type': RealtimeEvents.deleteStockItem,
          'id': oldId,
          'branchId': widget.branchId,
        });

        newData['addedAt'] = FieldValue.serverTimestamp();
        batch.set(inventory.doc(newId), newData);
      }

      // Add to log
      FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory_log')
          .add({
        'action': 'medicine_edited',
        'medicineName': name,
        'medicineType': type,
        'dose': dose,
        'oldId': oldId,
        'newId': newId,
        'performedBy': reviewerUid,
        'performedByName': reviewerName ?? 'Supervisor',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> _handleDeleteMedicine(
      List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;

    final inventory = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('inventory');
    final batch = FirebaseFirestore.instance.batch();

    for (final item in items) {
      final name = item['name']?.toString();
      final type = item['type']?.toString();
      if (name == null || type == null) continue;
      final dose           = item['dose']?.toString() ?? '';
      final expiry         = item['expiryDate']?.toString() ?? '';
      final distilledWater = (item['distilledWater'] as num?)?.toInt();
      final drops          = (item['drops']          as num?)?.toInt();

      final id = RequestUtils.generateDocId(
        name, type, dose, expiry,
        distilledWater: distilledWater, drops: drops,
      );
      batch.delete(inventory.doc(id));
    }
    await batch.commit();
  }

  Future<void> _handleChangePrescription(Map<String, dynamic> data,
      List<Map<String, dynamic>> items) async {
    final patientId = data['patientId']?.toString();
    if (patientId == null) return;

    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('patients')
        .doc(patientId)
        .update({'prescription': items});
  }

  Future<void> _showEditItemDialog(
      String requestId, int itemIndex, Map<String, dynamic> item) async {
    final reqRef  = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('edit_requests')
        .doc(requestId);
    final reqSnap = await reqRef.get();
    final status  = reqSnap.data()?['status']?.toString() ?? '';
    if (status != 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cannot edit — request is not pending'),
          backgroundColor: Colors.orange));
      return;
    }

    final nameCtrl  = TextEditingController(text: item['name']?.toString() ?? '');
    final qtyCtrl   = TextEditingController(
        text: (item['quantity'] ?? 0).toString());
    final priceCtrl = TextEditingController(
        text: (item['price'] ?? 0).toString());
    DateTime? pickedDate =
        _tryParseDateString(item['expiryDate']?.toString() ?? '');
    String expiryStr = pickedDate != null
        ? DateFormat('dd-MM-yyyy').format(pickedDate)
        : (item['expiryDate']?.toString() ?? '');

    await showDialog(
      context: context,
      builder: (context) =>
          StatefulBuilder(builder: (context, setState) {
        Future<void> pickDate() async {
          final d = await showDatePicker(
            context: context,
            initialDate: pickedDate ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (d != null) {
            setState(() {
              pickedDate  = d;
              expiryStr   = DateFormat('dd-MM-yyyy').format(d);
            });
          }
        }

        return AlertDialog(
          backgroundColor: Colors.teal.shade50,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Text('Edit Item',
              style: TextStyle(color: Colors.teal.shade800)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Name',
                  prefixIcon:
                      Icon(Icons.medication, color: Colors.teal.shade800),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  prefixIcon:
                      Icon(Icons.inventory, color: Colors.teal.shade800),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Price (PKR)',
                  prefixIcon: Icon(Icons.attach_money,
                      color: Colors.teal.shade800),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    readOnly: true,
                    controller:
                        TextEditingController(text: expiryStr),
                    decoration: InputDecoration(
                      labelText: 'Expiry',
                      prefixIcon: Icon(Icons.calendar_month,
                          color: Colors.teal.shade800),
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                ),
                IconButton(
                    onPressed: pickDate,
                    icon: Icon(Icons.calendar_today,
                        color: Colors.teal.shade800)),
              ]),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Cancel",
                    style: TextStyle(color: Colors.teal.shade800))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700),
              onPressed: () async {
                final newName  = nameCtrl.text.trim();
                final newQty   = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                final newPrice =
                    int.tryParse(priceCtrl.text.trim()) ?? 0;

                if (newName.isEmpty || newQty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid input')));
                  return;
                }

                final updatedItem = Map<String, dynamic>.from(item);
                updatedItem['name']       = newName;
                updatedItem['quantity']   = newQty;
                updatedItem['price']      = newPrice;
                updatedItem['expiryDate'] = expiryStr;

                await _editItemInRequestAsDraft(
                    requestId, itemIndex, updatedItem);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Item updated in draft')));
              },
              child: const Text("Save",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _editItemInRequestAsDraft(
      String requestId, int itemIndex, Map<String, dynamic> newItem) async {
    final ref = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('edit_requests')
        .doc(requestId);

    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data() as Map<String, dynamic>? ?? {};
    if (data['status'] != 'pending') return;

    final originalItems = _safeItemList(data['items']);
    var draftItems      = _safeItemList(data['draftItems']).isNotEmpty
        ? _safeItemList(data['draftItems'])
        : originalItems
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    if (itemIndex >= 0 && itemIndex < draftItems.length) {
      draftItems[itemIndex] = newItem;
    }

    await ref.update({
      'draftItems':   draftItems,
      'lastEditedAt': FieldValue.serverTimestamp(),
      'lastEditedBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }
}
