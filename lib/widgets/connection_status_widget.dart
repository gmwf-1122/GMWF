// lib/widgets/connection_status_widget.dart
// Drop-in AppBar widget showing live connection state for all client screens.

import 'package:flutter/material.dart';
import '../realtime/connection_manager.dart';

class ConnectionStatusBadge extends StatelessWidget {
  final ConnectionStatus status;
  final VoidCallback? onRetry;

  const ConnectionStatusBadge({
    super.key,
    required this.status,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: !status.isConnected ? onRetry : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: _bgColor.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIndicator(),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (status.ip != null)
                  Text(
                    '${status.ip}:${status.port}',
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
              ],
            ),
            if (!status.isConnected && onRetry != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.refresh, color: Colors.white, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIndicator() {
    if (status.isSearching || status.isConnecting) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      );
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: status.isConnected
            ? [BoxShadow(color: Colors.white.withOpacity(0.8), blurRadius: 4)]
            : null,
      ),
    );
  }

  Color get _bgColor {
    switch (status.state) {
      case LanConnectionState.connected:
        return const Color(0xFF2E7D32); // dark green
      case LanConnectionState.connecting:
        return const Color(0xFF1565C0); // dark blue
      case LanConnectionState.searching:
        return const Color(0xFFE65100); // deep orange
      case LanConnectionState.disconnected:
        return const Color(0xFFC62828); // dark red
    }
  }

  String get _label {
    switch (status.state) {
      case LanConnectionState.connected:
        return 'Connected';
      case LanConnectionState.connecting:
        return 'Connecting...';
      case LanConnectionState.searching:
        return 'Searching...';
      case LanConnectionState.disconnected:
        return 'Tap to Retry';
    }
  }
}