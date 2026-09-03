import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/services/camp_session_service.dart';

void main() {
  test('Department-specific shift configs and timing resolution test', () {
    // 1. Dispensary default sessions
    final dispConfig = CampSessionService.getDefaultSessionConfig('karachi', 'dispensary');
    expect(dispConfig.containsKey('morning'), isTrue);
    expect(dispConfig.containsKey('evening'), isTrue);
    expect(dispConfig.containsKey('night'), isTrue);
    expect(dispConfig['morning']['openTime'], equals('08:00'));
    expect(dispConfig['morning']['closeTime'], equals('14:00'));
    expect(dispConfig['evening']['openTime'], equals('16:00'));
    expect(dispConfig['evening']['closeTime'], equals('22:00'));
    expect(dispConfig['night']['enabled'], isFalse);

    // 2. Dasterkhwaan default sessions (Breakfast/Morning, Lunch, Dinner, Night)
    final dastConfig = CampSessionService.getDefaultSessionConfig('sialkot', 'dasterkhwaan');
    expect(dastConfig.containsKey('morning'), isTrue);
    expect(dastConfig.containsKey('lunch'), isTrue);
    expect(dastConfig.containsKey('dinner'), isTrue);
    expect(dastConfig.containsKey('night'), isTrue);
    expect(dastConfig['morning']['openTime'], equals('06:00'));
    expect(dastConfig['morning']['closeTime'], equals('10:00'));
    expect(dastConfig['lunch']['openTime'], equals('12:00'));
    expect(dastConfig['lunch']['closeTime'], equals('16:00'));
    expect(dastConfig['dinner']['openTime'], equals('18:00'));
    expect(dastConfig['dinner']['closeTime'], equals('22:00'));

    // 3. Madrassa default sessions
    final madConfig = CampSessionService.getDefaultSessionConfig('sialkot', 'madrassa');
    expect(madConfig['morning']['openTime'], equals('06:00'));
    expect(madConfig['morning']['closeTime'], equals('12:00'));
    expect(madConfig['evening']['openTime'], equals('14:00'));
    expect(madConfig['evening']['closeTime'], equals('18:00'));

    // 4. School default sessions
    final schConfig = CampSessionService.getDefaultSessionConfig('sialkot', 'school');
    expect(schConfig['morning']['openTime'], equals('07:30'));
    expect(schConfig['morning']['closeTime'], equals('13:30'));

    // 5. Allowed sessions by department
    final dispAllowed = CampSessionService.getAllowedSessions('karachi', department: 'dispensary');
    expect(dispAllowed, containsAll(['morning', 'evening']));
    expect(dispAllowed.contains('night'), isFalse);

    final dastAllowed = CampSessionService.getAllowedSessions('karachi', department: 'dasterkhwaan');
    expect(dastAllowed, containsAll(['morning', 'lunch', 'dinner']));
    expect(dastAllowed.contains('night'), isFalse);

    // 6. Test Dasterkhwaan Shift Resolution at 13:00 (Lunch) and 19:00 (Dinner)
    final lunchTime = DateTime(2026, 8, 28, 13, 0);
    final lunchShift = CampSessionService.resolveShiftAndDateKey(lunchTime, 'karachi', 'dasterkhwaan');
    expect(lunchShift.session, equals('lunch'));

    final dinnerTime = DateTime(2026, 8, 28, 19, 0);
    final dinnerShift = CampSessionService.resolveShiftAndDateKey(dinnerTime, 'karachi', 'dasterkhwaan');
    expect(dinnerShift.session, equals('dinner'));

    // 7. Test Dispensary Shift Resolution at 13:00 (Morning) and 19:00 (Evening)
    final dispMorning = CampSessionService.resolveShiftAndDateKey(lunchTime, 'karachi', 'dispensary');
    expect(dispMorning.session, equals('morning'));

    final dispEvening = CampSessionService.resolveShiftAndDateKey(dinnerTime, 'karachi', 'dispensary');
    expect(dispEvening.session, equals('evening'));
  });
}
