import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gmwf/firebase_options.dart';

void main() {
  test('Query Firestore Collections', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print("Firebase Initialized!");
    
    final db = FirebaseFirestore.instance;
    
    // Query branches
    final branchesSnap = await db.collection('branches').get();
    print("Found ${branchesSnap.docs.length} branches:");
    for (var doc in branchesSnap.docs) {
      print("  Branch ID: ${doc.id}, Data: ${doc.data()}");
    }
    
    final branchId = 'rawalpindi';
    print("\nQuerying branch: $branchId");
    
    // Query config
    final configSnap = await db.collection('branches').doc(branchId).collection('madrassa_config').doc('current').get();
    print("Config 'current' exists: ${configSnap.exists}");
    if (configSnap.exists) {
      print("Config Data: ${configSnap.data()}");
    }
    
    // Query students
    final studentsSnap = await db.collection('branches').doc(branchId).collection('madrassa_students').get();
    print("Students count: ${studentsSnap.docs.length}");
    for (var doc in studentsSnap.docs) {
      print("  Student ID: ${doc.id}, Name: ${doc.data()['name']}, Roll: ${doc.data()['rollNumber']}, Status: ${doc.data()['status']}");
    }
    
    // Query holidays
    final holidaysSnap = await db.collection('branches').doc(branchId).collection('madrassa_holidays').get();
    print("Holidays count: ${holidaysSnap.docs.length}");
    for (var doc in holidaysSnap.docs) {
      print("  Holiday ID: ${doc.id}, Date: ${doc.data()['date']}");
    }
    
    // Query daily logs
    final logsSnap = await db.collection('branches').doc(branchId).collection('madrassa_daily_logs').get();
    print("Daily logs count: ${logsSnap.docs.length}");
    for (var doc in logsSnap.docs) {
      print("  Log ID: ${doc.id}, Student Keys: ${doc.data().keys.toList()}");
    }
  });
}
