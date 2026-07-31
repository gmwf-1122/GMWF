// lib/widgets/multi_server_control_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/multi_server_service.dart';
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

  Future<void> _pingServer(String serverId, String ip, int port) async {
    setState(() => _isCheckingPing = true);
    final isReachable = await LanDiscovery.isReachable(ip, port);
    if (mounted) {
      setState(() {
        _pingResults[serverId] = isReachable;
        _isCheckingPing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isReachable
              ? '✅ Server ($ip:$port) is reachable & active on LAN!'
              : '❌ Server ($ip:$port) is unreachable on LAN.'),
          backgroundColor: isReachable ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _promoteServer(ServerNodeInfo server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Promote to Primary Server?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Make "${server.serverName}" (${server.ipAddress}) the primary LAN server node for this branch?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Promote Now', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MultiServerService().promoteToPrimary(widget.branchId, server.serverId, server.ipAddress);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ ${server.serverName} is now set as Primary Branch Server!'),
            backgroundColor: Colors.blueAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.branchId.isEmpty || widget.branchId == 'all') {
      return const Center(
        child: Text(
          'Please select a specific branch to view and manage branch servers.',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return StreamBuilder<List<ServerNodeInfo>>(
      stream: MultiServerService().getBranchServersStream(widget.branchId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
        }

        final servers = snapshot.data ?? [];

        if (servers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.dns_rounded, size: 48, color: Colors.white24),
                const SizedBox(height: 12),
                const Text(
                  'No registered server nodes found for this branch.',
                  style: TextStyle(color: Colors.white54, fontSize: 15),
                ),
                const SizedBox(height: 8),
                const Text(
                  'When GMWF launches on a server machine, it will automatically register here.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
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
                  color: const Color(0xFF1F2937).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.dns_rounded, size: 28, color: Colors.blueAccent),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Branch Multi-Server Cluster Management',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${servers.length} Registered Server Node(s) in Branch [${widget.branchId.toUpperCase()}]',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.8),
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

                  final roleColor = isPrimary ? Colors.purpleAccent : Colors.blueAccent;
                  final statusColor = srv.isOnline ? Colors.greenAccent : Colors.grey;

                  return Card(
                    color: const Color(0xFF1F2937).withValues(alpha: 0.85),
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: isPrimary ? Colors.purpleAccent.withValues(alpha: 0.5) : Colors.white10,
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
                                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: roleColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: roleColor.withValues(alpha: 0.4)),
                                          ),
                                          child: Text(
                                            srv.role.toUpperCase(),
                                            style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'LAN IP: ${srv.ipAddress}:${srv.port} • Version: ${srv.appVersion}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),

                              // Online Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.circle, size: 8, color: statusColor),
                                    const SizedBox(width: 6),
                                    Text(
                                      srv.isOnline ? 'ONLINE' : 'OFFLINE',
                                      style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: Colors.white10, height: 1),
                          const SizedBox(height: 14),

                          // Server Metrics Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _infoChip(Icons.devices_rounded, 'Clients Connected', '${srv.connectedClients} active'),
                              _infoChip(Icons.queue_rounded, 'Sync Queue Size', '${srv.syncQueueSize} items'),
                              _infoChip(
                                Icons.access_time_rounded,
                                'Last Heartbeat',
                                DateFormat('hh:mm:ss a').format(srv.lastHeartbeat),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Control Action Buttons
                          Row(
                            children: [
                              if (!isPrimary) ...[
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.bolt_rounded, size: 16),
                                  label: const Text('Set as Primary'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purpleAccent.withValues(alpha: 0.2),
                                    foregroundColor: Colors.purpleAccent,
                                    side: const BorderSide(color: Colors.purpleAccent),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _promoteServer(srv),
                                ),
                                const SizedBox(width: 10),
                              ],

                              OutlinedButton.icon(
                                icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                                label: Text(isPingSuccess == true ? 'Reachable' : (isPingSuccess == false ? 'Unreachable' : 'Ping Server')),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isPingSuccess == true ? Colors.greenAccent : (isPingSuccess == false ? Colors.redAccent : Colors.white70),
                                  side: BorderSide(color: isPingSuccess == true ? Colors.greenAccent : (isPingSuccess == false ? Colors.redAccent : Colors.white24)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _isCheckingPing ? null : () => _pingServer(srv.serverId, srv.ipAddress, srv.port),
                              ),

                              const Spacer(),

                              if (widget.onTriggerSync != null)
                                IconButton(
                                  icon: const Icon(Icons.sync_rounded, color: Colors.blueAccent),
                                  tooltip: 'Trigger Cloud Sync Now',
                                  onPressed: widget.onTriggerSync,
                                ),
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
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white38),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
