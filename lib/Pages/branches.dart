// lib/pages/branches.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Branches extends StatefulWidget {
  const Branches({super.key});

  @override
  State<Branches> createState() => _BranchesState();
}

class _BranchesState extends State<Branches> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isAdmin = false;

  final List<String> _roles = ["doctor", "receptionist", "dispensor"];

  final List<Map<String, String>> _fixedBranches = [
    {"branchId": "gujrat", "branchName": "Gujrat"},
    {"branchId": "sialkot", "branchName": "Sialkot"},
    {"branchId": "karachi1", "branchName": "Karachi-1"},
    {"branchId": "karachi2", "branchName": "Karachi-2"},
  ];

  late Future<List<Map<String, String>>> _branchesFuture;

  @override
  void initState() {
    super.initState();
    _branchesFuture = _buildFinalBranchList();
    _checkIfAdmin();
  }

  Future<void> _checkIfAdmin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _firestore.collection("users").doc(uid).get();
      if (snap.exists) {
        final data = snap.data()!;
        if (mounted) {
          setState(() {
            _isAdmin = (data["role"] == "admin");
          });
        }
      }
    } catch (e) {
      debugPrint("⚠️ Error checking admin: $e");
    }
  }

  // ✅ Add new user inside a branch
  void _createUser(String branchId, String branchName) {
    if (!_isAdmin) return;
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String? selectedRole;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setStateDialog) {
        return AlertDialog(
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
                onChanged: (v) => setStateDialog(() => selectedRole = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final email = emailCtrl.text.trim().toLowerCase();
                final password = passwordCtrl.text.trim();

                if (email.isEmpty || password.isEmpty || selectedRole == null) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("⚠️ Fill all fields")),
                    );
                  }
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
                    "branchId": branchId.toLowerCase().trim(),
                    "branchName": branchName,
                    "createdAt": FieldValue.serverTimestamp(),
                  };

                  if (selectedRole == "doctor") {
                    userData["doctorId"] =
                        "DOC-${DateTime.now().millisecondsSinceEpoch}";
                  }

                  await _firestore
                      .collection("users")
                      .doc(userId)
                      .set(userData);

                  if (!mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("✅ User added to $branchName")));
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text("❌ Error: $e")));
                  }
                }
              },
              child: const Text("Create"),
            ),
          ],
        );
      }),
    );
  }

  // ✅ Delete user
  Future<void> _confirmDeleteUser(String uid, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text("Are you sure you want to delete user:\n$email ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firestore.collection("users").doc(uid).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("✅ User $email deleted")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Error deleting user: $e")),
          );
        }
      }
    }
  }

  // ✅ Role name variations
  List<String> _roleVariants(String role) {
    switch (role.toLowerCase()) {
      case "doctor":
        return ["doctor", "Doctor"];
      case "receptionist":
        return ["receptionist", "Receptionist", "reception"];
      case "dispensor":
      case "dispensar":
        return ["dispensor", "Dispensor", "dispensar", "Dispensar"];
      default:
        return [role, role[0].toUpperCase() + role.substring(1)];
    }
  }

  // ✅ Role-based list of users
  Widget _buildRoleList(String branchId, String role) {
    final normalizedBranchId = branchId.toLowerCase().trim();
    final variants = _roleVariants(role);

    Stream<QuerySnapshot> stream;
    if (variants.length == 1) {
      stream = _firestore
          .collection("users")
          .where("branchId", isEqualTo: normalizedBranchId)
          .where("role", isEqualTo: variants.first)
          .snapshots();
    } else {
      stream = _firestore
          .collection("users")
          .where("branchId", isEqualTo: normalizedBranchId)
          .where("role", whereIn: variants)
          .snapshots();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return Text("⚠️ Error: ${snap.error}");
        }

        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Text("No $role(s)",
              style: const TextStyle(color: Colors.grey, fontSize: 12));
        }

        final docs = snap.data!.docs;

        return Column(
          children: docs.map((doc) {
            final user = Map<String, dynamic>.from(doc.data() as Map);
            user["uid"] = doc.id;
            return ListTile(
              dense: true,
              leading: const Icon(Icons.person, color: Colors.green),
              title: Text(user["email"] ?? ""),
              subtitle: Text(role == "doctor" && user.containsKey("doctorId")
                  ? "Role: ${user["role"]}, ID: ${user["doctorId"]}"
                  : "Role: ${user["role"]}"),
              trailing: _isAdmin
                  ? IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () =>
                          _confirmDeleteUser(doc.id, user["email"] ?? ""),
                    )
                  : null,
            );
          }).toList(),
        );
      },
    );
  }

  // ✅ Merge Firestore + Fixed branches
  Future<List<Map<String, String>>> _buildFinalBranchList() async {
    try {
      final snap = await _firestore.collection("branches").get();
      final existing =
          snap.docs.map((d) => Map<String, String>.from(d.data())).toList();

      final merged = {
        ...{for (var b in _fixedBranches) b["branchId"]!: b}
      };
      for (var b in existing) {
        merged[b["branchId"]!] = b;
      }

      return merged.values.toList();
    } catch (e) {
      debugPrint("⚠️ Error building branch list: $e");
      return _fixedBranches;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Branches"),
        backgroundColor: Colors.green,
      ),
      body: FutureBuilder<List<Map<String, String>>>(
        future: _branchesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return const Center(child: Text("⚠️ No branches found"));
          }

          final branches = snapshot.data!;
          return ListView(
            children: branches.map((branch) {
              final branchId = branch["branchId"] ?? "";
              final branchName = branch["branchName"] ?? branchId;

              return Card(
                margin: const EdgeInsets.all(10),
                child: ExpansionTile(
                  title: Text(branchName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    if (_isAdmin)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12.0),
                          child: ElevatedButton.icon(
                            onPressed: () => _createUser(branchId, branchName),
                            icon: const Icon(Icons.person_add),
                            label: const Text("Add User"),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
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
                    const Text("Dispensors",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    _buildRoleList(branchId, "dispensor"),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
