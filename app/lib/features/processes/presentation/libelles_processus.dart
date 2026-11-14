import 'package:flutter/material.dart';

import '../../../core/presentation/formats.dart';
import '../../recipes/domain/chronologie.dart';
import '../domain/modele_processus.dart';

/// Libellés communs à la liste, à la fiche et à l'éditeur des processus.

/// « 1 journée », « 3 journées ».
String formatJournees(int nombre) => '$nombre journée${nombre > 1 ? 's' : ''}';

/// « 3 journées · J+0, J+4, J+14 ».
String resumeModele(ContenuModele modele) =>
    '${formatJournees(modele.journees.length)} · '
    '${[for (final j in modele.journees) 'J+${j.offsetDays}'].join(', ')}';

/// Nom d'un bloc tiré de la recette.
String nomBloc(NatureElement nature) => switch (nature) {
  NatureElement.chronologieRecette => 'Chronologie de la recette',
  NatureElement.houblonsACru => 'Houblons à cru',
  NatureElement.ajoutsEmbouteillage => 'Ajouts à l\'embouteillage',
  NatureElement.etape => throw ArgumentError.value(nature, 'nature'),
};

/// Icône d'un bloc tiré de la recette (celle des Recettes).
const iconeBloc = Icons.menu_book_outlined;

/// « Bloc de la recette : Houblons à cru », lu par le lecteur d'écran.
String blocParle(NatureElement nature) =>
    'Bloc de la recette : ${nomBloc(nature)}';

/// Mention d'une journée conditionnée à son bloc, ou `null`.
String? mentionCondition(JourneeModele journee) {
  if (!journee.requiresRecipeBlock) return null;
  final natures = journee.elements.map((e) => e.nature);
  if (natures.contains(NatureElement.houblonsACru)) {
    return 'Seulement si la recette a des houblons à cru';
  }
  if (natures.contains(NatureElement.ajoutsEmbouteillage)) {
    return 'Seulement si la recette a des ajouts à l\'embouteillage';
  }
  return null;
}

/// Étape d'un modèle vue comme une étape de chronologie : même formulaire, et
/// durées calculées par `brewing/` (P3).
BrewStepLine ligneEtape(ElementModele etape) => BrewStepLine(
  key: etape.key,
  name: etape.name!,
  durationMin: etape.durationMin!,
  tempC: etape.tempC,
);

/// Élément « étape » tiré d'une ligne saisie dans [FormulaireEtape].
ElementModele elementEtape(BrewStepLine line) => ElementModele.etape(
  key: line.key,
  name: line.name,
  durationMin: line.durationMin,
  tempC: line.tempC,
);

/// « 30 min », « action » pour une durée nulle, puis la température.
List<String> detailsEtape(ElementModele etape) {
  final minutes = etape.durationMin!;
  final temp = etape.tempC;
  return [
    if (minutes == 0)
      'action'
    else
      '${formatNombre(minutes, decimales: 1)}${nbsp}min',
    if (temp != null) formatCelsius(temp),
  ];
}

/// « 9 étapes · 4 h 15 + chronologie de la recette » : étapes du modèle seules,
/// avec leur durée, puis le bloc tiré de la recette. Sans étape, le bloc seul
/// (« Houblons à cru »).
String resumeJournee(JourneeModele journee) {
  final etapes = [
    for (final e in journee.elements)
      if (!e.estBloc) ligneEtape(e),
  ];
  final blocs = [
    for (final e in journee.elements)
      if (e.estBloc) nomBloc(e.nature),
  ];
  if (etapes.isEmpty) {
    return blocs.isEmpty ? 'Aucune étape' : blocs.join(' + ');
  }
  return [
    '${formatEtapes(etapes.length)} · '
        '${formatDuree(dureeChronologie(etapes))}',
    for (final b in blocs) b.toLowerCase(),
  ].join(' + ');
}

/// Sous-titre de « Seulement si la recette en a », pour le bloc [nature] ;
/// `null` pour un bloc qui ne conditionne pas sa journée.
String? texteCondition(NatureElement nature) => switch (nature) {
  NatureElement.houblonsACru =>
    "Sans houblon à cru dans la recette, le brassin n'aura pas cette journée.",
  NatureElement.ajoutsEmbouteillage =>
    "Sans ajout à l'embouteillage dans la recette, le brassin n'aura pas "
        'cette journée.',
  _ => null,
};
