import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/models/module_registry.dart';
import 'package:gmwf/services/user_module_access_service.dart';

void main() {
  test('Office modules exact order and HQ Manager exclusions test', () {
    // 1. Test HQ Manager exclusions in ModuleRegistry
    final hqModules = ModuleRegistry.getAvailableModules('hq manager');
    final hqIds = hqModules.map((m) => m.id).toList();

    expect(hqIds.contains('server_sync'), isFalse, reason: 'HQ Manager should not have Server Control');
    expect(hqIds.contains('office_boy'), isFalse, reason: 'HQ Manager should not have Office Boy');

    // 2. Test UserModuleAccessService for HQ Manager
    expect(UserModuleAccessService.canUserAccessModule(userId: 'u1', role: 'hq manager', moduleId: 'server_sync'), isFalse);
    expect(UserModuleAccessService.canUserAccessModule(userId: 'u1', role: 'hq manager', moduleId: 'office_boy'), isFalse);

    // 3. Test Chairman / Admin still has access
    final adminModules = ModuleRegistry.getAvailableModules('admin');
    final adminIds = adminModules.map((m) => m.id).toList();
    expect(adminIds.contains('server_sync'), isTrue);
    expect(adminIds.contains('office_boy'), isTrue);

    expect(UserModuleAccessService.canUserAccessModule(userId: 'u2', role: 'admin', moduleId: 'server_sync'), isTrue);
    expect(UserModuleAccessService.canUserAccessModule(userId: 'u2', role: 'admin', moduleId: 'office_boy'), isTrue);

    // 4. Test Office modules sequence in ModuleRegistry.allModules
    final officeModules = ModuleRegistry.allModules
        .where((m) => m.category == ModuleCategory.office)
        .map((m) => m.id)
        .toList();

    expect(officeModules[0], equals('finance'), reason: '1st module must be Finance Overview');
    expect(officeModules[1], equals('donations'), reason: '2nd module must be Donations');
    expect(officeModules[2], equals('branches_management'), reason: '3rd module must be Branches Management');
    expect(officeModules[3], equals('users'), reason: '4th module must be User Management');
    expect(officeModules[4], equals('employees'), reason: '5th module must be Employee Management');
    expect(officeModules[5], equals('employee_attendance'), reason: '6th module must be Employee Attendance');
  });
}
