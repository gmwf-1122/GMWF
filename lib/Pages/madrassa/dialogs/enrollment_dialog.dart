// Imports
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../madrassa_strings.dart';
import '../widgets/madrassa_common_widgets.dart';
import '../../../services/auth_service.dart';
import '../../../utils/formatters.dart';

void showAddStudentDialog(
  BuildContext context,
  String branchId, {
  dynamic student,
  required String username,
  required String role,
}) {
  final isEdit = student != null;
  final studentData = isEdit 
      ? (student is DocumentSnapshot 
          ? student.data() as Map<String, dynamic> 
          : Map<String, dynamic>.from(student as Map))
      : null;
  final studentId = isEdit 
      ? (student is DocumentSnapshot ? student.id : (student as Map)['id']?.toString() ?? '')
      : '';

  final nameCtrl = TextEditingController(text: studentData?['name']);
  final rollCtrl = TextEditingController(text: studentData?['rollNumber']);
  final studentCnicCtrl = TextEditingController(text: studentData?['studentCnic']);
  final guardianNameCtrl = TextEditingController(text: studentData?['guardianName']);
  final guardianCnicCtrl = TextEditingController(text: studentData?['guardianCnic']);
  final contactCtrl = TextEditingController(text: studentData?['contactPhone']);
  final gUsernameCtrl = TextEditingController();
  final gPassCtrl = TextEditingController();
  final prevMadrassaCtrl = TextEditingController(text: studentData?['prevMadrassaName']);
  final prevHifzCtrl = TextEditingController(text: studentData?['prevHifzLines']?.toString());

  DateTime joinDate = DateTime.now();
  final joinDateVal = studentData?['joinDate'];
  if (joinDateVal is Timestamp) {
    joinDate = joinDateVal.toDate();
  } else if (joinDateVal is String) {
    joinDate = DateTime.tryParse(joinDateVal) ?? DateTime.now();
  }
  bool hasPrevMadrassa = studentData?['hasPrevMadrassa'] ?? false;
  bool isNewGuardian = true;
  bool linkAccount = false;
  bool isSaving = false;
  bool isSearching = false;
  Map<String, dynamic>? foundGuardian;
  Timer? debounce;
  bool initializedGuardian = false;
  
  // Image handling for student avatar
  Uint8List? selectedImageBytes;

  String? nameError;
  String? rollError;
  String? studentCnicError;
  String? guardianCnicError;
  String? guardianNameError;
  String? contactError;
  String? gUsernameError;
  String? gPassError;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDs) {
        if (isEdit && !initializedGuardian) {
          initializedGuardian = true;
          final cnic = guardianCnicCtrl.text.trim();
          if (cnic.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setDs(() => isSearching = true);
              FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'Madrassa Guardian')
                  .where('cnic', isEqualTo: cnic)
                  .limit(1)
                  .get()
                  .then((q) {
                if (q.docs.isNotEmpty) {
                  final g = q.docs.first;
                  final data = g.data();
                  setDs(() {
                    foundGuardian = {'uid': g.id, ...data};
                    gUsernameCtrl.text = data['username'] ?? '';
                    gPassCtrl.text = data['password'] ?? '';
                    isNewGuardian = false;
                    isSearching = false;
                  });
                } else {
                  setDs(() {
                    isSearching = false;
                  });
                }
              }).catchError((e) {
                setDs(() => isSearching = false);
              });
            });
          }
        }

        // Helper to pick student image
        Future<void> pickStudentImage() async {
          final picker = ImagePicker();
          final XFile? xfile = await picker.pickImage(source: ImageSource.gallery);
          if (xfile != null) {
            final bytes = await xfile.readAsBytes();
            setDs(() => selectedImageBytes = bytes);
          }
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            isEdit ? 'Edit Student Details' : context.l.enrollNewStudent,
            style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar picker
                Center(
                  child: GestureDetector(
                    onTap: pickStudentImage,
                    child: CircleAvatar(
                      radius: 48,
                      backgroundImage: selectedImageBytes != null 
                          ? MemoryImage(selectedImageBytes!) 
                          : (studentData?['photoUrl'] != null && studentData!['photoUrl'].toString().isNotEmpty)
                              ? NetworkImage(studentData['photoUrl']) as ImageProvider
                              : null,
                      backgroundColor: Colors.grey[300],
                      child: (selectedImageBytes == null && (studentData?['photoUrl'] == null || studentData!['photoUrl'].toString().isEmpty))
                          ? const Icon(Icons.camera_alt, size: 32, color: Colors.white70)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                sectionLabel(context.l.studentInformation),
                const SizedBox(height: 10),
                buildTf(
                  nameCtrl,
                  context.l.studentFullName,
                  Icons.person,
                  context,
                  isRequired: true,
                  errorText: nameError,
                  onChanged: (v) {
                    if (nameError != null) setDs(() => nameError = null);
                  },
                ),
                const SizedBox(height: 10),
                buildTf(
                  rollCtrl,
                  context.l.rollNumber,
                  Icons.badge,
                  context,
                  isRequired: true,
                  errorText: rollError,
                  onChanged: (v) {
                    if (rollError != null) setDs(() => rollError = null);
                  },
                ),
                const SizedBox(height: 10),
                buildTf(
                  studentCnicCtrl,
                  '${context.l.studentCnic} (XXXXX-XXXXXXX-X)',
                  Icons.credit_card,
                  context,
                  formatters: [CNICInputFormatter(), LengthLimitingTextInputFormatter(15)],
                  inputType: TextInputType.number,
                  errorText: studentCnicError,
                  onChanged: (v) {
                    if (studentCnicError != null) setDs(() => studentCnicError = null);
                  },
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: joinDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setDs(() => joinDate = d);
                  },
                  child: IgnorePointer(
                    child: buildTf(
                      TextEditingController(text: DateFormat('dd MMMM yyyy').format(joinDate)),
                      context.l.joinDate,
                      Icons.calendar_today,
                      context,
                      enabled: false,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                buildTf(prevHifzCtrl, context.l.hifzBeforeJoining, Icons.auto_stories_outlined, context, inputType: TextInputType.number),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: Text(context.l.previousMadrassa,
                      style: context.urduStyle(style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                  value: hasPrevMadrassa,
                  onChanged: (v) => setDs(() => hasPrevMadrassa = v),
                ),
                if (hasPrevMadrassa) ...[
                  buildTf(prevMadrassaCtrl, context.l.previousMadrassaName, Icons.school_outlined, context),
                ],
                const SizedBox(height: 20),
                sectionLabel(context.l.guardianInformation),
                const SizedBox(height: 4),
                Text(
                  context.t('Optional — leave blank if not applicable'),
                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 10),
                
                buildTf(
                  guardianCnicCtrl,
                  '${context.l.guardianCnic} (XXXXX-XXXXXXX-X)',
                  Icons.credit_card,
                  context,
                  errorText: guardianCnicError,
                  formatters: [CNICInputFormatter(), LengthLimitingTextInputFormatter(15)],
                  inputType: TextInputType.number,
                  onChanged: (v) {
                    if (guardianCnicError != null) setDs(() => guardianCnicError = null);
                    if (v.length == 15) {
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 300), () async {
                        setDs(() => isSearching = true);
                        final q = await FirebaseFirestore.instance
                            .collection('users')
                            .where('role', isEqualTo: 'Madrassa Guardian')
                            .where('cnic', isEqualTo: v)
                            .limit(1)
                            .get();
                        
                         if (q.docs.isNotEmpty) {
                          final g = q.docs.first;
                          final data = g.data();
                          setDs(() {
                            foundGuardian = {'uid': g.id, ...data};
                            // Pre-fill from the matched guardian, but keep fields
                            // editable so the user can correct/override them.
                            if (guardianNameCtrl.text.trim().isEmpty) {
                              guardianNameCtrl.text = data['name'] ?? '';
                            }
                            if (contactCtrl.text.trim().isEmpty) {
                              contactCtrl.text = data['phone'] ?? '';
                            }
                            gUsernameCtrl.text = data['username'] ?? '';
                            gPassCtrl.text = data['password'] ?? '';
                            isNewGuardian = false;
                            isSearching = false;
                            guardianNameError = null;
                            contactError = null;
                          });
                        } else {
                          setDs(() {
                            foundGuardian = null;
                            isNewGuardian = true;
                            isSearching = false;
                            gUsernameCtrl.clear();
                            gPassCtrl.clear();
                          });
                        }
                      });
                    } else {
                      // CNIC no longer complete/matching - stop treating as a
                      // "found" guardian so fields go back to fully manual edit.
                      if (foundGuardian != null) {
                        setDs(() {
                          foundGuardian = null;
                        });
                      }
                    }
                  },
                ),
                if (isSearching) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
                if (foundGuardian != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Existing Guardian Found: ${foundGuardian!['name']} (fields below are editable)',
                            style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                buildTf(
                  guardianNameCtrl,
                  context.l.guardianFullName,
                  Icons.family_restroom,
                  context,
                  errorText: guardianNameError,
                  onChanged: (v) {
                    if (guardianNameError != null) setDs(() => guardianNameError = null);
                  },
                ),
                const SizedBox(height: 10),
                buildTf(
                  contactCtrl,
                  context.l.contactPhone,
                  Icons.phone,
                  context,
                  errorText: contactError,
                  inputType: TextInputType.phone,
                  formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                  onChanged: (v) {
                    if (contactError != null) setDs(() => contactError = null);
                  },
                ),
                
                const SizedBox(height: 16),
                const Divider(),
                if (foundGuardian != null) ...[
                  sectionLabel('Parent Account Details'),
                  const SizedBox(height: 10),
                  buildTf(
                    gUsernameCtrl,
                    context.l.loginUsername,
                    Icons.badge_outlined,
                    context,
                    hint: context.l.loginUsernameHint,
                    isRequired: true,
                    errorText: gUsernameError,
                    onChanged: (v) {
                      if (gUsernameError != null) setDs(() => gUsernameError = null);
                    },
                  ),
                  const SizedBox(height: 10),
                  buildTf(
                    gPassCtrl,
                    context.l.loginPassword,
                    Icons.lock_outline,
                    context,
                    obscure: true,
                    isRequired: true,
                    errorText: gPassError,
                    onChanged: (v) {
                      if (gPassError != null) setDs(() => gPassError = null);
                    },
                  ),
                ] else ...[
                  SwitchListTile(
                    title: Text(context.l.createLinkAccount, style: context.urduStyle(style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                    subtitle: Text(context.l.createLinkSubtitle, style: const TextStyle(fontSize: 11)),
                    value: linkAccount,
                    activeThumbColor: const Color(0xFF4F46E5),
                    onChanged: (v) => setDs(() => linkAccount = v),
                  ),
                  if (linkAccount) ...[
                    const SizedBox(height: 10),
                    buildTf(
                      gUsernameCtrl,
                      context.l.loginUsername,
                      Icons.badge_outlined,
                      context,
                      hint: context.l.loginUsernameHint,
                      isRequired: true,
                      errorText: gUsernameError,
                      onChanged: (v) {
                        if (gUsernameError != null) setDs(() => gUsernameError = null);
                      },
                    ),
                    const SizedBox(height: 10),
                    buildTf(
                      gPassCtrl,
                      context.l.loginPassword,
                      Icons.lock_outline,
                      context,
                      obscure: true,
                      isRequired: true,
                      errorText: gPassError,
                      onChanged: (v) {
                        if (gPassError != null) setDs(() => gPassError = null);
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l.cancel, style: context.urduStyle())),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                final nav = Navigator.of(ctx);
                bool isValid = true;
                if (nameCtrl.text.trim().isEmpty) {
                  nameError = context.t('Student name is required');
                  isValid = false;
                } else {
                  nameError = null;
                }

                if (rollCtrl.text.trim().isEmpty) {
                  rollError = context.t('Roll number is required');
                  isValid = false;
                } else {
                  rollError = null;
                }

                if (studentCnicCtrl.text.trim().isNotEmpty && studentCnicCtrl.text.length != 15) {
                  studentCnicError = context.t('Enter a valid 15-character CNIC (e.g. 12345-1234567-1)');
                  isValid = false;
                } else {
                  studentCnicError = null;
                }

                // Guardian info is entirely optional. We only format-validate
                // fields that have actually been filled in - we never force
                // the guardian section to be completed.
                if (guardianCnicCtrl.text.trim().isNotEmpty && guardianCnicCtrl.text.length != 15) {
                  guardianCnicError = context.t('Enter a valid 15-character CNIC (e.g. 12345-1234567-1)');
                  isValid = false;
                } else {
                  guardianCnicError = null;
                }

                guardianNameError = null;

                if (contactCtrl.text.trim().isNotEmpty && contactCtrl.text.trim().length != 11) {
                  contactError = context.t('Enter a valid 11-digit phone number');
                  isValid = false;
                } else {
                  contactError = null;
                }

                // Username/password are only relevant when we're actually
                // creating or updating a guardian login - i.e. an existing
                // guardian was matched, or the teacher opted to link a new
                // account. If no guardian info was entered at all, skip this
                // entirely.
                final hasAnyGuardianInfo = guardianNameCtrl.text.trim().isNotEmpty ||
                    guardianCnicCtrl.text.trim().isNotEmpty ||
                    contactCtrl.text.trim().isNotEmpty;
                final bool isGuardianLinkedOrCreating =
                    (foundGuardian != null || linkAccount) && hasAnyGuardianInfo;

                if (isGuardianLinkedOrCreating) {
                  if (gUsernameCtrl.text.trim().isEmpty) {
                    gUsernameError = context.t('Username is required');
                    isValid = false;
                  } else {
                    gUsernameError = null;
                  }

                  if (gPassCtrl.text.trim().isEmpty) {
                    gPassError = context.t('Password is required');
                    isValid = false;
                  } else {
                    gPassError = null;
                  }
                } else {
                  gUsernameError = null;
                  gPassError = null;
                }

                if (!isValid) {
                  setDs(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.t('Please correct all validation errors to continue'),
                        style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                setDs(() => isSaving = true);
                try {
                  String? gUid;
                  if (isGuardianLinkedOrCreating && foundGuardian != null) {
                    gUid = foundGuardian!['uid'];
                    final gUpdates = <String, dynamic>{
                      'username': gUsernameCtrl.text.trim(),
                      'usernameLower': gUsernameCtrl.text.trim().toLowerCase(),
                      'password': gPassCtrl.text.trim(),
                      'phone': contactCtrl.text.trim(),
                      'name': guardianNameCtrl.text.trim(),
                      'cnic': guardianCnicCtrl.text.trim(),
                      if (isEdit) 'studentIds': FieldValue.arrayUnion([studentId]),
                    };
                    await FirebaseFirestore.instance.collection('users').doc(gUid).set(gUpdates, SetOptions(merge: true));
                    await FirebaseFirestore.instance
                        .collection('branches')
                        .doc(branchId)
                        .collection('users')
                        .doc(gUid)
                        .set(gUpdates, SetOptions(merge: true));
                  } else if (isGuardianLinkedOrCreating && linkAccount) {
                    final usernameInput = gUsernameCtrl.text.trim().toLowerCase();
                    gUid = await AuthService().signUp(
                      email: '$usernameInput@gmwf.com',
                      password: gPassCtrl.text.trim(),
                      username: usernameInput,
                      role: 'Madrassa Guardian',
                      branchId: branchId,
                      branchName: 'Madrassa',
                      phone: contactCtrl.text.trim(),
                      name: guardianNameCtrl.text.trim(),
                      cnic: guardianCnicCtrl.text.trim(),
                      studentIds: isEdit ? [studentId] : [],
                    );
                  }

                  String photoUrl = studentData?['photoUrl'] ?? '';
                  if (selectedImageBytes != null && isEdit) {
                    final ref = FirebaseStorage.instance.ref().child('students/$branchId/$studentId/${DateTime.now().millisecondsSinceEpoch}.jpg');
                    await ref.putData(selectedImageBytes!);
                    photoUrl = await ref.getDownloadURL();
                  }

                  final finalData = {
                    'name': nameCtrl.text.trim(),
                    'rollNumber': rollCtrl.text.trim(),
                    'studentCnic': studentCnicCtrl.text.trim(),
                    'guardianName': guardianNameCtrl.text.trim(),
                    'guardianCnic': guardianCnicCtrl.text.trim(),
                    'contactPhone': contactCtrl.text.trim(),
                    'joinDate': Timestamp.fromDate(joinDate),
                    'hasPrevMadrassa': hasPrevMadrassa,
                    'prevMadrassaName': prevMadrassaCtrl.text.trim(),
                    'prevHifzLines': int.tryParse(prevHifzCtrl.text.trim()) ?? 0,
                    'lastUpdatedAt': FieldValue.serverTimestamp(),
                    'photoUrl': photoUrl,
                  };

                  if (isEdit) {
                    await FirebaseFirestore.instance
                        .collection('branches')
                        .doc(branchId)
                        .collection('madrassa_students')
                        .doc(studentId)
                        .set(finalData, SetOptions(merge: true));

                    // Write central audit log
                    await MadrassaAuditService.logAction(
                      branchId: branchId,
                      editor: username,
                      role: role,
                      type: 'student_edit',
                      message: 'Updated details for student ${finalData['name']} (Roll: ${finalData['rollNumber']})',
                      studentId: studentId,
                      studentName: finalData['name'] as String?,
                    );
                  } else {
                    final now = DateTime.now();
                    final sRef = await FirebaseFirestore.instance
                        .collection('branches')
                        .doc(branchId)
                        .collection('madrassa_students')
                        .add({
                      ...finalData,
                      'branchId': branchId,
                      'status': 'active',
                      'auditLog': [
                        {
                          'status': 'active',
                          'type': 'enrollment',
                          'date': Timestamp.fromDate(joinDate),
                          'reason': 'Initial Enrollment'
                        }
                      ],
                      'currentLines': 0,
                      'enrolledMonth': DateFormat('yyyy-MM').format(now),
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                    
                    if (selectedImageBytes != null) {
                      final ref = FirebaseStorage.instance.ref().child('students/$branchId/${sRef.id}/${DateTime.now().millisecondsSinceEpoch}.jpg');
                      await ref.putData(selectedImageBytes!);
                      final newPhotoUrl = await ref.getDownloadURL();
                      await sRef.update({'photoUrl': newPhotoUrl});
                    }

                     if (gUid != null) {
                      final linkUpdate = {'studentIds': FieldValue.arrayUnion([sRef.id])};
                      await FirebaseFirestore.instance.collection('users').doc(gUid).update(linkUpdate);
                      await FirebaseFirestore.instance
                          .collection('branches')
                          .doc(branchId)
                          .collection('users')
                          .doc(gUid)
                          .set(linkUpdate, SetOptions(merge: true));
                    }

                    // Write central audit log
                    await MadrassaAuditService.logAction(
                      branchId: branchId,
                      editor: username,
                      role: role,
                      type: 'student_enrollment',
                      message: 'Enrolled new student ${finalData['name']} (Roll: ${finalData['rollNumber']})',
                      studentId: sRef.id,
                      studentName: finalData['name'] as String?,
                    );
                  }
                  nav.pop();
                } catch (e) {
                  setDs(() => isSaving = false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      isEdit ? context.l.save : context.l.enrollAndLink,
                      style: context.urduStyle(style: const TextStyle(color: Colors.white)),
                    ),
            ),
          ],
        );
      },
    ),
  );
}