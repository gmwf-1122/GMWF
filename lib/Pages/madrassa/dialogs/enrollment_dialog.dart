import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../madrassa_strings.dart';
import '../widgets/madrassa_common_widgets.dart';
import '../../../services/auth_service.dart';
import '../../../utils/formatters.dart';

void showAddStudentDialog(BuildContext context, String branchId, {QueryDocumentSnapshot? student}) {
  final isEdit = student != null;
  final studentData = isEdit ? student.data() as Map<String, dynamic> : null;

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

  DateTime joinDate = (studentData?['joinDate'] as Timestamp?)?.toDate() ?? DateTime.now();
  bool hasPrevMadrassa = studentData?['hasPrevMadrassa'] ?? false;
  bool isNewGuardian = true;
  bool linkAccount = false;
  bool isSaving = false;
  bool isSearching = false;
  Map<String, dynamic>? foundGuardian;
  Timer? debounce;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDs) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          isEdit ? 'Edit Student Details' : MStr.en.enrollNewStudent,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionLabel(MStr.en.studentInformation),
              const SizedBox(height: 10),
              buildTf(nameCtrl, MStr.en.studentFullName, Icons.person, context),
              const SizedBox(height: 10),
              buildTf(rollCtrl, MStr.en.rollNumber, Icons.badge, context),
              const SizedBox(height: 10),
              buildTf(
                studentCnicCtrl,
                '${MStr.en.studentCnic} (XXXXX-XXXXXXX-X)',
                Icons.credit_card,
                context,
                formatters: [CNICInputFormatter(), LengthLimitingTextInputFormatter(15)],
                inputType: TextInputType.number,
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
                child: buildTf(
                  TextEditingController(text: DateFormat('dd MMMM yyyy').format(joinDate)),
                  MStr.en.joinDate,
                  Icons.calendar_today,
                  context,
                  enabled: false,
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(MStr.en.previousMadrassa,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                value: hasPrevMadrassa,
                onChanged: (v) => setDs(() => hasPrevMadrassa = v),
              ),
              if (hasPrevMadrassa) ...[
                buildTf(prevMadrassaCtrl, '${MStr.en.previousMadrassa} Name', Icons.school_outlined, context),
                const SizedBox(height: 10),
                buildTf(prevHifzCtrl, MStr.en.hifzBeforeJoining, Icons.auto_stories_outlined, context, inputType: TextInputType.number),
              ],
              const SizedBox(height: 20),
              sectionLabel(MStr.en.guardianInformation),
              const SizedBox(height: 10),
              
              buildTf(
                guardianCnicCtrl,
                '${MStr.en.guardianCnic} (XXXXX-XXXXXXX-X)',
                Icons.credit_card,
                context,
                formatters: [CNICInputFormatter(), LengthLimitingTextInputFormatter(15)],
                inputType: TextInputType.number,
                onChanged: (v) {
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
                          guardianNameCtrl.text = data['name'] ?? '';
                          contactCtrl.text = data['phone'] ?? '';
                          isNewGuardian = false;
                          isSearching = false;
                        });
                      } else {
                        setDs(() {
                          foundGuardian = null;
                          isNewGuardian = true;
                          isSearching = false;
                        });
                      }
                    });
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
                      Text('Existing Guardian Found: ${foundGuardian!['name']}', style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              buildTf(guardianNameCtrl, MStr.en.guardianFullName, Icons.family_restroom, context, enabled: foundGuardian == null),
              const SizedBox(height: 10),
              buildTf(contactCtrl, MStr.en.contactPhone, Icons.phone, context,
                  enabled: foundGuardian == null,
                  inputType: TextInputType.phone, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)]),
              
              if (!isEdit) ...[
                const SizedBox(height: 16),
                const Divider(),
                SwitchListTile(
                  title: Text(MStr.en.createLinkAccount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text(foundGuardian != null ? 'Link to existing account' : MStr.en.createLinkSubtitle, style: const TextStyle(fontSize: 11)),
                  value: linkAccount || foundGuardian != null,
                  activeThumbColor: const Color(0xFF4F46E5),
                  onChanged: foundGuardian != null ? null : (v) => setDs(() => linkAccount = v),
                ),
                if ((linkAccount || foundGuardian != null) && isNewGuardian) ...[
                  const SizedBox(height: 10),
                  buildTf(gUsernameCtrl, MStr.en.loginUsername, Icons.badge_outlined, context, hint: MStr.en.loginUsernameHint),
                  const SizedBox(height: 10),
                  buildTf(gPassCtrl, MStr.en.loginPassword, Icons.lock_outline, context, obscure: true),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(MStr.en.cancel)),
          ElevatedButton(
            onPressed: isSaving ? null : () async {
              if (nameCtrl.text.trim().isEmpty || rollCtrl.text.trim().isEmpty || guardianNameCtrl.text.trim().isEmpty || guardianCnicCtrl.text.trim().isEmpty || contactCtrl.text.trim().isEmpty) {
                return;
              }
              setDs(() => isSaving = true);
              try {
                String? gUid;
                if (!isEdit) {
                  if (foundGuardian != null) {
                    gUid = foundGuardian!['uid'];
                  } else if (linkAccount) {
                    final username = gUsernameCtrl.text.trim().toLowerCase();
                    gUid = await AuthService().signUp(
                      email: '$username@gmwf.com', password: gPassCtrl.text.trim(), username: username, role: 'Madrassa Guardian',
                      branchId: branchId, branchName: 'Madrassa', phone: contactCtrl.text.trim(), name: guardianNameCtrl.text.trim(), cnic: guardianCnicCtrl.text.trim(), studentIds: [],
                    );
                  }
                }
                
                final finalData = {
                  'name': nameCtrl.text.trim(), 'rollNumber': rollCtrl.text.trim(), 'studentCnic': studentCnicCtrl.text.trim(),
                  'guardianName': guardianNameCtrl.text.trim(), 'guardianCnic': guardianCnicCtrl.text.trim(),
                  'contactPhone': contactCtrl.text.trim(),
                  'joinDate': Timestamp.fromDate(joinDate),
                  'hasPrevMadrassa': hasPrevMadrassa, 'prevMadrassaName': prevMadrassaCtrl.text.trim(),
                  'prevHifzLines': int.tryParse(prevHifzCtrl.text.trim()) ?? 0,
                  'lastUpdatedAt': FieldValue.serverTimestamp(),
                };

                if (isEdit) {
                  await FirebaseFirestore.instance.collection('branches').doc(branchId).collection('madrassa_students').doc(student.id).set(finalData, SetOptions(merge: true));
                } else {
                  final now = DateTime.now();
                  final sRef = await FirebaseFirestore.instance.collection('branches').doc(branchId).collection('madrassa_students').add({
                    ...finalData,
                    'branchId': branchId, 'status': 'active',
                    'auditLog': [{'status': 'active', 'type': 'enrollment', 'date': Timestamp.fromDate(joinDate), 'reason': 'Initial Enrollment'}],
                    'currentLines': 0, 'enrolledMonth': DateFormat('yyyy-MM').format(now), 'createdAt': FieldValue.serverTimestamp(),
                  });
                  if (gUid != null) {
                    await FirebaseFirestore.instance.collection('users').doc(gUid).update({'studentIds': FieldValue.arrayUnion([sRef.id])});
                  }
                }
                Navigator.pop(ctx);
              } catch (e) {
                setDs(() => isSaving = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(isEdit ? 'Save Changes' : MStr.en.enrollAndLink, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
}
