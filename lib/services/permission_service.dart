// lib/services/permission_service.dart
import 'package:flutter/foundation.dart';

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
  manageAssets,
  
  // Data
  downloadData,
  
  // Madrassa
  manageMadrassa,
  manageMadrassaAdmin,
  viewMadrassaParent,
  
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
    
    // Branch Manager — locked to their own branch only
    'branch manager': {
      AppPermission.viewBranchSpecificStats, // own branch summary only
      AppPermission.reverseTokens, 
      AppPermission.manageInventory, 
      AppPermission.manageStock, 
      AppPermission.manageAssets, 
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
      AppPermission.manageAssets,
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
}
