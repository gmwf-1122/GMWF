// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'home_router.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameOrEmailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkLocalLogin();
  }

  /// ✅ Offline login check with Hive
  Future<void> _checkLocalLogin() async {
    final authBox = await Hive.openBox('authBox');
    final userId = authBox.get('userId');
    final username = authBox.get('username');
    final email = authBox.get('email');
    final branchId = authBox.get('branchId');
    final role = authBox.get('role');

    final currentUser = FirebaseAuth.instance.currentUser;

    if (userId != null &&
        (username != null || email != null) &&
        role != null &&
        currentUser != null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeRouter(
            user: currentUser,
            localUser: {
              "uid": userId,
              "username": username,
              "email": email,
              "branchId": branchId,
              "role": role,
            },
          ),
        ),
      );
    }
  }

  Future<void> _login() async {
    final input = _usernameOrEmailController.text.trim();
    final password = _passwordController.text.trim();

    if (input.isEmpty || password.isEmpty) {
      _showSnack("⚠️ Fill all fields");
      return;
    }

    setState(() => _loading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final authBox = await Hive.openBox('authBox');

      // ✅ Special case for admin
      if (input.toLowerCase() == "admin" ||
          input.toLowerCase() == "admin@system.com") {
        const email = "admin@system.com";
        final cred = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);

        final user = cred.user;
        if (user == null) throw Exception("Admin user not found");

        await authBox.clear();
        await authBox.put('userId', user.uid);
        await authBox.put('username', "admin");
        await authBox.put('email', email);
        await authBox.put('role', "admin");
        await authBox.put('branchId', "all");

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeRouter(
              user: user,
              localUser: {
                "uid": user.uid,
                "username": "admin",
                "email": email,
                "role": "admin",
                "branchId": "all",
              },
            ),
          ),
        );
        return;
      }

      String? email;
      String? username;
      String? branchId;
      String? role;
      String? uid;

      // ✅ If user typed an email
      if (input.contains("@")) {
        email = input;
        username = null;

        // Look for user in branches
        final branchesSnap = await firestore.collection("branches").get();
        for (var branchDoc in branchesSnap.docs) {
          final userDoc = await branchDoc.reference
              .collection("users")
              .where("email", isEqualTo: email)
              .get();

          if (userDoc.docs.isNotEmpty) {
            final data = userDoc.docs.first.data();
            branchId = branchDoc.id;
            uid = userDoc.docs.first.id;
            role = data['role'];
            username = data['username'];
            break;
          }
        }
      } else {
        // ✅ Otherwise treat input as username
        username = input;

        final branchesSnap = await firestore.collection("branches").get();
        for (var branchDoc in branchesSnap.docs) {
          final usersSnap = await branchDoc.reference.collection("users").get();

          for (var userDoc in usersSnap.docs) {
            final data = userDoc.data();
            if (data['username']?.toString().toLowerCase() ==
                username.toLowerCase()) {
              email = data['email'];
              role = data['role'];
              branchId = branchDoc.id;
              uid = userDoc.id;
              break;
            }
          }
          if (email != null) break;
        }
      }

      if (email == null || role == null || branchId == null) {
        _showSnack("❌ User not found or unauthorized");
        return;
      }

      // ✅ Authenticate
      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final user = cred.user;
      if (user == null) throw Exception("Failed to login");

      // ✅ Save session locally
      await authBox.clear();
      await authBox.put('userId', uid ?? user.uid);
      await authBox.put('username', username);
      await authBox.put('email', email);
      await authBox.put('branchId', branchId);
      await authBox.put('role', role);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeRouter(
            user: user,
            localUser: {
              "uid": uid ?? user.uid,
              "username": username,
              "email": email,
              "branchId": branchId,
              "role": role,
            },
          ),
        ),
      );
    } catch (e) {
      _showSnack("❌ Login failed: $e");
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              Colors.green,
              Colors.green,
            ],
            stops: [0.3, 1.0],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset("assets/logo/gmwf.png", height: 120),
                  const SizedBox(height: 30),
                  const Text(
                    "Login",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Username/Email field
                  TextField(
                    controller: _usernameOrEmailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Username or Email",
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.person, color: Colors.white),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white70),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Password field
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Password",
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.lock, color: Colors.white),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white70),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Colors.white, width: 2),
                      ),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 20),

                  _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text("Login"),
                        ),
                  const SizedBox(height: 10),
                  const Text(
                    "Contact admin to create an account",
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.white70,
                    ),
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
