// lib/pages/admin_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOnline = true;

  // keep consistent role spelling
  final List<String> _roles = ["doctor", "receptionist", "dispensor"];

  // fixed branches
  final List<Map<String, String>> _fixedBranches = [
    {"branchId": "gujrat", "branchName": "Gujrat"},
    {"branchId": "sialkot", "branchName": "Sialkot"},
    {"branchId": "karachi1", "branchName": "Karachi-1"},
    {"branchId": "karachi2", "branchName": "Karachi-2"},
  ];

  @override
  void initState() {
    super.initState();
    _listenConnectivity();
  }

  void _listenConnectivity() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final hasConnection =
          results.isNotEmpty && results.first != ConnectivityResult.none;
      if (mounted) setState(() => _isOnline = hasConnection);
    });
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, "/login");
  }

  /// Create a new branch + first user
  void _createBranchWithUser() {
    final branchCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String? selectedRole;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Create Branch + First User"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: branchCtrl,
                decoration: const InputDecoration(labelText: "Branch Name"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: "User Email"),
              ),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password"),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedRole,
                hint: const Text("Select Role"),
                items: _roles
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r[0].toUpperCase() + r.substring(1)),
                        ))
                    .toList(),
                onChanged: (v) => selectedRole = v,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final branchName = branchCtrl.text.trim();
              final email = emailCtrl.text.trim().toLowerCase();
              final password = passwordCtrl.text.trim();

              if (branchName.isEmpty ||
                  email.isEmpty ||
                  password.isEmpty ||
                  selectedRole == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("⚠️ Fill all fields")),
                );
                return;
              }

              try {
                final branchId =
                    branchName.toLowerCase().replaceAll(RegExp(r"\s+"), "");

                // create branch doc
                await _firestore.collection("branches").doc(branchId).set({
                  "branchId": branchId,
                  "branchName": branchName,
                  "createdAt": FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                // create first user
                final userCred = await _auth.createUserWithEmailAndPassword(
                    email: email, password: password);
                final userId = userCred.user!.uid;

                final userData = {
                  "uid": userId,
                  "email": email,
                  "role": selectedRole,
                  "branchId": branchId,
                  "branchName": branchName,
                  "createdAt": FieldValue.serverTimestamp(),
                };

                if (selectedRole == "doctor") {
                  userData["doctorId"] =
                      "DOC-${DateTime.now().millisecondsSinceEpoch}";
                }

                await _firestore.collection("users").doc(userId).set(userData);

                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        "✅ Branch '$branchName' created with first user")));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("❌ Error: $e")),
                );
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  /// Create user inside a branch
  void _createUser(String branchId, String branchName) {
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String? selectedRole;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Add User to $branchName"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: "User Email")),
            TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password")),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedRole,
              hint: const Text("Select Role"),
              items: _roles
                  .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(r[0].toUpperCase() + r.substring(1)),
                      ))
                  .toList(),
              onChanged: (v) => selectedRole = v,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final email = emailCtrl.text.trim().toLowerCase();
              final password = passwordCtrl.text.trim();

              if (email.isEmpty || password.isEmpty || selectedRole == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("⚠️ Fill all fields")),
                );
                return;
              }

              try {
                final userCred = await _auth.createUserWithEmailAndPassword(
                    email: email, password: password);
                final userId = userCred.user!.uid;

                final userData = {
                  "uid": userId,
                  "email": email,
                  "role": selectedRole,
                  "branchId": branchId.toLowerCase(),
                  "branchName": branchName,
                  "createdAt": FieldValue.serverTimestamp(),
                };

                if (selectedRole == "doctor") {
                  userData["doctorId"] =
                      "DOC-${DateTime.now().millisecondsSinceEpoch}";
                }

                await _firestore.collection("users").doc(userId).set(userData);

                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("✅ User added to $branchName")));
              } catch (e) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text("❌ Error: $e")));
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  /// Edit user
  void _editUser(Map<String, dynamic> user) {
    final emailCtrl = TextEditingController(text: user["email"]);
    String selectedRole = user["role"] ?? "receptionist";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit User"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: "Email")),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedRole,
              items: _roles
                  .map((r) =>
                      DropdownMenuItem(value: r, child: Text(r.toUpperCase())))
                  .toList(),
              onChanged: (v) => selectedRole = v ?? selectedRole,
              decoration: const InputDecoration(labelText: "Role"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _firestore.collection("users").doc(user["uid"]).update({
                  "email": emailCtrl.text.trim().toLowerCase(),
                  "role": selectedRole,
                });
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✅ User updated")));
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("❌ Update error: $e")));
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  /// Delete user
  Future<void> _deleteUser(String uid) async {
    try {
      await _firestore.collection("users").doc(uid).delete();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("✅ User deleted")));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("❌ Error deleting user: $e")));
    }
  }

  /// Role-based user list
  Widget _buildRoleList(String branchId, String role) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection("users")
          .where("branchId", isEqualTo: branchId.toLowerCase())
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 40, child: Center(child: CircularProgressIndicator()));
        }

        final allUsers = snap.data?.docs ?? [];

        final users = allUsers.where((doc) {
          final user = doc.data() as Map<String, dynamic>;
          final r = (user["role"] ?? "").toString().toLowerCase();
          if (role == "dispensor") {
            return r == "dispensor" || r == "dispensar";
          }
          return r == role.toLowerCase();
        }).toList();

        if (users.isEmpty) {
          return Text("No $role(s)",
              style: const TextStyle(color: Colors.grey, fontSize: 12));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: users.map((doc) {
            final user = doc.data() as Map<String, dynamic>;
            user["uid"] = doc.id;
            return ListTile(
              dense: true,
              leading: const Icon(Icons.person, color: Colors.green),
              title: Text(user["email"] ?? ""),
              subtitle: Text(role == "doctor" && user.containsKey("doctorId")
                  ? "Role: ${user["role"]}, ID: ${user["doctorId"]}"
                  : "Role: ${user["role"]}"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _editUser(user)),
                  IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteUser(user["uid"])),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Download receipts
  Future<void> _downloadReceipts(String branchId, String branchName) async {
    try {
      final snap = await _firestore
          .collection("receipts")
          .where("branchId", isEqualTo: branchId.toLowerCase())
          .get();

      if (snap.docs.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("⚠️ No receipts for $branchName")));
        return;
      }

      final receipts = snap.docs.map((d) {
        final m = d.data();
        m["id"] = d.id;
        return m;
      }).toList();

      final jsonStr = const JsonEncoder.withIndent("  ").convert(receipts);
      final dir = await getApplicationDocumentsDirectory();
      final safeName = branchName.replaceAll(RegExp(r'[^\w\-]'), '_');
      final file = File("${dir.path}/${safeName}_receipts.json");
      await file.writeAsString(jsonStr);

      debugPrint("📑 Receipts saved at: ${file.path}");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "✅ Receipts exported for $branchName\nSaved at: ${file.path}",
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("❌ Error exporting: $e")));
    }
  }

  /// Build branch list (fixed + Firestore)
  Future<List<Map<String, String>>> _buildFinalBranchList() async {
    final result = List<Map<String, String>>.from(_fixedBranches);
    try {
      final snap = await _firestore.collection("branches").get();
      for (var doc in snap.docs) {
        final d = doc.data();
        final id = (d['branchId'] ?? doc.id).toString().toLowerCase();
        final name = d['branchName']?.toString() ?? id;
        if (!result.any((b) => b['branchId'] == id)) {
          result.add({"branchId": id, "branchName": name});
        }
      }
    } catch (_) {}
    return result;
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: const Text("Admin Dashboard",
            style: TextStyle(color: Colors.white)),
        actions: [
          TextButton.icon(
            onPressed: _createBranchWithUser,
            icon: const Icon(Icons.add_business, color: Colors.white),
            label:
                const Text("Add Branch", style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, String>>>(
        future: _buildFinalBranchList(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final branches = snap.data ?? _fixedBranches;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: branches.map((branch) {
              final branchId = branch["branchId"]!;
              final branchName = branch["branchName"]!;
              return Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(branchName,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green)),
                            Row(children: [
                              IconButton(
                                  icon: const Icon(Icons.person_add,
                                      color: Colors.green),
                                  onPressed: () =>
                                      _createUser(branchId, branchName)),
                              IconButton(
                                  icon: const Icon(Icons.download,
                                      color: Colors.blue),
                                  onPressed: () =>
                                      _downloadReceipts(branchId, branchName)),
                            ]),
                          ],
                        ),
                        const Divider(),
                        const Text("Doctors",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        _buildRoleList(branchId, "doctor"),
                        const SizedBox(height: 8),
                        const Text("Receptionists",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        _buildRoleList(branchId, "receptionist"),
                        const SizedBox(height: 8),
                        const Text("Dispensars",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        _buildRoleList(branchId, "dispensor"),
                      ]),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
