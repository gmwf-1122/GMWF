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

  /// 🔄 Updated to new signature
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOnline = true;

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

  /// ✅ Updated listener
  void _listenConnectivity() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final hasConnection =
          results.isNotEmpty && results.first != ConnectivityResult.none;
      if (mounted) setState(() => _isOnline = hasConnection);
    });
  }

  /// ✅ Updated checker
  Future<bool> _checkOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.isNotEmpty && results.first != ConnectivityResult.none;
  }

  /// ========== BRANCH MANAGEMENT ==========

  Future<void> _addBranch() async {
    final branchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add Branch"),
        content: TextField(
          controller: branchCtrl,
          decoration: const InputDecoration(labelText: "Branch Name"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final branchName = branchCtrl.text.trim();
              if (branchName.isEmpty) return;

              if (await _checkOnline()) {
                final branchRef =
                    _firestore.collection("branches").doc(branchName);

                await branchRef.set({
                  "name": branchName,
                  "createdAt": FieldValue.serverTimestamp(),
                });

                // Init subcollections with placeholder
                for (final sub in ["inventory", "patients", "users"]) {
                  await branchRef.collection(sub).doc("init").set({
                    "note": "$sub initialized",
                  });
                }
              }

              if (mounted) {
                Navigator.pop(ctx);
                setState(() {});
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBranch(String branchName) async {
    if (await _checkOnline()) {
      final branchRef = _firestore.collection("branches").doc(branchName);

      // Delete subcollections
      for (final sub in ["inventory", "patients", "users"]) {
        final snap = await branchRef.collection(sub).get();
        for (final doc in snap.docs) {
          await branchRef.collection(sub).doc(doc.id).delete();
          if (sub == "users") await _userBox?.delete(doc.id);
        }
      }

      // Delete branch doc
      await branchRef.delete();
    }

    if (mounted) setState(() {});
  }

  void _confirmDeleteBranch(String branchName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text("Delete branch '$branchName' and all its data?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteBranch(branchName);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  /// ========== USER MANAGEMENT ==========

  Future<void> _deleteUser(String branchId, String uid) async {
    try {
      if (await _checkOnline()) {
        await _firestore
            .collection("branches")
            .doc(branchId)
            .collection("users")
            .doc(uid)
            .delete();
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

  Future<void> _updateUser(
      String branchId, String uid, Map<String, dynamic> newData) async {
    try {
      if (await _checkOnline()) {
        await _firestore
            .collection("branches")
            .doc(branchId)
            .collection("users")
            .doc(uid)
            .update(newData);
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

  void _editUser(String branchId, Map<String, dynamic> user) {
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
              _updateUser(branchId, user["uid"], {
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

  /// ✅ Fetch all branches and users
  Future<Map<String, Map<String, List<Map<String, dynamic>>>>>
      _getBranchesAndUsers() async {
    final result = <String, Map<String, List<Map<String, dynamic>>>>{};

    if (await _checkOnline()) {
      final branchesSnap = await _firestore.collection("branches").get();

      for (var branchDoc in branchesSnap.docs) {
        final branchName = branchDoc.id;
        final usersSnap = await branchDoc.reference.collection("users").get();

        for (var doc in usersSnap.docs) {
          final data = doc.data();
          if (data.containsKey("note")) continue; // skip init docs

          final role = data["role"] ?? "Unknown";
          final user = {
            "uid": doc.id,
            "email": data["email"] ?? "",
            "role": role,
            "branch": branchName,
          };

          result.putIfAbsent(branchName, () => {});
          result[branchName]!.putIfAbsent(role, () => []);
          result[branchName]![role]!.add(user);
        }
      }
    }
    return result;
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
          IconButton(
              icon: const Icon(Icons.add_business), onPressed: _addBranch),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: FutureBuilder<Map<String, Map<String, List<Map<String, dynamic>>>>>(
        future: _getBranchesAndUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No users found"));
          }

          final branches = snapshot.data!;
          return ListView(
            children: branches.entries.map((branchEntry) {
              final branchName = branchEntry.key;
              final roleGroups = branchEntry.value;

              return Card(
                margin: const EdgeInsets.all(12),
                child: ExpansionTile(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(branchName,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDeleteBranch(branchName),
                        tooltip: "Delete Branch",
                      ),
                    ],
                  ),
                  children: roleGroups.entries.map((roleEntry) {
                    final role = roleEntry.key;
                    final users = roleEntry.value;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(role,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green)),
                        ),
                        ...users.map((user) {
                          return ListTile(
                            leading:
                                const Icon(Icons.person, color: Colors.green),
                            title: Text(user["email"] ?? "Unknown"),
                            subtitle: Text("Role: ${user["role"]}"),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.blue),
                                  onPressed: () => _editUser(branchName, user),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () =>
                                      _deleteUser(branchName, user["uid"]),
                                ),
                              ],
                            ),
                          );
                        }),
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
