import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .delete();

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

  Future<void> _addBranchDialog(BuildContext context) async {
    final branchController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String? selectedRole;
    final List<String> roles = ["Doctor", "Receptionist", "Dispenser"];

    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: const Text("Create New Branch"),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: branchController,
                      decoration: const InputDecoration(
                        labelText: "Branch Name",
                        prefixIcon: Icon(Icons.apartment),
                      ),
                      validator: (val) => val == null || val.isEmpty
                          ? "Enter branch name"
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: "User Email",
                        prefixIcon: Icon(Icons.email),
                      ),
                      validator: (val) =>
                          val == null || val.isEmpty ? "Enter email" : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(
                              () => obscurePassword = !obscurePassword),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return "Enter password";
                        }
                        if (val.length < 6) {
                          return "Password must be at least 6 chars";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      hint: const Text("Select Role"),
                      items: roles
                          .map((role) =>
                              DropdownMenuItem(value: role, child: Text(role)))
                          .toList(),
                      onChanged: (val) => setState(() => selectedRole = val),
                      validator: (val) => val == null ? "Select role" : null,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  final branchName = branchController.text.trim();
                  final branchId = branchName.toLowerCase().replaceAll(" ", "");
                  final email = emailController.text.trim();
                  final password = passwordController.text.trim();
                  final role = selectedRole!;

                  try {
                    // ✅ Create user in Firebase Auth
                    final userCred = await FirebaseAuth.instance
                        .createUserWithEmailAndPassword(
                      email: email,
                      password: password,
                    );

                    final userId = userCred.user!.uid;

                    final userData = {
                      "email": email,
                      "role": role.toLowerCase(),
                      "branchId": branchId,
                      "branchName": branchName,
                    };

                    // ✅ Save in global users
                    await FirebaseFirestore.instance
                        .collection("users")
                        .doc(userId)
                        .set(userData);

                    // ✅ Save under branch subcollection
                    await FirebaseFirestore.instance
                        .collection("branches")
                        .doc(branchId)
                        .set({"name": branchName}, SetOptions(merge: true));

                    await FirebaseFirestore.instance
                        .collection("branches")
                        .doc(branchId)
                        .collection("users")
                        .doc(userId)
                        .set(userData);

                    Navigator.pop(ctx);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              "✅ Branch $branchName created successfully")),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error: $e")),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text("Create Branch",
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF8FF),
      appBar: AppBar(
        title: const Text("Manage Branches"),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business, color: Colors.white),
            onPressed: () => _addBranchDialog(context),
          ),
        ],
      ),
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
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collectionGroup('users')
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

                // Ensure default branches are always visible
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
                        leading:
                            const Icon(Icons.apartment, color: Colors.green),
                        title: Text(
                          branchName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        trailing: null,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: roleOrder.map((role) {
                                final roleUsers = branchUsers
                                    .where((u) =>
                                        (u['role'] ?? "").toLowerCase() == role)
                                    .toList();

                                if (roleUsers.isEmpty) return Container();

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        title: Text(
                                            user['email'] ?? "Unknown Email"),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.red),
                                          onPressed: () => _deleteUser(
                                            context,
                                            user['id'],
                                            user['email'],
                                            user['branchId'] ?? "",
                                          ),
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
            )),
      ),
    );
  }
}
