import 'package:brewing/brewing.dart'
    show
        HopUse,
        ProcessOffsetSource,
        ProcessRecipe,
        ProcessSessionDraft,
        ProcessSessionRole,
        ProcessStepDraft,
        ProcessStepSource,
        ProcessWarningKind,
        maxProcessSessions,
        resolveProcess;
import 'package:flutter/foundation.dart';

import '../../processes/domain/modele_processus.dart';
import '../../recipes/domain/chronologie.dart';
import '../../recipes/domain/libelles_etapes.dart';
import '../../recipes/domain/recipe.dart';
import 'deroule.dart';

/// Assemblage du déroulé d'un brassin (ADR-009, lot D3) : `resolveProcess` de
/// `brewing/` rend des brouillons sans clé ni libellé (P3) ; ce fichier crée les
/// clés, les noms et les annonces de l'écran de choix, puis vérifie le déroulé
/// par [erreurDeroule] (P37).

/// Déroulé assemblé et les annonces de l'écran de choix, dans l'ordre :
/// préremplissage, puis journées retirées, puis houblons à cru.
@immutable
class DerouleAssemble {
  const DerouleAssemble({required this.deroule, required this.annonces});

  final Deroule deroule;
  final List<String> annonces;
}

/// Le modèle ne s'applique pas à la recette : chronologie de la recette
/// illisible, ou déroulé refusé par [erreurDeroule] (plus de 120 étapes dans une
/// journée, par exemple). `brewing/` lève `BrewingInputException` pour un
/// modèle invalide ou un jour d'ajout hors limites.
class AssemblageImpossible implements Exception {
  const AssemblageImpossible(this.raison, {required this.cause});

  /// Raison technique, rapportée.
  final String raison;

  /// Cause affichée au brasseur.
  final String cause;

  @override
  String toString() => 'AssemblageImpossible : $raison';
}

/// Recette figée vue par la résolution de `brewing/`.
ProcessRecipe processRecipe(RecipeContent recipe) => ProcessRecipe(
  brewStepCount: recipe.brewSteps.length,
  mashSteps: mashStepInputs(recipe),
  boilMinutes: recipe.boilTimeMin?.toDouble(),
  hops: [for (final h in recipe.hops) h.toInput()],
  hopDayMinutes: [
    for (final h in recipe.hops) h.use == HopUse.dryHop ? h.dayMin : null,
  ],
  othersAtPackaging: [
    for (final o in recipe.others) o.use == OtherUse.bottling,
  ],
);

/// Assemble le déroulé du modèle [modele] (`process_templates/[templateId]`)
/// avec la recette figée [recipe]. Chaque étape du modèle, des houblons à cru et
/// des ajouts à l'embouteillage, et chaque étape préremplie, reçoit une clé
/// neuve ([nouvelleCle] : `doc().id`) ; les étapes de la chronologie de la
/// recette gardent la leur. Une journée de houblonnage répétée se nomme
/// « {nom} 1 », « {nom} 2 ».
///
/// Lève [AssemblageImpossible] pour une chronologie de recette illisible (aucun
/// repli sur le préremplissage) ou un déroulé refusé par [erreurDeroule], et
/// `BrewingInputException` quand `brewing/` refuse le modèle ou la recette.
DerouleAssemble assemblerDeroule({
  required String templateId,
  required ContenuModele modele,
  required RecipeContent recipe,
  required String Function() nouvelleCle,
}) {
  final problem = recipe.brewStepsProblem;
  if (problem != null) {
    throw AssemblageImpossible(
      'chronologie de la recette illisible : $problem',
      cause: 'La chronologie de cette recette est illisible.',
    );
  }
  final resolution = resolveProcess(
    template: [for (final j in modele.journees) j.toInput()],
    recipe: processRecipe(recipe),
  );
  final prefill = resolution.prefill;
  final prefillNames = [for (final d in prefill) nomEtapePreremplie(d, recipe)];

  EtapeDeroulee etape(JourneeModele journee, ProcessStepDraft draft) {
    switch (draft.source) {
      case ProcessStepSource.template:
        final e = journee.elements[draft.index];
        return EtapeDeroulee(
          ligne: BrewStepLine(
            key: nouvelleCle(),
            name: e.name!,
            durationMin: e.durationMin!,
            tempC: e.tempC,
          ),
          origine: OrigineEtape.modele,
          cleEtapeModele: e.key,
        );
      case ProcessStepSource.recipeStep:
        return EtapeDeroulee(
          ligne: recipe.brewSteps[draft.index],
          origine: OrigineEtape.chronologieRecette,
        );
      case ProcessStepSource.prefill:
        final d = prefill[draft.index];
        return EtapeDeroulee(
          ligne: BrewStepLine(
            key: nouvelleCle(),
            name: prefillNames[draft.index],
            durationMin: d.durationMinutes!,
            tempC: d.tempC,
          ),
          origine: OrigineEtape.chronologieRecette,
        );
      case ProcessStepSource.dryHop:
      case ProcessStepSource.packagingHop:
        final hop = recipe.hops[draft.index];
        return _ajout(
          nouvelleCle(),
          nomEtapeAjout(hop.name, hop.amount),
          draft.source == ProcessStepSource.dryHop
              ? OrigineEtape.houblonsACru
              : OrigineEtape.ajoutsEmbouteillage,
        );
      case ProcessStepSource.packagingOther:
        final other = recipe.others[draft.index];
        return _ajout(
          nouvelleCle(),
          nomEtapeAjout(other.name, other.amount),
          OrigineEtape.ajoutsEmbouteillage,
        );
    }
  }

  JourneeDeroulee journeeDe(ProcessSessionDraft s) {
    final journee = modele.journees[s.templateSessionIndex];
    final name = journee.name.trim();
    return JourneeDeroulee(
      key: nouvelleCle(),
      name: s.repeat == null
          ? name
          : truncateName('$name ${s.repeat}', kNomJourneeMaxLength),
      offsetDays: s.offsetDays,
      sourceEcart: s.offsetSource == ProcessOffsetSource.recipe
          ? SourceEcart.recette
          : SourceEcart.modele,
      role: switch (s.role) {
        ProcessSessionRole.brew => RoleJournee.brassage,
        ProcessSessionRole.packaging => RoleJournee.embouteillage,
        ProcessSessionRole.other => RoleJournee.autre,
      },
      cleJourneeModele: journee.key,
      etapes: List.unmodifiable([for (final d in s.steps) etape(journee, d)]),
    );
  }

  final deroule = Deroule(
    journees: List.unmodifiable([
      for (final s in resolution.sessions) journeeDe(s),
    ]),
    templateId: templateId,
    templateName: truncateName(modele.name.trim(), kNomJourneeMaxLength),
  );
  for (final j in deroule.journees) {
    if (j.etapes.length > kMaxEtapesJournee) {
      throw AssemblageImpossible(
        'journée ${j.name} : ${j.etapes.length} étapes',
        cause:
            'Ce processus donne plus de $kMaxEtapesJournee étapes dans la '
            'journée « ${j.name.trim()} ». Retirez des étapes du processus.',
      );
    }
  }
  final erreur = erreurDeroule(deroule);
  if (erreur != null) {
    throw AssemblageImpossible(
      erreur,
      cause: 'Ce processus donne un déroulé invalide. $erreur',
    );
  }

  final gardees = {for (final s in resolution.sessions) s.templateSessionIndex};
  final annonces = <String>[
    if (recipe.brewSteps.isEmpty && prefill.isNotEmpty)
      'Chronologie de la recette vide : paliers et ébullition préremplis.',
    for (final w in resolution.warnings)
      if (w.prefillIndex case final int i)
        ?avertissementPreremplissage(prefill[i], prefillNames[i]),
    for (final (i, j) in modele.journees.indexed)
      if (!gardees.contains(i)) ?_journeeRetiree(j),
    for (final w in resolution.warnings)
      ?switch (w.kind) {
        ProcessWarningKind.dryHopsWithoutSession =>
          'La recette a ${w.hopCount} houblon${w.hopCount! > 1 ? 's' : ''} '
              'à cru. Ce processus n\'a pas de journée pour eux.',
        ProcessWarningKind.dryHopDayMerged =>
          'Houblons à cru du J+${w.day} regroupés au J+${w.intoDay} : '
              '$maxProcessSessions journées au plus.',
        _ => null,
      },
  ];
  return DerouleAssemble(
    deroule: deroule,
    annonces: List.unmodifiable(annonces),
  );
}

EtapeDeroulee _ajout(String key, String name, OrigineEtape origine) =>
    EtapeDeroulee(
      ligne: BrewStepLine(key: key, name: name, durationMin: 0),
      origine: origine,
    );

/// Annonce d'une journée du modèle absente du déroulé : son bloc tiré de la
/// recette est vide et elle porte `requires_recipe_block`.
String? _journeeRetiree(JourneeModele journee) {
  final natures = journee.elements.map((e) => e.nature);
  final name = journee.name.trim();
  if (natures.contains(NatureElement.houblonsACru)) {
    return 'Recette sans houblon à cru : pas de journée « $name ».';
  }
  if (natures.contains(NatureElement.ajoutsEmbouteillage)) {
    return 'Recette sans ajout à l\'embouteillage : pas de journée « $name ».';
  }
  return null;
}

/// Écart que le processus donne à la journée [journee] d'un déroulé, lu dans
/// [resolu], le même modèle assemblé de nouveau avec la recette figée :
/// « Rétablir la date du processus ». La journée se retrouve par sa journée du
/// modèle (`template_session_key`), et par son nom quand le modèle en donne
/// plusieurs (houblonnage répété). `null` si elle ne s'y retrouve pas.
({int offset, SourceEcart source})? ecartDuProcessus(
  JourneeDeroulee journee,
  Deroule resolu,
) {
  final cle = journee.cleJourneeModele;
  if (cle == null) return null;
  final memes = [
    for (final j in resolu.journees)
      if (j.cleJourneeModele == cle) j,
  ];
  final trouvee = memes.length == 1
      ? memes.single
      : memes.where((j) => j.name == journee.name).firstOrNull;
  if (trouvee == null) return null;
  return (offset: trouvee.offsetDays, source: trouvee.sourceEcart);
}
