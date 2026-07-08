import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class MadrassaPhotoHelper {
  static Future<String> uploadPhoto(Uint8List bytes, String branchId, String studentId) {
    return _uploadPhoto(bytes, branchId, studentId);
  }

  static Future<String> _uploadPhoto(Uint8List bytes, String branchId, String studentId) async {
    final storageRef = FirebaseStorage.instance.ref();
    final fileName = 'students/$branchId/$studentId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = storageRef.child(fileName);
    await ref.putData(bytes);
    final downloadUrl = await ref.getDownloadURL();
    return downloadUrl;
  }
}
