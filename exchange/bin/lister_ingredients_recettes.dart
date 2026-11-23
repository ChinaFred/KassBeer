import 'dart:convert';
import 'dart:io';

import 'package:exchange/exchange.dart' show kMaxOctetsParFichier;
import 'package:exchange/ingestion.dart';

/// Chemins par défaut de chaque nature : noms lus, référentiel préparé, sortie.
const Map<String, Map<String, String>> _defauts = {
  'hop': {
    '--noms': '../import/ingest/aromes/noms-houblons.json',
    '--referentiel': '../import/ingest/prepare/beer_hops.json',
    '--sortie': '../import/ingest/aromes/houblons-recettes.json',
  },
  'culture': {
    '--noms': '../import/ingest/aromes/levures/noms-levures.json',
    '--referentiel': '../import/ingest/prepare/beer_cultures.json',
    '--sortie': '../import/ingest/aromes/levures/levures-recettes.json',
  },
  'misc': {
    '--noms': '../import/ingest/divers/noms-divers.json',
    '--referentiel': '../import/ingest/prepare/beer_miscs.json',
    '--sortie': '../import/ingest/divers/divers-recettes.json',
  },
};

/// Mot de chaque nature, dans le résumé.
const Map<String, String> _mots = {
  'hop': 'houblons',
  'culture': 'levures',
  'misc': 'divers',
};

const String _usage =
    'Usage : dart run bin/lister_ingredients_recettes.dart '
    '[--nature hop|culture|misc] [--noms <fichier>] '
    '[--referentiel <beer_hops.json|beer_cultures.json|beer_miscs.json>] '
    '[--sortie <fichier>]';

/// Résout les noms d'ingrédients des recettes du groupe vers `beer_hops/`
/// (`--nature hop`, par défaut, ADR-013, décisions 9 à 11), `beer_cultures/`
/// (`--nature culture`, ADR-017) ou `beer_miscs/` (`--nature misc`, ADR-018),
/// depuis `exchange/` :
///
/// ```
/// dart run bin/lister_ingredients_recettes.dart
/// dart run bin/lister_ingredients_recettes.dart --nature culture
/// dart run bin/lister_ingredients_recettes.dart --nature misc
/// dart run bin/lister_ingredients_recettes.dart --nature culture \
///   --noms ../import/ingest/aromes/levures/noms-essai.json \
///   --sortie ../import/ingest/aromes/levures/levures-essai.json
/// ```
///
/// Lit `--noms` (écrit par `ingest/lister-ingredients-recettes.mjs`, ou une
/// liste de noms écrite à la main pour l'essai) et `--referentiel` (fichier
/// préparé de la nature), et écrit `--sortie`, avec la cible (`target`) et la
/// date (`generated_at`) de la liste des noms. Un nom non résolu est listé
/// avec ses candidats. N'écrit que des noms et des identifiants. Code de
/// sortie : 0, ou 64 pour un usage faux ; un fichier illisible arrête le
/// programme sur son exception.
void main(List<String> arguments) {
  var nature = 'hop';
  final donnes = <String, String>{};
  for (var i = 0; i < arguments.length; i += 2) {
    final nom = arguments[i];
    final valide =
        nom == '--nature' ||
        nom == '--noms' ||
        nom == '--referentiel' ||
        nom == '--sortie';
    if (!valide || i + 1 >= arguments.length) {
      stderr.writeln(_usage);
      exitCode = 64;
      return;
    }
    if (nom == '--nature') {
      nature = arguments[i + 1];
    } else {
      donnes[nom] = arguments[i + 1];
    }
  }
  final defauts = _defauts[nature];
  if (defauts == null) {
    stderr.writeln('--nature : hop, culture ou misc.\n$_usage');
    exitCode = 64;
    return;
  }
  final chemins = {...defauts, ...donnes};
  final fichierNoms = _lire(chemins['--noms']!);
  final noms = lireNomsIngredients(fichierNoms);
  final referentiel = _lire(chemins['--referentiel']!);
  final index = switch (nature) {
    'culture' => indexLevures(referentiel),
    'misc' => indexDivers(referentiel),
    _ => indexHoublons(referentiel),
  };
  final origine = origineNoms(fichierNoms);
  final resultat = ingredientsRecettes(noms, index, origine: origine);
  final sortie = File(chemins['--sortie']!);
  sortie.parent.createSync(recursive: true);
  sortie.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(resultat)}\n',
  );
  final resolus = (resultat['resolus']! as List).length;
  final nonResolus = resultat['non_resolus']! as List;
  final mot = _mots[nature]!;
  stdout.writeln(
    '${noms.length} noms : $resolus $mot résolus, '
    '${nonResolus.length} noms non résolus.',
  );
  for (final n in nonResolus.cast<Map<String, Object?>>()) {
    final candidats = (n['candidats']! as List).cast<String>();
    stdout.writeln(
      '  ${n['nom']} : ${n['raison']}'
      '${candidats.isEmpty ? '' : ' (${candidats.join(', ')})'}',
    );
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
