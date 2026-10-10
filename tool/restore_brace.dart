import 'dart:io';

void main() {
  final drpPath = 'lib/pages/dispensary/doctor/doctor_right_panel.dart';
  var lines = File(drpPath).readAsLinesSync();

  for (int i = 2018; i < 2030 && i < lines.length; i++) {
    if (lines[i].trim() == '}' && lines[i - 1].contains('if (mounted) setState(() {});')) {
      print('Inserting } after line $i');
      lines.insert(i + 1, '  }');
      break;
    }
  }

  File(drpPath).writeAsStringSync(lines.join('\r\n') + '\r\n');
  print('Restored closing } for _showMedicineSelectionDialog');
}
