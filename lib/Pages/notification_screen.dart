// lib/pages/notification_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationScreen extends StatefulWidget {
  final String branchId;
  final String userId;
  final String role; // admin, supervisor, doctor, receptionist, dispenser

  const NotificationScreen({
    super.key,
    required this.branchId,
    required this.userId,
    required this.role,
  });

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final TextEditingController _messageController = TextEditingController();
  String? _selectedReceiverId;
  String? _selectedReceiverRole;

  /// Stream of notifications visible to this user
  Stream<QuerySnapshot> get _notificationsStream {
    final coll = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('notifications')
        .orderBy('timestamp', descending: true);

    if (widget.role == 'admin') return coll.snapshots();

    if (widget.role == 'supervisor') {
      // Supervisor sees only notifications sent to them
      return coll.where('receiverId', isEqualTo: widget.userId).snapshots();
    }

    // Other users (doc/rec/disp) see notifications sent by supervisor/admin to them
    return coll.where('receiverId', isEqualTo: widget.userId).snapshots();
  }

  /// Send notification to a specific user or role
  Future<void> _sendNotification() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    if (widget.role == 'supervisor' && _selectedReceiverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Select a user to send notification")));
      return;
    }

    if (widget.role == 'admin' &&
        _selectedReceiverRole == null &&
        _selectedReceiverId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Select a user or role")));
      return;
    }

    String receiverId = _selectedReceiverId ?? 'all';
    String receiverRole = _selectedReceiverRole ?? 'all';

    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('notifications')
        .add({
      'senderId': widget.userId,
      'senderRole': widget.role,
      'receiverId': receiverId,
      'receiverRole': receiverRole,
      'message': message,
      'seen': false,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'pending',
    });

    _messageController.clear();
    _selectedReceiverId = null;
    _selectedReceiverRole = null;
    Navigator.pop(context);
  }

  /// Show dialog to send notification
  void _showSendDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Send Notification"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.role == 'supervisor' || widget.role == 'admin')
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('branches')
                    .doc(widget.branchId)
                    .collection('users')
                    .snapshots(),
                builder: (context, snapshot) {
                  final users = snapshot.data?.docs ?? [];
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedReceiverId,
                    hint: const Text("Select User"),
                    items: users
                        .map((doc) => DropdownMenuItem(
                              value: doc.id,
                              child: Text(doc['name'] ?? doc['email'] ?? ''),
                            ))
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedReceiverId = val),
                  );
                },
              ),
            if (widget.role == 'admin')
              DropdownButtonFormField<String>(
                initialValue: _selectedReceiverRole,
                hint: const Text("Select Role (Optional)"),
                items: ['doctor', 'receptionist', 'dispenser', 'supervisor']
                    .map((role) => DropdownMenuItem(
                          value: role,
                          child: Text(role),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => _selectedReceiverRole = val),
              ),
            TextFormField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: "Message",
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: _sendNotification,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Send", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  /// Mark notification as seen
  Future<void> _markAsSeen(DocumentSnapshot doc) async {
    if (!(doc['seen'] ?? false)) {
      await doc.reference.update({'seen': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: Colors.green.shade800,
      ),
      floatingActionButton: (widget.role != 'doctor' &&
              widget.role != 'receptionist' &&
              widget.role != 'dispenser')
          ? FloatingActionButton(
              onPressed: _showSendDialog,
              backgroundColor: Colors.green,
              child: const Icon(Icons.send),
            )
          : null,
      body: StreamBuilder<QuerySnapshot>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final notifications = snapshot.data?.docs ?? [];
          if (notifications.isEmpty) {
            return const Center(child: Text("No notifications"));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final data = doc.data() as Map<String, dynamic>;
              final seen = data['seen'] ?? false;
              final timestamp =
                  (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
              final senderRole = data['senderRole'] ?? '';
              final message = data['message'] ?? '';

              return Card(
                color: seen ? Colors.white : Colors.green.shade50,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(
                    senderRole == 'admin'
                        ? Icons.admin_panel_settings
                        : senderRole == 'supervisor'
                            ? Icons.supervised_user_circle
                            : Icons.person,
                    color: Colors.green.shade800,
                  ),
                  title: Text(message),
                  subtitle: Text(
                      "${data['senderRole']} - ${timestamp.toLocal().toString().split('.')[0]}"),
                  trailing: seen
                      ? const Icon(Icons.done, color: Colors.green)
                      : const Icon(Icons.circle, color: Colors.red, size: 12),
                  onTap: () => _markAsSeen(doc),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
