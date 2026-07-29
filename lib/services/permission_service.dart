// lib/services/permission_service.dart

enum AppPermission {
  // Global / Executive
  viewExecutiveDashboard,
  manageBranches,
  viewAllBranchesStats,
  
  // User Management
  manageUsers,
  
  // Donations
  viewDonations,
  manageDonations,
  
  // Patients & Dispensary
  viewPatients,
  registerPatients,
  viewTodayTokens,
  prescribeMedicine,
  dispenseMedicine,
  reverseTokens,
  
  // Inventory
  viewInventory,
  manageInventory,
  adjustStock,
  
  // Reports
  viewReports,
  viewBranchSpecificStats,
  
  // Dasterkhwaan
  generateFoodTokens,
  viewKitchenOrders,
  manageKitchen,
  
  // Assets & Stock
  manageStock,
  manageFinance,
  voidFinanceRecord,
  transferEmployeeBranch,
  
  // Data
  downloadData,
  
  // Madrassa
  manageMadrassa,
  manageMadrassaAdmin,
  viewMadrassaParent,
  
  // School
  manageSchool,
  manageSchoolAdmin,
  manageSchoolLibrary,
  
  // System
  syncData,
  manageSettings,
}

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// Maps role strings to a set of permissions.
  /// This can be moved to a separate config file later.
  final Map<String, Set<AppPermission>> _rolePermissions = {
    // Executive Roles
    'admin': AppPermission.values.toSet(),
    'ceo': AppPermission.values.toSet(),
    'chairman': AppPermission.values.toSet(),
    'hq manager': AppPermission.values.toSet(),
    'manager': AppPermission.values.toSet(),
    'global admin': AppPermission.values.toSet(),
    
    // Global Accounts - focused on financial entries, payouts, audits
    'global accounts': {
      AppPermission.manageFinance,
      AppPermission.voidFinanceRecord,
      AppPermission.viewBranchSpecificStats,
      AppPermission.viewReports,
      AppPermission.downloadData,
      AppPermission.viewDonations,
    },
    
    // Branch Manager — locked to their own branch only
    'branch manager': {
      AppPermission.viewBranchSpecificStats, // own branch summary only
      AppPermission.reverseTokens, 
      AppPermission.manageInventory, 
      AppPermission.manageStock, 
      AppPermission.manageFinance, 
      AppPermission.voidFinanceRecord,
      AppPermission.viewDonations, 
      AppPermission.manageDonations, 
      AppPermission.manageKitchen, 
      AppPermission.generateFoodTokens, 
      AppPermission.manageMadrassa, 
      AppPermission.manageMadrassaAdmin, // Added for full Madrassa Admin view
      AppPermission.viewPatients,        // Added for Patients list
      AppPermission.registerPatients,    // Added for Registration
      AppPermission.downloadData,        // Added for Downloads
    },
    
    // Supervisor — locked to their own branch only
    'supervisor': {
      AppPermission.viewBranchSpecificStats, // own branch summary only
      AppPermission.reverseTokens, 
      AppPermission.manageInventory, 
      AppPermission.manageStock, 
      AppPermission.manageFinance,
      AppPermission.manageMadrassaAdmin, // Added for full Madrassa Admin view
      AppPermission.viewPatients,        // Added for Patients list
      AppPermission.registerPatients,    // Added for Registration
      AppPermission.downloadData,        // Added for Downloads
    },
    
    'doctor': {
      AppPermission.viewPatients,
      AppPermission.viewTodayTokens,
      AppPermission.prescribeMedicine,
    },
    
    'receptionist': {
      AppPermission.viewPatients,
      AppPermission.registerPatients,
      AppPermission.viewTodayTokens,
    },
    
    'dispenser': {
      AppPermission.viewPatients,
      AppPermission.viewTodayTokens,
      AppPermission.dispenseMedicine,
      AppPermission.viewInventory,
    },
    
    'rec+dis': {
      AppPermission.viewPatients,
      AppPermission.registerPatients,
      AppPermission.viewTodayTokens,
      AppPermission.dispenseMedicine,
      AppPermission.viewInventory,
    },
    
    'doc+rec': {
      AppPermission.viewPatients,
      AppPermission.viewTodayTokens,
      AppPermission.prescribeMedicine,
      AppPermission.registerPatients,
    },
    
    'doc+dis': {
      AppPermission.viewPatients,
      AppPermission.viewTodayTokens,
      AppPermission.prescribeMedicine,
      AppPermission.dispenseMedicine,
      AppPermission.viewInventory,
    },
    
    'doc+rec+dis': {
      AppPermission.viewPatients,
      AppPermission.viewTodayTokens,
      AppPermission.prescribeMedicine,
      AppPermission.registerPatients,
      AppPermission.dispenseMedicine,
      AppPermission.viewInventory,
    },
    
    'server': {
      AppPermission.generateFoodTokens,
      AppPermission.viewKitchenOrders,
      AppPermission.syncData,
    },
    
    'office boy': {
      AppPermission.generateFoodTokens,
      AppPermission.viewDonations,
      AppPermission.manageDonations,
    },
    
    'kitchen': {
      AppPermission.viewKitchenOrders,
    },
    
    'donations': {
      AppPermission.viewDonations,
      AppPermission.manageDonations,
    },
    
    'madrassa admin': {
      AppPermission.manageMadrassa,
      AppPermission.manageMadrassaAdmin,
    },
    
    'madrassa teacher': {
      AppPermission.manageMadrassa,
    },
    
    'madrassa guardian': {
      AppPermission.viewMadrassaParent,
    },
    
    // School Roles
    'principal': {
      AppPermission.manageSchool,
      AppPermission.manageSchoolAdmin,
      AppPermission.manageSchoolLibrary,
      AppPermission.viewReports,
      AppPermission.downloadData,
    },
    
    'school admin': {
      AppPermission.manageSchool,
      AppPermission.manageSchoolAdmin,
      AppPermission.manageSchoolLibrary,
    },
    
    'school teacher': {
      AppPermission.manageSchool,
    },
  };

  bool hasPermission(String role, AppPermission permission) {
    final normalizedRole = role.toLowerCase().trim();
    final permissions = _rolePermissions[normalizedRole];
    if (permissions == null) return false;
    return permissions.contains(permission);
  }

  Set<AppPermission> getPermissionsForRole(String role) {
    final normalizedRole = role.toLowerCase().trim();
    return _rolePermissions[normalizedRole] ?? {};
  }

  // ── GMWF Finance v2 RBAC matrix checks ──────────────────────────────────────
  
  static const List<String> financeRoles = [
    'chairman', 'ceo', 'admin', 'hq manager', 'branch manager', 'global accounts'
  ];

  /// Checks if a role is allowed to open the GMWF Finance module.
  bool isFinanceUser(String role) {
    return financeRoles.contains(role.toLowerCase().trim());
  }

  /// Mark attendance (own branch)
  FinanceAccess getAttendanceAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':
      case 'branch manager':
      case 'hq manager':
      case 'admin':
      case 'ceo':
        return FinanceAccess.full;
      default:
        return FinanceAccess.none;
    }
  }

  /// Add/edit employee profile
  FinanceAccess getEmployeeProfileAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':
      case 'branch manager':
      case 'hq manager':
      case 'admin':
      case 'ceo':
        return FinanceAccess.full;
      default:
        return FinanceAccess.none;
    }
  }

  /// Approve salary change
  FinanceAccess getSalaryApprovalAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'ceo':
      case 'chairman':
        return FinanceAccess.full;
      case 'branch manager':
      case 'hq manager':
        return FinanceAccess.requestOnly;
      default:
        return FinanceAccess.none;
    }
  }

  /// Run payroll payout
  FinanceAccess getPayrollPayoutAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':
      case 'global accounts':
      case 'admin':
      case 'ceo':
        return FinanceAccess.full;
      case 'hq manager':
        return FinanceAccess.requestOnly;
      default:
        return FinanceAccess.none;
    }
  }

  /// Record/void expense entry
  FinanceAccess getExpenseAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':
      case 'branch manager':
      case 'hq manager':
      case 'global accounts':
      case 'admin':
      case 'ceo':
        return FinanceAccess.full;
      default:
        return FinanceAccess.none;
    }
  }

  /// Issue/close a loan
  FinanceAccess getLoanAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':
      case 'global accounts':
      case 'admin':
      case 'ceo':
      case 'hq manager':
        return FinanceAccess.full;
      case 'branch manager':
        return FinanceAccess.requestOnly;
      default:
        return FinanceAccess.none;
    }
  }

  /// Void a ledger entry
  FinanceAccess getLedgerVoidAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':
      case 'global accounts':
      case 'admin':
      case 'ceo':
      case 'hq manager':
        return FinanceAccess.full;
      default:
        return FinanceAccess.none;
    }
  }

  /// Lock/unlock a payroll period
  FinanceAccess getPeriodLockAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'ceo':
      case 'chairman':
      case 'admin':
      case 'hq manager':
        return FinanceAccess.full;
      case 'global accounts':
        return FinanceAccess.requestOnly;
      default:
        return FinanceAccess.none;
    }
  }

  /// Manage user accounts/roles
  FinanceAccess getUserManagementAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':
      case 'admin':
      case 'ceo':
      case 'hq manager':
        return FinanceAccess.full;
      default:
        return FinanceAccess.none;
    }
  }

  /// Resolve sync conflicts
  FinanceAccess getSyncConflictAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':
      case 'global accounts':
      case 'admin':
      case 'ceo':
      case 'hq manager':
        return FinanceAccess.full;
      default:
        return FinanceAccess.none;
    }
  }

  /// Bank reconciliation
  FinanceAccess getBankReconciliationAccess(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':
      case 'global accounts':
        return FinanceAccess.full;
      case 'hq manager':
      case 'admin':
      case 'ceo':
        return FinanceAccess.viewOnly;
      default:
        return FinanceAccess.none;
    }
  }

  /// View audit trail scope: returns 'none', 'own', or 'all'
  String getAuditTrailScope(String role) {
    switch (role.toLowerCase().trim()) {
      case 'branch manager':
        return 'own';
      case 'hq manager':
      case 'global accounts':
      case 'admin':
      case 'ceo':
      case 'chairman':
        return 'all';
      default:
        return 'none';
    }
  }
}

enum FinanceAccess {
  none,
  viewOnly,
  requestOnly,
  full,
}
