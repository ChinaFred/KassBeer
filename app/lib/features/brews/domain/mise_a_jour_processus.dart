import 'package:brewing/brewing.dart'
    show
        ActualDayDuration,
        ActualStepDuration,
        ActualStepKind,
        DurationUpdateIssue,
        durationUpdateIssue;
import 'package:flutter/foundation.dart';

import '../../processes/domain/modele_processus.dart';
import 'deroule.dart';

/// « Mettre à jour mon processus avec ce brassin » (ADR-010) : durées réelles
/// d'un brassin proposées aux étapes de son modèle de processus. Une étape du
/// brassin se rattache à l'étape du modèle par `template_step_key` ; ses
/// journées répétées (houblonnage à cru 1, 2…) partagent la même clé, et la
/// même `template_session_key`. Durées et écarts viennent de `brewing/` (P3).

/// Durée réelle d'une journée du brassin pour une étape du modèle.
@immutable
class DureeDeJournee {
  const DureeDeJournee({
    required this.journee,
    required this.minutes,
    this.raison,
  });

  /// Nom de la journée du brassin (« Houblonnage à cru 2 »).
  final String journee;

  /// Durée réelle arrondie, ou `null` sans durée réelle.
  final int? minutes;

  /// Raison de ne pas proposer cette valeur, ou `null` si elle se propose.
  final DurationUpdateIssue? raison;
}

/// Étape du modèle à laquelle une durée réelle au moins se propose.
@immutable
class EtapeAMettreAJour {
  const EtapeAMettreAJour({
    required this.cle,
    required this.nom,
    required this.dureeActuelle,
    required this.repetee,
    required this.valeurs,
    required this.autres,
  });

  /// Clé de l'élément du modèle (`template_step_key`).
  final String cle;

  /// Nom actuel de l'étape dans le modèle.
  final String nom;

  /// Durée actuelle dans le modèle, en minutes.
  final double dureeActuelle;

  /// L'étape revient dans plusieurs journées du brassin.
  final bool repetee;

  /// Durées réelles proposables, dans l'ordre des journées du brassin.
  final List<DureeDeJournee> valeurs;

  /// Journées du brassin où l'étape n'a pas de valeur proposable, avec leur
  /// raison.
  final List<DureeDeJournee> autres;
}

/// Étapes à mettre à jour d'une journée du modèle.
@immutable
class GroupeAMettreAJour {
  const GroupeAMettreAJour({required this.journee, required this.etapes});

  /// Nom de la journée du modèle.
  final String journee;
  final List<EtapeAMettreAJour> etapes;
}

/// Durées proposées et étapes non proposées, comptées par raison.
@immutable
class MiseAJourProposee {
  const MiseAJourProposee({
    required this.groupes,
    required this.sansDureeReelle,
    required this.dejaALaDuree,
    required this.retirees,
    required this.horsBornes,
    required this.etapesDeLaRecette,
  });

  /// Groupes dans l'ordre des journées du modèle, étapes dans leur ordre.
  final List<GroupeAMettreAJour> groupes;

  /// Étapes du modèle non proposées, par raison.
  final int sansDureeReelle;
  final int dejaALaDuree;

  /// Clés d'étapes du modèle absentes du modèle actuel, chacune une fois.
  final int retirees;
  final int horsBornes;

  /// Le brassin a des étapes tirées de la recette : elles ne se proposent pas.
  final bool etapesDeLaRecette;

  bool get vide => groupes.isEmpty;

  /// Étape proposée de clé [cle], ou `null`.
  EtapeAMettreAJour? etape(String cle) {
    for (final g in groupes) {
      for (final e in g.etapes) {
        if (e.cle == cle) return e;
      }
    }
    return null;
  }
}

/// Propose les durées réelles de [deroule] aux étapes de [modele].
///
/// [durees] : prévu et réel de chaque journée commencée du brassin, par clé de
/// journée ; une journée absente n'a pas de durée réelle. Une étape du brassin
/// se propose si elle vient du modèle (`origin: template`), si sa
/// `template_step_key` désigne encore une étape (pas un bloc) du modèle, et si
/// `durationUpdateIssue` de `brewing/` l'accepte : durée réelle connue, de 1 à
/// 600 min, différente de la durée actuelle. Une étape du modèle qui revient
/// dans plusieurs journées est proposée si une de ses valeurs l'est ; sinon
/// elle compte une fois, pour la raison la plus avancée (déjà à cette durée,
/// puis hors bornes, puis sans durée réelle). Une clé absente du modèle compte
/// une fois dans [MiseAJourProposee.retirees], quel que soit son nombre de
/// journées ; une étape d'origine `template` sans clé n'est pas comptée.
///
/// Lève `BrewingInputException` pour une durée de modèle négative.
MiseAJourProposee proposerMiseAJour({
  required Deroule deroule,
  required Map<String, ActualDayDuration> durees,
  required ContenuModele modele,
}) {
  final elements = <String, ElementModele>{
    for (final j in modele.journees)
      for (final e in j.elements)
        if (!e.estBloc) e.key: e,
  };
  final occurrences =
      <String, List<({String journee, ActualStepDuration? d})>>{};
  final retirees = <String>{};
  var recette = false;
  for (final j in deroule.journees) {
    final etapes = durees[j.key]?.steps;
    for (final (i, e) in j.etapes.indexed) {
      if (e.origine != OrigineEtape.modele) {
        recette = true;
        continue;
      }
      final cle = e.cleEtapeModele;
      // Sans clé, l'étape n'a pas de lien avec le processus : ni proposée, ni
      // comptée.
      if (cle == null) continue;
      if (!elements.containsKey(cle)) {
        retirees.add(cle);
        continue;
      }
      final d = etapes != null && etapes.length == j.etapes.length
          ? etapes[i]
          : null;
      (occurrences[cle] ??= []).add((journee: j.name.trim(), d: d));
    }
  }

  var sansDuree = 0;
  var deja = 0;
  var horsBornes = 0;
  final proposees = <String, EtapeAMettreAJour>{};
  for (final MapEntry(key: cle, value: liste) in occurrences.entries) {
    final element = elements[cle]!;
    final valeurs = <DureeDeJournee>[];
    final autres = <DureeDeJournee>[];
    var raison = DurationUpdateIssue.noActual;
    for (final o in liste) {
      final reelle =
          o.d ??
          const ActualStepDuration(
            kind: ActualStepKind.none,
            plannedMinutes: 0,
          );
      final issue = durationUpdateIssue(
        actual: reelle,
        currentMinutes: element.durationMin!,
      );
      final valeur = DureeDeJournee(
        journee: o.journee,
        minutes: reelle.actualMinutes,
        raison: issue,
      );
      if (issue == null) {
        valeurs.add(valeur);
        continue;
      }
      autres.add(valeur);
      // Raison la plus avancée : l'ordre de DurationUpdateIssue.
      if (issue.index > raison.index) raison = issue;
    }
    if (valeurs.isNotEmpty) {
      proposees[cle] = EtapeAMettreAJour(
        cle: cle,
        nom: element.name!.trim(),
        dureeActuelle: element.durationMin!,
        repetee: liste.length > 1,
        valeurs: List.unmodifiable(valeurs),
        autres: List.unmodifiable(autres),
      );
      continue;
    }
    switch (raison) {
      case DurationUpdateIssue.noActual:
        sansDuree++;
      case DurationUpdateIssue.outOfBounds:
        horsBornes++;
      case DurationUpdateIssue.unchanged:
        deja++;
    }
  }

  return MiseAJourProposee(
    groupes: List.unmodifiable([
      for (final j in modele.journees)
        if (j.elements.any((e) => proposees.containsKey(e.key)))
          GroupeAMettreAJour(
            journee: j.name.trim(),
            etapes: List.unmodifiable([
              for (final e in j.elements) ?proposees[e.key],
            ]),
          ),
    ]),
    sansDureeReelle: sansDuree,
    dejaALaDuree: deja,
    retirees: retirees.length,
    horsBornes: horsBornes,
    etapesDeLaRecette: recette,
  );
}

/// [modele] dont les étapes de [durees] (clé de l'élément → minutes) prennent
/// leur nouvelle durée ; tout le reste est inchangé. Une clé absente du modèle
/// est ignorée.
ContenuModele avecDurees(ContenuModele modele, Map<String, double> durees) =>
    ContenuModele(
      name: modele.name,
      notes: modele.notes,
      journees: [
        for (final j in modele.journees)
          JourneeModele(
            key: j.key,
            name: j.name,
            offsetDays: j.offsetDays,
            requiresRecipeBlock: j.requiresRecipeBlock,
            elements: [
              for (final e in j.elements)
                e.estBloc || !durees.containsKey(e.key)
                    ? e
                    : ElementModele.etape(
                        key: e.key,
                        name: e.name!,
                        durationMin: durees[e.key]!,
                        tempC: e.tempC,
                      ),
            ],
          ),
      ],
    );

/// Durées actuelles de [modele] pour les clés [cles] : ce que « Annuler »
/// réécrit.
Map<String, double> dureesActuelles(
  ContenuModele modele,
  Iterable<String> cles,
) {
  final voulues = cles.toSet();
  return {
    for (final j in modele.journees)
      for (final e in j.elements)
        if (!e.estBloc && voulues.contains(e.key)) e.key: e.durationMin!,
  };
}
