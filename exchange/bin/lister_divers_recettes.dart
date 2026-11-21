import 'package:exchange/ingestion.dart';

import 'src/lister_recettes.dart';

/// Résout les noms de divers des recettes du groupe vers `beer_miscs/`
/// (ADR-018), depuis `exchange/` :
///
/// ```
/// dart run bin/lister_divers_recettes.dart
/// dart run bin/lister_divers_recettes.dart --noms ../import/ingest/divers/noms-essai.json \
///   --sortie ../import/ingest/divers/divers-essai.json
/// ```
///
/// Lit `--noms` (par défaut `../import/ingest/divers/noms-divers.json`, écrit
/// par `ingest/lister-divers-recettes.mjs`, ou une liste de noms écrite à la
/// main pour l'essai) et `--divers` (par défaut
/// `../import/ingest/prepare/beer_miscs.json`), et écrit `--sortie` (par
/// défaut `../import/ingest/divers/divers-recettes.json`), avec la cible
/// (`target`) et la date (`generated_at`) de la liste des noms. Un nom non
/// résolu reçoit la raison `aucun` ou `plusieurs`. N'écrit que des noms et des
/// identifiants de divers. Code de sortie : 0, ou 64 pour un usage faux ; un
/// fichier illisible arrête le programme sur son exception.
void main(List<String> arguments) => listerRecettes(
  arguments,
  nature: NatureRecettes.divers,
  script: 'lister_divers_recettes.dart',
  optionReferentiel: '--divers',
  defauts: {
    '--noms': '../import/ingest/divers/noms-divers.json',
    '--divers': '../import/ingest/prepare/beer_miscs.json',
    '--sortie': '../import/ingest/divers/divers-recettes.json',
  },
  mots: 'divers',
);
