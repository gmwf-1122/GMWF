import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  final hiveDir = Directory(r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive');
  Hive.init(hiveDir.path);
  final box = await Hive.openBox('local_stock');
  print('Total keys in local_stock Hive: ${box.length}');
  int hajiCount = 0;
  int saddarCount = 0;
  for (final k in box.keys) {
    if (k.toString().startsWith('stock:')) continue;
    final id = k.toString().toLowerCase();
    if (id.startsWith('haji')) hajiCount++;
    if (id.startsWith('saddar')) saddarCount++;
  }
  print('Haji items in Hive: $hajiCount');
  print('Saddar items in Hive: $saddarCount');

  print('\nSample Saddar items in Hive:');
  int count = 0;
  for (final k in box.keys) {
    if (k.toString().startsWith('stock:')) continue;
    final id = k.toString().toLowerCase();
    if (id.startsWith('saddar')) {
      final v = box.get(k);
      if (v is Map) {
        print(' - ${v['name']} (${v['type']} ${v['dose']}) | Qty: ${v['quantity']} | id: $id');
        count++;
        if (count >= 10) break;
      }
    }
  }

  await box.close();
}
