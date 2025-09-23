import 'package:flutter/material.dart';
import 'package:gmwf/services/auth_service.dart';

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  String? _selectedRole;
  String? _selectedBranch;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  final List<String> roles = ["Doctor", "Receptionist", "Dispenser"];
  final List<String> branches = ["Gujrat", "Sialkot", "Karachi-1", "Karachi-2"];

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final branchId = _selectedBranch!.toLowerCase().replaceAll(" ", "");
      final branchName = _selectedBranch!;

      await _authService.signUp(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _selectedRole!,
        branchId,
        branchName, // ✅ now passed correctly
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ User registered successfully"),
          backgroundColor: Colors.green,
        ),
      );

      _emailController.clear();
      _passwordController.clear();
      setState(() {
        _selectedRole = null;
        _selectedBranch = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text("Register User", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Image.asset("assets/logo/gmwf.png", height: 100),
              const SizedBox(height: 20),
              const Text("Register New User",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
              const SizedBox(height: 20),
              _buildTextField(_emailController, "Email", Icons.email, false),
              const SizedBox(height: 15),
              _buildTextField(
                  _passwordController, "Password", Icons.lock, true),
              const SizedBox(height: 15),
              _buildDropdown(
                  value: _selectedRole,
                  items: roles,
                  hint: "Select Role",
                  icon: Icons.admin_panel_settings,
                  onChanged: (val) => setState(() => _selectedRole = val)),
              const SizedBox(height: 15),
              _buildDropdown(
                  value: _selectedBranch,
                  items: branches,
                  hint: "Select Branch",
                  icon: Icons.location_city,
                  onChanged: (val) => setState(() => _selectedBranch = val)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _registerUser,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.app_registration),
                  label: Text(_loading ? "Registering..." : "Register User"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label,
      IconData icon, bool obscure) {
    return TextFormField(
      controller: controller,
      obscureText: (label == "Password") ? _obscurePassword : obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: label == "Password"
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              )
            : null,
      ),
      validator: (val) {
        if (val == null || val.isEmpty) return "Enter $label";
        if (label == "Password" && val.length < 6) {
          return "Password must be at least 6 chars";
        }
        return null;
      },
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<String> items,
    required String hint,
    required IconData icon,
    required Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      hint: Text(hint),
      items:
          items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (val) => val == null ? "Select $hint" : null,
    );
  }
}
