import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _selectedRole;
  String? _selectedBranch;
  bool _loading = false;
  bool _obscurePassword = true;

  final Map<String, String> _branches = {
    "gujrat": "Gujrat",
    "sialkot": "Sialkot",
    "karachi1": "Karachi-1",
    "karachi2": "Karachi-2",
  };

  final List<String> _roles = ["doctor", "receptionist", "dispensar"];

  Future<void> _register() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        _selectedBranch == null ||
        _selectedRole == null) {
      _showSnack("⚠️ Fill all fields and select Branch/Role");
      return;
    }

    setState(() => _loading = true);

    try {
      final userCred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = userCred.user?.uid;
      if (uid == null) throw Exception("❌ Failed to create user");

      final normalizedRole = _selectedRole!.toLowerCase().trim();
      final normalizedBranch = _selectedBranch!.toLowerCase().trim();

      final userData = {
        "uid": uid,
        "email": email,
        "role": normalizedRole,
        "branchId": normalizedBranch,
        "branchName": _branches[normalizedBranch],
        "createdAt": FieldValue.serverTimestamp(),
      };

      if (normalizedRole == "doctor") {
        userData["doctorId"] = uid;
      }

      await _firestore.collection("users").doc(uid).set(userData);

      await _firestore.collection("branches").doc(normalizedBranch).set({
        "name": _branches[normalizedBranch],
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showSnack("✅ Registered successfully");
      if (mounted) Navigator.pushReplacementNamed(context, "/login");
    } on FirebaseAuthException catch (e) {
      _showSnack("❌ ${e.message}");
    } catch (e) {
      _showSnack("❌ Registration failed: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Register", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 500,
            child: Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 15,
                    spreadRadius: 2,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Register",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _selectedBranch,
                    decoration: const InputDecoration(
                      labelText: "Branch",
                      prefixIcon: Icon(Icons.account_tree),
                    ),
                    hint: const Text("Select Branch"),
                    items: _branches.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedBranch = v),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: "Role",
                      prefixIcon: Icon(Icons.badge),
                    ),
                    hint: const Text("Select Role"),
                    items: _roles
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(
                                '${r[0].toUpperCase()}${r.substring(1)}',
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedRole = v),
                  ),
                  const SizedBox(height: 20),
                  _loading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: const Text("Register"),
                        ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context,
                      "/login",
                    ),
                    child: const Text("Already have an account? Login"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
