// lib/pages/login_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:another_flushbar/flushbar.dart';

import '../services/offline_auth_service.dart';
import 'home_router.dart';
import 'admin_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameOrEmailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _scrollController = ScrollController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _loginHover = false;
  bool _changeHover = false;
  bool _isOnline = true;

  // ── Live connectivity listener (fixes "stuck offline" bug) ────────────────
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _checkConnectivityFast();
    _loadCachedCredentials();

    // Subscribe to connectivity changes so the UI updates automatically
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (mounted && online != _isOnline) {
        setState(() => _isOnline = online);
        debugPrint('[LoginPage] Connectivity changed → online: $online');
      }
    });

    _usernameFocus.addListener(_handleFocusChange);
    _passwordFocus.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _usernameFocus.removeListener(_handleFocusChange);
    _passwordFocus.removeListener(_handleFocusChange);
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _scrollController.dispose();
    _usernameOrEmailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final node = _usernameFocus.hasFocus ? _usernameFocus : _passwordFocus;
    if (node.hasFocus) _scrollToField(node);
  }

  void _scrollToField(FocusNode node) {
    if (!mounted || node.context == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Scrollable.ensureVisible(
        node.context!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    });
  }

  Future<void> _checkConnectivityFast() async {
    try {
      final result = await Connectivity().checkConnectivity();
      final online = result.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _isOnline = online);
      debugPrint('[LoginPage] Initial connectivity: online=$online');
    } catch (e) {
      debugPrint('[LoginPage] Connectivity check error: $e — assuming offline');
      if (mounted) setState(() => _isOnline = false);
    }
  }

  Future<void> _loadCachedCredentials() async {
    try {
      final cached = await OfflineAuthService.getCachedUsername();
      if (cached != null && cached.isNotEmpty && mounted) {
        _usernameOrEmailController.text = cached;
        debugPrint('[LoginPage] Pre-filled username: $cached');
      }
    } catch (e) {
      debugPrint('[LoginPage] Error loading cached credentials: $e');
    }
  }

  // ── Main login entry point ────────────────────────────────────────────────
  Future<void> _login() async {
    final input = _usernameOrEmailController.text.trim();
    final password = _passwordController.text.trim();

    debugPrint('════════════════════════════════════════');
    debugPrint('🔐 LOGIN ATTEMPT');
    debugPrint('👤 Input: $input');
    debugPrint('🌐 Is online: $_isOnline');
    debugPrint('════════════════════════════════════════');

    if (input.isEmpty || password.isEmpty) {
      _showError("Please enter username/email and password");
      return;
    }

    if (mounted) setState(() => _loading = true);

    try {
      if (!_isOnline) {
        // ── Pure offline path ────────────────────────────────────────────────
        debugPrint('[LoginPage] OFFLINE MODE — fast offline login');
        final ok = await _attemptOfflineLogin(input, password);
        if (!ok && mounted) {
          _showError(
              "Offline login failed. Check your credentials or connect to the internet.");
        }
        return;
      }

      // ── Online path ──────────────────────────────────────────────────────
      debugPrint('[LoginPage] ONLINE MODE — Firebase login');
      String email = input;

      if (!input.contains('@')) {
        debugPrint('[LoginPage] Looking up email for username: $input');
        final found = await _findUserByUsername(input);
        if (found == null) {
          debugPrint('[LoginPage] Username not found online — trying offline');
          final ok = await _attemptOfflineLogin(input, password);
          if (!ok && mounted) {
            _showError("No account found for username '$input'");
          }
          return;
        }
        email = found['email'] as String;
        debugPrint('[LoginPage] Resolved email: $email');
      }

      // Firebase sign-in
      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: email.toLowerCase(),
            password: password,
          )
          .timeout(const Duration(seconds: 15));

      final user = cred.user;
      if (user == null) {
        _showError("Login failed: no user returned");
        return;
      }

      debugPrint('[LoginPage] Firebase sign-in OK — fetching user data');

      // Fetch user data from Firestore
      final userData = await _fetchUserDataFromFirestore(user, input);
      if (userData == null) {
        _showError("User account data not found. Contact admin.");
        return;
      }

      // Cache for offline login
      try {
        await OfflineAuthService.saveCredentials(
          usernameOrEmail: input.toLowerCase(),
          password: password,
          userData: userData,
        );
        debugPrint('[LoginPage] Credentials cached for offline');
      } catch (e) {
        debugPrint('[LoginPage] Failed to cache credentials (non-fatal): $e');
      }

      if (mounted) {
        Flushbar(
          message: "Welcome back, ${userData['username']}!",
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ).show(context);
        _navigateToHome(user, userData);
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[LoginPage] FirebaseAuthException: ${e.code} — ${e.message}');
      await _handleFirebaseAuthError(e, input, password);
    } catch (e) {
      debugPrint('[LoginPage] Unexpected error: $e');
      // Timeout or unknown — try offline as last resort
      if (e.toString().contains('timeout') ||
          e.toString().contains('TimeoutException')) {
        debugPrint('[LoginPage] Timeout — trying offline');
        final ok = await _attemptOfflineLogin(input, password);
        if (!ok && mounted) {
          _showError("Connection timed out and offline login failed.");
        }
      } else {
        // Swallow internal/platform errors that aren't auth failures;
        // try offline before showing the message to the user.
        final ok = await _attemptOfflineLogin(input, password);
        if (!ok && mounted) {
          _showError("An unexpected error occurred. Please try again.");
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Firebase error handler ────────────────────────────────────────────────
  Future<void> _handleFirebaseAuthError(
      FirebaseAuthException e, String input, String password) async {
    const networkCodes = {
      'network-request-failed',
      'unavailable',
      'deadline-exceeded',
    };
    const credentialCodes = {
      'wrong-password',
      'invalid-credential',
      'user-not-found',
    };

    if (networkCodes.contains(e.code)) {
      debugPrint('[LoginPage] Network error — trying offline');
      final ok = await _attemptOfflineLogin(input, password);
      if (!ok && mounted) _showError("Network error and offline login failed.");
      return;
    }

    if (credentialCodes.contains(e.code)) {
      // Try offline first before showing an error — the credentials might be
      // cached from an earlier session.
      final ok = await _attemptOfflineLogin(input, password);
      if (ok) return;

      final msg = e.code == 'wrong-password' || e.code == 'invalid-credential'
          ? "Incorrect password"
          : "No account found for '$input'";
      if (mounted) _showError(msg);
      return;
    }

    if (e.code == 'too-many-requests') {
      if (mounted) _showError("Too many attempts. Please try again later.");
      return;
    }

    // For every other Firebase error (including 'unknown-error' which is
    // usually a platform/internal error, NOT a wrong-credential error) try
    // offline before giving up.
    debugPrint('[LoginPage] Unhandled FirebaseAuthException ${e.code} — trying offline');
    final ok = await _attemptOfflineLogin(input, password);
    if (!ok && mounted) {
      _showError("Login failed: ${e.message ?? e.code}");
    }
  }

  // ── Offline login ─────────────────────────────────────────────────────────
  Future<bool> _attemptOfflineLogin(String input, String password) async {
    try {
      debugPrint('[LoginPage] Attempting offline login for: $input');
      final userData = await OfflineAuthService.verifyOfflineCredentials(
        usernameOrEmail: input.toLowerCase(),
        password: password,
      );

      if (userData == null) {
        debugPrint('[LoginPage] Offline login failed — no matching credentials');
        return false;
      }

      debugPrint('[LoginPage] Offline login successful');
      if (mounted) {
        Flushbar(
          message: "Welcome back, ${userData['username']}! (Offline Mode)",
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 2),
        ).show(context);
        _navigateToHomeOffline(userData);
      }
      return true;
    } catch (e) {
      debugPrint('[LoginPage] Offline login exception: $e');
      return false;
    }
  }

  // ── Firestore user data fetch ─────────────────────────────────────────────
  Future<Map<String, dynamic>?> _fetchUserDataFromFirestore(
      User user, String inputUsername) async {
    final uid = user.uid;

    // Top-level /users
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));
      if (doc.exists && doc.data() != null) {
        final d = doc.data()!;
        return {
          'uid': uid,
          'email': user.email,
          'username': d['username'] ?? inputUsername.split('@').first.toLowerCase(),
          'role': d['role'] ?? 'unknown',
          'branchId': d['branchId'] ?? '',
          'name': d['name'] ?? d['username'] ?? inputUsername.split('@').first,
          ...d,
        };
      }
    } catch (e) {
      debugPrint('[LoginPage] Top-level /users fetch failed: $e');
    }

    // Branch sub-collections
    try {
      final branches = await FirebaseFirestore.instance
          .collection('branches')
          .get()
          .timeout(const Duration(seconds: 10));

      for (final branch in branches.docs) {
        final doc = await branch.reference
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 5));
        if (doc.exists && doc.data() != null) {
          final d = doc.data()!;
          return {
            'uid': uid,
            'email': user.email,
            'username': d['username'] ?? inputUsername.split('@').first.toLowerCase(),
            'role': d['role'] ?? 'unknown',
            'branchId': branch.id,
            'name': d['name'] ?? d['username'] ?? inputUsername.split('@').first,
            ...d,
          };
        }
      }
    } catch (e) {
      debugPrint('[LoginPage] Branch /users fetch failed: $e');
    }

    debugPrint('[LoginPage] User data not found in Firestore for uid=$uid');
    return null;
  }

  // ── Username → email lookup ───────────────────────────────────────────────
  Future<Map<String, dynamic>?> _findUserByUsername(String username) async {
    final lower = username.trim().toLowerCase();
    try {
      // Top-level collection first
      final q = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: lower)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));
      if (q.docs.isNotEmpty) {
        final doc = q.docs.first;
        return {'email': doc['email'], 'username': doc['username']};
      }

      // Branch sub-collections
      final branches = await FirebaseFirestore.instance
          .collection('branches')
          .get()
          .timeout(const Duration(seconds: 10));

      for (final branch in branches.docs) {
        final users = await branch.reference
            .collection('users')
            .where('username', isEqualTo: lower)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 5));
        if (users.docs.isNotEmpty) {
          final doc = users.docs.first;
          return {
            'email': doc['email'],
            'username': doc['username'],
            'branchId': branch.id,
          };
        }
      }
    } catch (e) {
      debugPrint('[LoginPage] Username lookup failed: $e');
    }
    return null;
  }

  // ── Navigation helpers ────────────────────────────────────────────────────
  void _navigateToHome(User user, Map<String, dynamic> userData) {
    final role = (userData['role'] as String?)?.toLowerCase() ?? 'unknown';
    if (role == 'admin' || role == 'chairman' || role == 'ceo') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => AdminScreen(branchId: 'all')),
        (r) => false,
      );
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomeRouter(user: user, localUser: userData)),
        (r) => false,
      );
    }
  }

  void _navigateToHomeOffline(Map<String, dynamic> userData) {
    final role = (userData['role'] as String?)?.toLowerCase() ?? 'unknown';
    if (role == 'admin' || role == 'chairman' || role == 'ceo') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => AdminScreen(branchId: 'all')),
        (r) => false,
      );
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomeRouter(user: null, localUser: userData)),
        (r) => false,
      );
    }
  }

  // ── Change password dialog ────────────────────────────────────────────────
  Future<void> _showChangePasswordDialog() async {
    if (!_isOnline) {
      _showError("Password change requires an internet connection.");
      return;
    }

    final emailCtrl = TextEditingController(
      text: _usernameOrEmailController.text.contains('@')
          ? _usernameOrEmailController.text
          : '',
    );
    final oldPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Change Password",
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF00695C))),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                    labelText: "Email", prefixIcon: Icon(Icons.email)),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? "Enter valid email" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: oldPwCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: "Old Password", prefixIcon: Icon(Icons.lock)),
                validator: (v) =>
                    (v == null || v.isEmpty) ? "Required" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newPwCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: "New Password",
                    prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) =>
                    (v == null || v.length < 6) ? "Min 6 characters" : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C)),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final currentUser = FirebaseAuth.instance.currentUser;
                if (currentUser == null) {
                  _showError("You must be logged in to change password.");
                  return;
                }
                final cred = EmailAuthProvider.credential(
                  email: emailCtrl.text.trim().toLowerCase(),
                  password: oldPwCtrl.text.trim(),
                );
                await currentUser.reauthenticateWithCredential(cred);
                await currentUser
                    .updatePassword(newPwCtrl.text.trim());
                try {
                  await OfflineAuthService.updateCachedPassword(
                      newPwCtrl.text.trim());
                } catch (_) {}
                if (mounted) {
                  Navigator.pop(context);
                  Flushbar(
                    message: "Password changed successfully",
                    backgroundColor: Colors.green.shade700,
                    duration: const Duration(seconds: 3),
                  ).show(context);
                }
              } on FirebaseAuthException catch (e) {
                _showError(e.code == 'wrong-password'
                    ? "Incorrect old password"
                    : e.message ?? "Failed to change password");
              } catch (e) {
                _showError("Unexpected error: $e");
              }
            },
            child:
                const Text("Change", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    Flushbar(
      message: msg,
      backgroundColor: Colors.red.shade700,
      duration: const Duration(seconds: 5),
    ).show(context);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF00695C), Color(0xFF004D40)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 24,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32)),
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 48, 40, 40),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          "assets/logo/gmwf.png",
                          height: 120,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.local_pharmacy,
                            size: 100,
                            color: Color(0xFF00695C),
                          ),
                        ),
                        const SizedBox(height: 40),
                        const Text(
                          "Welcome Back",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF004D40),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Live online/offline badge
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _isOnline ? "Sign in to continue" : "⚠️ OFFLINE MODE",
                            key: ValueKey(_isOnline),
                            style: TextStyle(
                              fontSize: 16,
                              color: _isOnline
                                  ? Colors.grey.shade700
                                  : Colors.orange.shade800,
                              fontWeight: _isOnline
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),

                        // Username / email field
                        TextField(
                          controller: _usernameOrEmailController,
                          focusNode: _usernameFocus,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: "Username or Email",
                            prefixIcon: const Icon(Icons.person_outline),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                  color: Color(0xFF00695C), width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Password field
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                  color: Color(0xFF00695C), width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Sign In button
                        MouseRegion(
                          onEnter: (_) =>
                              setState(() => _loginHover = true),
                          onExit: (_) =>
                              setState(() => _loginHover = false),
                          child: SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00695C),
                                foregroundColor: Colors.white,
                                elevation: _loginHover ? 16 : 8,
                                shadowColor: Colors.teal.shade700,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18)),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      height: 28,
                                      width: 28,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 3),
                                    )
                                  : const Text("Sign In",
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Change Password button
                        MouseRegion(
                          onEnter: (_) =>
                              setState(() => _changeHover = true),
                          onExit: (_) =>
                              setState(() => _changeHover = false),
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton(
                              onPressed: _showChangePasswordDialog,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Color(0xFF00695C), width: 2),
                                backgroundColor: _changeHover
                                    ? const Color(0xFFE0F2F1)
                                    : Colors.transparent,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text(
                                "Change Password",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _changeHover
                                      ? const Color(0xFF004D40)
                                      : const Color(0xFF00695C),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        Text(
                          "Contact admin to create an account",
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}