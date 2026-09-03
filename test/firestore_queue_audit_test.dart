import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gmwf/firebase_options.dart';

void main() {
  test('Audit Firestore Queue Types and Document Counts', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print("=== 🔥 FIRESTORE AUDIT STARTED ===");
    
    final db = FirebaseFirestore.instance;
    final branchesSnap = await db.collection('branches').get();
    final branchIds = branchesSnap.docs.map((d) => d.id).toList();
    print("Found ${branchIds.length} branches: $branchIds");

    int totalPatients = 0;
    final Map<String, int> patientQueueCounts = {};

    // 1. Global & Branch Patients
    try {
      final globalPatients = await db.collection('patients').get();
      print("Global /patients collection: ${globalPatients.docs.length} docs");
      for (var doc in globalPatients.docs) {
        totalPatients++;
        final qt = (doc.data()['queueType'] ?? doc.data()['category'] ?? doc.data()['status'] ?? 'NONE').toString().toLowerCase();
        patientQueueCounts[qt] = (patientQueueCounts[qt] ?? 0) + 1;
      }
    } catch (e) {
      print("Error reading global patients: $e");
    }

    for (var bId in branchIds) {
      try {
        final bPatients = await db.collection('branches').doc(bId).collection('patients').get();
        print("Branch '$bId' /patients: ${bPatients.docs.length} docs");
        for (var doc in bPatients.docs) {
          totalPatients++;
          final qt = (doc.data()['queueType'] ?? doc.data()['category'] ?? doc.data()['status'] ?? 'NONE').toString().toLowerCase();
          patientQueueCounts[qt] = (patientQueueCounts[qt] ?? 0) + 1;
        }
      } catch (e) {
        print("Error reading branch '$bId' patients: $e");
      }
    }

    print("\n--- PATIENT COLLECTION STATS ---");
    print("Total Patient Profiles: $totalPatients");
    print("Queue / Category distribution on patient profiles: $patientQueueCounts");

    // 2. Serials across all branches & dates
    int totalSerials = 0;
    final Map<String, int> serialSubcollectionCounts = {};
    final Map<String, int> serialFieldQueueCounts = {};
    final subcollectionNames = ['zakat', 'non-zakat', 'gmwf', 'general', 'emergency', 'credits', 'non_zakat', 'gm_wf'];

    for (var bId in branchIds) {
      try {
        final serialDatesSnap = await db.collection('branches').doc(bId).collection('serials').get();
        print("\nBranch '$bId' has ${serialDatesSnap.docs.length} date records in /serials");
        
        for (var dateDoc in serialDatesSnap.docs) {
          final dateKey = dateDoc.id;
          for (var subName in subcollectionNames) {
            try {
              final subSnap = await db.collection('branches').doc(bId).collection('serials').doc(dateKey).collection(subName).get();
              if (subSnap.docs.isNotEmpty) {
                totalSerials += subSnap.docs.length;
                serialSubcollectionCounts[subName] = (serialSubcollectionCounts[subName] ?? 0) + subSnap.docs.length;
                for (var doc in subSnap.docs) {
                  final data = doc.data();
                  final fieldQt = (data['queueType'] ?? data['category'] ?? 'NONE').toString().toLowerCase();
                  serialFieldQueueCounts[fieldQt] = (serialFieldQueueCounts[fieldQt] ?? 0) + 1;
                }
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        print("Error reading serials for $bId: $e");
      }
    }

    print("\n--- SERIALS SUBCOLLECTIONS STATS ---");
    print("Total Serial Documents: $totalSerials");
    print("Subcollection breakdown: $serialSubcollectionCounts");
    print("queueType field breakdown inside serial documents: $serialFieldQueueCounts");

    // 3. Dispensary logs
    int totalDispensary = 0;
    final Map<String, int> dispensaryQueueCounts = {};
    for (var bId in branchIds) {
      try {
        final dispDatesSnap = await db.collection('branches').doc(bId).collection('dispensary').get();
        for (var dateDoc in dispDatesSnap.docs) {
          final dKey = dateDoc.id;
          final logsSnap = await db.collection('branches').doc(bId).collection('dispensary').doc(dKey).collection(dKey).get();
          for (var doc in logsSnap.docs) {
            totalDispensary++;
            final qt = (doc.data()['queueType'] ?? doc.data()['category'] ?? doc.data()['status'] ?? 'NONE').toString().toLowerCase();
            dispensaryQueueCounts[qt] = (dispensaryQueueCounts[qt] ?? 0) + 1;
          }
        }
      } catch (e) {
        print("Error reading dispensary for $bId: $e");
      }
    }

    print("\n--- DISPENSARY STATS ---");
    print("Total Dispensary Logs: $totalDispensary");
    print("Dispensary queueType distribution: $dispensaryQueueCounts");

    print("\n=== 🔥 AUDIT COMPLETE ===");
  }, timeout: const Timeout(Duration(minutes: 5)));
}
