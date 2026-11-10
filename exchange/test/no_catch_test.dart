import 'dart:io';

import 'package:test/test.dart';

/// Le paquet ne fait aucun `catch` : il lève, l'appelant journalise (CLAUDE.md).
void main() {
  test('aucun catch ni dépendance Flutter ou Firebase dans lib/', () {
    final forbidden = RegExp(
      r'\bcatch\s*\(|\bon\s+\w+\s*(catch|\{)|package:(flutter|firebase|cloud_firestore)',
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (forbidden.hasMatch(code)) offenders.add('${entity.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
