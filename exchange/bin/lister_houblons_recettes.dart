import 'dart:convert';
import 'dart:io';

import 'package:exchange/exchange.dart' show kMaxOctetsParFichier;
import 'package:exchange/ingestion.dart';

/// Résout les noms de houblons des recettes du groupe vers `beer_hops/`
/// (ADR-013, décisions 9 à 11), depuis `exchange/` :
///
/// ```
/// dart run bin/lister_houblons_recettes.dart
/// dart run bin/lister_houblons_recettes.dart --noms ../import/ingest/aromes/noms-essai.json \
///   --sortie ../import/ingest/aromes/houblons-essai.json
/// ```
///
/// Lit `--noms` (par défaut `../import/ingest/aromes/noms-houblons.json`,
/// écrit par `ingest/lister-houblons-recettes.mjs`, ou une liste de noms écrite
/// à la main pour l'essai) et `--houblons` (par défaut
/// `../import/ingest/prepare/beer_hops.json`), et écrit `--sortie` (par défaut
/// `../import/ingest/aromes/houblons-recettes.json`), avec la cible
/// (`target`) et la date (`generated_at`) de la liste des noms. N'écrit que
/// des noms et des identifiants de houblons. Code de sortie : 0, ou 64 pour un usage faux ;
/// un fichier illisible arrête le programme sur son exception.
void main(List<String> arguments) {
  final chemins = {
    '--noms': '../import/ingest/aromes/noms-houblons.json',
    '--houblons': '../import/ingest/prepare/beer_hops.json',
    '--sortie': '../import/ingest/aromes/houblons-recettes.json',
  };
  for (var i = 0; i < arguments.length; i += 2) {
    if (!chemins.containsKey(arguments[i]) || i + 1 >= arguments.length) {
      stderr.writeln(
        'Usage : dart run bin/lister_houblons_recettes.dart '
        '[--noms <fichier>] [--houblons <beer_hops.json>] [--sortie <fichier>]',
      );
      exitCode = 64;
      return;
    }
    chemins[arguments[i]] = arguments[i + 1];
  }
  final fichierNoms = _lire(chemins['--noms']!);
  final noms = lireNomsHoublons(fichierNoms);
  final index = indexHoublons(_lire(chemins['--houblons']!));
  final origine = origineNomsHoublons(fichierNoms);
  final resultat = houblonsRecettes(noms, index, origine: origine);
  final sortie = File(chemins['--sortie']!);
  sortie.parent.createSync(recursive: true);
  sortie.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(resultat)}\n',
  );
  final resolus = (resultat['resolus']! as List).length;
  final nonResolus = resultat['non_resolus']! as List;
  stdout.writeln(
    '${noms.length} noms : $resolus houblons résolus, '
    '${nonResolus.length} noms non résolus.',
  );
  for (final n in nonResolus.cast<Map<String, Object?>>()) {
    stdout.writeln('  ${n['nom']} : ${n['raison']}');
  }
  stdout.writeln(
    'Cible de la liste : ${origine.cible ?? 'inconnue'}, '
    'lue le ${origine.genereLe ?? 'date inconnue'}.',
  );
  stdout.writeln('Liste : ${sortie.path}');
}

/// JSON du fichier [chemin], 10 Mo au plus.
Object? _lire(String chemin) {
  final fichier = File(chemin);
  final taille = fichier.lengthSync();
  if (taille > kMaxOctetsParFichier) {
    throw FormatException(
      '$chemin : $taille octets, $kMaxOctetsParFichier au plus',
    );
  }
  return jsonDecode(fichier.readAsStringSync());
}
