import 'package:exchange/ingestion.dart';

import 'src/lister_recettes.dart';

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
void main(List<String> arguments) => listerRecettes(
  arguments,
  nature: NatureRecettes.houblons,
  script: 'lister_houblons_recettes.dart',
  optionReferentiel: '--houblons',
  defauts: {
    '--noms': '../import/ingest/aromes/noms-houblons.json',
    '--houblons': '../import/ingest/prepare/beer_hops.json',
    '--sortie': '../import/ingest/aromes/houblons-recettes.json',
  },
  mots: 'houblons',
);
