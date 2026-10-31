import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:gmwf/pages/madrassa/utils/madrassa_local_storage.dart';
import 'package:gmwf/pages/school/utils/school_local_storage.dart';
import 'package:gmwf/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('student_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox(LocalStorageService.deadLetterQueueBox);
    await Hive.openBox(LocalStorageService.madrassaStudentsBox);
    await Hive.openBox(LocalStorageService.schoolStudentsBox);
    await Hive.openBox('app_settings');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  String createTestImageBase64(int width, int height) {
    final image = img.Image(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        image.setPixelRgba(x, y, (x * 17) % 256, (y * 31) % 256, (x + y) % 256, 255);
      }
    }
    final jpg = img.encodeJpg(image, quality: 90);
    return 'data:image/jpeg;base64,${base64Encode(jpg)}';
  }

  test('MadrassaLocalStorage.compactMediaForCloud compresses images and removes aliases', () {
    final largeImage = createTestImageBase64(1000, 1000);
    final rawData = {
      'id': 'std_123',
      'name': 'Ahmad Ali',
      'photoUrl': largeImage,
      'photoBase64': largeImage,
      'studentPhotoBase64': largeImage,
      'bFormUrl': largeImage,
      'bFormBase64': largeImage,
      'guardianCnicUrl': largeImage,
      'guardianCnicBase64': largeImage,
    };

    // Before compaction, raw data has duplicates and large dimensions
    final beforeSize = jsonEncode(rawData).length;
    expect(beforeSize, greaterThan(150000));

    final compacted = MadrassaLocalStorage.compactMediaForCloud(rawData);

    // Aliases must be stripped
    expect(compacted.containsKey('photoBase64'), isFalse);
    expect(compacted.containsKey('studentPhotoBase64'), isFalse);
    expect(compacted.containsKey('bFormBase64'), isFalse);
    expect(compacted.containsKey('guardianCnicBase64'), isFalse);

    // Primary keys preserved
    expect(compacted['photoUrl'], isNotEmpty);
    expect(compacted['bFormUrl'], isNotEmpty);
    expect(compacted['guardianCnicUrl'], isNotEmpty);

    // Total size must be significantly smaller
    final afterSize = jsonEncode(compacted).length;
    expect(afterSize, lessThan(beforeSize));
    expect(afterSize, lessThan(500000)); // Safely below Firestore 1MB limit
  });

  test('SchoolLocalStorage.compactMediaForCloud compresses primary docs and additionalDocuments', () {
    final largeImage = createTestImageBase64(800, 800);
    final rawData = {
      'id': 'SCH-001',
      'name': 'Fatima Bibi',
      'photoUrl': largeImage,
      'photoBase64': largeImage,
      'bformUrl': largeImage,
      'bFormBase64': largeImage,
      'guardianCnicUrl': largeImage,
      'additionalDocuments': [
        {'name': 'Certificate', 'url': largeImage},
      ],
    };

    final beforeSize = jsonEncode(rawData).length;
    final compacted = SchoolLocalStorage.compactMediaForCloud(rawData);

    // Aliases stripped
    expect(compacted.containsKey('photoBase64'), isFalse);
    expect(compacted.containsKey('bFormBase64'), isFalse);

    // Additional documents compressed
    final docs = compacted['additionalDocuments'] as List;
    expect(docs.length, equals(1));
    final docUrl = docs.first['url'] as String;
    expect(docUrl.length, lessThan(largeImage.length));

    final afterSize = jsonEncode(compacted).length;
    expect(afterSize, lessThan(beforeSize));
    expect(afterSize, lessThan(500000));
  });

  test('healPoisonedMadrassaSyncQueue unparks and repairs both Madrassa and School DLQ students', () async {
    final largeImage = createTestImageBase64(900, 900);
    final dlq = Hive.box(LocalStorageService.deadLetterQueueBox);
    final syncBox = Hive.box(LocalStorageService.syncBox);

    // 1. Enqueue a stuck Madrassa student in DLQ
    await dlq.put('dlq_madrassa_1', {
      'type': 'save_madrassa_student',
      'studentId': 'std_999',
      'branchId': 'gujrat',
      'attempts': 15,
      'parked': true,
      'autoRevivals': 3,
      'lastError': 'HTTP 400: Document exceeds maximum allowed size of 1048576 bytes',
      'data': {
        'id': 'std_999',
        'name': 'Bilal Khan',
        'photoUrl': largeImage,
        'photoBase64': largeImage,
        'bFormUrl': largeImage,
      },
    });

    // 2. Enqueue a stuck School student in DLQ
    await dlq.put('dlq_school_1', {
      'type': 'save_school_student',
      'studentId': 'SCH-888',
      'branchId': 'gujrat',
      'attempts': 15,
      'parked': true,
      'autoRevivals': 3,
      'lastError': 'HTTP 400: Document exceeds maximum allowed size of 1048576 bytes',
      'data': {
        'id': 'SCH-888',
        'name': 'Zainab Bibi',
        'photoUrl': largeImage,
        'guardianCnicUrl': largeImage,
      },
    });

    expect(dlq.length, equals(2));
    expect(syncBox.length, equals(0));

    final healed = await MadrassaLocalStorage.healPoisonedMadrassaSyncQueue();
    expect(healed, equals(2));

    // Both should be cleared from DLQ and moved back into syncBox
    expect(dlq.length, equals(0));
    expect(syncBox.length, equals(2));

    final healedMadrassa = syncBox.get('dlq_madrassa_1') as Map;
    expect(healedMadrassa['attempts'], equals(0));
    expect(healedMadrassa['parked'], isNull);
    expect(healedMadrassa['autoRevivals'], isNull);
    expect(healedMadrassa['lastError'], isNull);
    expect(healedMadrassa['data']['photoBase64'], isNull); // Aliases removed

    final healedSchool = syncBox.get('dlq_school_1') as Map;
    expect(healedSchool['attempts'], equals(0));
    expect(healedSchool['parked'], isNull);
    expect(healedSchool['autoRevivals'], isNull);
    expect(healedSchool['type'], equals('save_school_student'));
  });
}
