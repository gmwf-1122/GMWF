// lib/pages/pages/office/employee_form_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/finance_ledger_storage.dart';
import '../../services/zkteco_network_service.dart';

import '../../services/image_upload_service.dart';
import '../../utils/formatters.dart';
import 'shared_widgets.dart';

void openEmployeeFormSheet(
  BuildContext context, {
  required String activeBranchId,
  required List<Map<String, dynamic>> branches,
  String? employeeId,
  VoidCallback? onSaved,
}) {
  final tOriginal = RoleThemeScope.dataOf(context);
  final t = RoleThemeData(
    roleLabel: tOriginal.roleLabel,
    isDarkCanvas: false,
    bg: const Color(0xFFF8FAFC),
    bgCard: Colors.white,
    bgCardAlt: const Color(0xFFF1F5F9),
    bgRule: const Color(0xFFE2E8F0),
    accent: const Color(0xFF10B981),
    accentLight: const Color(0xFF34D399),
    accentMuted: const Color(0xFFD1FAE5),
    accentGradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
    glassTint: const Color(0x1A10B981),
    textPrimary: const Color(0xFF111827),
    textSecondary: const Color(0xFF6B7280),
    textTertiary: const Color(0xFF9CA3AF),
    danger: const Color(0xFFEF4444),
    zakat: tOriginal.zakat,
    nonZakat: tOriginal.nonZakat,
    gmwf: tOriginal.gmwf,
    cardFillTokens: tOriginal.cardFillTokens,
    cardFillPrescriptions: tOriginal.cardFillPrescriptions,
    cardFillDispensary: tOriginal.cardFillDispensary,
    chartBar1: tOriginal.chartBar1,
    chartBar2: tOriginal.chartBar2,
    chartBar3: tOriginal.chartBar3,
    chartGrid: tOriginal.chartGrid,
  );
  final isEdit = employeeId != null;
  final Map<String, dynamic> existing = isEdit ? FinanceLocalStorage.getEmployee(employeeId)! : {};

  final String initialBank = existing['bankName']?.toString() ??
      (isEdit
          ? ((existing['bankName'] == 'Cash' || (existing['bankName'] == null && existing['bankAccount'] == null))
              ? 'Cash'
              : 'Meezan Bank Limited')
          : 'Meezan Bank Limited');

  final nameController = TextEditingController(text: existing['name'] ?? '');
  final phoneController = TextEditingController(text: existing['phone'] ?? '');
  final alternatePhoneController = TextEditingController(text: existing['alternatePhone'] ?? '');
  final relationshipController = TextEditingController(text: existing['relationshipName'] ?? '');
  final addressController = TextEditingController(text: existing['currentAddress'] ?? '');
  
  final double initialSalary = existing['currentSalaryMinor'] != null
      ? (existing['currentSalaryMinor'] as int) / 100.0
      : (existing['currentSalary'] as num?)?.toDouble() ?? 0.0;
  final double initialInstallment = existing['monthlyAdvanceInstallmentMinor'] != null
      ? (existing['monthlyAdvanceInstallmentMinor'] as int) / 100.0
      : (existing['monthlyAdvanceInstallment'] as num?)?.toDouble() ?? 0.0;

  // Persist raw salary text so they can enter TBD/temp strings
  final salaryController = TextEditingController(
    text: existing['salaryText']?.toString() ?? (initialSalary > 0 ? initialSalary.toStringAsFixed(0) : ''),
  );
  final bankNameController = TextEditingController(text: initialBank);
  final bankAccountController = TextEditingController(text: existing['bankAccount'] ?? '');
  final educationController = TextEditingController(text: existing['education'] ?? '');
  final monthlyInstallmentController = TextEditingController(text: initialInstallment > 0 ? initialInstallment.toStringAsFixed(0) : '');

  final cnicController = TextEditingController(text: existing['cnic'] ?? '');
  final cnicExpiryController = TextEditingController(
      text: existing['cnicExpiry'] != null && existing['cnicExpiry'].toString().isNotEmpty
          ? DateFormat('yyyy-MM-dd').format(DateTime.parse(existing['cnicExpiry']))
          : '');
  final dobController = TextEditingController(
      text: existing['dob'] != null && existing['dob'].toString().isNotEmpty
          ? DateFormat('yyyy-MM-dd').format(DateTime.parse(existing['dob']))
          : '');
  final joiningController = TextEditingController(
      text: existing['joiningDate'] != null && existing['joiningDate'].toString().isNotEmpty
          ? DateFormat('yyyy-MM-dd').format(DateTime.parse(existing['joiningDate']))
          : '');

  final existingCred = isEdit ? ZkTecoNetworkService.getCredentialByEntityId(employeeId!) : null;
  final initialPin = existingCred?.biometricPin ?? existing['biometricPin']?.toString() ?? '';
  final biometricPinController = TextEditingController(text: initialPin);

  String selectedBranchId = existing['branchId']?.toString() ?? activeBranchId;
  String compensationType = existing['compensationType'] ?? 'monthly';
  String maritalStatus = existing['maritalStatus'] ?? 'Single';
  String role = existing['role'] ?? 'Office Boy';
  String department = existing['department'] ?? 'Office';
  String relationshipType = existing['relationshipType'] ?? 'Father';
  String gender = existing['gender'] ?? 'Male';
  String paymentMethod = isEdit
      ? ((existing['bankName'] == 'Cash' || (existing['bankName'] == null && existing['bankAccount'] == null))
          ? 'Cash'
          : 'Bank Transfer')
      : 'Bank Transfer';
  String selectedBank = initialBank;

  final winterShiftController = TextEditingController(text: existing['workScheduleOverride']?['winter'] ?? '');
  final summerShiftController = TextEditingController(text: existing['workScheduleOverride']?['summer'] ?? '');

  List<Map<String, String>> emergencyContacts = List<Map<String, dynamic>>.from(existing['emergencyContacts'] ?? [])
      .map((e) => {
            'name': e['name']?.toString() ?? '',
            'relation': e['relation']?.toString() ?? '',
            'phone': e['phone']?.toString() ?? '',
          })
      .toList();

  String? existingProfileUrl = existing['profilePictureUrl']?.toString();
  String? existingIdFrontUrl = existing['identificationUrl']?.toString();
  String? existingIdBackUrl  = existing['identificationBackUrl']?.toString();

  XFile? selectedProfileFile;
  XFile? selectedIdFrontFile;
  XFile? selectedIdBackFile;
  bool isSaving = false;

  Widget buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    required RoleThemeData theme,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      return RoleThemeScope(
        role: RoleTheme.admin,
        child: StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final isNarrow = MediaQuery.of(sheetCtx).size.width < 600;
            
            final List<String> rolesList = List<String>.from(FinanceLocalStorage.getRolesForDepartment(department));
            final curUserRole = RoleThemeScope.dataOf(context).roleLabel.toLowerCase().trim();
            if (curUserRole != 'chairman') {
              rolesList.removeWhere((r) => r.toLowerCase().trim() == 'chairman');
            }
            if (!rolesList.contains(role)) rolesList.add(role);
            if (!rolesList.contains('+ Add Custom Role...')) rolesList.add('+ Add Custom Role...');

            final List<String> deptsList = FinanceLedgerStorage.sortDepartmentsCanonical(
              ['Administration Staff', 'Office', 'Dasterkhwaan', 'Dispensary', 'Madrassa', 'School']
                ..addAll(FinanceLocalStorage.getCustomDepartments())
            );
            if (!deptsList.contains(department)) deptsList.add(department);
            if (!deptsList.contains('+ Add Custom Department...')) deptsList.add('+ Add Custom Department...');


            return Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Container(
                  padding: EdgeInsets.only(
                      top: 20, left: 16, right: 16, bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(isEdit ? 'Edit Employee Profile' : 'Add Employee',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: t.textPrimary)),
                                const SizedBox(height: 2),
                                Text(isEdit ? 'Update details of this employee' : 'Fill in the details below to register a new employee',
                                    style: TextStyle(fontSize: 11, color: t.textSecondary)),
                              ],
                            ),
                            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Assigned Branch card
                        StatefulBuilder(
                          builder: (branchCtx, setBranchState) {
                            final allBranches = FinanceLocalStorage.getAllBranches(branches)
                                .where((b) {
                                  final id = b['id']?.toString() ?? '';
                                  return id != 'karachi-2' && id != 'karachi2';
                                }).toList();

                            final List<String> dropdownItems = allBranches.map((b) => b['id']?.toString() ?? '').toList();
                            if (!dropdownItems.contains('+ Add Custom Branch...')) {
                              dropdownItems.add('+ Add Custom Branch...');
                            }

                            if (!dropdownItems.contains(selectedBranchId)) {
                              if (dropdownItems.isNotEmpty) {
                                selectedBranchId = dropdownItems.first;
                              }
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: t.accent.withOpacity(0.35), width: 1.2),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.business_outlined, color: t.accent, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Assigned Branch *',
                                        style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: selectedBranchId,
                                    dropdownColor: t.bgCard,
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: t.bgRule),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                                    items: dropdownItems.map((id) {
                                      if (id == '+ Add Custom Branch...') {
                                        return const DropdownMenuItem(
                                          value: '+ Add Custom Branch...',
                                          child: Text('+ Add Custom Branch...', style: TextStyle(fontWeight: FontWeight.bold)),
                                        );
                                      }
                                      final b = allBranches.firstWhereOrNull((x) => x['id'] == id);
                                      String name = b?['name']?.toString() ?? id;
                                      if (id == 'karachi-1' || id == 'karachi1') {
                                        name = 'Karachi';
                                      }
                                      return DropdownMenuItem(value: id, child: Text('$name ($id)'));
                                    }).toList(),
                                    onChanged: isEdit ? null : (val) {
                                      if (val == '+ Add Custom Branch...') {
                                        showCustomBranchDialog(
                                          context: sheetCtx,
                                          theme: t,
                                          onAdded: (newId, newName) {
                                            setSheetState(() {
                                              selectedBranchId = newId;
                                            });
                                            setBranchState(() {});
                                          },
                                        );
                                      } else {
                                        setSheetState(() => selectedBranchId = val ?? selectedBranchId);
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Select the branch where this employee will be working.',
                                    style: TextStyle(color: t.accent, fontSize: 10),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        // Documents & Pictures Section
                        buildSectionCard(
                          title: 'Media & Documents',
                          icon: Icons.camera_alt_outlined,
                          color: const Color(0xFF6366F1),
                          theme: t,
                          child: StatefulBuilder(
                            builder: (mediaCtx, setMediaState) {
                              return Column(
                                children: [
                                  // Profile Image Row
                                  _buildMediaPickerRow(
                                    label: 'Profile Picture',
                                    existingUrl: existingProfileUrl,
                                    selectedFile: selectedProfileFile,
                                    onPick: () async {
                                      final source = await ImageUploadService.showSourceDialog(context, title: 'Select Profile Picture Source');
                                      if (source == null) return;
                                      final b64 = await ImageUploadService.pickAndProcessImage(source: source, quality: 80);
                                      if (b64 != null && b64.isNotEmpty) {
                                        setSheetState(() {
                                          existingProfileUrl = b64;
                                          selectedProfileFile = null;
                                        });
                                        setMediaState(() {});
                                      }
                                    },
                                    onClear: () {
                                      setSheetState(() {
                                        selectedProfileFile = null;
                                        existingProfileUrl = null;
                                      });
                                      setMediaState(() {});
                                    },
                                    theme: t,
                                  ),
                                  const SizedBox(height: 12),
                                  // ID Front Row
                                  _buildMediaPickerRow(
                                    label: 'ID Card (Front)',
                                    existingUrl: existingIdFrontUrl,
                                    selectedFile: selectedIdFrontFile,
                                    onPick: () async {
                                      final source = await ImageUploadService.showSourceDialog(context, title: 'Select ID Card Front Source');
                                      if (source == null) return;
                                      final b64 = await ImageUploadService.pickAndProcessImage(source: source, quality: 80);
                                      if (b64 != null && b64.isNotEmpty) {
                                        setSheetState(() {
                                          existingIdFrontUrl = b64;
                                          selectedIdFrontFile = null;
                                        });
                                        setMediaState(() {});
                                      }
                                    },
                                    onClear: () {
                                      setSheetState(() {
                                        selectedIdFrontFile = null;
                                        existingIdFrontUrl = null;
                                      });
                                      setMediaState(() {});
                                    },
                                    theme: t,
                                  ),
                                  const SizedBox(height: 12),
                                  // ID Back Row
                                  _buildMediaPickerRow(
                                    label: 'ID Card (Back)',
                                    existingUrl: existingIdBackUrl,
                                    selectedFile: selectedIdBackFile,
                                    onPick: () async {
                                      final source = await ImageUploadService.showSourceDialog(context, title: 'Select ID Card Back Source');
                                      if (source == null) return;
                                      final b64 = await ImageUploadService.pickAndProcessImage(source: source, quality: 80);
                                      if (b64 != null && b64.isNotEmpty) {
                                        setSheetState(() {
                                          existingIdBackUrl = b64;
                                          selectedIdBackFile = null;
                                        });
                                        setMediaState(() {});
                                      }
                                    },
                                    onClear: () {
                                      setSheetState(() {
                                        selectedIdBackFile = null;
                                        existingIdBackUrl = null;
                                      });
                                      setMediaState(() {});
                                    },
                                    theme: t,
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        // 1. Personal Information Section
                        buildSectionCard(
                          title: '1. Personal Information',
                          icon: Icons.person_outline,
                          color: const Color(0xFF059669),
                          theme: t,
                          child: Column(
                            children: [
                              buildFormField(controller: nameController, label: 'Full Name *', icon: Icons.person_outline, theme: t),
                              const SizedBox(height: 10),
                              buildResponsiveFieldRow(
                                isNarrow: isNarrow,
                                children: [
                                  Expanded(
                                    child: buildDropdownField(
                                      label: 'Gender',
                                      value: gender,
                                      items: const ['Male', 'Female'],
                                      onChanged: (val) {
                                        setSheetState(() {
                                          gender = val!;
                                          if (gender == 'Male') {
                                            relationshipType = 'Father';
                                          }
                                        });
                                      },
                                      theme: t,
                                    ),
                                  ),
                                  Expanded(
                                    child: buildDatePickerField(
                                      context: sheetCtx,
                                      controller: dobController,
                                      label: 'Date of Birth',
                                      icon: Icons.calendar_today,
                                      theme: t,
                                    ),
                                  ),
                                ],
                              ),
                              buildResponsiveFieldRow(
                                isNarrow: isNarrow,
                                children: [
                                  Expanded(
                                    child: buildFormField(
                                      controller: phoneController,
                                      label: 'Primary Phone (11 digits)',
                                      icon: Icons.phone,
                                      theme: t,
                                      keyboardType: TextInputType.phone,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(11),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: buildFormField(
                                      controller: alternatePhoneController,
                                      label: 'Alternate Phone (11 digits)',
                                      icon: Icons.phone_android,
                                      theme: t,
                                      keyboardType: TextInputType.phone,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(11),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              buildResponsiveFieldRow(
                                isNarrow: isNarrow,
                                children: [
                                  Expanded(
                                    child: buildDropdownField(
                                      label: 'Marital Status',
                                      value: maritalStatus,
                                      items: const ['Single', 'Married', 'Divorced', 'Widowed'],
                                      onChanged: (val) => setSheetState(() => maritalStatus = val!),
                                      theme: t,
                                    ),
                                  ),
                                  Expanded(
                                    child: buildFormField(
                                      controller: cnicController,
                                      label: 'CNIC (Optional)',
                                      icon: Icons.credit_card,
                                      theme: t,
                                      inputFormatters: [CNICInputFormatter()],
                                    ),
                                  ),
                                ],
                              ),
                              buildResponsiveFieldRow(
                                isNarrow: isNarrow,
                                children: [
                                  Expanded(
                                    child: buildDatePickerField(
                                      context: sheetCtx,
                                      controller: cnicExpiryController,
                                      label: 'CNIC Expiry Date',
                                      icon: Icons.calendar_month,
                                      theme: t,
                                    ),
                                  ),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: buildDropdownField(
                                            label: 'Relation',
                                            value: relationshipType,
                                            items: gender == 'Male' ? const ['Father'] : const ['Father', 'Spouse'],
                                            onChanged: (val) => setSheetState(() => relationshipType = val!),
                                            theme: t,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 3,
                                          child: buildFormField(
                                            controller: relationshipController,
                                            label: '$relationshipType Name',
                                            icon: Icons.people_outline,
                                            theme: t,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              buildFormField(
                                  controller: addressController, label: 'Current Address', icon: Icons.home_outlined, theme: t, maxLines: 2),
                              const SizedBox(height: 10),
                              buildFormField(controller: educationController, label: 'Highest Education / Degree', icon: Icons.school, theme: t),
                            ],
                          ),
                        ),

                        // 2. Employment Details Section
                        buildSectionCard(
                          title: '2. Employment Details',
                          icon: Icons.work_outline,
                          color: const Color(0xFF0D9488),
                          theme: t,
                          child: Column(
                            children: [
                              buildResponsiveFieldRow(
                                isNarrow: isNarrow,
                                children: [
                                  Expanded(
                                    child: buildDropdownField(
                                      label: 'Role',
                                      value: role,
                                      items: rolesList,
                                      onChanged: (val) {
                                        if (val == '+ Add Custom Role...') {
                                          showAddCustomDialog(
                                            context: sheetCtx,
                                            title: 'Add Custom Role',
                                            hint: 'Enter custom role name',
                                            onAdded: (newVal) async {
                                              if (newVal.isNotEmpty) {
                                                await FinanceLocalStorage.addCustomRoleForDepartment(department, newVal);
                                                setSheetState(() {
                                                  role = newVal;
                                                });
                                              }
                                            },
                                            theme: t,
                                          );
                                        } else {
                                          setSheetState(() => role = val!);
                                        }
                                      },
                                      theme: t,
                                    ),
                                  ),
                                  Expanded(
                                    child: buildDropdownField(
                                      label: 'Department',
                                      value: department,
                                      items: deptsList,
                                      onChanged: (val) {
                                        if (val == '+ Add Custom Department...') {
                                          showAddCustomDialog(
                                            context: sheetCtx,
                                            title: 'Add Custom Department',
                                            hint: 'Enter custom department name',
                                            onAdded: (newVal) async {
                                              if (newVal.isNotEmpty) {
                                                await FinanceLocalStorage.addCustomDepartment(newVal);
                                                setSheetState(() {
                                                  department = newVal;
                                                  final newRoles = FinanceLocalStorage.getRolesForDepartment(newVal);
                                                  role = newRoles.isNotEmpty ? newRoles.first : 'Staff';
                                                });
                                              }
                                            },
                                            theme: t,
                                          );
                                        } else {
                                          setSheetState(() {
                                            department = val!;
                                            final newRoles = FinanceLocalStorage.getRolesForDepartment(val);
                                            role = newRoles.isNotEmpty ? newRoles.first : 'Staff';
                                          });
                                        }
                                      },
                                      theme: t,
                                    ),
                                  ),
                                ],
                              ),
                              buildResponsiveFieldRow(
                                isNarrow: isNarrow,
                                children: [
                                  Expanded(
                                    child: buildDatePickerField(
                                      context: sheetCtx,
                                      controller: joiningController,
                                      label: 'Joining Date',
                                      icon: Icons.login,
                                      theme: t,
                                    ),
                                  ),
                                  Expanded(
                                    child: buildDropdownField(
                                      label: 'Pay Type',
                                      value: compensationType == 'monthly'
                                          ? 'Monthly'
                                          : (compensationType == 'hourly' ? 'Hourly' : 'Contract'),
                                      items: const ['Monthly', 'Hourly', 'Contract'],
                                      onChanged: (val) => setSheetState(() {
                                        if (val == 'Monthly') compensationType = 'monthly';
                                        if (val == 'Hourly') compensationType = 'hourly';
                                        if (val == 'Contract') compensationType = 'contract';
                                      }),
                                      theme: t,
                                    ),
                                  ),
                                ],
                              ),
                              buildResponsiveFieldRow(
                                isNarrow: isNarrow,
                                children: [
                                  Expanded(
                                    child: buildFormField(
                                      controller: biometricPinController,
                                      label: 'Biometric Scanner PIN',
                                      icon: Icons.fingerprint_rounded,
                                      theme: t,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 14.0, left: 4.0),
                                      child: Text(
                                        'Numeric PIN for physical ZKTeco fingerprint/face scanners (e.g. 159). Must be unique.',
                                        style: TextStyle(color: t.textSecondary, fontSize: 11),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              
                              // Highlighted Salary Box with helper subtitle
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: t.bgCardAlt,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.4), width: 1.2),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.payments_outlined, color: Color(0xFF0D9488), size: 18),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Base Salary (PKR) *',
                                          style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Text('PKR', style: TextStyle(fontWeight: FontWeight.bold, color: t.textSecondary, fontSize: 13)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: salaryController,
                                            keyboardType: TextInputType.text,
                                            style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                                            decoration: const InputDecoration(
                                              hintText: '0.00',
                                              isDense: true,
                                              border: InputBorder.none,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Monthly salary before deductions',
                                      style: TextStyle(color: t.textSecondary, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 3. Financial & Bank Details Section
                        buildSectionCard(
                          title: '3. Financial & Bank Details',
                          icon: Icons.account_balance_outlined,
                          color: const Color(0xFF2563EB),
                          theme: t,
                          child: Column(
                            children: [
                              buildDropdownField(
                                label: 'Payment Method *',
                                value: paymentMethod,
                                items: const ['Bank Transfer', 'Cash'],
                                onChanged: (val) {
                                  setSheetState(() {
                                    paymentMethod = val!;
                                    if (paymentMethod == 'Cash') {
                                      selectedBank = 'Cash';
                                      bankNameController.text = 'Cash';
                                      bankAccountController.text = 'N/A';
                                    } else {
                                      selectedBank = 'Meezan Bank Limited';
                                      bankNameController.text = 'Meezan Bank Limited';
                                      if (bankAccountController.text == 'N/A') {
                                        bankAccountController.text = '';
                                      }
                                    }
                                  });
                                },
                                theme: t,
                              ),
                              const SizedBox(height: 10),
                              
                              // Load bank dropdown items
                              StatefulBuilder(
                                builder: (bankCtx, setBankState) {
                                  List<String> banksList = [
                                    'Habib Bank Limited (HBL)',
                                    'United Bank Limited (UBL)',
                                    'MCB Bank Limited (MCB)',
                                    'National Bank of Pakistan (NBP)',
                                    'Meezan Bank Limited',
                                    'Bank Alfalah Limited',
                                    'Allied Bank Limited (ABL)',
                                  ];
                                  banksList.addAll(FinanceLocalStorage.getCustomBanks());
                                  if (paymentMethod == 'Bank Transfer') {
                                    if (selectedBank == 'Cash') {
                                      selectedBank = 'Meezan Bank Limited';
                                    }
                                    if (!banksList.contains(selectedBank)) {
                                      banksList.add(selectedBank);
                                    }
                                    if (!banksList.contains('+ Add Custom Bank...')) {
                                      banksList.add('+ Add Custom Bank...');
                                    }
                                  } else {
                                    selectedBank = 'Cash';
                                    banksList = ['Cash'];
                                  }

                                  return buildResponsiveFieldRow(
                                    isNarrow: isNarrow,
                                    children: [
                                      Expanded(
                                        child: paymentMethod == 'Bank Transfer'
                                            ? buildDropdownField(
                                                label: 'Bank Name',
                                                value: selectedBank,
                                                items: banksList,
                                                onChanged: (val) {
                                                  if (val == '+ Add Custom Bank...') {
                                                    showAddCustomDialog(
                                                      context: sheetCtx,
                                                      title: 'Add Custom Bank',
                                                      hint: 'Enter bank name',
                                                      onAdded: (newVal) async {
                                                        if (newVal.isNotEmpty) {
                                                          await FinanceLocalStorage.addCustomBank(newVal);
                                                          setSheetState(() {
                                                            selectedBank = newVal;
                                                            bankNameController.text = newVal;
                                                          });
                                                        }
                                                      },
                                                      theme: t,
                                                    );
                                                  } else {
                                                    setSheetState(() {
                                                      selectedBank = val!;
                                                      bankNameController.text = val;
                                                    });
                                                  }
                                                },
                                                theme: t,
                                              )
                                            : buildFormField(
                                                controller: bankNameController,
                                                label: 'Bank Name',
                                                icon: Icons.account_balance,
                                                theme: t,
                                                enabled: false,
                                              ),
                                      ),
                                      Expanded(
                                        child: buildFormField(
                                          controller: bankAccountController,
                                          label: 'Account Number / IBAN',
                                          icon: Icons.numbers,
                                          theme: t,
                                          enabled: paymentMethod == 'Bank Transfer',
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              buildFormField(
                                controller: monthlyInstallmentController,
                                label: 'Monthly Advance Limit (Optional)',
                                icon: Icons.money_off,
                                theme: t,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              ),
                            ],
                          ),
                        ),

                        // 4. Work Schedule Section
                        buildSectionCard(
                          title: '4. Work Schedule (Optional)',
                          icon: Icons.watch_later_outlined,
                          color: const Color(0xFFEA580C),
                          theme: t,
                          child: buildResponsiveFieldRow(
                            isNarrow: isNarrow,
                            children: [
                              Expanded(
                                child: buildFormField(
                                  controller: winterShiftController,
                                  label: 'Winter Timing',
                                  icon: Icons.schedule,
                                  theme: t,
                                ),
                              ),
                              Expanded(
                                child: buildFormField(
                                  controller: summerShiftController,
                                  label: 'Summer Timing',
                                  icon: Icons.sunny,
                                  theme: t,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 5. Emergency Contacts Section
                        buildSectionCard(
                          title: '5. Emergency Contacts (Optional)',
                          icon: Icons.contact_phone_outlined,
                          color: const Color(0xFF7C3AED),
                          theme: t,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Contacts list (${emergencyContacts.length})',
                                    style: TextStyle(fontSize: 12, color: t.textSecondary, fontWeight: FontWeight.bold),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF7C3AED),
                                      side: const BorderSide(color: Color(0xFF7C3AED), width: 0.8),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    onPressed: () => setSheetState(() {
                                      emergencyContacts.add({'name': '', 'relation': '', 'phone': ''});
                                    }),
                                    icon: const Icon(Icons.add, size: 14),
                                    label: const Text('Add Contact', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  )
                                ],
                              ),
                              const SizedBox(height: 10),
                              ...emergencyContacts.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final contact = entry.value;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: t.bgCard,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: t.bgRule),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Contact #${idx + 1}',
                                              style: TextStyle(fontSize: 12, color: t.textSecondary, fontWeight: FontWeight.bold)),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                            onPressed: () => setSheetState(() => emergencyContacts.removeAt(idx)),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        style: TextStyle(color: t.textPrimary, fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'Contact Name',
                                          hintStyle: TextStyle(color: t.textTertiary),
                                          isDense: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        ),
                                        onChanged: (val) => contact['name'] = val,
                                        controller: TextEditingController(text: contact['name'])
                                          ..selection = TextSelection.fromPosition(TextPosition(offset: (contact['name'] ?? '').length)),
                                      ),
                                      const SizedBox(height: 8),
                                      buildResponsiveFieldRow(
                                        isNarrow: isNarrow,
                                        spacing: 8,
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              style: TextStyle(color: t.textPrimary, fontSize: 13),
                                              decoration: InputDecoration(
                                                hintText: 'Relation (e.g. Spouse)',
                                                hintStyle: TextStyle(color: t.textTertiary),
                                                isDense: true,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              ),
                                              onChanged: (val) => contact['relation'] = val,
                                              controller: TextEditingController(text: contact['relation'])
                                                ..selection = TextSelection.fromPosition(TextPosition(offset: (contact['relation'] ?? '').length)),
                                            ),
                                          ),
                                          Expanded(
                                            child: TextField(
                                              style: TextStyle(color: t.textPrimary, fontSize: 13),
                                              decoration: InputDecoration(
                                                hintText: 'Phone Number',
                                                hintStyle: TextStyle(color: t.textTertiary),
                                                isDense: true,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              ),
                                              keyboardType: TextInputType.phone,
                                              inputFormatters: [
                                                FilteringTextInputFormatter.digitsOnly,
                                                LengthLimitingTextInputFormatter(11),
                                              ],
                                              onChanged: (val) => contact['phone'] = val,
                                              controller: TextEditingController(text: contact['phone'])
                                                ..selection = TextSelection.fromPosition(TextPosition(offset: (contact['phone'] ?? '').length)),
                                            ),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Register button
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: isSaving
                              ? const SizedBox.shrink()
                              : const Icon(Icons.person_add, size: 16),
                          label: isSaving
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(isEdit ? 'Save Profile Changes' : 'Register Employee', style: const TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            if (isSaving) return;

                            // Validation checks: Only Name and Salary are strictly mandatory
                            if (nameController.text.trim().isEmpty) {
                              showCustomSnackBar(sheetCtx, 'Please fill in Name.', error: true);
                              return;
                            }

                            if (salaryController.text.trim().isEmpty) {
                              showCustomSnackBar(sheetCtx, 'Please fill in Base Salary.', error: true);
                              return;
                            }

                            final parsedSalary =
                                salaryController.text.trim().isNotEmpty ? double.tryParse(salaryController.text) ?? 0.0 : 0.0;
                            final parsedInstallment = monthlyInstallmentController.text.trim().isNotEmpty
                                ? double.tryParse(monthlyInstallmentController.text) ?? 0.0
                                : 0.0;
                            if (parsedInstallment > parsedSalary && parsedSalary > 0) {
                              showCustomSnackBar(
                                  sheetCtx,
                                  'Warning: Monthly Installment Limit (PKR ${NumberFormat('#,###').format(parsedInstallment)}) cannot exceed Base Salary (PKR ${NumberFormat('#,###').format(parsedSalary)}).',
                                  error: true);
                              return;
                            }

                            final validContacts =
                                emergencyContacts.where((e) => e['name']!.isNotEmpty && e['phone']!.isNotEmpty).toList();

                            final enteredPin = biometricPinController.text.trim();
                            if (enteredPin.isNotEmpty) {
                              final conflict = ZkTecoNetworkService.findPinConflict(enteredPin, excludeEntityId: isEdit ? employeeId : null);
                              if (conflict != null) {
                                showCustomSnackBar(
                                  sheetCtx,
                                  '❌ PIN $enteredPin is already assigned to "${conflict.entityName}" (${conflict.branchId.toUpperCase()} • ${conflict.entityType.toUpperCase()}). Please choose a unique PIN.',
                                  error: true,
                                );
                                return;
                              }
                            }

                            try {
                              setSheetState(() { isSaving = true; });

                              final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';

                              Map<String, dynamic>? scheduleOverride;
                              if (winterShiftController.text.isNotEmpty || summerShiftController.text.isNotEmpty) {
                                scheduleOverride = {
                                  'winter': winterShiftController.text,
                                  'summer': summerShiftController.text,
                                };
                              }

                              final empId = isEdit ? employeeId : 'emp_${DateTime.now().millisecondsSinceEpoch}';

                              String? profileUrl = existingProfileUrl;
                              String? idFrontUrl = existingIdFrontUrl;
                              String? idBackUrl  = existingIdBackUrl;

                              String? profilePath = existingProfileUrl == null ? null : (isEdit ? existing['profilePicturePath']?.toString() : null);
                              String? idFrontPath = existingIdFrontUrl == null ? null : (isEdit ? existing['identificationPath']?.toString() : null);
                              String? idBackPath  = existingIdBackUrl == null ? null : (isEdit ? existing['identificationBackPath']?.toString() : null);

                              Future<String?> saveFileLocally(XFile f, String name) async {
                                if (kIsWeb) return null;
                                try {
                                  final appSupportDir = await getApplicationSupportDirectory();
                                  final employeesDir = Directory('${appSupportDir.path}/employees/$empId');
                                  if (!await employeesDir.exists()) {
                                    await employeesDir.create(recursive: true);
                                  }
                                  final extension = f.name.split('.').last;
                                  final targetPath = '${employeesDir.path}/$name.$extension';
                                  final savedFile = await File(f.path).copy(targetPath);
                                  return savedFile.path;
                                } catch (e) {
                                  debugPrint('Local file copy failed: $e');
                                  return null;
                                }
                              }

                              Future<String?> uploadEmpFile(XFile f, String name) async {
                                try {
                                  final bytes = await f.readAsBytes();
                                  final b64 = ImageUploadService.processBytesToBase64(bytes);
                                  if (b64 != null && b64.isNotEmpty) return b64;
                                  final path = 'branches/$selectedBranchId/employees/$empId/$name.${f.name.split('.').last}';
                                  final ref = FirebaseStorage.instance.ref(path);
                                  await ref.putData(bytes);
                                  return await ref.getDownloadURL();
                                } catch (e) {
                                  debugPrint('File upload failed: $e');
                                  return null;
                                }
                              }

                              if (selectedProfileFile != null) {
                                profilePath = await saveFileLocally(selectedProfileFile!, 'profile');
                                profileUrl = await uploadEmpFile(selectedProfileFile!, 'profile');
                              }
                              if (selectedIdFrontFile != null) {
                                idFrontPath = await saveFileLocally(selectedIdFrontFile!, 'id_front');
                                idFrontUrl = await uploadEmpFile(selectedIdFrontFile!, 'id_front');
                              }
                              if (selectedIdBackFile != null) {
                                idBackPath = await saveFileLocally(selectedIdBackFile!, 'id_back');
                                idBackUrl = await uploadEmpFile(selectedIdBackFile!, 'id_back');
                              }

                              final employeeData = {
                                'localId': empId,
                                'name': nameController.text.trim(),
                                'dob': dobController.text.trim().isNotEmpty ? dobController.text.trim() : null,
                                'cnic': cnicController.text.trim(),
                                'cnicExpiry': cnicExpiryController.text.trim().isNotEmpty ? cnicExpiryController.text.trim() : null,
                                'gender': gender,
                                'phone': phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                                'alternatePhone': alternatePhoneController.text.isNotEmpty ? alternatePhoneController.text.trim() : null,
                                'relationshipType': relationshipType,
                                'relationshipName': relationshipController.text.trim().isNotEmpty ? relationshipController.text.trim() : null,
                                'maritalStatus': maritalStatus,
                                'role': role,
                                'department': department,
                                'joiningDate': joiningController.text.trim().isNotEmpty ? joiningController.text.trim() : null,
                                'compensationType': compensationType,
                                'currentSalary': parsedSalary,
                                'salaryText': salaryController.text.trim(), // Raw text (e.g. "temp")
                                'bankName': bankNameController.text.trim(),
                                'bankAccount': bankAccountController.text.trim(),
                                'education': educationController.text.isNotEmpty ? educationController.text.trim() : null,
                                'currentAddress': addressController.text.trim().isNotEmpty ? addressController.text.trim() : null,
                                'emergencyContacts': validContacts,
                                'workScheduleOverride': scheduleOverride,
                                'isActive': existing['isActive'] ?? true,
                                'biometricPin': enteredPin.isNotEmpty ? enteredPin : null,
                                'monthlyAdvanceInstallment': monthlyInstallmentController.text.trim().isNotEmpty
                                    ? double.tryParse(monthlyInstallmentController.text) ?? 0.0
                                    : 0.0,
                                'branchId': selectedBranchId,
                                'profilePictureUrl': profileUrl,
                                'profilePicturePath': profilePath,
                                'identificationUrl': idFrontUrl,
                                'identificationPath': idFrontPath,
                                'identificationBackUrl': idBackUrl,
                                'identificationBackPath': idBackPath,
                              };

                              final targetBranchId = isEdit ? (existing['branchId']?.toString() ?? activeBranchId) : selectedBranchId;
                              final empLocalId = await FinanceLocalStorage.saveEmployee(
                                branchId: targetBranchId,
                                data: employeeData,
                                performedBy: curUser,
                              );

                              if (enteredPin.isNotEmpty) {
                                await ZkTecoNetworkService.assignPinToEntity(
                                  entityId: empLocalId,
                                  entityName: nameController.text.trim(),
                                  entityType: 'employee',
                                  branchId: targetBranchId,
                                  customPin: enteredPin,
                                );
                              }

                              if (!isEdit) {
                                await FinanceLocalStorage.saveSalaryHistory(
                                  branchId: targetBranchId,
                                  employeeId: empLocalId,
                                  amount: parsedSalary,
                                  effectiveDate: joiningController.text.isNotEmpty ? DateTime.parse(joiningController.text) : DateTime.now(),
                                  reason: 'Initial onboarding salary configuration',
                                  approvedBy: curUser,
                                  performedBy: curUser,
                                );
                              } else if (existing['currentSalary'] != parsedSalary) {
                                await FinanceLocalStorage.saveSalaryHistory(
                                  branchId: activeBranchId,
                                  employeeId: empLocalId,
                                  amount: parsedSalary,
                                  effectiveDate: DateTime.now(),
                                  reason: 'Updated during employee profile modification',
                                  approvedBy: curUser,
                                  performedBy: curUser,
                                );
                              }

                              // Auto-assign biometric PIN & map credentials for hardware ZKTeco scanners
                              try {
                                await ZkTecoNetworkService.bulkAutoAssignBiometricPins();
                              } catch (e) {
                                debugPrint('[EmployeeForm] Auto-assign biometric PIN notice: $e');
                              }

                              if (sheetCtx.mounted) {
                                Navigator.pop(sheetCtx);
                                if (onSaved != null) onSaved();
                                showCustomSnackBar(context, '${nameController.text.trim()} profile saved successfully!');
                              }
                            } catch (e) {
                              setSheetState(() { isSaving = false; });
                              showCustomSnackBar(sheetCtx, e.toString().replaceAll('Exception: ', ''), error: true);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

void showCustomBranchDialog({
  required BuildContext context,
  required RoleThemeData theme,
  required void Function(String id, String name) onAdded,
}) {
  final idController = TextEditingController();
  final nameController = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: theme.bgCard,
        title: Text('Add Custom Branch', style: TextStyle(color: theme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idController,
              autofocus: true,
              style: TextStyle(color: theme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter Branch ID (e.g. lahore)',
                hintStyle: TextStyle(color: theme.textTertiary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.bgRule)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.accent)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              style: TextStyle(color: theme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter Branch Name (e.g. Lahore)',
                hintStyle: TextStyle(color: theme.textTertiary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.bgRule)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.accent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.accent),
            onPressed: () async {
              final id = idController.text.trim().toLowerCase();
              final name = nameController.text.trim();
              if (id.isNotEmpty && name.isNotEmpty) {
                await FinanceLocalStorage.addCustomBranch(id, name);
                Navigator.pop(ctx);
                onAdded(id, name);
              }
            },
            child: const Text('Add Branch', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    },
  );
}

Widget _buildMediaPickerRow({
  required String label,
  required String? existingUrl,
  required XFile? selectedFile,
  required VoidCallback onPick,
  required VoidCallback onClear,
  required RoleThemeData theme,
}) {
  final bool hasImage = selectedFile != null || (existingUrl != null && existingUrl.isNotEmpty);

  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: theme.bgCardAlt,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: theme.bgRule),
    ),
    child: Row(
      children: [
        // Thumbnail Preview
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: theme.bgRule,
            borderRadius: BorderRadius.circular(8),
            image: hasImage
                ? DecorationImage(
                    image: selectedFile != null
                        ? FileImage(File(selectedFile.path))
                        : (ImageUploadService.decodeBase64ToBytes(existingUrl) != null
                            ? MemoryImage(ImageUploadService.decodeBase64ToBytes(existingUrl)!)
                            : NetworkImage(existingUrl!) as ImageProvider),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: !hasImage
              ? Icon(Icons.image_outlined, color: theme.textTertiary, size: 20)
              : null,
        ),
        const SizedBox(width: 12),
        // Title & Status
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                selectedFile != null
                    ? 'Ready to upload'
                    : (existingUrl != null ? 'Uploaded' : 'No file chosen'),
                style: TextStyle(
                  color: selectedFile != null
                      ? theme.accent
                      : (existingUrl != null ? theme.textSecondary : theme.textTertiary),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // Action Buttons
        if (hasImage) ...[
          IconButton(
            icon: Icon(Icons.delete_outline, color: theme.danger, size: 20),
            onPressed: onClear,
          ),
        ] else ...[
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: theme.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            icon: const Icon(Icons.upload_file, size: 14),
            label: const Text('Choose', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: onPick,
          ),
        ],
      ],
    ),
  );
}
