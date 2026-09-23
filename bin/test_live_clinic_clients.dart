import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  const host = '127.0.0.1';
  const port = 53281;
  final url = 'ws://$host:$port';

  print('===============================================================');
  print('🏥 GMWF LIVE CLINIC CLIENT TEST RUNNER');
  print('Connecting to running app on $url ...');
  print('===============================================================');

  WebSocket? ws;
  try {
    ws = await WebSocket.connect(url).timeout(const Duration(seconds: 4));
  } catch (e) {
    print('\n❌ Connection Failed: $e');
    print('\n👉 IMPORTANT: In your running Flutter app window:');
    print('   1. Navigate to the "Server" screen (or Settings > Server)');
    print('   2. Ensure the Server is turned ON / Started on port 53281.');
    print('   3. Run this command again: dart bin/test_live_clinic_clients.dart');
    print('===============================================================\n');
    exit(1);
  }

  print('✅ CONNECTED TO LIVE APP SERVER!');

  // Listen to live broadcasts from the server
  ws.listen((raw) {
    try {
      final msg = jsonDecode(raw.toString());
      final type = msg['event_type'] ?? msg['type'] ?? 'unknown';
      print('\n[LIVE APP REPLIED] ──> Event: $type');
      print(const JsonEncoder.withIndent('  ').convert(msg));
    } catch (_) {
      print('\n[LIVE APP REPLIED (RAW)]: $raw');
    }
  }, onDone: () {
    print('\n⚠️ Server closed the connection.');
    exit(0);
  }, onError: (err) {
    print('\n❌ Socket Error: $err');
    exit(1);
  });

  // Step 1: Send identify handshake
  print('\n[1/3] Identifying as "reception" (Branch: karachi)...');
  ws.add(jsonEncode({
    'event_type': 'identify',
    'role': 'reception',
    'branchId': 'karachi',
    'username': 'Automated-Live-Tester',
    'protocolVersion': 2,
    'appVersion': '1.3.7',
    '_clientId': 'live_test_client_${DateTime.now().millisecondsSinceEpoch}',
  }));

  await Future.delayed(const Duration(seconds: 1));

  // Step 2: Emit a live test token
  final serial = 'LIVE-${DateTime.now().minute}${DateTime.now().second}';
  print('\n[2/3] Generating Live Token: $serial ...');
  ws.add(jsonEncode({
    'event_type': 'token_created',
    'branchId': 'karachi',
    'serial': serial,
    'patientName': 'Live Test Patient (Automated)',
    'cnic': '42101-9999999-1',
    'status': 'waiting',
    'createdAt': DateTime.now().toIso8601String(),
  }));

  await Future.delayed(const Duration(seconds: 2));

  // Step 3: Emit prescription and dispense
  print('\n[3/3] Emitting Prescription & Inventory Deduction for $serial ...');
  ws.add(jsonEncode({
    'event_type': 'save_prescription',
    'branchId': 'karachi',
    'serial': serial,
    'doctorName': 'Dr. Live Tester',
    'medicines': [
      {'id': 'test_med_1', 'name': 'Panadol 500mg', 'quantity': 10},
    ],
  }));

  await Future.delayed(const Duration(milliseconds: 500));

  ws.add(jsonEncode({
    'event_type': 'update_inventory',
    'branchId': 'karachi',
    'medicineId': 'test_med_1',
    'delta': -10,
  }));

  print('\n✅ Test events sent! Check your running app screen to see if "$serial" appears.');
  print('Listening for incoming server events (press Ctrl+C to exit)...');

  // Keep alive for 10 seconds to listen for server responses
  await Future.delayed(const Duration(seconds: 10));
  await ws.close();
  print('\nDone.');
}
