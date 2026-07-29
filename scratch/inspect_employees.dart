import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final path = r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive';
  Hive.init(path);
  
  final box = await Hive.openBox('local_employees');
  print('Total employees: ${box.length}');
  
  for (final key in box.keys) {
    final val = box.get(key);
    if (val is Map) {
      final name = val['name'];
      final joiningDate = val['joiningDate'];
      final exitDate = val['exitDate'];
      final currentSalary = val['currentSalary'];
      final localId = val['localId'];
      final branchId = val['branchId'];
      final profilePicturePath = val['profilePicturePath'];
      print('ID: $localId | Name: $name | Branch: $branchId | Join: $joiningDate | Exit: $exitDate | Salary: $currentSalary | PicPath: $profilePicturePath');
    }
  }
}
