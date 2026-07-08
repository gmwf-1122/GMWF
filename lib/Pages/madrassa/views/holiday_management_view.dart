import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/holiday.dart';
import '../madrassa_strings.dart';

class HolidayManagementView extends StatefulWidget {
  final String branchId;
  const HolidayManagementView({super.key, required this.branchId});

  @override
  State<HolidayManagementView> createState() => _HolidayManagementViewState();
}

class _HolidayManagementViewState extends State<HolidayManagementView> {
  Future<void> _showAddHolidayDialog() async {
    final nameController = TextEditingController();
    DateTime? selectedDate;
    String? nameError;
    String? dateError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              context.t('Add Holiday'),
              style: TextStyle(fontWeight: FontWeight.bold, fontFamily: context.isUrdu ? 'Noori' : null),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: context.t('Holiday Name'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B),
                          fontFamily: context.isUrdu ? 'Noori' : null,
                        ),
                      ),
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                  decoration: InputDecoration(
                    hintText: context.t('Holiday Name'),
                    hintStyle: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                    errorText: nameError,
                    errorStyle: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: nameError != null ? const Color(0xFFD32F2F) : const Color(0xFFD0D3D9)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF008080), width: 2),
                    ),
                  ),
                  onChanged: (v) {
                    if (nameError != null) setStateDialog(() => nameError = null);
                  },
                ),
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: context.t('Holiday Date'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B),
                          fontFamily: context.isUrdu ? 'Noori' : null,
                        ),
                      ),
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedDate == null
                            ? context.t('No date chosen')
                            : DateFormat('yyyy-MM-dd').format(selectedDate!),
                        style: TextStyle(
                          color: selectedDate == null ? Colors.grey[600] : Colors.black,
                          fontWeight: selectedDate == null ? FontWeight.normal : FontWeight.bold,
                          fontFamily: context.isUrdu ? 'Noori' : null,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.date_range, color: Color(0xFF008080)),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 5),
                        );
                        if (picked != null) {
                          setStateDialog(() {
                            selectedDate = picked;
                            dateError = null;
                          });
                        }
                      },
                      label: Text(
                        context.t('Select Date'),
                        style: TextStyle(color: const Color(0xFF008080), fontFamily: context.isUrdu ? 'Noori' : null),
                      ),
                    ),
                  ],
                ),
                if (dateError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      dateError!,
                      style: TextStyle(color: const Color(0xFFD32F2F), fontSize: 12, fontFamily: context.isUrdu ? 'Noori' : null),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(context.t('Cancel'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
              ElevatedButton(
                onPressed: () async {
                  bool isValid = true;
                  if (nameController.text.trim().isEmpty) {
                    setStateDialog(() => nameError = context.t('Holiday name is required'));
                    isValid = false;
                  }
                  if (selectedDate == null) {
                    setStateDialog(() => dateError = context.t('Holiday date is required'));
                    isValid = false;
                  }

                  if (!isValid) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.t('Please correct all validation errors to continue'),
                          style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                        ),
                        backgroundColor: const Color(0xFFDC2626),
                      ),
                    );
                    return;
                  }

                  final nav = Navigator.of(ctx);
                  await FirebaseFirestore.instance
                      .collection('branches')
                      .doc(widget.branchId)
                      .collection('madrassa_holidays')
                      .add({
                    'name': nameController.text.trim(),
                    'date': Timestamp.fromDate(selectedDate!),
                  });
                  nav.pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008080),
                  foregroundColor: Colors.white,
                ),
                child: Text(context.t('Add'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteHoliday(String docId) async {
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('madrassa_holidays')
        .doc(docId)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Holiday Management'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddHolidayDialog),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('madrassa_holidays')
            .orderBy('date')
            .snapshots(),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No holidays added yet.'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (c, i) {
               final holiday = Holiday.fromFirestore(docs[i]);
              return ListTile(
                leading: const Icon(Icons.event_note),
                title: Text(holiday.name),
                subtitle: Text(DateFormat('yyyy-MM-dd').format(holiday.date)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteHoliday(docs[i].id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
