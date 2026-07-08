import 'package:flutter/foundation.dart';
import 'dart:io' as io;
import 'package:firebase_storage/firebase_storage.dart';

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
    yield PhotoUploadState(status: PhotoUploadStatus.uploading, progress: 0.0);

    try {
      final storageRef = FirebaseStorage.instance.ref();
      // Using child path builder to avoid slash/backslash issues on Windows/desktop
      final ref = storageRef
          .child('students')
          .child(branchId)
          .child(studentId)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      final metadata = SettableMetadata(contentType: 'image/jpeg');
      final UploadTask uploadTask = ref.putData(bytes, metadata);

      TaskSnapshot snapshot;

      // On Windows/Desktop, snapshotEvents triggers non-platform thread channel errors
      // and aborts/corrupts the upload. We skip streaming progress events on Windows.
      final bool isWindows = !kIsWeb && io.Platform.isWindows;

      if (isWindows) {
        snapshot = await uploadTask;
      } else {
        // Yield progress updates during upload
        await for (final event in uploadTask.snapshotEvents) {
          final double progress = event.totalBytes > 0
              ? event.bytesTransferred / event.totalBytes
              : 0.0;
          yield PhotoUploadState(status: PhotoUploadStatus.uploading, progress: progress);
        }
        snapshot = await uploadTask;
      }

      // Fetch download URL with retry back-off to handle replication/timing delay on desktop
      String? url;
      int retries = 5;
      while (retries > 0) {
        try {
          url = await snapshot.ref.getDownloadURL();
          break;
        } catch (e) {
          retries--;
          if (retries == 0) rethrow;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (url != null) {
        yield PhotoUploadState(status: PhotoUploadStatus.success, progress: 1.0, downloadUrl: url);
      } else {
        yield PhotoUploadState(status: PhotoUploadStatus.error, progress: 0.0, error: 'Download URL is null');
      }
    } catch (e) {
      yield PhotoUploadState(status: PhotoUploadStatus.error, progress: 0.0, error: e.toString());
    }
  }
}
