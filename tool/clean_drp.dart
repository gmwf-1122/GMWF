import 'dart:io';

void main() {
  final drpPath = 'lib/pages/dispensary/doctor/doctor_right_panel.dart';
  var lines = File(drpPath).readAsLinesSync();

  // Find the duplicate block around line 1775
  int dupStart = -1;
  int dupEnd = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains('] else ...[') && i < 1850) {
      if (lines[i + 1].contains('InkWell(')) {
        dupStart = i;
        for (int j = i + 1; j < lines.length; j++) {
          if (lines[j].trim() == '],') {
            dupEnd = j;
            break;
          }
        }
        break;
      }
    }
  }

  print('dupStart: $dupStart, dupEnd: $dupEnd');
  if (dupStart != -1 && dupEnd != -1) {
    final correctAvailBadge = [
      '                                             ] else ...[',
      '                                               Container(',
      '                                                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),',
      '                                                 decoration: BoxDecoration(',
      '                                                   color: Colors.green.shade50,',
      '                                                   borderRadius: BorderRadius.circular(8),',
      '                                                   border: Border.all(color: Colors.green.shade300, width: 0.8),',
      '                                                 ),',
      '                                                 child: Text(',
      '                                                   \'Avail: \$availableStock\',',
      '                                                   style: TextStyle(',
      '                                                     color: Colors.green.shade800,',
      '                                                     fontWeight: FontWeight.bold,',
      '                                                     fontSize: 11,',
      '                                                   ),',
      '                                                 ),',
      '                                               ),',
      '                                             ],',
    ];
    lines.replaceRange(dupStart, dupEnd + 1, correctAvailBadge);
    print('Restored Avail badge');
  }

  // Now fix the + Select InkWell around line 1920
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains('] else ...[') && i > 1850) {
      if (lines[i + 1].contains('InkWell(')) {
        // find where the container ends
        int containerEnd = -1;
        for (int j = i + 2; j < lines.length; j++) {
          if (lines[j].trim() == '],') {
            containerEnd = j;
            break;
          }
        }
        if (containerEnd != -1) {
          final cleanSelect = [
            '                                         ] else ...[',
            '                                           InkWell(',
            '                                             onTap: () async {',
            '                                               setDialogState(() => stockWarningNotice = null);',
            '                                               await _addMedicineDialog(',
            '                                                 inventoryMed: m,',
            '                                                 existingPrescriptionMed: existingMed,',
            '                                                 callerContext: dialogCtx,',
            '                                               );',
            '                                               if (dialogCtx.mounted) setDialogState(() {});',
            '                                             },',
            '                                             borderRadius: BorderRadius.circular(8),',
            '                                             child: Container(',
            '                                               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),',
            '                                               decoration: BoxDecoration(',
            '                                                 color: isOutOfStock',
            '                                                     ? (isDark ? const Color(0xFF991B1B) : Colors.red.shade700)',
            '                                                     : (isLowStock ? (isDark ? const Color(0xFFC2410C) : Colors.orange.shade700) : _teal),',
            '                                                 borderRadius: BorderRadius.circular(8),',
            '                                               ),',
            '                                               child: Row(',
            '                                                 mainAxisSize: MainAxisSize.min,',
            '                                                 children: [',
            '                                                   Icon(',
            '                                                     isOutOfStock ? Icons.add_shopping_cart : Icons.add,',
            '                                                     color: Colors.white,',
            '                                                     size: 14,',
            '                                                   ),',
            '                                                   const SizedBox(width: 4),',
            '                                                   Text(',
            '                                                     isOutOfStock ? \'Select (0 Stock)\' : \'+ Select\',',
            '                                                     style: const TextStyle(',
            '                                                       color: Colors.white,',
            '                                                       fontWeight: FontWeight.bold,',
            '                                                       fontSize: 11.5,',
            '                                                     ),',
            '                                                   ),',
            '                                                 ],',
            '                                               ),',
            '                                             ),',
            '                                           ),',
            '                                         ],',
          ];
          lines.replaceRange(i, containerEnd + 1, cleanSelect);
          print('Cleaned + Select button');
          break;
        }
      }
    }
  }

  File(drpPath).writeAsStringSync(lines.join('\r\n') + '\r\n');
  print('Done cleaning doctor_right_panel.dart');
}
