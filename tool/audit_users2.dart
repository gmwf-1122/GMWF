import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class UniversalAdapter extends TypeAdapter<dynamic> {
  final int _typeId;
  UniversalAdapter(this._typeId);
  @override
  int get typeId => _typeId;
  @override
  dynamic read(BinaryReader reader) {
    try {
      final s = reader.readInt();
      final n = reader.readInt();
      return Timestamp(s, n);
    } catch (_) {
      return null;
    }
  }
  @override
  void write(BinaryWriter writer, dynamic obj) {}
}

void main() async {
  final hiveSourceDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  final tempDir = Directory(r'e:\GMWF\gmwf\tool\temp_users_audit2');
  if (tempDir.existsSync()) {
    try { tempDir.deleteSync(recursive: true); } catch (_) {}
  }
  tempDir.createSync(recursive: true);

  for (final file in hiveSourceDir.listSync()) {
    if (file is File && file.path.endsWith('.hive')) {
      final destPath = '${tempDir.path}\\${file.uri.pathSegments.last}';
      file.copySync(destPath);
    }
  }

  Hive.init(tempDir.path);
  for (int i = 0; i <= 200; i++) {
    try { Hive.registerAdapter(UniversalAdapter(i)); } catch (_) {}
  }

  final usersBox = await Hive.openBox('local_users');
  print('=== 👥 LOCAL USERS IN USERS_BOX (${usersBox.length} users) ===\n');

  final pinsOfInterest = {'155', '136', '15', '158', '159', '160', '161', '162', '134', '135', '127', '137'};

  for (var key in usersBox.keys) {
    final raw = usersBox.get(key);
    if (raw is Map) {
      final uid = (raw['uid'] ?? raw['id'] ?? raw['userId'] ?? key).toString().trim();
      final name = (raw['name'] ?? raw['username'] ?? raw['displayName'] ?? '').toString().trim();
      final email = (raw['email'] ?? '').toString().trim();
      final role = (raw['role'] ?? '').toString().trim();
      final branchId = (raw['branchId'] ?? '').toString().trim();
      final branches = raw['allowedBranches'] ?? raw['branches'];
      final pin = (raw['biometricPin'] ?? raw['pin'] ?? '').toString().trim();

      print('USER: name="$name" | role="$role" | branch="$branchId" | branches=$branches | pin="$pin" | email="$email" | uid="$uid"');
      if (pinsOfInterest.contains(pin)) {
        print('  ⭐ MATCHED PIN $pin to User: $name');
      }
    }
  }
}
