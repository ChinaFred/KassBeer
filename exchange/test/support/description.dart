import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

export 'decrire.dart';

/// Compare [actual] à `test/fixtures/<chemin>`, ou l'écrit si la variable
/// d'environnement `MAJ_FIXTURES` vaut 1 (fixture à relire avant le commit).
void expectFixture(String chemin, Object? actual) {
  final file = File('test/fixtures/$chemin');
  final texte = '${const JsonEncoder.withIndent('  ').convert(actual)}\n';
  if (Platform.environment['MAJ_FIXTURES'] == '1') {
    file.writeAsStringSync(texte);
    return;
  }
  expect(
    jsonDecode(texte),
    jsonDecode(file.readAsStringSync()),
    reason: 'test/fixtures/$chemin',
  );
}

/// Octets de `test/fixtures/<chemin>`.
List<int> octetsFixture(String chemin) =>
    File('test/fixtures/$chemin').readAsBytesSync();
