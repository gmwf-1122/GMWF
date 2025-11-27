import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'inventory.dart';
import 'warehouse.dart';
import 'assets.dart';

class Branches extends StatefulWidget {
  const Branches({super.key});

  @override
  State<Branches> createState() => _BranchesState();
}

class _BranchesState extends State<Branches> {
  final List<String> defaultBranches = const [
    "Gujrat",
    "Sialkot",
    "Karachi-1",
    "Karachi-2",
  ];

  final Map<String, IconData> roleIcons = const {
    "supervisor": Icons.supervisor_account,
    "receptionist": Icons.person_add,
    "doctor": Icons.medical_services,
    "dispenser": Icons.local_pharmacy,
  };

  final List<String> roleOrder = const [
    "supervisor",
    "receptionist",
    "doctor",
    "dispenser",
  ];

  String? selectedBranch;
  String selectedPeriod = 'today';

  @override
  void initState() {
    super.initState();
    selectedBranch = defaultBranches.first;
  }

  Future<void> _deleteUser(BuildContext context, String userId, String email,
      String branchId) async {
    final codeController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete User"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Enter admin code to delete \"$email\":"),
            const SizedBox(height: 10),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: "Admin Code",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (codeController.text == "admin1122") {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text("Invalid admin code")),
                );
              }
            },
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

  Future<void> _editUser(BuildContext context, String userId, String branchId,
      Map<String, dynamic> currentData) async {
    final usernameController =
        TextEditingController(text: currentData['username']);
    final phoneController = TextEditingController(text: currentData['phone']);
    String? selectedRole = currentData['role'];

    final List<String> roles = [
      "supervisor",
      "receptionist",
      "doctor",
      "dispenser"
    ];

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: const Text("Edit User"),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: "Username",
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (val) =>
                          val == null || val.isEmpty ? "Enter username" : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Phone Number",
                        prefixIcon: Icon(Icons.phone),
                      ),
                      maxLength: 11,
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return "Enter phone number";
                        } else if (val.length != 11) {
                          return "Phone number must be 11 digits";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      hint: const Text("Select Role"),
                      items: roles
                          .map((role) => DropdownMenuItem(
                                value: role,
                                child: Text(
                                    role[0].toUpperCase() + role.substring(1)),
                              ))
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

                  final updatedData = {
                    "username": usernameController.text.trim(),
                    "phone": phoneController.text.trim(),
                    "role": selectedRole,
                  };

                  try {
                    await FirebaseFirestore.instance
                        .collection("users")
                        .doc(userId)
                        .update(updatedData);

                    await FirebaseFirestore.instance
                        .collection("branches")
                        .doc(branchId)
                        .collection("users")
                        .doc(userId)
                        .update(updatedData);

                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("User updated successfully"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Error updating user: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text(
                  "Save Changes",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _addBranchDialog(BuildContext context) async {
    final branchController = TextEditingController();
    final usernameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String? selectedRole;

    final List<String> roles = [
      "Supervisor",
      "Doctor",
      "Receptionist",
      "Dispenser"
    ];

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
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: "Username",
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (val) =>
                          val == null || val.isEmpty ? "Enter username" : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: "Email",
                        prefixIcon: Icon(Icons.email),
                      ),
                      validator: (val) =>
                          val == null || val.isEmpty ? "Enter email" : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Phone Number",
                        prefixIcon: Icon(Icons.phone),
                      ),
                      maxLength: 11,
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return "Enter phone number";
                        } else if (val.length != 11) {
                          return "Phone number must be 11 digits";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
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
                      value: selectedRole,
                      hint: const Text("Select Role"),
                      items: roles
                          .map((role) => DropdownMenuItem(
                                value: role,
                                child: Text(role),
                              ))
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
                  final username = usernameController.text.trim();
                  final email = emailController.text.trim();
                  final phone = phoneController.text.trim();
                  final password = passwordController.text.trim();
                  final role = selectedRole!.toLowerCase();

                  try {
                    // ✅ Check if branch already exists
                    final existing = await FirebaseFirestore.instance
                        .collection("branches")
                        .doc(branchId)
                        .get();

                    if (existing.exists) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text("⚠️ Branch \"$branchName\" already exists!"),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    // ✅ Create user in Firebase Auth
                    final userCred = await FirebaseAuth.instance
                        .createUserWithEmailAndPassword(
                      email: email,
                      password: password,
                    );

                    final userId = userCred.user!.uid;

                    final userData = {
                      "username": username,
                      "email": email,
                      "phone": phone,
                      "role": role,
                      "branchId": branchId,
                      "branchName": branchName,
                      "createdAt": FieldValue.serverTimestamp(),
                    };

                    // ✅ Add user globally
                    await FirebaseFirestore.instance
                        .collection("users")
                        .doc(userId)
                        .set(userData);

                    // ✅ Create branch
                    await FirebaseFirestore.instance
                        .collection("branches")
                        .doc(branchId)
                        .set({"name": branchName}, SetOptions(merge: true));

                    // ✅ Add user under branch
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
                            "✅ Branch \"$branchName\" created successfully"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("❌ Error: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text(
                  "Create Branch",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        });
      },
    );
  }

  Future<int> _getTotalPatients(
      String branchId, String userId, String role) async {
    if (role != 'receptionist') return 0;
    try {
      final query = FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('patients')
          .where('registeredBy', isEqualTo: userId);

      final aggregate = await query.count().get();
      return aggregate.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getTodayTokens(
      String branchId, String userId, String role) async {
    if (role != 'receptionist') return 0;
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final query = FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('patients')
          .where('registeredBy', isEqualTo: userId)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay));

      final aggregate = await query.count().get();
      return aggregate.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getTotalPrescriptions(String branchId, String period) async {
    try {
      final dates = _getDatesForPeriod(period);
      int total = 0;
      for (String date in dates) {
        // Assuming prescriptions are stored daily or something, but since structure is /prescriptions/{cnic}/prescriptions/{id}
        // Use collectionGroup with time filter
        // Assume 'createdAt' field in prescriptions docs
        final start = Timestamp.fromDate(DateFormat('ddMMyy').parse(date));
        final end = start.toDate().add(const Duration(days: 1));
        final query = FirebaseFirestore.instance
            .collectionGroup('prescriptions')
            .where('branchId',
                isEqualTo: branchId) // Assume branchId field if needed
            .where('createdAt', isGreaterThanOrEqualTo: start)
            .where('createdAt', isLessThan: Timestamp.fromDate(end));

        final aggregate = await query.count().get();
        total += aggregate.count ?? 0;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getTotalDispenses(String branchId, String period) async {
    try {
      final dates = _getDatesForPeriod(period);
      int total = 0;
      for (String date in dates) {
        final query = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('dispensary')
            .doc(date)
            .collection(date);

        final aggregate = await query.count().get();
        total += aggregate.count ?? 0;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getInventoryRequests(
      String branchId, String userId, String role) async {
    if (role != 'dispenser') return 0;
    try {
      final query = FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('inventory_requests')
          .where('requestedBy', isEqualTo: userId);

      final aggregate = await query.count().get();
      return aggregate.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getTokenCount(String branchId, String period) async {
    List<String> dates = _getDatesForPeriod(period);
    int total = 0;
    for (String date in dates) {
      try {
        final zakatQuery = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('serials')
            .doc(date)
            .collection('zakat');
        final zakatCount = await zakatQuery.count().get();
        total += zakatCount.count ?? 0;

        final nonZakatQuery = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('serials')
            .doc(date)
            .collection('non-zakat');
        final nonZakatCount = await nonZakatQuery.count().get();
        total += nonZakatCount.count ?? 0;
      } catch (e) {
        // Ignore errors for missing dates
      }
    }
    return total;
  }

  List<String> _getDatesForPeriod(String period) {
    final now = DateTime.now();
    List<String> dates = [];
    final format = DateFormat('ddMMyy');

    if (period == 'today') {
      dates.add(format.format(now));
    } else if (period == 'week') {
      for (int i = 0; i < 7; i++) {
        dates.add(format.format(now.subtract(Duration(days: i))));
      }
    } else if (period == 'month') {
      final firstDay = DateTime(now.year, now.month, 1);
      final lastDay = DateTime(now.year, now.month + 1, 0);
      for (DateTime d = firstDay;
          !d.isAfter(lastDay);
          d = d.add(const Duration(days: 1))) {
        dates.add(format.format(d));
      }
    }
    return dates;
  }

  Widget _buildBranchSidebar(List<String> branches) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.2,
      color: Colors.green.shade700,
      child: ListView.builder(
        itemCount: branches.length,
        itemBuilder: (context, index) {
          final branch = branches[index];
          final isSelected = branch == selectedBranch;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: isSelected
                    ? Colors.white.withOpacity(0.9)
                    : Colors.green.shade600,
                foregroundColor:
                    isSelected ? Colors.green.shade900 : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                setState(() {
                  selectedBranch = branch;
                  selectedPeriod = 'today';
                });
              },
              child: Row(
                children: [
                  const Icon(Icons.apartment, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      branch,
                      style: const TextStyle(fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBranchDetails(Map<String, List<Map<String, dynamic>>> branches) {
    if (selectedBranch == null) {
      return const Expanded(
        child: Center(child: Text("Select a branch")),
      );
    }

    final branchUsers = branches[selectedBranch] ?? [];
    final branchId =
        selectedBranch!.toLowerCase().replaceAll(" ", "").replaceAll("-", "");

    return Expanded(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Users Section
              if (branchUsers.isNotEmpty)
                ...roleOrder.map((role) {
                  final roleUsers = branchUsers
                      .where((u) => (u['role'] ?? "").toLowerCase() == role)
                      .toList();
                  if (roleUsers.isEmpty) return const SizedBox.shrink();

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(roleIcons[role], color: Colors.green),
                              const SizedBox(width: 8),
                              Text(
                                role[0].toUpperCase() + role.substring(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          ...roleUsers.map((user) {
                            return FutureBuilder<List<int>>(
                              future: Future.wait([
                                _getTotalPatients(branchId, user['id'], role),
                                _getTodayTokens(branchId, user['id'], role),
                                _getInventoryRequests(
                                    branchId, user['id'], role),
                              ]),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const ListTile(
                                    leading: CircularProgressIndicator(),
                                  );
                                }

                                final totalPatients = snapshot.data?[0] ?? 0;
                                final todayTokens = snapshot.data?[1] ?? 0;
                                final inventoryRequests =
                                    snapshot.data?[2] ?? 0;

                                String subtitleText = "";
                                if (role == 'receptionist') {
                                  subtitleText =
                                      "Total Patients: $totalPatients\nTokens Today: $todayTokens";
                                } else if (role == 'doctor') {
                                  subtitleText = "";
                                } else if (role == 'dispenser') {
                                  subtitleText =
                                      "Inventory Requests: $inventoryRequests";
                                } else if (role == 'supervisor') {
                                  subtitleText = "Overseeing branch activities";
                                }

                                return ListTile(
                                  leading: const Icon(Icons.person,
                                      color: Colors.amber),
                                  title: Text(user['email'] ?? "Unknown Email"),
                                  subtitle: Text(subtitleText),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit,
                                            color: Colors.blue),
                                        onPressed: () => _editUser(
                                          context,
                                          user['id'],
                                          branchId,
                                          user,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () => _deleteUser(
                                          context,
                                          user['id'],
                                          user['email'],
                                          branchId,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                }),
              if (branchUsers.isEmpty)
                const Center(
                  child: Text(
                    "No users found",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),

              // Tokens Section
              Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.token, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            "Tokens",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        children: [
                          const Text("Filter: "),
                          DropdownButton<String>(
                            value: selectedPeriod,
                            items: ['today', 'week', 'month']
                                .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(
                                        p[0].toUpperCase() + p.substring(1))))
                                .toList(),
                            onChanged: (val) =>
                                setState(() => selectedPeriod = val!),
                          ),
                        ],
                      ),
                      FutureBuilder<int>(
                        future: _getTokenCount(branchId, selectedPeriod),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const CircularProgressIndicator();
                          }
                          final count = snapshot.data ?? 0;
                          return Text("Total Tokens: $count");
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Prescriptions Section
              Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.medical_information, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            "Prescriptions",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        children: [
                          const Text("Filter: "),
                          DropdownButton<String>(
                            value: selectedPeriod,
                            items: ['today', 'week', 'month']
                                .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(
                                        p[0].toUpperCase() + p.substring(1))))
                                .toList(),
                            onChanged: (val) =>
                                setState(() => selectedPeriod = val!),
                          ),
                        ],
                      ),
                      FutureBuilder<int>(
                        future:
                            _getTotalPrescriptions(branchId, selectedPeriod),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const CircularProgressIndicator();
                          }
                          final count = snapshot.data ?? 0;
                          return Text("Total Prescriptions: $count");
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Dispensary Section
              Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.local_pharmacy, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            "Dispensary Data",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        children: [
                          const Text("Filter: "),
                          DropdownButton<String>(
                            value: selectedPeriod,
                            items: ['today', 'week', 'month']
                                .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(
                                        p[0].toUpperCase() + p.substring(1))))
                                .toList(),
                            onChanged: (val) =>
                                setState(() => selectedPeriod = val!),
                          ),
                        ],
                      ),
                      FutureBuilder<int>(
                        future: _getTotalDispenses(branchId, selectedPeriod),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const CircularProgressIndicator();
                          }
                          final count = snapshot.data ?? 0;
                          return Text("Total Dispensary Entries: $count");
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Inventory, Warehouse, and Assets Buttons
              LayoutBuilder(
                builder: (context, constraints) {
                  bool isWide = constraints.maxWidth > 600;
                  return isWide
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _buildResourceButtons(branchId),
                        )
                      : Column(
                          children: _buildResourceButtons(branchId),
                        );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildResourceButtons(String branchId) {
    return [
      ElevatedButton.icon(
        icon: const Icon(Icons.inventory),
        label: const Text("View Inventory"),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => InventoryPage(branchId: branchId),
            ),
          );
        },
      ),
      const SizedBox(width: 8, height: 8),
      ElevatedButton.icon(
        icon: const Icon(Icons.warehouse),
        label: const Text("View Warehouse"),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => WarehouseScreen(
                branchId: branchId,
              ),
            ),
          );
        },
      ),
      const SizedBox(width: 8, height: 8),
      ElevatedButton.icon(
        icon: const Icon(Icons.account_balance_wallet),
        label: const Text("View Assets"),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => AssetsPage(branchId: branchId, isAdmin: false),
            ),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collectionGroup('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs;
          final Map<String, List<Map<String, dynamic>>> branches = {};

          for (var user in users) {
            final data = user.data() as Map<String, dynamic>;
            final branchId = data['branchId'] ?? "unknown";
            final branchName = data['branchName'] ?? branchId.toUpperCase();
            data['id'] = user.id;

            if ((data['role'] ?? "").toLowerCase() == "admin") continue;
            branches.putIfAbsent(branchName, () => []);
            branches[branchName]!.add(data);
          }

          for (var branch in defaultBranches) {
            branches.putIfAbsent(branch, () => []);
          }

          final allBranches = branches.keys.toList()..sort();

          return Row(
            children: [
              _buildBranchSidebar(allBranches),
              _buildBranchDetails(branches),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green,
        onPressed: () => _addBranchDialog(context),
        child: const Icon(Icons.add_business, color: Colors.white),
      ),
    );
  }
}
