import 'dart:io';

const _classDeclaration =
    r'^\s*(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*class\s+([A-Za-z_]\w*)';
const _largeFileWarningLines = 1500;

void main() {
  final violations = <String>[];
  final largeFiles = <String>[];

  for (final root in ['lib', 'test', 'integration_test', 'tool']) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relativePath = entity.path.replaceFirst('./', '');
      final lines = entity.readAsLinesSync();
      final classes = <String>[];
      for (final line in lines) {
        final match = RegExp(_classDeclaration).firstMatch(line);
        if (match != null) classes.add(match.group(1)!);
      }

      if (classes.length > 1) {
        violations.add(
          '$relativePath defines ${classes.length} classes: ${classes.join(', ')}',
        );
      }
      for (final name in classes.where((name) => name.startsWith('_'))) {
        violations.add('$relativePath defines private class $name');
      }
      if (lines.any((line) => line.trimLeft().startsWith('part '))) {
        violations.add(
          '$relativePath uses part/part of; hidden implementations are not allowed',
        );
      }
      if (lines.length > _largeFileWarningLines) {
        largeFiles.add('$relativePath (${lines.length} lines)');
      }
    }
  }

  if (largeFiles.isNotEmpty) {
    stdout.writeln(
      'Dart structure warnings: files over $_largeFileWarningLines lines:',
    );
    for (final file in largeFiles..sort()) {
      stdout.writeln('  - $file');
    }
  }
  if (violations.isNotEmpty) {
    stderr.writeln('Dart structure violations:');
    for (final violation in violations..sort()) {
      stderr.writeln('  - $violation');
    }
    exitCode = 1;
  }
}
