import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:exchange/exchange.dart' show kMaxOctetsParFichier;
import 'package:exchange/ingestion.dart';

/// Prépare l'ingestion (ADR-005, D5) depuis `exchange/` :
///
/// ```
/// dart run bin/preparer_referentiels.dart [--sources ../import/sources] [--fabricants donnees/fabricants/cultures.json] [--sortie ../import/ingest/prepare] [--ba ../import/sources/ba-2026] [--table-ba donnees/styles/ba.json]
/// ```
///
/// `--ba <dossier>` (ADR-018) : joint la table de décisions versionnée
/// (`--table-ba`) et les plages recopiées du PDF (`<dossier>/styles.json`),
/// après contrôle du SHA-256 de `<dossier>/guide.pdf` contre l'en-tête de
/// `styles.json`. Sans `--ba`, aucun style de la Brewers Association.
///
/// Lit `brewtarget-v5.2.3/` et `punkapi-e6c12ab/data/` sous `--sources`, et
/// les fiches des fabricants dans `--fabricants`, fichier versionné dans
/// `exchange/donnees/` (ADR-005, amendement du 2026-11-15). Écrit
/// `<collection>.json` (listes `{id, data}`) et `rapport.json` sous `--sortie`.
/// Aucun réseau. Une source absente ou illisible arrête la préparation avec
/// son erreur : rien n'est écrit.
Future<void> main(List<String> arguments) async {
  final options = _options(arguments);
  final racine = options['--sources'] ?? '../import/sources';
  final sortie = options['--sortie'] ?? '../import/ingest/prepare';
  final fabricants =
      options['--fabricants'] ??
      'donnees/fabricants/${Source.fabricants.fichier}';
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

  final dossierBa = options['--ba'];
  final tableBa = options['--table-ba'] ?? 'donnees/styles/ba.json';
  final ba = dossierBa == null ? null : await _sourcesBa(dossierBa, tableBa);
  if (dossierBa == null) _avertirSansBa(tableBa);

  final preparation = preparer(
    SourcesBrutes(
      octets001: _borne(
        File('$brewtarget/${Source.brewtarget001.fichier}'),
      ).readAsBytesSync(),
      texte002: texte(Source.brewtarget002),
      texte003: texte(Source.brewtarget003),
      texte004: texte(Source.brewtarget004),
      texte005: texte(Source.brewtarget005),
      texteFabricants: _borne(File(fabricants)).readAsStringSync(),
      diyDog: [
        for (final f in fichiers)
          (
            fichier: f.uri.pathSegments.last,
            texte: _borne(f).readAsStringSync(),
          ),
      ],
      ba: ba,
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
  final inconnues = preparation.rapport['origines_inconnues']! as List;
  final restants = preparation.rapport['groupes_sans_parenthese']! as List;
  stdout
    ..writeln(
      'origines hors de la liste des pays : ${inconnues.length} '
      '(origines_inconnues)',
    )
    ..writeln(
      'houblons de même nom sans parenthèse : ${restants.length} groupes '
      '(groupes_sans_parenthese)',
    )
    ..writeln('rapport : ${dossier.path}/rapport.json');
  if (preparation.rapport['styles_ba'] case final Map<String, Object?> b) {
    stdout.writeln(
      'styles BA ${b['edition']} : ${b['lus']} lus, ${b['nouveaux']} '
      'nouveaux, ${(b['equivalents']! as List).length} équivalents '
      '(styles_ba.chevauchements à revoir)',
    );
  }
}

/// Sans `--ba`, avertit sur la sortie d'erreur quand la table [table] a des
/// lignes non retirées : écrire cette préparation remplacerait
/// `beer_index/styles` par un index sans entrée `ba-` ni `ba_mention`. Une
/// table absente n'avertit pas ; une table illisible arrête la préparation.
void _avertirSansBa(String table) {
  final fichier = File(table);
  if (!fichier.existsSync()) return;
  final t = lireTableBa(_borne(fichier).readAsStringSync());
  final actives = t.lignesActives.length;
  if (actives == 0) return;
  stderr.writeln(
    'ATTENTION : --ba absent, alors que $table compte $actives styles BA de '
    'l\'édition ${t.editionCourante}. Écrite, cette préparation retirera de '
    'beer_index/styles les entrées ba- et ba_mention, et laissera les '
    'documents beer_styles/ba-… sans entrée d\'index. Relancer avec --ba '
    '../import/sources/ba-${t.editionCourante} pour les garder.',
  );
}

/// Table de décisions [table] et plages de [dossier] ; [StateError] si le
/// SHA-256 de `guide.pdf` diffère de `pdf_sha256` de `styles.json`, ou si le
/// PDF manque. Le PDF n'est pas lu : il est haché.
Future<({String table, String plages})> _sourcesBa(
  String dossier,
  String table,
) async {
  final plages = _borne(File('$dossier/styles.json')).readAsStringSync();
  final attendu = lirePlagesBa(plages).pdfSha256;
  final pdf = File('$dossier/guide.pdf');
  if (!pdf.existsSync()) {
    throw StateError(
      '${pdf.path} absent : le SHA-256 du PDF ne peut être contrôlé',
    );
  }
  final lu = (await sha256.bind(pdf.openRead()).first).toString();
  if (lu != attendu) {
    throw StateError('${pdf.path} : SHA-256 $lu, styles.json attend $attendu');
  }
  return (table: _borne(File(table)).readAsStringSync(), plages: plages);
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
  const connues = {
    '--sources',
    '--fabricants',
    '--sortie',
    '--ba',
    '--table-ba',
  };
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
