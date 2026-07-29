import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../../services/image_upload_service.dart';

enum PhotoUploadStatus { idle, uploading, success, error }

class PhotoUploadState {
  final PhotoUploadStatus status;
  final double progress;
  final String? downloadUrl;
  final String? error;

  PhotoUploadState({
    required this.status,
    required this.progress,
    this.downloadUrl,
    this.error,
  });
}

class PhotoUploadHelper {
  static Stream<PhotoUploadState> upload({
    required Uint8List bytes,
    required String branchId,
    required String studentId,
  }) async* {
    yield PhotoUploadState(status: PhotoUploadStatus.uploading, progress: 0.5);

    try {
      // 1. Primary: Compress & encode image directly into Base64 string (storage-free & 100% offline)
      final b64 = ImageUploadService.processBytesToBase64(bytes);
      if (b64 != null && b64.isNotEmpty) {
        yield PhotoUploadState(
          status: PhotoUploadStatus.success,
          progress: 1.0,
          downloadUrl: b64,
        );
        return;
      }
    } catch (e) {
      debugPrint('[PhotoUploadHelper] Base64 compression failed: $e — trying Storage fallback');
    }

    // 2. Fallback: Upload to Firebase Storage
    try {
      final storageRef = FirebaseStorage.instance.ref();
      final ref = storageRef
          .child('students')
          .child(branchId)
          .child(studentId)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      final metadata = SettableMetadata(contentType: 'image/jpeg');
      final UploadTask uploadTask = ref.putData(bytes, metadata);
      final TaskSnapshot snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      yield PhotoUploadState(
        status: PhotoUploadStatus.success,
        progress: 1.0,
        downloadUrl: url,
      );
    } catch (e) {
      debugPrint('[PhotoUploadHelper] Storage fallback failed: $e — using raw Base64 data URI');
      // 3. Fail-safe: raw Base64 data URI
      final rawB64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      yield PhotoUploadState(
        status: PhotoUploadStatus.success,
        progress: 1.0,
        downloadUrl: rawB64,
      );
    }
  }
}
