import 'dart:io';

void main() {
  final file = File('lib/services/master_proforma_service.dart');
  final lines = file.readAsLinesSync();
  String? curCode, curName, curType;
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.contains("'code':")) curCode = line.split(":")[1].replaceAll(RegExp(r"[', ]"), "").trim();
    if (line.contains("'name':")) curName = line.split(":")[1].replaceAll(RegExp(r"[',]"), "").trim();
    if (line.contains("'type':")) {
      curType = line.split(":")[1].replaceAll(RegExp(r"[',]"), "").trim();
      if (curCode != null && curType != null) {
        if (curCode.contains('INJ') && curType != 'Injection' && curType != 'Infusion') {
          print('MISMATCH INJ at line ${i+1}: code=$curCode, type=$curType, name=$curName');
        }
        if (curCode.contains('TAB') && curType != 'Tablet') {
          print('MISMATCH TAB at line ${i+1}: code=$curCode, type=$curType, name=$curName');
        }
        if (curCode.contains('SYR') && curType != 'Syrup' && !curCode.startsWith('EQUIP-SYR')) {
          print('MISMATCH SYR at line ${i+1}: code=$curCode, type=$curType, name=$curName');
        }
      }
    }
  }
}
