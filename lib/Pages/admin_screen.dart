// lib/pages/admin_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  Box? _userBox;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOnline = true;

  final List<String> _roles = ["doctor", "receptionist", "dispensor"];

  final Map<String, String> _defaultBranches = {
    "gujrat": "Gujrat",
    "sialkot": "Sialkot",
    "karachi1": "Karachi-1",
    "karachi2": "Karachi-2",
  };

  @override
  void initState() {
    super.initState();
    _openLocalBox();
    _listenConnectivity();
  }

  Future<void> _openLocalBox() async {
    try {
      _userBox = await Hive.openBox("usersBox");
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("❌ Failed to open Hive box: $e");
    }
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

  Future<bool> _checkOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.isNotEmpty && results.first != ConnectivityResult.none;
  }

  /// ✅ Fetch all branches and users grouped by role
  Future<Map<String, Map<String, List<Map<String, dynamic>>>>>
      _getBranchesAndUsers() async {
    final result = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (var branchName in _defaultBranches.values) {
      result[branchName] = {for (var role in _roles) role: []};
    }

    if (await _checkOnline()) {
      final usersSnap = await _firestore.collection("users").get();

      for (var doc in usersSnap.docs) {
        final data = doc.data();
        final branchId =
            data["branchId"]?.toString().toLowerCase() ?? "unknown";
        final branchName = _defaultBranches[branchId] ??
            data["branchName"]?.toString() ??
            branchId;
        final role = (data["role"] ?? "unknown").toString().toLowerCase();

        final user = {
          "uid": doc.id,
          "email": data["email"] ?? "",
          "role": role,
          "branchId": branchId,
          "branchName": branchName,
        };

        result.putIfAbsent(branchName, () => {for (var r in _roles) r: []});
        result[branchName]![role] ??= [];
        result[branchName]![role]!.add(user);
      }
    }

    return result;
  }

  /// ✅ Add new branch with first user
  void _createBranch() {
    final branchCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String? selectedRole;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Create Branch"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: branchCtrl,
              decoration: const InputDecoration(labelText: "Branch Name"),
            ),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: "User Email"),
            ),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
            DropdownButtonFormField<String>(
              initialValue: selectedRole,
              hint: const Text("Select Role"),
              items: _roles
                  .map((r) =>
                      DropdownMenuItem(value: r, child: Text(r.toUpperCase())))
                  .toList(),
              onChanged: (v) => selectedRole = v,
              decoration: const InputDecoration(labelText: "Role"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final branchName = branchCtrl.text.trim();
              final email = emailCtrl.text.trim();
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
                // 1️⃣ Normalize branchId
                final branchId = _defaultBranches.entries
                    .firstWhere(
                      (e) => e.value.toLowerCase() == branchName.toLowerCase(),
                      orElse: () =>
                          MapEntry(branchName.toLowerCase(), branchName),
                    )
                    .key;

                // 2️⃣ Create user in FirebaseAuth
                final userCred = await _auth.createUserWithEmailAndPassword(
                  email: email,
                  password: password,
                );

                // 3️⃣ Save user in Firestore
                await _firestore
                    .collection("users")
                    .doc(userCred.user!.uid)
                    .set({
                  "email": email,
                  "role": selectedRole,
                  "branchId": branchId,
                  "branchName": branchName,
                  "createdAt": FieldValue.serverTimestamp(),
                });

                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("✅ Branch '$branchName' created")),
                );
                setState(() {});
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

  /// ✅ Edit user info
  void _editUser(Map<String, dynamic> user) {
    final emailCtrl = TextEditingController(text: user["email"]);
    String selectedRole = user["role"];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit User"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            DropdownButtonFormField<String>(
              initialValue: selectedRole,
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _firestore.collection("users").doc(user["uid"]).update({
                "email": emailCtrl.text.trim(),
                "role": selectedRole,
              });
              if (mounted) setState(() {});
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  /// ✅ Delete user (Firestore only – admin cannot delete FirebaseAuth directly)
  Future<void> _deleteUser(String uid) async {
    try {
      await _firestore.collection("users").doc(uid).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ User deleted")),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error deleting user: $e")),
        );
      }
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, "/login");
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
            onPressed: _createBranch,
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
      body: FutureBuilder<Map<String, Map<String, List<Map<String, dynamic>>>>>(
        future: _getBranchesAndUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No branches found"));
          }

          final branches = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: branches.entries.map((branchEntry) {
              final branchName = branchEntry.key;
              final roleGroups = branchEntry.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Text(
                      branchName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: roleGroups.entries.map((roleEntry) {
                          final role = roleEntry.key;
                          final users = roleEntry.value;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                role[0].toUpperCase() + role.substring(1),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              users.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Text("No users yet",
                                          style: TextStyle(color: Colors.grey)),
                                    )
                                  : Column(
                                      children: users.map((user) {
                                        return ListTile(
                                          leading: const Icon(Icons.person,
                                              color: Colors.green),
                                          title: Text(user["email"] ?? ""),
                                          subtitle:
                                              Text("Role: ${user["role"]}"),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit,
                                                    color: Colors.blue),
                                                onPressed: () =>
                                                    _editUser(user),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete,
                                                    color: Colors.red),
                                                onPressed: () =>
                                                    _deleteUser(user["uid"]),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green,
        onPressed: () => Navigator.pushNamed(context, "/register"),
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }
}
