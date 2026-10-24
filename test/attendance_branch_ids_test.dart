import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/services/finance_local_storage.dart';

/// Attendance is uploaded under the marking PC's branch spelling, so readers must query
/// every spelling of a branch ('grt' and 'gujrat', 'jalalpur_jattan' and 'jalalpurjattan').
void main() {
  test('every spelling of a branch maps to the same attendance branch ids', () {
    for (final id in ['gujrat', 'grt', 'GJT']) {
      expect(FinanceLocalStorage.attendanceBranchIds(id), containsAll(['gujrat', 'grt']));
    }
    for (final id in ['jalalpurjattan', 'jalalpur_jattan', 'jlj']) {
      expect(FinanceLocalStorage.attendanceBranchIds(id),
          containsAll(['jalalpurjattan', 'jalalpur_jattan']));
    }
    expect(FinanceLocalStorage.attendanceBranchIds('skt'), containsAll(['sialkot', 'skt']));
    expect(FinanceLocalStorage.attendanceBranchIds('khi'), contains('karachi'));
    expect(FinanceLocalStorage.attendanceBranchIds('haji_camp'), containsAll(['karachi', 'haji_camp']));
    expect(FinanceLocalStorage.attendanceBranchIds('newbranch'), ['newbranch']);
  });
}
