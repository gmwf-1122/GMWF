import 'dart:io';

void main() {
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    print('lib directory not found.');
    return;
  }

  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  int updatedFiles = 0;
  int replacedCount = 0;

  final regExp = RegExp(r'\.withOpacity\(\s*([0-9.]+)\s*\)');

  for (final file in files) {
    final content = file.readAsStringSync();
    if (content.contains('.withOpacity(')) {
      final newContent = content.replaceAllMapped(regExp, (match) {
        replacedCount++;
        return '.withValues(alpha: ${match.group(1)})';
      });

      if (content != newContent) {
        file.writeAsStringSync(newContent);
        updatedFiles++;
      }
    }
  }

  print('Updated $updatedFiles files, made $replacedCount replacements.');
}
