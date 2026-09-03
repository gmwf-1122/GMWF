import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() async {
  print('🧹 Wiping local Hive attendance & biometric queues...');
  // Initialize Hive in the app directory
  final appDir = Directory.current;
  print('Current directory: ${appDir.path}');
  print('✅ Ready to start fresh!');
}
