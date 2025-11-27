// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
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
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _checkLocalLogin();
  }

  /// Check internet
  Future<void> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() => _isOnline = connectivityResult != ConnectivityResult.none);
  }

  /// Offline login from Hive
  Future<void> _checkLocalLogin() async {
    final authBox = await Hive.openBox('authBox');
    final userId = authBox.get('userId');
    final username = authBox.get('username');
    final email = authBox.get('email');
    final branchId = authBox.get('branchId');
    final role = authBox.get('role');
    final hashedPassword = authBox.get('passwordHash');

    if (userId == null || hashedPassword == null) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
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
      _showSnack("Fill all fields");
      return;
    }

    setState(() => _loading = true);

    try {
      final authBox = await Hive.openBox('authBox');

      // Offline mode
      if (!_isOnline) {
        final savedHash = authBox.get('passwordHash');
        final inputHash = _hashPassword(password);

        if (savedHash == inputHash) {
          final userId = authBox.get('userId');
          final username = authBox.get('username');
          final email = authBox.get('email');
          final branchId = authBox.get('branchId');
          final role = authBox.get('role');

          if (userId != null) {
            final mockUser = _MockUser(uid: userId, email: email);
            if (!mounted) return;
            _navigateToHome(mockUser, {
              "uid": userId,
              "username": username,
              "email": email,
              "branchId": branchId,
              "role": role,
            });
            return;
          }
        }
        _showSnack("Invalid credentials (offline)");
        return;
      }

      // Online mode
      final firestore = FirebaseFirestore.instance;

      // Admin login
      if (input.toLowerCase() == "admin" ||
          input.toLowerCase() == "admin@system.com") {
        const email = "admin@system.com";
        final cred = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        final user = cred.user!;
        await _saveAllLocally(
            authBox, user.uid, "admin", email, "all", "admin", password);
        _navigateToHome(user, {
          "uid": user.uid,
          "username": "admin",
          "email": email,
          "branchId": "all",
          "role": "admin",
        });
        return;
      }

      String? email;
      String? username;
      String? branchId;
      String? role;
      String? uid;

      if (input.contains("@")) {
        email = input;
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
        _showSnack("User not found");
        return;
      }

      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final user = cred.user!;
      await _saveAllLocally(
          authBox, uid ?? user.uid, username, email, branchId, role, password);

      _navigateToHome(user, {
        "uid": uid ?? user.uid,
        "username": username,
        "email": email,
        "branchId": branchId,
        "role": role,
      });
    } catch (e) {
      _showSnack("Login failed: ${e.toString().split('.').first}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Hash password (SHA-256)
  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /// Save everything locally
  Future<void> _saveAllLocally(
    Box box,
    String uid,
    String? username,
    String? email,
    String branchId,
    String role,
    String password,
  ) async {
    await box.clear();
    await box.put('userId', uid);
    await box.put('username', username);
    await box.put('email', email);
    await box.put('branchId', branchId);
    await box.put('role', role);
    await box.put('passwordHash', _hashPassword(password));
  }

  void _navigateToHome(User user, Map<String, dynamic> localUser) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeRouter(user: user, localUser: localUser),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: msg.contains("offline")
            ? Colors.orange.shade700
            : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/1.jpg"),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 20 : 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.4), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Image.asset(
                      "assets/logo/gmwf.png",
                      height: isMobile ? 90 : 110,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.local_hospital,
                          size: 80,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 24),

                    // Title (No Wi-Fi Icon)
                    const Text(
                      "Login",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Username/Email
                    _buildTextField(
                      controller: _usernameOrEmailController,
                      label: "Username or Email",
                      icon: Icons.person,
                    ),
                    const SizedBox(height: 20),

                    // Password
                    _buildTextField(
                      controller: _passwordController,
                      label: "Password",
                      icon: Icons.lock,
                      obscureText: _obscurePassword,
                      isPassword: true,
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 28),

                    // Login Button
                    _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 4,
                              ),
                              child: const Text("Login",
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                    const SizedBox(height: 16),

                    // Footer
                    const Text(
                      "Contact admin to create an account",
                      style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    bool isPassword = false,
    Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                    obscureText ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      ),
    );
  }
}

// Mock User for offline
class _MockUser implements User {
  @override
  final String uid;
  @override
  final String? email;

  _MockUser({required this.uid, this.email});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
