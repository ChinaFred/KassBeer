import 'package:brewing/brewing.dart';

import '../../../core/presentation/formats.dart';
import 'chronologie.dart';
import 'recipe.dart';

/// Libellés des étapes tirées d'une recette : préremplissage de la chronologie
/// (éditeur « Chronologie du jour ») et blocs du déroulé d'un brassin
/// (ADR-009). Texte seul : les étapes et leurs durées viennent de `brewing/`
/// (P3).

/// Quantité d'une ligne : « 22,4 g », « 5 ml », « 1,5 L ».
String formatQuantiteRecette(Quantite q) =>
    q.enLitres ? formatVolumeLigne(q.valeur) : formatGrammes(q.valeur);

/// « Ajouter Cascade 20 g », coupé à [kBrewStepNameMaxLength] caractères.
String nomEtapeAjout(String nom, Quantite quantite) => truncateName(
  'Ajouter $nom ${formatQuantiteRecette(quantite)}',
  kBrewStepNameMaxLength,
);

/// Préremplissage de la chronologie de [content] par `defaultBrewSteps` :
/// paliers, ébullition, whirlpool et houblons, étapes sans durée comprises.
List<BrewStepDraft> preremplissageChronologie(RecipeContent content) =>
    defaultBrewSteps(
      mashSteps: mashStepInputs(content),
      boilMinutes: content.boilTimeMin?.toDouble(),
      hops: [for (final h in content.hops) h.toInput()],
    );

/// Paliers de [content] vus par `brewing/`.
List<MashStepInput> mashStepInputs(RecipeContent content) => [
  for (final m in content.mashSteps)
    MashStepInput(tempC: m.tempC, durationMinutes: m.durationMin.toDouble()),
];

/// Nom d'une étape préremplie : nom du palier, « Ébullition », « Whirlpool »,
/// « Ajouter Cascade 20 g ».
String nomEtapePreremplie(BrewStepDraft draft, RecipeContent content) {
  final index = draft.sourceIndex;
  return switch (draft.kind) {
    BrewStepKind.mashStep => content.mashSteps[index!].name,
    BrewStepKind.boil => 'Ébullition',
    BrewStepKind.whirlpool => 'Whirlpool',
    BrewStepKind.hopAddition => nomEtapeAjout(
      content.hops[index!].name,
      content.hops[index].amount,
    ),
  };
}

/// Avertissement d'une étape préremplie nommée [nom], ou `null`.
String? avertissementPreremplissage(BrewStepDraft draft, String nom) {
  if (draft.durationMinutes == null) {
    return '« $nom » : durée non renseignée, étape non ajoutée.';
  }
  return switch (draft.problem) {
    BrewStepProblem.missingHopTime =>
      '« $nom » : houblon sans durée, placé en tête.',
    BrewStepProblem.hopLongerThanBoil =>
      '« $nom » : plus long que l\'ébullition, placé en tête.',
    _ => null,
  };
}
