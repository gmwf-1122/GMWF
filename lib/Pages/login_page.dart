import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  final Set<String> _adminEmails = {"admin@gmd.com"};

  Future<void> _login() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack("⚠️ Fill all fields");
      return;
    }

    setState(() => _loading = true);

    try {
      final userCred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCred.user!;
      print("✅ Firebase Auth successful for UID: ${user.uid}");

      // Admin shortcut
      if (_adminEmails.contains(email) || user.uid == "admin_uid") {
        Navigator.pushReplacementNamed(context, "/admin");
        return;
      }

      // Fetch user from Firestore
      final userDoc = await _firestore.collection("users").doc(user.uid).get();

      if (!userDoc.exists) {
        _showSnack("❌ User data not found in Firestore");
        await _auth.signOut();
        return;
      }

      final userData = userDoc.data();
      if (userData == null) {
        _showSnack("❌ User data is empty");
        await _auth.signOut();
        return;
      }

      final role = userData["role"]?.toString().toLowerCase();
      final branchId = userData["branchId"]?.toString() ?? "";
      final branchName = userData["branchName"]?.toString() ?? branchId;

      if (role == null) {
        _showSnack("❌ Role not assigned");
        await _auth.signOut();
        return;
      }

      // Navigate based on role
      if (role == "doctor") {
        Navigator.pushReplacementNamed(
          context,
          "/doctor",
          arguments: {"branchId": branchId, "branchName": branchName},
        );
      } else if (role == "receptionist") {
        Navigator.pushReplacementNamed(
          context,
          "/receptionist",
          arguments: {"branchId": branchId, "branchName": branchName},
        );
      } else if (role == "dispensor") {
        Navigator.pushReplacementNamed(
          context,
          "/dispensor",
          arguments: {"branchId": branchId, "branchName": branchName},
        );
      } else if (role == "admin") {
        Navigator.pushReplacementNamed(context, "/admin");
      } else {
        _showSnack("❌ Unknown role: $role");
      }
    } on FirebaseAuthException catch (e) {
      _showSnack("❌ Wrong credentials: ${e.message}");
    } catch (e) {
      _showSnack("❌ Login failed: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green, Colors.lightGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SizedBox(
            width: 900,
            child: Row(
              children: [
                // Logo on left
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Image.asset(
                      "assets/logo/gmwf.png",
                      height: 240,
                    ),
                  ),
                ),
                // Login form on right
                Expanded(
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
                            offset: Offset(0, 8)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Login",
                            style: TextStyle(
                                fontSize: 28, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                              labelText: "Email",
                              prefixIcon: Icon(Icons.email)),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          onSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 20),
                        _loading
                            ? const CircularProgressIndicator()
                            : ElevatedButton(
                                onPressed: _login,
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    minimumSize:
                                        const Size(double.infinity, 50)),
                                child: const Text("Login"),
                              ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.pushReplacementNamed(
                              context, "/register"),
                          child: const Text("Don’t have an account? Register"),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
