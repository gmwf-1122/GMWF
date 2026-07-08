// lib/pages/madrassa/madrassa_guardian_screen.dart
//
// FIXES:
//  • Global-level admin/staff (non-guardian) now sees a student picker
//    dialog first when viewing the guardian portal, then renders the
//    ParentReportCard for the selected student — exactly like a guardian would see.
//  • Regular guardians continue to work as before (their linked studentIds).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/parent_report_card.dart';
import 'madrassa_strings.dart';
import '../../services/offline_auth_service.dart';
import '../login_page.dart';

class MadrassaGuardianScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const MadrassaGuardianScreen({super.key, required this.userData});

  @override
  State<MadrassaGuardianScreen> createState() =>
      _MadrassaGuardianScreenState();
}

class _MadrassaGuardianScreenState extends State<MadrassaGuardianScreen> {
  int _selectedIndex = 0;

  /// null = still loading from prefs, '' = not set yet, 'en'/'ur' = chosen
  String? _langCode;

  // For admin preview — the student they picked from the dialog
  String? _adminPreviewStudentId;
  Map<String, dynamic>? _adminPreviewStudentData;

  // Added: selected branch for global/HQ accounts
  String? _selectedBranchId;
  String? _selectedBranchName;

  // Prevent repeated dialog triggers (existing flag)
  bool _dialogShown = false;

  // Prevent repeated dialog triggers
  // (kept from earlier definition)
  // Cache the last branchId to invalidate student future when branch changes
  String? _lastBranchId;
  // Prevent the language provider sync from running on every rebuild
  bool _providerSynced = false;
  // Cache the students future so it isn't recreated on every rebuild
  Future<List<DocumentSnapshot>>? _studentsFuture;

  bool _autoBranchDialogTriggered = false;
  bool _autoStudentDialogTriggered = false;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('madrassa_locale');
      if (mounted) setState(() => _langCode = saved ?? '');
    } catch (_) {
      if (mounted) setState(() => _langCode = 'en');
    }
  }

  Future<void> _selectLanguage(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('madrassa_locale', code);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _langCode = code;
        _providerSynced = false;
      });
      // Also update the Provider if it exists in the tree
      try {
        Provider.of<MadrassaLanguageProvider>(context, listen: false).setLanguage(code);
      } catch (_) {}
    }
  }


  Future<void> _logout() async {
    try {
      await OfflineAuthService.clearCredentials();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (r) => false,
        );
      }
    } catch (e) {
      // Removed debugPrint for dead code audit
    }
  }

  Future<List<DocumentSnapshot>> _fetchStudents(
      String branchId, List<String> ids) {
    return Future.wait(ids.map((id) => FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('madrassa_students')
        .doc(id)
        .get()));
  }

  bool _isAdminViewing() {
    final role = (widget.userData['role'] as String? ?? '').toLowerCase();
    return role != 'madrassa guardian';
  }

  // New helper to fetch branches and show a picker when branchId is missing
  Future<void> _showBranchPickerDialog(BuildContext context) async {
    final snap = await FirebaseFirestore.instance.collection('branches').get();
    if (!mounted) return;
    final branches = snap.docs;
    if (branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('No branches available.'))),
      );
      return;
    }
    final searchCtrl = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final query = searchCtrl.text.toLowerCase().trim();
            final filtered = branches.where((doc) {
              final name = (doc.data()['name'] as String? ?? '').toLowerCase();
              return name.contains(query);
            }).toList();
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: context.t('Search branches...'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final doc = filtered[i];
                          final name = (doc.data()['name'] as String?) ?? 'Branch';
                          return ListTile(
                            title: Text(name),
                            onTap: () {
                              setState(() {
                                _selectedBranchId = doc.id;
                                _selectedBranchName = name;
                                _studentsFuture = null;
                                _lastBranchId = null;
                                _autoStudentDialogTriggered = false;
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(context.t('Cancel')),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showStudentPickerDialog(BuildContext context, String branchId) async {
    final snap = await FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('madrassa_students')
        .get();

    if (!mounted) return;

    final allDocs = snap.docs;
    final allStudents = allDocs.where((doc) {
      final d = Map<String, dynamic>.from(doc.data() as Map? ?? {});
      final statusVal = d['status'];
      return (statusVal == null || statusVal == '')
          ? (d['active'] == true)
          : (statusVal == 'active');
    }).toList()
      ..sort((a, b) {
        final aVal = int.tryParse(a['rollNumber']?.toString() ?? '') ?? 999999;
        final bVal = int.tryParse(b['rollNumber']?.toString() ?? '') ?? 999999;
        return aVal.compareTo(bVal);
      });

    if (allStudents.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('No active students found.'))));
      return;
    }

    final searchCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final query = searchCtrl.text.toLowerCase().trim();
            final filteredStudents = allStudents.where((s) {
              final d = s.data();
              final name = (d['name'] as String? ?? '').toLowerCase();
              final rollNumber = (d['rollNumber'] as String? ?? '').toLowerCase();
              return name.contains(query) || rollNumber.contains(query);
            }).toList();

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: Colors.white),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFF4C4DDC).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.person_search_rounded, color: Color(0xFF4C4DDC), size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.t('Guardian Portal'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF1A1C1E), fontFamily: context.isUrdu ? 'Noori' : null)),
                              Text(context.t('Select student to preview'), style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: context.isUrdu ? 'Noori' : null)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: context.t('Search by name or roll number...'),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setStateDialog(() {});
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (val) {
                        setStateDialog(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: filteredStudents.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 32.0),
                                child: Center(child: Text(context.t('No matching students found.'), style: TextStyle(color: Colors.grey, fontFamily: context.isUrdu ? 'Noori' : null))),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filteredStudents.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final s = filteredStudents[i];
                                  final d = s.data();
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        _adminPreviewStudentId = s.id;
                                        _adminPreviewStudentData = d;
                                      });
                                      Navigator.pop(ctx);
                                    },
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8F9FD),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: const Color(0xFFE0E2E7)),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: const Color(0xFF4C4DDC),
                                            child: Text(d['name']?[0] ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(d['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                                Text('Roll: ${d['rollNumber'] ?? "?"} • Guardian: ${d['guardianName'] ?? "?"}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.chevron_right, color: Color(0xFF4C4DDC)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _logout();
                        },
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: Text(context.t('Logout'), style: TextStyle(color: Colors.red, fontFamily: context.isUrdu ? 'Noori' : null)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── 1. Still loading pref from SharedPreferences ──
    if (_langCode == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4C4DDC))),
      );
    }

    // ── 2. Language not chosen yet → full-screen picker ──
    if (_langCode!.isEmpty) {
      return _LanguagePickerScreen(onSelect: _selectLanguage);
    }

    // ── 3. Language is set → render normal content ──
    return ChangeNotifierProvider(
      create: (_) => MadrassaLanguageProvider(),
      child: Builder(
        builder: (context) {
          // Sync provider with chosen language (only once, not on every rebuild)
          if (!_providerSynced) {
            _providerSynced = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                try {
                  final provider = Provider.of<MadrassaLanguageProvider>(context, listen: false);
                  if (provider.languageCode != _langCode) {
                    provider.setLanguage(_langCode!);
                  }
                } catch (_) {}
              }
            });
          }

           final branchId = widget.userData['branchId'] as String? ?? '';
           final isAdmin = _isAdminViewing();
           // Invalidate cached students future if branchId changed
           if (branchId != _lastBranchId) {
             _studentsFuture = null;
             _lastBranchId = branchId;
           }
          debugPrint("[Diagnostic] MadrassaGuardianScreen build - branchId: $branchId, isAdmin: $isAdmin, userData: ${widget.userData}");
          if (branchId.isEmpty && !isAdmin) return _EmptyState(onLogout: _logout, message: 'Branch missing');

          if (isAdmin) {
            final effectiveBranchId = (branchId.isNotEmpty && branchId != 'all') ? branchId : (_selectedBranchId ?? '');
            debugPrint("[Diagnostic] MadrassaGuardianScreen Admin - effectiveBranchId: $effectiveBranchId, previewStudentId: $_adminPreviewStudentId, dialogShown: $_dialogShown");
            if (effectiveBranchId.isEmpty) {
              if (!_autoBranchDialogTriggered) {
                _autoBranchDialogTriggered = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showBranchPickerDialog(context);
                });
              }
              return _AdminSelectionPlaceholder(
                title: context.t('Select Branch'),
                subtitle: context.t('Please select a branch to preview the Guardian Portal.'),
                buttonText: context.t('Select Branch'),
                onButtonPressed: () => _showBranchPickerDialog(context),
                onLogout: _logout,
              );
            }

            if (_adminPreviewStudentId == null) {
              if (!_autoStudentDialogTriggered) {
                _autoStudentDialogTriggered = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showStudentPickerDialog(context, effectiveBranchId);
                });
              }
              return _AdminSelectionPlaceholder(
                title: context.t('Select Student'),
                subtitle: '${context.t('Branch')}: ${branchId != 'all' && branchId.isNotEmpty ? branchId : (_selectedBranchName ?? '')}\n${context.t('Please select a student to preview their report card.')}',
                buttonText: context.t('Select Student'),
                onButtonPressed: () => _showStudentPickerDialog(context, effectiveBranchId),
                onLogout: _logout,
                onChangeBranch: (branchId == 'all' || branchId.isEmpty)
                    ? () {
                        setState(() {
                          _selectedBranchId = null;
                          _selectedBranchName = null;
                          _autoBranchDialogTriggered = false;
                          _autoStudentDialogTriggered = false;
                        });
                      }
                    : null,
                changeBranchText: context.t('Change Branch'),
              );
            }
            return Stack(
              children: [
                ParentReportCard(
                  branchId: effectiveBranchId,
                  studentId: _adminPreviewStudentId!,
                  studentData: _adminPreviewStudentData!,
                  onLogout: null,
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  child: _AdminStudentSwitchButton(
                    onTap: () {
                      _dialogShown = false;
                      _autoStudentDialogTriggered = false;
                      setState(() => _adminPreviewStudentId = null);
                    },
                    studentName: _adminPreviewStudentData?['name'] ?? '',
                  ),
                ),
              ],
            );
          }
          // ── Regular guardian path ──
          final dynamic rawIds = widget.userData['studentIds'] ?? widget.userData['studentId'];
          final List<String> studentIds = rawIds is List
              ? List<String>.from(rawIds)
              : (rawIds is String && rawIds.isNotEmpty ? [rawIds] : []);

          debugPrint("[Diagnostic] MadrassaGuardianScreen Guardian - branchId: $branchId, studentIds: $studentIds");
          if (studentIds.isEmpty) return _EmptyState(onLogout: _logout);

          return FutureBuilder<List<DocumentSnapshot>>(
            future: _studentsFuture ??= _fetchStudents(branchId, studentIds),
            builder: (context, allSnap) {
              debugPrint("[Diagnostic] MadrassaGuardianScreen fetchStudents - connectionState: ${allSnap.connectionState}, hasData: ${allSnap.hasData}, hasError: ${allSnap.hasError}, error: ${allSnap.error}");
              if (allSnap.connectionState == ConnectionState.waiting) return _LoadingScreen();
              if (allSnap.hasError) return _EmptyState(onLogout: _logout, message: 'Error loading data');
              final allDocs = allSnap.data ?? [];
              if (allDocs.isEmpty) return _EmptyState(onLogout: _logout);

              final selectedDoc = _selectedIndex < allDocs.length ? allDocs[_selectedIndex] : allDocs.first;
              if (!selectedDoc.exists) return _EmptyState(onLogout: _logout);
              final studentData = selectedDoc.data() as Map<String, dynamic>;

              return Stack(
                children: [
                  ParentReportCard(
                    branchId: branchId,
                    studentId: selectedDoc.id,
                    studentData: studentData,
                    onLogout: _logout,
                  ),
                  if (studentIds.length > 1)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 12,
                      child: _StudentSwitcher(
                        allDocs: allDocs,
                        studentIds: studentIds,
                        selectedIndex: _selectedIndex,
                        onChanged: (i) => setState(() => _selectedIndex = i),
                      ),
                    ),
                ],
              );
            },
          );
        }
      ),
    );
  }
}

// ── Full-screen language picker ───────────────────────────────────────────────
class _LanguagePickerScreen extends StatelessWidget {
  final Future<void> Function(String) onSelect;
  const _LanguagePickerScreen({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 32, offset: const Offset(0, 8)),
            ],
            border: Border.all(color: const Color(0xFFE8EAF0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF4C4DDC).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.language_rounded, color: Color(0xFF4C4DDC), size: 36),
              ),
              const SizedBox(height: 24),
              // Title
              const Text(
                'زبان منتخب کریں',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Noori', color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Select Language',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please choose your preferred language to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'براہ کرم جاری رکھنے کے لیے اپنی پسندیدہ زبان منتخب کریں۔',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontFamily: 'Noori', height: 1.5),
              ),
              const SizedBox(height: 32),
              // English button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => onSelect('en'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C4DDC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('English', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              // Urdu button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => onSelect('ur'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    foregroundColor: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('اردو', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Noori')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminStudentSwitchButton extends StatelessWidget {
  final VoidCallback onTap;
  final String studentName;
  const _AdminStudentSwitchButton({required this.onTap, required this.studentName});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF4C4DDC),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFF4C4DDC).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(studentName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator(color: Color(0xFF4C4DDC))),
    );
  }
}

class _StudentSwitcher extends StatelessWidget {
  final List<DocumentSnapshot> allDocs;
  final List<String> studentIds;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _StudentSwitcher({required this.allDocs, required this.studentIds, required this.selectedIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF4C4DDC),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF4C4DDC).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: DropdownButton<int>(
        value: selectedIndex,
        dropdownColor: const Color(0xFF4C4DDC),
        underline: const SizedBox(),
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
        items: List.generate(studentIds.length, (i) {
          String name = 'Student ${i + 1}';
          if (allDocs.length > i && allDocs[i].exists) name = (allDocs[i].data() as Map<String, dynamic>)['name'] ?? name;
          return DropdownMenuItem(value: i, child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)));
        }),
        onChanged: (v) => onChanged(v!),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onLogout;
  final String? message;
  const _EmptyState({required this.onLogout, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.link_off_rounded, size: 64, color: Color(0xFF4C4DDC)),
              const SizedBox(height: 24),
              Text(context.t('Account Not Linked'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null)),
              const SizedBox(height: 8),
              Text(context.t(message ?? 'Your account is not linked to any student.'), textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontFamily: context.isUrdu ? 'Noori' : null)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onLogout,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4C4DDC), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text(context.t('Back to Login'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSelectionPlaceholder extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onButtonPressed;
  final VoidCallback onLogout;
  final VoidCallback? onChangeBranch;
  final String? changeBranchText;

  const _AdminSelectionPlaceholder({
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onButtonPressed,
    required this.onLogout,
    this.onChangeBranch,
    this.changeBranchText,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 32, offset: const Offset(0, 8)),
            ],
            border: Border.all(color: const Color(0xFFE8EAF0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF4C4DDC).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.family_restroom_rounded, color: Color(0xFF4C4DDC), size: 36),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onButtonPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C4DDC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(buttonText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              if (onChangeBranch != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onChangeBranch,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Color(0xFFE8EAF0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(changeBranchText ?? 'Change Branch', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onLogout,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(context.t('Logout'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}