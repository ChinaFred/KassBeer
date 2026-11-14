import 'dart:convert';
import 'dart:io';

import 'package:exchange/exchange.dart' show kMaxOctetsParFichier;
import 'package:exchange/ingestion.dart';

/// Prépare l'ingestion (ADR-005, D5) depuis `exchange/` :
///
/// ```
/// dart run bin/preparer_referentiels.dart [--sources ../import/sources] [--sortie ../import/ingest/prepare]
/// ```
///
/// Lit `brewtarget-v5.2.3/`, `fabricants/cultures.json` et
/// `punkapi-e6c12ab/data/` sous `--sources`, écrit
/// `<collection>.json` (listes `{id, data}`) et `rapport.json` sous `--sortie`.
/// Aucun réseau. Une source absente ou illisible arrête la préparation avec
/// son erreur : rien n'est écrit.
Future<void> main(List<String> arguments) async {
  final options = _options(arguments);
  final racine = options['--sources'] ?? '../import/sources';
  final sortie = options['--sortie'] ?? '../import/ingest/prepare';
  final brewtarget = '$racine/brewtarget-v5.2.3';
  String texte(Source s) =>
      _borne(File('$brewtarget/${s.fichier}')).readAsStringSync();

  final dossierDiyDog = Directory('$racine/punkapi-e6c12ab/data');
  final fichiers =
      dossierDiyDog
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (fichiers.length > kMaxFichiersDiyDog) {
    throw StateError(
      '${fichiers.length} fichiers DIY Dog, $kMaxFichiersDiyDog au plus',
    );
  }

  final preparation = preparer(
    SourcesBrutes(
      octets001: _borne(
        File('$brewtarget/${Source.brewtarget001.fichier}'),
      ).readAsBytesSync(),
      texte002: texte(Source.brewtarget002),
      texte003: texte(Source.brewtarget003),
      texte004: texte(Source.brewtarget004),
      texte005: texte(Source.brewtarget005),
      texteFabricants: _borne(
        File('$racine/fabricants/${Source.fabricants.fichier}'),
      ).readAsStringSync(),
      diyDog: [
        for (final f in fichiers)
          (
            fichier: f.uri.pathSegments.last,
            texte: _borne(f).readAsStringSync(),
          ),
      ],
    ),
  );

  final dossier = Directory(sortie)..createSync(recursive: true);
  const json = JsonEncoder.withIndent('  ');
  for (final MapEntry(:key, :value) in preparation.collections.entries) {
    File(
      '${dossier.path}/$key.json',
    ).writeAsStringSync('${json.convert(value)}\n');
  }
  File(
    '${dossier.path}/rapport.json',
  ).writeAsStringSync('${json.convert(preparation.rapport)}\n');

  final documents = preparation.rapport['documents']! as Map;
  for (final MapEntry(:key, :value) in documents.entries) {
    stdout.writeln('$key : $value documents');
  }
  final resolution = preparation.rapport['resolution']! as Map;
  for (final MapEntry(:key, :value) in resolution.entries) {
    final r = value as Map;
    stdout.writeln(
      'résolution $key : ${r['lignes']} lignes, '
      '${r['taux_avant_alias']} % avant alias, '
      '${r['taux_apres_alias']} % après alias',
    );
  }
  stdout.writeln('rapport : ${dossier.path}/rapport.json');
}

/// [fichier], si sa taille ne dépasse pas [kMaxOctetsParFichier] (10 Mo) ;
/// sinon [StateError], avant toute lecture.
File _borne(File fichier) {
  final taille = fichier.lengthSync();
  if (taille > kMaxOctetsParFichier) {
    throw StateError(
      '${fichier.path} : $taille octets, $kMaxOctetsParFichier au plus',
    );
  }
  return fichier;
}

/// Options `--nom valeur`. Une option inconnue ou sans valeur arrête le
/// programme.
Map<String, String> _options(List<String> arguments) {
  const connues = {'--sources', '--sortie'};
  final options = <String, String>{};
  for (var i = 0; i < arguments.length; i++) {
    final nom = arguments[i];
    if (!connues.contains(nom) || i + 1 >= arguments.length) {
      throw ArgumentError('option inconnue ou sans valeur : $nom');
    }
    options[nom] = arguments[++i];
  }
  return options;
}
