import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:gmwf/design/tokens/comfort_colors.dart';
import 'package:gmwf/design/components/app_toast.dart';
import 'package:intl/intl.dart';
import '../madrassa_strings.dart';
import '../utils/madrassa_local_storage.dart';

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
                        style: TextStyle(fontWeight: FontWeight.bold, color: context.adapt(SoftPalette.gray900A87)),
                      ),
                      TextSpan(
                        text: ' *',
                        style: TextStyle(color: context.adapt(SoftPalette.red400), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: context.t('Enter holiday name (e.g. Eid-ul-Fitr)'),
                    errorText: nameError,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (val) {
                    if (nameError != null) setStateDialog(() => nameError = null);
                  },
                ),
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: context.t('Holiday Date'),
                        style: TextStyle(fontWeight: FontWeight.bold, color: context.adapt(SoftPalette.gray900A87)),
                      ),
                      TextSpan(
                        text: ' *',
                        style: TextStyle(color: context.adapt(SoftPalette.red400), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setStateDialog(() {
                        selectedDate = picked;
                        dateError = null;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: dateError != null ? context.adapt(SoftPalette.red400) : context.adapt(SoftPalette.gray350)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedDate == null
                              ? context.t('Select Date')
                              : DateFormat('yyyy-MM-dd').format(selectedDate!),
                          style: TextStyle(
                            color: selectedDate == null ? context.adapt(SoftPalette.gray350) : context.adapt(SoftPalette.gray900A87),
                          ),
                        ),
                        Icon(Icons.calendar_today, size: 20, color: context.adapt(SoftPalette.teal550)),
                      ],
                    ),
                  ),
                ),
                if (dateError != null) ...[
                  const SizedBox(height: 4),
                  Text(dateError!, style: TextStyle(color: context.adapt(SoftPalette.red400), fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
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
                    AppToast.showSnackBar(context, 
                      SnackBar(
                        content: Text(
                          context.t('Please correct all validation errors to continue'),
                          style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null),
                        ),
                        backgroundColor: SoftPalette.red500,
                      ),
                    );
                    return;
                  }

                  final nav = Navigator.of(ctx);
                  await MadrassaLocalStorage.saveHolidayLocalAndSync(
                    branchId: widget.branchId,
                    name: nameController.text.trim(),
                    date: selectedDate!,
                  );
                  nav.pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: SoftPalette.teal550,
                  foregroundColor: SoftPalette.gray50,
                ),
                child: Text(context.t('Add'), style: TextStyle(fontFamily: context.isUrdu ? 'Noori' : null)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteHoliday(String holidayId) async {
    await MadrassaLocalStorage.deleteHolidayLocalAndSync(
      branchId: widget.branchId,
      holidayId: holidayId,
    );
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
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: MadrassaLocalStorage.streamHolidaysCached(widget.branchId),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final holidays = snapshot.data!;
          if (holidays.isEmpty) {
            return const Center(child: Text('No holidays added yet.'));
          }

          final sortedHolidays = List<Map<String, dynamic>>.from(holidays)..sort((a, b) {
            final da = a['date']?.toString() ?? a['id']?.toString() ?? '';
            final db = b['date']?.toString() ?? b['id']?.toString() ?? '';
            return da.compareTo(db);
          });

          return ListView.builder(
            itemCount: sortedHolidays.length,
            itemBuilder: (c, i) {
              final h = sortedHolidays[i];
              final name = h['name']?.toString() ?? 'Holiday';
              final dateStr = h['date']?.toString() ?? h['id']?.toString() ?? '';
              DateTime? parsedDate;
              if (dateStr.isNotEmpty) {
                parsedDate = DateTime.tryParse(dateStr);
              }
              final displayDate = parsedDate != null ? DateFormat('yyyy-MM-dd').format(parsedDate) : dateStr;
              final hId = h['id']?.toString() ?? '';

              return ListTile(
                leading: Icon(Icons.event_note, color: ctx.adapt(SoftPalette.teal550)),
                title: Text(name),
                subtitle: Text(displayDate),
                trailing: IconButton(
                  icon: Icon(Icons.delete, color: ctx.adapt(SoftPalette.red400)),
                  onPressed: () => _deleteHoliday(hId),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
