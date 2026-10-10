import 'dart:io';

void main() {
  final drpPath = 'lib/pages/dispensary/doctor/doctor_right_panel.dart';
  var lines = File(drpPath).readAsLinesSync();

  int openBraces = 0;
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    // Simple brace counter (ignore strings for rough estimate)
    for (int j = 0; j < line.length; j++) {
      if (line[j] == '{') openBraces++;
      if (line[j] == '}') openBraces--;
    }
    if (openBraces == 0 && i > 100 && i < lines.length - 20) {
      print('Braces reached 0 at line ${i + 1}: ${line.trim()}');
    }
  }
}
