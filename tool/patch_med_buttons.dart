import 'dart:io';

void main() {
  final drpPath = 'lib/pages/dispensary/doctor/doctor_right_panel.dart';
  var lines = File(drpPath).readAsLinesSync();

  // Find Edit button with closeSelectionDialog
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains('await Future.delayed(const Duration(milliseconds: 100));') &&
        lines[i + 1].contains('closeSelectionDialog();')) {
      print('Found delayed closeSelectionDialog at line $i');
      // Look back for final res = await _addMedicineDialog
      for (int j = i - 1; j >= i - 10; j--) {
        if (lines[j].contains('final res = await _addMedicineDialog(')) {
          lines[j] = lines[j].replaceAll('final res = await _addMedicineDialog(', 'await _addMedicineDialog(');
          break;
        }
      }
      // Remove the delayed closeSelectionDialog
      // lines[i - 1] is if (res == true && dialogCtx.mounted) {
      // lines[i] is await Future...
      // lines[i + 1] is closeSelectionDialog();
      // lines[i + 2] is } else if (dialogCtx.mounted) {
      lines.removeRange(i - 1, i + 3);
      lines.insert(i - 1, '                                                   if (dialogCtx.mounted) {');
      print('Replaced delayed closeSelectionDialog');
      break;
    }
  }

  // Find + Select button Container and wrap with InkWell
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains("isOutOfStock ? 'Select (0 Stock)' : '+ Select'")) {
      print('Found + Select text at line $i');
      // Look back for `] else ...[`
      for (int j = i - 1; j >= i - 30; j--) {
        if (lines[j].trim() == '] else ...[') {
          print('Found ] else ...[ at line $j');
          if (lines[j + 1].contains('InkWell(')) {
            print('Already has InkWell');
          } else if (lines[j + 1].contains('Container(')) {
            // Replace `Container(` with InkWell wrapping Container
            final indent = lines[j + 1].substring(0, lines[j + 1].indexOf('Container'));
            lines.insert(j + 1, '$indent  onTap: () async {');
            lines.insert(j + 2, '$indent    setDialogState(() => stockWarningNotice = null);');
            lines.insert(j + 3, '$indent    await _addMedicineDialog(');
            lines.insert(j + 4, '$indent      inventoryMed: m,');
            lines.insert(j + 5, '$indent      existingPrescriptionMed: existingMed,');
            lines.insert(j + 6, '$indent      callerContext: dialogCtx,');
            lines.insert(j + 7, '$indent    );');
            lines.insert(j + 8, '$indent    if (dialogCtx.mounted) setDialogState(() {});');
            lines.insert(j + 9, '$indent  },');
            lines.insert(j + 10, '$indent  borderRadius: BorderRadius.circular(8),');
            lines.insert(j + 1, '$indent' + 'InkWell(');

            // Now find where the container ends before `],`
            // search forward
            for (int k = j + 15; k < lines.length; k++) {
              if (lines[k].trim() == '],') {
                lines.insert(k, '$indent),');
                print('Inserted closing InkWell parenthesis at line $k');
                break;
              }
            }
          }
          break;
        }
      }
      break;
    }
  }

  File(drpPath).writeAsStringSync(lines.join('\r\n') + '\r\n');
  print('Successfully updated doctor_right_panel.dart line by line');
}
