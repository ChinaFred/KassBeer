import 'dart:convert';
import 'dart:io';

import 'package:exchange/exchange.dart' show kMaxOctetsParFichier;
import 'package:exchange/ingestion.dart';

/// Résolution des noms des recettes du groupe d'une nature rédigée, commune à
/// `bin/lister_houblons_recettes.dart` (ADR-013) et
/// `bin/lister_divers_recettes.dart` (ADR-018). [arguments] : options de la
/// ligne de commande ; [script] : nom du programme dans l'usage ;
/// [optionReferentiel] : option du référentiel préparé (`--houblons`,
/// `--divers`) ; [defauts] : chemins par défaut de `--noms`,
/// [optionReferentiel] et `--sortie` ; [mots] : nom des entrées résolues dans
/// le résumé (« houblons », « divers »).
///
/// Lit `--noms` (écrit par `ingest/`, ou une liste de noms écrite à la main
/// pour l'essai) et le référentiel, et écrit `--sortie`, avec la cible
/// (`target`) et la date (`generated_at`) de la liste des noms. N'écrit que des
/// noms et des identifiants d'ingrédients. Code de sortie : 0, ou 64 pour un
/// usage faux ; un fichier illisible arrête le programme sur son exception.
void listerRecettes(
  List<String> arguments, {
  required NatureRecettes nature,
  required String script,
  required String optionReferentiel,
  required Map<String, String> defauts,
  required String mots,
}) {
  final chemins = Map.of(defauts);
  for (var i = 0; i < arguments.length; i += 2) {
    if (!chemins.containsKey(arguments[i]) || i + 1 >= arguments.length) {
      stderr.writeln(
        'Usage : dart run bin/$script '
        '[--noms <fichier>] [$optionReferentiel <${nature.referentiel}>] '
        '[--sortie <fichier>]',
      );
      exitCode = 64;
      return;
    }
    chemins[arguments[i]] = arguments[i + 1];
  }
  final fichierNoms = _lire(chemins['--noms']!);
  final noms = lireNomsIngredients(fichierNoms);
  final index = indexIngredients(nature, _lire(chemins[optionReferentiel]!));
  final origine = origineNoms(fichierNoms);
  final resultat = ingredientsRecettes(nature, noms, index, origine: origine);
  final sortie = File(chemins['--sortie']!);
  sortie.parent.createSync(recursive: true);
  sortie.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(resultat)}\n',
  );
  final resolus = (resultat['resolus']! as List).length;
  final nonResolus = resultat['non_resolus']! as List;
  stdout.writeln(
    '${noms.length} noms : $resolus $mots résolus, '
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
