import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/donation_models.dart';
import 'donations_shared.dart';

class GlobalAuditTrailScreen extends StatefulWidget {
  final UserRole role;
  const GlobalAuditTrailScreen({super.key, required this.role});

  @override
  State<GlobalAuditTrailScreen> createState() => _GlobalAuditTrailScreenState();
}

class _GlobalAuditTrailScreenState extends State<GlobalAuditTrailScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _filterAction = 'all';
  Future<QuerySnapshot>? _logsFuture;
  List<QueryDocumentSnapshot> _cachedDocs = []; // PERSISTENCE CACHE

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    try {
      Query query = _db.collection('global_audit_logs').orderBy('timestamp', descending: true).limit(50);
      if (_filterAction != 'all') {
        query = query.where('action', isEqualTo: _filterAction);
      }
      setState(() {
        _logsFuture = query.get();
      });
    } catch (e) {
      debugPrint('Error loading audit logs: $e');
      setState(() {
        _logsFuture = Future.error(e);
      });
    }
  }

  void _updateFilter(String action) {
    if (_filterAction == action) return;
    setState(() {
      _filterAction = action;
    });
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    final isAuthorized = widget.role.isChairman || widget.role.isHqManager;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: !isAuthorized 
        ? _buildUnauthorizedView()
        : Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
            ),
            child: Column(
              children: [
                _buildHeader(context),
                _buildFilterBar(),
                Expanded(child: _buildLogsList()),
              ],
            ),
          ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 48, 24, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: Color(0x0A000000), blurRadius: 20, offset: Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE65100).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.history_toggle_off_rounded, color: Color(0xFFE65100), size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Global Audit Trail', 
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    const Text('AUTHORIZED SYSTEM ACCESS', 
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 1)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildUnauthorizedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_person_rounded, size: 80, color: Colors.red.withValues(alpha: 0.1)),
          const SizedBox(height: 24),
          const Text('Access Restricted', 
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
          const SizedBox(height: 8),
          const Text('Only Chairman and HQ Manager can view global audit logs.',
            style: TextStyle(color: Color(0xFF64748B)), textAlign: TextAlign.center),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterTab(
              label: 'ALL ACTIVITY',
              isActive: _filterAction == 'all',
              onTap: () => _updateFilter('all'),
            ),
            const SizedBox(width: 12),
            _FilterTab(
              label: 'CREATED',
              isActive: _filterAction == 'create',
              onTap: () => _updateFilter('create'),
            ),
            const SizedBox(width: 12),
            _FilterTab(
              label: 'EDITED',
              isActive: _filterAction == 'update',
              onTap: () => _updateFilter('update'),
            ),
            const SizedBox(width: 12),
            _FilterTab(
              label: 'DELETED',
              isActive: _filterAction == 'delete',
              onTap: () => _updateFilter('delete'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsList() {
    if (_logsFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<QuerySnapshot>(
      future: _logsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (_cachedDocs.isNotEmpty) {
            return Column(
              children: [
                _buildErrorBanner(snapshot.error.toString()),
                Expanded(child: _buildDocsListView(_cachedDocs)),
              ],
            );
          }
          return _buildErrorState(snapshot.error.toString());
        }

        if (snapshot.connectionState == ConnectionState.waiting && _cachedDocs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? _cachedDocs;
        if (snapshot.hasData) {
          _cachedDocs = snapshot.data!.docs;
        }

        if (docs.isEmpty) return _buildEmptyState();

        return _buildDocsListView(docs);
      },
    );
  }

  Widget _buildDocsListView(List<QueryDocumentSnapshot> docs) {
    return ListView.builder(
      padding: const EdgeInsets.all(32),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final entry = AuditLogEntry.fromMap(docs[index].data() as Map<String, dynamic>);
        return _AuditLogCard(entry: entry);
      },
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
        const SizedBox(width: 12),
        const Expanded(child: Text('Live updates paused. Showing cached data.', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold))),
      ]),
    );
  }

  Widget _buildErrorState(String error) {
    final bool isIndexError = error.contains('index') || error.contains('failed-precondition');
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
              const SizedBox(height: 20),
              const Text('Database Index Required', 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const SizedBox(height: 12),
              Text(
                isIndexError 
                  ? 'This view requires a simple index for "global_audit_logs".\n\n1. Go to Firebase Console\n2. Firestore -> Indexes\n3. Add Index\n4. Collection: global_audit_logs\n5. Field: timestamp (Descending)'
                  : 'Error: $error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
              ),
              const SizedBox(height: 24),
              const Text('Data will appear here automatically once the index is ready.', 
                style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_turned_in_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('No activity logs found', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterTab({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF6366F1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)),
          boxShadow: isActive ? [BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isActive ? Colors.white : const Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  final AuditLogEntry entry;
  const _AuditLogCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(entry.timestamp) ?? DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(dt);
    final dateStr = DateFormat('MMM dd, yyyy').format(dt);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0).withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildActionBadge(),
                Text('$dateStr • $timeStr', 
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(color: Color(0xFF0F172A), shape: BoxShape.circle),
                      child: Center(child: Text(entry.username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.username, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A), fontSize: 15)),
                          Row(
                            children: [
                              Text('User ID: ${entry.userId}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              if (entry.branchName.isNotEmpty) ...[
                                const Text(' • ', style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
                                Text(entry.branchName.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6366F1), letterSpacing: 0.5)),
                              ]
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildDescription(),
                if (entry.reason != null && entry.reason!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildReasonPanel(),
                ],
                if (entry.action == 'update' && entry.oldData != null && entry.newData != null) ...[
                  const SizedBox(height: 20),
                  _buildDiffView(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBadge() {
    Color color;
    String label;
    IconData icon;

    switch (entry.action) {
      case 'create':
        color = const Color(0xFF10B981);
        label = 'CREATED';
        icon = Icons.add_circle_outline_rounded;
        break;
      case 'update':
        color = const Color(0xFF6366F1);
        label = 'EDITED';
        icon = Icons.edit_note_rounded;
        break;
      case 'delete':
        color = const Color(0xFFEF4444);
        label = 'DELETED';
        icon = Icons.delete_outline_rounded;
        break;
      default:
        color = const Color(0xFF64748B);
        label = 'ACTIVITY';
        icon = Icons.info_outline_rounded;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildDescription() {
    final donor = entry.oldData?['donorName'] ?? entry.newData?['donorName'] ?? 'Unknown';
    final amount = entry.oldData?['amount'] ?? entry.newData?['amount'] ?? 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.5),
          children: [
            const TextSpan(text: 'Donation record for '),
            TextSpan(text: donor, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
            const TextSpan(text: ' with value of '),
            TextSpan(text: 'PKR ${NumberFormat('#,###').format(amount)}', 
              style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A), fontFamily: 'DMMono')),
            TextSpan(text: ' was ${entry.action == 'create' ? 'created' : entry.action == 'update' ? 'modified' : 'permanently deleted'}.'),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFF59E0B).withValues(alpha: 0.15), const Color(0xFFF59E0B).withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFB45309)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(entry.reason!, 
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309), fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffView() {
    final oldData = entry.oldData!;
    final newData = entry.newData!;
    final keys = ['amount', 'donorName', 'date', 'status', 'categoryId', 'notes'];
    
    final List<Widget> changes = [];
    for (var k in keys) {
      if (oldData[k]?.toString() != newData[k]?.toString()) {
        changes.add(_buildDiffRow(k, oldData[k]?.toString() ?? 'N/A', newData[k]?.toString() ?? 'N/A'));
      }
    }

    if (changes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MODIFICATIONS', 
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 1.2)),
        const SizedBox(height: 12),
        ...changes,
      ],
    );
  }

  Widget _buildDiffRow(String field, String oldVal, String newVal) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 80, 
            child: Text(field.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(oldVal, style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444), decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 8),
                const Icon(Icons.east_rounded, size: 12, color: Color(0xFFCBD5E1)),
                const SizedBox(width: 8),
                Text(newVal, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
