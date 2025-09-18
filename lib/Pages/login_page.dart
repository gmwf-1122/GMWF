import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.signOut();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack("⚠️ Fill all fields");
      return;
    }

    setState(() => _loading = true);

    try {
      final userData = await _authService.login(email, password);

      if (userData == null) {
        _showSnack("❌ Login failed: no user data found");
        return;
      }

      final role = (userData["role"]?.toString() ?? "").toLowerCase();
      final branchId = userData["branchId"]?.toString() ?? "";
      final branchName = userData["branchName"]?.toString() ?? branchId;

      if (role.isEmpty) {
        _showSnack("❌ Role not assigned");
        return;
      }

      if (!mounted) return;

      debugPrint("✅ Logged in: $email as $role (branch=$branchId)");

      // If auth used Firebase, Main's authStateChanges will route via HomeRouter.
      // For hardcoded admin (no Firebase user) your app may navigate directly.
      // We'll try to navigate to HomeRouter route that expects FirebaseUser;
      // if you prefer direct screen push for admin, you can check role here.
      if (role == 'admin') {
        Navigator.pushReplacementNamed(context, '/admin');
        return;
      }

      // For other roles, push to a route that will trigger HomeRouter via authStateChanges.
      // If your app expects a different flow, adjust accordingly.
      Navigator.pushReplacementNamed(context,
          "/login"); // fallback: allow authStateChanges to handle routing
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
          gradient: LinearGradient(
            colors: [Colors.green, Colors.lightGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 900,
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Image.asset(
                        "assets/logo/gmwf.png",
                        height: 240,
                      ),
                    ),
                  ),
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
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Login",
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
                                        const Size(double.infinity, 50),
                                  ),
                                  child: const Text("Login"),
                                ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => Navigator.pushReplacementNamed(
                              context,
                              "/register",
                            ),
                            child: const Text(
                              "Don’t have an account? Register",
                            ),
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
      ),
    );
  }
}
