import 'dart:io';

void main() {
  final drpPath = 'lib/pages/dispensary/doctor/doctor_right_panel.dart';
  var lines = File(drpPath).readAsLinesSync();

  for (int i = 2015; i < 2035 && i < lines.length; i++) {
    if (lines[i].trim() == '}' && lines[i - 1].trim() == '}') {
      print('Removing extra } at line $i');
      lines.removeAt(i);
      break;
    }
  }

  File(drpPath).writeAsStringSync(lines.join('\r\n') + '\r\n');
  print('Done');
}
