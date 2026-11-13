import 'dart:io';

import 'package:exchange/exchange.dart'
    show kMaxOctetsParFichier, RecetteDuFichier, RecetteRefusee;
import 'package:exchange/fiches.dart';

/// Vérifie un fichier de fiches préparé pour Admin › Import (v0.6, FO7),
/// depuis `exchange/` :
///
/// ```
/// dart run bin/verifier_fiches.dart ../import/fiches/fiches-kassbeer.json
/// ```
///
/// Lit le fichier avec le lecteur de l'application ([lireFichierFiches]) et
/// affiche les comptes et chaque refus, avec le chemin du champ en cause.
/// N'écrit rien, n'affiche aucun prix. Code de sortie : 0 si toutes les fiches
/// sont lues, 1 sinon, 64 pour un usage faux. Un JSON mal formé arrête le
/// programme avec la `FormatException` de `jsonDecode`.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage : dart run bin/verifier_fiches.dart <fichier.json>');
    exitCode = 64;
    return;
  }
  final fichier = File(arguments.single);
  final taille = fichier.lengthSync();
  if (taille > kMaxOctetsParFichier) {
    stdout.writeln(
      'Fichier refusé : $taille octets, $kMaxOctetsParFichier au plus.',
    );
    exitCode = 1;
    return;
  }
  final lecture = lireFichierFiches(
    fichier.readAsBytesSync(),
    maintenant: DateTime.now(),
  );
  switch (lecture) {
    case FichierFichesRefuse(:final raison, :final ficheId):
      stdout.writeln(
        'Fichier refusé : ${_raisonFichier(raison)}'
        '${ficheId == null ? '' : ' ($ficheId)'}.',
      );
      exitCode = 1;
    case FichierFiches(:final recettes, :final fiches):
      exitCode = _rapport(recettes, fiches) ? 0 : 1;
  }
}

/// Affiche le rapport ; vrai si aucune fiche n'est refusée.
bool _rapport(List<RecetteDuFichier> recettes, List<FicheDuFichier> fiches) {
  final recettesRefusees = recettes
      .where((r) => r.resultat is RecetteRefusee)
      .length;
  stdout.writeln(
    'Recettes BeerJSON : ${recettes.length}, dont $recettesRefusees refusées.',
  );
  final lues = <FicheLue>[];
  final refus = <String>[];
  for (final f in fiches) {
    switch (f.resultat) {
      case FicheAcceptee(:final fiche):
        lues.add(fiche);
      case FicheRefusee(refus: final r):
        refus.add(
          '  fiche ${f.numero} (${f.ficheId ?? 'identifiant illisible'}) : '
          '${r.chemin.isEmpty ? 'entrée' : r.chemin} : ${_code(r)}',
        );
    }
  }
  stdout.writeln(
    'Fiches : ${fiches.length}, ${lues.length} lues, '
    '${refus.length} refusées.',
  );
  var evenements = 0;
  var couts = 0;
  for (final f in lues) {
    evenements += f.evenements.length;
    if (f.cout != null) couts++;
    final debuts = f.evenements
        .where((e) => e.nature == NatureEvenementFiche.debutEtape)
        .length;
    final releves = f.evenements.where((e) => e.fermentation).length;
    final estimees = f.evenements
        .where((e) => e.origineHeure == OrigineHeure.estimeeJ28)
        .length;
    stdout.writeln(
      '  ${f.ficheId} : ${f.etapes.length} étapes, '
      '${f.evenements.length} événements ($debuts heures réelles, '
      '$releves relevés, $estimees datés J+28), '
      '${f.cout == null ? 'sans coût' : '${f.cout!.prix.length} prix et ${f.cout!.frais.length} frais'}, '
      '${f.corrections.length} corrections, ${f.deductions.length} déductions, '
      '${f.divergences.length} divergences, ${f.nonImporte.length} non importés.',
    );
  }
  final documents = {for (final f in lues) f.recipeDocId};
  stdout.writeln(
    'Total : ${lues.length} brassins, ${documents.length} recettes, '
    '$evenements heures et mesures, $couts fiches avec prix.',
  );
  if (refus.isNotEmpty) {
    stdout.writeln('Refus :');
    refus.forEach(stdout.writeln);
  }
  return refus.isEmpty;
}

String _raisonFichier(RaisonFichierFiches raison) => switch (raison) {
  RaisonFichierFiches.tropGros => 'plus de 10 Mo',
  RaisonFichierFiches.pasUnFichierDeFiches =>
    'ni `beerjson` ni `kassbeer_fiches` lisibles, ou champ inconnu à la racine',
  RaisonFichierFiches.versionInconnue => 'format_version autre que 1',
  RaisonFichierFiches.tropDeFiches => 'plus de $kMaxFiches fiches',
  RaisonFichierFiches.identifiantEnDouble => 'fiche_id en double',
};

String _code(RefusFiche refus) => switch (refus.code) {
  CodeRefusFiche.champInconnu => 'champ inconnu',
  CodeRefusFiche.champAbsent => 'champ obligatoire absent',
  CodeRefusFiche.typeInattendu => 'type inattendu',
  CodeRefusFiche.horsBornes => 'valeur hors bornes',
  CodeRefusFiche.formatInvalide => 'format invalide',
  CodeRefusFiche.enDouble => 'en double',
  CodeRefusFiche.etapeInconnue => 'step_key absente de brew_steps',
  CodeRefusFiche.evenementInconnu => 'ne désigne aucun événement du bon type',
  CodeRefusFiche.adresseWeb => 'adresse web',
  CodeRefusFiche.montant => 'montant dans un texte lu par le groupe',
  CodeRefusFiche.recetteAbsente => 'recipe_index hors des recettes',
  CodeRefusFiche.recetteRefusee =>
    'recette refusée par la lecture BeerJSON (${refus.refusRecette.runtimeType})',
  CodeRefusFiche.recetteIncoherente =>
    'même recipe_doc_id qu\'une fiche précédente, autre recette ou autre '
        'chronologie',
};
