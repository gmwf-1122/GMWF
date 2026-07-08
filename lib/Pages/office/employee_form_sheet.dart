// lib/pages/office/employee_form_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../utils/formatters.dart';
import 'shared_widgets.dart';

void openEmployeeFormSheet(
  BuildContext context, {
  required String activeBranchId,
  required List<Map<String, dynamic>> branches,
  String? employeeId,
  VoidCallback? onSaved,
}) {
  final t = RoleThemeScope.dataOf(context);
  final isEdit = employeeId != null;
  final Map<String, dynamic> existing = isEdit ? FinanceLocalStorage.getEmployee(employeeId)! : {};

  final nameController = TextEditingController(text: existing['name'] ?? '');
  final phoneController = TextEditingController(text: existing['phone'] ?? '');
  final alternatePhoneController = TextEditingController(text: existing['alternatePhone'] ?? '');
  final relationshipController = TextEditingController(text: existing['relationshipName'] ?? '');
  final addressController = TextEditingController(text: existing['currentAddress'] ?? '');
  final salaryController = TextEditingController(text: existing['currentSalary']?.toString() ?? '');
  final bankNameController = TextEditingController(text: existing['bankName'] ?? '');
  final bankAccountController = TextEditingController(text: existing['bankAccount'] ?? '');
  final educationController = TextEditingController(text: existing['education'] ?? '');
  final monthlyInstallmentController = TextEditingController(text: existing['monthlyAdvanceInstallment']?.toString() ?? '');

  // CNIC masks / formatting
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

  String selectedBranchId = existing['branchId']?.toString() ?? activeBranchId;
  String compensationType = existing['compensationType'] ?? 'monthly';
  String maritalStatus = existing['maritalStatus'] ?? 'Single';
  String role = existing['role'] ?? 'Office Boy';
  String department = existing['department'] ?? 'Office';
  String relationshipType = existing['relationshipType'] ?? 'Father';
  String gender = existing['gender'] ?? (existing['relationshipType'] == 'Spouse' ? 'Female' : 'Male');
  if (gender == 'Male') {
    relationshipType = 'Father';
  }
  String paymentMethod = (existing['bankName'] == 'Cash' || (existing['bankName'] == null && existing['bankAccount'] == null))
      ? 'Cash'
      : 'Bank Transfer';

  // Shifts default
  final winterShiftController = TextEditingController(text: existing['workScheduleOverride']?['winter'] ?? '');
  final summerShiftController = TextEditingController(text: existing['workScheduleOverride']?['summer'] ?? '');

  // Emergency Contacts
  List<Map<String, String>> emergencyContacts = List<Map<String, dynamic>>.from(existing['emergencyContacts'] ?? [])
      .map((e) => {
            'name': e['name']?.toString() ?? '',
            'relation': e['relation']?.toString() ?? '',
            'phone': e['phone']?.toString() ?? '',
          })
      .toList();

  Widget buildFormHeader(String label, RoleThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
      child: Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.accent, letterSpacing: 1.2)),
    );
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: t.bgCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final isNarrow = MediaQuery.of(sheetCtx).size.width < 600;
          // Dynamic list of roles
          List<String> rolesList = [
            'Branch Manager',
            'Doctor',
            'Receptionist',
            'Dispenser',
            'Supervisor',
            'Office Boy',
            'Kitchen',
            'Madrassa Admin',
            'Madrassa Teacher'
          ];
          rolesList.addAll(FinanceLocalStorage.getCustomRoles());
          if (!rolesList.contains(role)) {
            rolesList.add(role);
          }
          if (!rolesList.contains('+ Add Custom Role...')) {
            rolesList.add('+ Add Custom Role...');
          }

          // Dynamic list of departments
          List<String> deptsList = ['Dispensary', 'Dasterkhwaan', 'Madrassa', 'Office', 'Administration'];
          deptsList.addAll(FinanceLocalStorage.getCustomDepartments());
          if (!deptsList.contains(department)) {
            deptsList.add(department);
          }
          if (!deptsList.contains('+ Add Custom Department...')) {
            deptsList.add('+ Add Custom Department...');
          }

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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isEdit ? 'Edit Employee Profile' : 'Register New Employee',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: t.textPrimary)),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Basic Information Section
                      buildFormHeader('Basic Personal Details', t),
                      buildFormField(controller: nameController, label: 'Full Name *', icon: Icons.person_outline, theme: t),
                      const SizedBox(height: 10),

                      buildResponsiveFieldRow(
                        isNarrow: isNarrow,
                        children: [
                          Expanded(
                            child: buildDropdownField(
                              label: 'Gender *',
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
                              controller: cnicController,
                              label: 'CNIC (XXXXX-XXXXXXX-X) *',
                              icon: Icons.credit_card,
                              theme: t,
                              inputFormatters: [
                                CNICInputFormatter(),
                              ],
                            ),
                          ),
                          Expanded(
                            child: buildDatePickerField(
                              context: sheetCtx,
                              controller: cnicExpiryController,
                              label: 'CNIC Expiry Date',
                              icon: Icons.calendar_month,
                              theme: t,
                            ),
                          ),
                        ],
                      ),

                      buildDropdownField(
                        label: 'Marital Status',
                        value: maritalStatus,
                        items: const ['Single', 'Married', 'Divorced', 'Widowed'],
                        onChanged: (val) => setSheetState(() => maritalStatus = val!),
                        theme: t,
                      ),
                      const SizedBox(height: 10),

                      buildResponsiveFieldRow(
                        isNarrow: isNarrow,
                        children: [
                          Expanded(
                            child: buildFormField(
                              controller: phoneController,
                              label: 'Primary Phone',
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
                              label: 'Alternate Phone',
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
                            flex: 2,
                            child: buildDropdownField(
                              label: 'Relation',
                              value: relationshipType,
                              items: gender == 'Male' ? const ['Father'] : const ['Father', 'Spouse'],
                              onChanged: (val) => setSheetState(() => relationshipType = val!),
                              theme: t,
                            ),
                          ),
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

                      buildFormField(
                          controller: addressController, label: 'Current Address', icon: Icons.home_outlined, theme: t, maxLines: 2),
                      const SizedBox(height: 10),
                      buildFormField(controller: educationController, label: 'Highest Education / Degree', icon: Icons.school, theme: t),

                      const SizedBox(height: 20),
                      // Employment Details
                      buildFormHeader('Employment Details', t),
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
                                        await FinanceLocalStorage.addCustomRole(newVal);
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
                                        });
                                      }
                                    },
                                    theme: t,
                                  );
                                } else {
                                  setSheetState(() => department = val!);
                                }
                              },
                              theme: t,
                            ),
                          ),
                        ],
                      ),
                      if (branches.length > 1)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: t.bgCardAlt,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: t.bgRule),
                          ),
                          child: DropdownButtonFormField<String>(
                            value: selectedBranchId,
                            dropdownColor: t.bgCard,
                            decoration: InputDecoration(
                              labelText: isEdit ? 'Assigned Branch' : 'Assigned Branch *',
                              labelStyle: TextStyle(color: t.textTertiary, fontSize: 11),
                              border: InputBorder.none,
                            ),
                            style: TextStyle(color: t.textPrimary, fontSize: 13),
                            items: branches.map((b) {
                              final id = b['id']?.toString() ?? '';
                              final name = b['name']?.toString() ?? id;
                              return DropdownMenuItem(value: id, child: Text('$name ($id)'));
                            }).toList(),
                            onChanged: isEdit ? null : (val) => setSheetState(() => selectedBranchId = val ?? selectedBranchId),
                          ),
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

                      buildFormField(
                        controller: salaryController,
                        label: 'Base Salary (PKR)',
                        icon: Icons.payments,
                        theme: t,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),

                      const SizedBox(height: 20),
                      // Financial / Bank Details
                      buildFormHeader('Financial & Bank details', t),
                      buildDropdownField(
                        label: 'Payment Method *',
                        value: paymentMethod,
                        items: const ['Bank Transfer', 'Cash'],
                        onChanged: (val) {
                          setSheetState(() {
                            paymentMethod = val!;
                            if (paymentMethod == 'Cash') {
                              bankNameController.text = 'Cash';
                              bankAccountController.text = 'N/A';
                            } else {
                              if (bankNameController.text == 'Cash') {
                                bankNameController.text = '';
                              }
                              if (bankAccountController.text == 'N/A') {
                                bankAccountController.text = '';
                              }
                            }
                          });
                        },
                        theme: t,
                      ),
                      const SizedBox(height: 10),
                      buildResponsiveFieldRow(
                        isNarrow: isNarrow,
                        children: [
                          Expanded(
                            child: buildFormField(
                              controller: bankNameController,
                              label: paymentMethod == 'Bank Transfer' ? 'Bank Name *' : 'Bank Name',
                              icon: Icons.account_balance,
                              theme: t,
                              enabled: paymentMethod == 'Bank Transfer',
                            ),
                          ),
                          Expanded(
                            child: buildFormField(
                              controller: bankAccountController,
                              label: paymentMethod == 'Bank Transfer' ? 'Account Number / IBAN *' : 'Account Number / IBAN',
                              icon: Icons.numbers,
                              theme: t,
                              enabled: paymentMethod == 'Bank Transfer',
                            ),
                          ),
                        ],
                      ),
                      buildFormField(
                        controller: monthlyInstallmentController,
                        label: 'Monthly Advance Installment Limit (Optional)',
                        icon: Icons.money_off,
                        theme: t,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),

                      const SizedBox(height: 20),
                      // Shifts Custom Overrides
                      buildFormHeader('Schedule Overrides (Optional)', t),
                      buildResponsiveFieldRow(
                        isNarrow: isNarrow,
                        children: [
                          Expanded(
                              child: buildFormField(
                                  controller: winterShiftController,
                                  label: 'Winter (e.g. 09 AM - 05 PM)',
                                  icon: Icons.schedule,
                                  theme: t)),
                          Expanded(
                              child: buildFormField(
                                  controller: summerShiftController,
                                  label: 'Summer (e.g. 08 AM - 04 PM)',
                                  icon: Icons.sunny,
                                  theme: t)),
                        ],
                      ),

                      const SizedBox(height: 20),
                      // Emergency Contacts Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          buildFormHeader('Emergency Contacts (${emergencyContacts.length})', t),
                          TextButton.icon(
                            onPressed: () => setSheetState(() {
                              emergencyContacts.add({'name': '', 'relation': '', 'phone': ''});
                            }),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Contact', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                      ...emergencyContacts.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final contact = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: t.bgCardAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Contact #${idx + 1}',
                                      style: TextStyle(fontSize: 12, color: t.textSecondary, fontWeight: FontWeight.bold)),
                                  InkWell(
                                    onTap: () => setSheetState(() => emergencyContacts.removeAt(idx)),
                                    child: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                style: TextStyle(color: t.textPrimary, fontSize: 13),
                                decoration:
                                    InputDecoration(hintText: 'Contact Name', hintStyle: TextStyle(color: t.textTertiary), isDense: true),
                                onChanged: (val) => contact['name'] = val,
                                controller: TextEditingController(text: contact['name'])
                                  ..selection = TextSelection.fromPosition(TextPosition(offset: (contact['name'] ?? '').length)),
                              ),
                              const SizedBox(height: 6),
                              buildResponsiveFieldRow(
                                isNarrow: isNarrow,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      style: TextStyle(color: t.textPrimary, fontSize: 13),
                                      decoration: InputDecoration(
                                          hintText: 'Relation (e.g. Father)', hintStyle: TextStyle(color: t.textTertiary), isDense: true),
                                      onChanged: (val) => contact['relation'] = val,
                                      controller: TextEditingController(text: contact['relation'])
                                        ..selection =
                                            TextSelection.fromPosition(TextPosition(offset: (contact['relation'] ?? '').length)),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      style: TextStyle(color: t.textPrimary, fontSize: 13),
                                      decoration: InputDecoration(
                                          hintText: 'Phone Number', hintStyle: TextStyle(color: t.textTertiary), isDense: true),
                                      keyboardType: TextInputType.phone,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(11),
                                      ],
                                      onChanged: (val) => contact['phone'] = val,
                                      controller: TextEditingController(text: contact['phone'])
                                        ..selection =
                                            TextSelection.fromPosition(TextPosition(offset: (contact['phone'] ?? '').length)),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          // Form validations
                          if (nameController.text.trim().isEmpty || cnicController.text.trim().isEmpty) {
                            showCustomSnackBar(sheetCtx, 'Please fill in Name and CNIC.', error: true);
                            return;
                          }

                          if (paymentMethod == 'Bank Transfer') {
                            if (bankNameController.text.trim().isEmpty || bankAccountController.text.trim().isEmpty) {
                              showCustomSnackBar(sheetCtx, 'Please fill in Bank Name and Account/IBAN.', error: true);
                              return;
                            }
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

                          // Sanitize emergency contacts
                          final validContacts =
                              emergencyContacts.where((e) => e['name']!.isNotEmpty && e['phone']!.isNotEmpty).toList();

                          try {
                            final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';

                            Map<String, dynamic>? scheduleOverride;
                            if (winterShiftController.text.isNotEmpty || summerShiftController.text.isNotEmpty) {
                              scheduleOverride = {
                                'winter': winterShiftController.text,
                                'summer': summerShiftController.text,
                              };
                            }

                            final employeeData = {
                              'localId': isEdit ? employeeId : null,
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
                              'bankName': bankNameController.text.trim(),
                              'bankAccount': bankAccountController.text.trim(),
                              'education': educationController.text.isNotEmpty ? educationController.text.trim() : null,
                              'currentAddress': addressController.text.trim().isNotEmpty ? addressController.text.trim() : null,
                              'emergencyContacts': validContacts,
                              'workScheduleOverride': scheduleOverride,
                              'isActive': existing['isActive'] ?? true,
                              'monthlyAdvanceInstallment': monthlyInstallmentController.text.trim().isNotEmpty
                                  ? double.tryParse(monthlyInstallmentController.text) ?? 0.0
                                  : 0.0,
                              'branchId': selectedBranchId,
                            };

                            final targetBranchId = isEdit ? (existing['branchId']?.toString() ?? activeBranchId) : selectedBranchId;
                            final empLocalId = await FinanceLocalStorage.saveEmployee(
                              branchId: targetBranchId,
                              data: employeeData,
                              performedBy: curUser,
                            );

                            // If registering a new employee, create an initial Salary History record
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
                              // If base salary was changed in edit, prompt/save a salary history raise
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

                            if (sheetCtx.mounted) {
                              Navigator.pop(sheetCtx);
                              if (onSaved != null) onSaved();
                              showCustomSnackBar(context, '${nameController.text.trim()} profile saved successfully!');
                            }
                          } catch (e) {
                            showCustomSnackBar(sheetCtx, e.toString().replaceAll('Exception: ', ''), error: true);
                          }
                        },
                        child: Text(isEdit ? 'Save Profile Changes' : 'Register Employee', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
