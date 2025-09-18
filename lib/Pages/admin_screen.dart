// lib/pages/admin_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class AdminScreen extends StatefulWidget {
  final String? userEmail;

  const AdminScreen({super.key, this.userEmail});

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

  /// ✅ Fetch all branches (always shown) and their users grouped by role
  Future<Map<String, Map<String, List<Map<String, dynamic>>>>>
      _getBranchesAndUsers() async {
    final result = <String, Map<String, List<Map<String, dynamic>>>>{};

    if (await _checkOnline()) {
      // Fetch all branches
      final branchSnap = await _firestore.collection("branches").get();
      final branchMap = {
        for (var doc in branchSnap.docs) doc.id: doc["name"] ?? doc.id
      };

      // Init result with empty role maps
      for (var branchName in branchMap.values) {
        result[branchName] = {
          for (var role in _roles) role: [] // ensure every role exists
        };
      }

      // Fetch all users
      final usersSnap = await _firestore.collection("users").get();
      for (var doc in usersSnap.docs) {
        final data = doc.data();
        final branchId = data["branchId"] ?? "unknown";
        final branchName = branchMap[branchId] ?? branchId;
        final role = (data["role"] ?? "Unknown").toString().toLowerCase();

        final user = {
          "uid": doc.id,
          "email": data["email"] ?? "",
          "role": role,
          "branchId": branchId,
          "branchName": branchName,
        };

        // Group into branch → role → users
        result.putIfAbsent(branchName, () => {for (var r in _roles) r: []});
        result[branchName]!.putIfAbsent(role, () => []);
        result[branchName]![role]!.add(user);
      }
    }
    return result;
  }

  Future<void> _deleteUser(String uid) async {
    try {
      if (await _checkOnline()) {
        await _firestore.collection("users").doc(uid).delete();
      }
      await _userBox?.delete(uid);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ User deleted successfully")),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error deleting user: $e")),
      );
    }
  }

  Future<void> _updateUser(String uid, Map<String, dynamic> newData) async {
    try {
      if (await _checkOnline()) {
        await _firestore.collection("users").doc(uid).update(newData);
      }

      final user = _userBox?.get(uid);
      if (user != null) {
        final updated = Map<String, dynamic>.from(user)..addAll(newData);
        await _userBox?.put(uid, updated);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ User updated")),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error updating user: $e")),
      );
    }
  }

  void _editUser(Map<String, dynamic> user) {
    final emailCtrl = TextEditingController(text: user["email"]);
    final roleCtrl = TextEditingController(text: user["role"]);

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
            TextField(
                controller: roleCtrl,
                decoration: const InputDecoration(labelText: "Role")),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateUser(user["uid"], {
                "email": emailCtrl.text.trim(),
                "role": roleCtrl.text.trim(),
              });
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await _auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _goToRegister() {
    Navigator.pushNamed(context, '/register');
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Admin Dashboard ${widget.userEmail ?? ""}"),
        backgroundColor: Colors.green,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: FutureBuilder<Map<String, Map<String, List<Map<String, dynamic>>>>>(
        // branch → role → users
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
            children: branches.entries.map((branchEntry) {
              final branchName = branchEntry.key;
              final roleGroups = branchEntry.value;

              return Card(
                margin: const EdgeInsets.all(12),
                child: ExpansionTile(
                  title: Text(
                    branchName,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  children: roleGroups.entries.map((roleEntry) {
                    final role = roleEntry.key;
                    final users = roleEntry.value;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            role[0].toUpperCase() + role.substring(1),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.green),
                          ),
                        ),
                        users.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.only(left: 16, bottom: 8),
                                child: Text(
                                  "No users yet",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : Column(
                                children: users.map((user) {
                                  return ListTile(
                                    leading: const Icon(Icons.person,
                                        color: Colors.green),
                                    title: Text(user["email"] ?? "Unknown"),
                                    subtitle: Text("Role: ${user["role"]}"),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.blue),
                                          onPressed: () => _editUser(user),
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
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green,
        onPressed: _goToRegister,
        tooltip: "Add New User",
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
