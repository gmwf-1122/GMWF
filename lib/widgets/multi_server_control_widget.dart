import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:gmwf/design/components/app_toast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/multi_server_service.dart';
import '../services/local_storage_service.dart';
import '../services/finance_local_storage.dart';
import '../realtime/lan_discovery.dart';

class MultiServerControlWidget extends StatefulWidget {
  final String branchId;
  final VoidCallback? onTriggerSync;

  const MultiServerControlWidget({
    super.key,
    required this.branchId,
    this.onTriggerSync,
  });

  @override
  State<MultiServerControlWidget> createState() => _MultiServerControlWidgetState();
}

class _MultiServerControlWidgetState extends State<MultiServerControlWidget> {
  final Map<String, bool?> _pingResults = {};
  bool _isCheckingPing = false;
  String _selectedBranch = 'all';

  @override
  void initState() {
    super.initState();
    _selectedBranch = widget.branchId.isEmpty ? 'all' : widget.branchId;
  }

  @override
  void didUpdateWidget(covariant MultiServerControlWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId && widget.branchId.isNotEmpty) {
      setState(() {
        _selectedBranch = widget.branchId;
      });
    }
  }

  Future<void> _pingServer(String serverId, String ip, int port) async {
    setState(() => _isCheckingPing = true);
    final isReachable = await LanDiscovery.isReachable(ip, port);
    if (mounted) {
      setState(() {
        _pingResults[serverId] = isReachable;
        _isCheckingPing = false;
      });

      AppToast.showSnackBar(context, 
        SnackBar(
          content: Text(isReachable
              ? '✅ Server ($ip:$port) is reachable & active on LAN!'
              : '❌ Server ($ip:$port) is unreachable on LAN.'),
          backgroundColor: isReachable ? SoftPalette.green400 : SoftPalette.red400,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _promoteServer(ServerNodeInfo server) async {
    final targetBranch = server.branchId.isNotEmpty ? server.branchId : _selectedBranch;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SoftPalette.slate800,
        title: const Text('Promote to Primary Server?', style: TextStyle(color: SoftPalette.gray50)),
        content: Text(
          'Make "${server.serverName}" (${server.ipAddress}) the primary LAN server node for branch [${targetBranch.toUpperCase()}]?',
          style: const TextStyle(color: SoftPalette.gray50A70),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: SoftPalette.gray50A54)),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SoftPalette.blue400),
            child: const Text('Promote Now', style: TextStyle(color: SoftPalette.gray50)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MultiServerService().promoteToPrimary(targetBranch, server.serverId, server.ipAddress);
      if (mounted) {
        AppToast.showSnackBar(context, 
          SnackBar(
            content: Text('⚡ ${server.serverName} is now set as Primary Branch Server!'),
            backgroundColor: SoftPalette.blue400,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allBranches = FinanceLocalStorage.getAllBranches([])
        .where((b) => (b['id']?.toString() ?? '') != 'all')
        .toList();

    final branches = [
      {'id': 'all', 'name': 'All Branches (Cluster)'},
      ...allBranches,
    ];

    return Column(
      children: [
        // Branch Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: SoftPalette.slate900,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: branches.map((b) {
                final bId = b['id'] ?? '';
                final isSelected = _selectedBranch == bId;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(
                      b['name'] ?? bId,
                      style: TextStyle(
                        color: isSelected ? SoftPalette.gray50 : SoftPalette.gray50A70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: SoftPalette.blue400.withValues(alpha: 0.35),
                    backgroundColor: SoftPalette.slate800,
                    checkmarkColor: SoftPalette.blue400,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? SoftPalette.blue400 : SoftPalette.gray50A12,
                      ),
                    ),
                    onSelected: (_) => setState(() => _selectedBranch = bId),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        Expanded(
          child: StreamBuilder<List<ServerNodeInfo>>(
            stream: MultiServerService().getBranchServersStream(_selectedBranch),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: SoftPalette.blue400));
              }

              final servers = snapshot.data ?? [];

              if (servers.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.dns_rounded, size: 48, color: SoftPalette.gray50A24),
                      const SizedBox(height: 12),
                      Text(
                        _selectedBranch == 'all'
                            ? 'No registered server nodes found across any branch.'
                            : 'No registered server nodes found for branch [${_selectedBranch.toUpperCase()}].',
                        style: const TextStyle(color: SoftPalette.gray50A54, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'When GMWF launches on a server machine, it will automatically register here.',
                        style: TextStyle(color: SoftPalette.gray50A38, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Summary Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: SoftPalette.slate800.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: SoftPalette.blue400.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: SoftPalette.blue400.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.dns_rounded, size: 28, color: SoftPalette.blue400),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Multi-Server Cluster Management',
                                  style: TextStyle(color: SoftPalette.gray50, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${servers.length} Registered Server Node(s) [${_selectedBranch.toUpperCase()}]',
                                  style: const TextStyle(color: SoftPalette.gray50A54, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Server Cards Grid / List
                    const Text(
                      'ACTIVE BRANCH SERVERS & NODE CLUSTER',
                      style: TextStyle(color: SoftPalette.gray50, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 12),

                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: servers.length,
                      itemBuilder: (ctx, idx) {
                        final srv = servers[idx];
                        final isPrimary = srv.role == 'primary';
                        final isPingSuccess = _pingResults[srv.serverId];

                        final roleColor = isPrimary ? SoftPalette.purple400 : SoftPalette.blue400;
                        final statusColor = srv.isOnline ? SoftPalette.emerald200 : SoftPalette.gray350;

                        return Card(
                          color: SoftPalette.slate800.withValues(alpha: 0.85),
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: isPrimary ? SoftPalette.purple400.withValues(alpha: 0.5) : SoftPalette.gray50A10,
                              width: isPrimary ? 1.5 : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.dns_rounded, color: roleColor, size: 24),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                srv.serverName,
                                                style: const TextStyle(color: SoftPalette.gray50, fontSize: 17, fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(width: 10),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: roleColor.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: roleColor.withValues(alpha: 0.4)),
                                                ),
                                                child: Text(
                                                  srv.role.toUpperCase(),
                                                  style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: SoftPalette.gray50A10,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  LocalStorageService.getBranchName(srv.branchId),
                                                  style: const TextStyle(color: SoftPalette.gray50A70, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${srv.ipAddress}:${srv.port}',
                                            style: const TextStyle(color: SoftPalette.gray50A54, fontSize: 13, fontFamily: 'monospace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            srv.isOnline ? 'Online' : 'Offline',
                                            style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Metrics Chips
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    _buildMetricChip(Icons.people_alt_rounded, '${srv.connectedClients} Connected Clients', SoftPalette.blue400),
                                    _buildMetricChip(Icons.sync_rounded, '${srv.syncQueueSize} Queued for Sync', SoftPalette.yellow200),
                                    _buildMetricChip(Icons.schedule_rounded, 'Heartbeat: ${DateFormat('hh:mm:ss a').format(srv.lastHeartbeat)}', SoftPalette.gray50A54),
                                    _buildMetricChip(Icons.verified_rounded, 'App Version: ${srv.appVersion}', SoftPalette.gray50A54),
                                  ],
                                ),

                                const SizedBox(height: 16),
                                const Divider(color: SoftPalette.gray50A10),
                                const SizedBox(height: 12),

                                // Actions Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _isCheckingPing
                                          ? null
                                          : () => _pingServer(srv.serverId, srv.ipAddress, srv.port),
                                      icon: const Icon(Icons.network_ping_rounded, size: 16),
                                      label: Text(
                                        isPingSuccess == null
                                            ? 'LAN Ping'
                                            : (isPingSuccess ? 'Reachable' : 'Unreachable'),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: isPingSuccess == null
                                            ? SoftPalette.gray50A70
                                            : (isPingSuccess ? SoftPalette.emerald200 : SoftPalette.red400),
                                        side: BorderSide(
                                          color: isPingSuccess == null
                                              ? SoftPalette.gray50A24
                                              : (isPingSuccess ? SoftPalette.emerald200 : SoftPalette.red400),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!isPrimary)
                                      ElevatedButton.icon(
                                        onPressed: () => _promoteServer(srv),
                                        icon: const Icon(Icons.upgrade_rounded, size: 16),
                                        label: const Text('Set as Primary'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: SoftPalette.blue400,
                                          foregroundColor: SoftPalette.gray50,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        ),
                                      ),
                                    if (widget.onTriggerSync != null) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.sync_rounded, color: SoftPalette.blue400),
                                        tooltip: 'Trigger Cloud Sync Now',
                                        onPressed: widget.onTriggerSync,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMetricChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
