// lib/widgets/protected_screen.dart
import 'package:flutter/material.dart';
import '../services/permission_service.dart';

class ProtectedScreen extends StatelessWidget {
  final Widget child;
  final AppPermission requiredPermission;
  final String userRole;

  const ProtectedScreen({
    super.key,
    required this.child,
    required this.requiredPermission,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    final hasAccess = PermissionService().hasPermission(userRole, requiredPermission);

    if (!hasAccess) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 80, color: Colors.red),
                const SizedBox(height: 24),
                const Text(
                  'Access Denied',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'You do not have permission to view this module (${requiredPermission.name}).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return child;
  }
}
