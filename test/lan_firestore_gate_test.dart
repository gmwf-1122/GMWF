import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/services/cloud/lan_firestore_gate.dart';

void main() {
  test('only dispensary desk roles are gated on the LAN', () {
    for (final role in ['Doctor', 'dispensar', 'Dispenser', 'receptionist', 'Pharmacist', 'Hybrid Desk', 'nurse', 'rec+dis', 'doc+rec', 'doc+dis', 'doc+rec+dis']) {
      expect(LanFirestoreGate.isDispensaryDeskRole(role), isTrue, reason: role);
    }
    for (final role in ['Admin', 'HQ Manager', 'supervisor', 'Director', 'chairman', 'CEO', 'office boy', 'madrassa teacher', '', null]) {
      expect(LanFirestoreGate.isDispensaryDeskRole(role), isFalse, reason: '$role');
    }
  });

  test('the gate starts inactive', () {
    expect(LanFirestoreGate.active, isFalse);
  });
}
