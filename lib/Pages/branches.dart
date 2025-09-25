import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Branches extends StatelessWidget {
  const Branches({super.key});

  final List<String> defaultBranches = const [
    "Gujrat",
    "Sialkot",
    "Karachi-1",
    "Karachi-2",
  ];

  final Map<String, IconData> roleIcons = const {
    "receptionist": Icons.person_add,
    "doctor": Icons.medical_services,
    "dispenser": Icons.local_pharmacy,
  };

  final List<String> roleOrder = const [
    "receptionist",
    "doctor",
    "dispenser",
  ];

  Future<void> _deleteUser(BuildContext context, String userId, String email,
      String branchId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete User"),
        content: Text("Are you sure you want to delete \"$email\"?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // ✅ Delete from global users
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .delete();

        // ✅ Delete from branch subcollection
        if (branchId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(branchId)
              .collection('users')
              .doc(userId)
              .delete();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User deleted successfully")),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error deleting user: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF8FF),
      body: Center(
        child: Container(
          width: 900,
          height: 600,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Manage Branches",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final users = snapshot.data!.docs;

                    final Map<String, List<Map<String, dynamic>>> branches = {};
                    for (var user in users) {
                      final data = user.data() as Map<String, dynamic>;
                      final branchId = data['branchId'] ?? "unknown";
                      final branchName =
                          data['branchName'] ?? branchId.toUpperCase();
                      data['id'] = user.id;

                      if ((data['role'] ?? "").toLowerCase() == "admin") {
                        continue;
                      }

                      branches.putIfAbsent(branchName, () => []);
                      branches[branchName]!.add(data);
                    }

                    // Ensure default branches always appear
                    for (var branch in defaultBranches) {
                      branches.putIfAbsent(branch, () => []);
                    }

                    return ListView.separated(
                      itemCount: branches.keys.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final branchName = branches.keys.elementAt(index);
                        final branchUsers = branches[branchName]!;

                        return Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ExpansionTile(
                            leading: const Icon(Icons.apartment,
                                color: Colors.green),
                            title: Text(
                              branchName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            trailing: null, // ❌ no branch delete
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: roleOrder.map((role) {
                                    final roleUsers = branchUsers
                                        .where((u) =>
                                            (u['role'] ?? "").toLowerCase() ==
                                            role)
                                        .toList();

                                    if (roleUsers.isEmpty) return Container();

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(roleIcons[role],
                                                color: Colors.black),
                                            const SizedBox(width: 6),
                                            Text(
                                              role[0].toUpperCase() +
                                                  role.substring(1),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        ...roleUsers.map((user) {
                                          return ListTile(
                                            leading: const Icon(Icons.person,
                                                color: Colors.amber),
                                            title: Text(user['email'] ??
                                                "Unknown Email"),
                                            trailing: IconButton(
                                              icon: const Icon(Icons.delete,
                                                  color: Colors.red),
                                              onPressed: () => _deleteUser(
                                                  context,
                                                  user['id'],
                                                  user['email'],
                                                  user['branchId'] ?? ""),
                                            ),
                                          );
                                        }),
                                        const Divider(),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
