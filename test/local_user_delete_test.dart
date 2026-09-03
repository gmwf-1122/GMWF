import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:gmwf/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(LocalStorageService.usersBox)) {
      await Hive.openBox(LocalStorageService.usersBox);
    }
    await Hive.box(LocalStorageService.usersBox).clear();
  });

  tearDown(() async {
    if (Hive.isBoxOpen(LocalStorageService.usersBox)) {
      await Hive.box(LocalStorageService.usersBox).clear();
    }
  });

  test('deleteUserOffline removes the user by uid, email, and username lower entries', () async {
    final box = Hive.box(LocalStorageService.usersBox);
    final user = {
      'uid': 'uid_123',
      'email': 'alice@example.com',
      'username': 'Alice',
      'usernameLower': 'alice',
      'branchId': 'branch_a',
    };

    await box.put('user:alice@example.com', user);
    await box.put('user:uid_123', user);
    await box.put('user:alice', user);

    await LocalStorageService.deleteUserOffline(
      uid: 'uid_123',
      branchId: 'branch_a',
      email: 'alice@example.com',
    );

    expect(box.get('user:alice@example.com'), isNull);
    expect(box.get('user:uid_123'), isNull);
    expect(box.get('user:alice'), isNull);
    expect(
      box.values.whereType<Map>().any((entry) => (entry['uid'] ?? '') == 'uid_123'),
      isFalse,
    );
  });
}
