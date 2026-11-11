import 'package:brewing/brewing.dart'
    show
        maxProcessOffsetDays,
        maxProcessSessions,
        processSessionDate,
        processSessionOrder;
import 'package:flutter/foundation.dart';

import '../../recipes/domain/chronologie.dart';
import '../../recipes/domain/recipe.dart';

/// Déroulé figé d'un brassin (`brews/{id}.process`, ADR-009) : de 1 à 5 journées
/// résolues depuis un modèle de processus et la recette figée. Se lit par
/// `Brew.deroule`, seul accès aux étapes d'un brassin (P37).

/// Version du format de `process`.
const kDerouleFormatVersion = 1;

/// Étapes d'une journée résolue : 59 du modèle et 60 de la recette.
const kMaxEtapesJournee = 120;

/// Longueurs maximales (`firestore.rules` pour l'identifiant et le nom du modèle).
const kTemplateIdMaxLength = 128;
const kNomJourneeMaxLength = 120;
const kCleJourneeMaxLength = 100;

/// Clé de la journée unique d'un brassin sans `process` : elle ne s'écrit nulle part.
const kCleJourneeRecette = 'recette';

/// Nom de la journée unique d'un brassin sans `process`.
const kNomJourneeBrassage = 'Brassage';

/// Origine d'une étape résolue (`origin`).
enum OrigineEtape {
  modele('template'),
  chronologieRecette('recipe_steps'),
  houblonsACru('dry_hops'),
  ajoutsEmbouteillage('packaging_additions');

  const OrigineEtape(this.storedValue);

  final String storedValue;
}

/// Rôle d'une journée résolue (`role`).
enum RoleJournee {
  brassage('brew'),
  embouteillage('packaging'),
  autre('other');

  const RoleJournee(this.storedValue);

  final String storedValue;
}

/// Source de l'écart d'une journée (`offset_source`).
enum SourceEcart {
  modele('template'),
  recette('recipe'),
  brasseur('brewer');

  const SourceEcart(this.storedValue);

  final String storedValue;
}

/// Étape d'une journée résolue : une ligne de chronologie, son origine, et la clé
/// de l'étape du modèle dont elle vient (lue par le prévu/réel d'une livraison
/// suivante).
@immutable
class EtapeDeroulee {
  const EtapeDeroulee({
    required this.ligne,
    required this.origine,
    this.cleEtapeModele,
  });

  final BrewStepLine ligne;
  final OrigineEtape origine;
  final String? cleEtapeModele;

  /// Liste blanche des champs : aucun prix ni coût (P5).
  Map<String, Object?> toFirestore() => {
    ...ligne.toFirestore(),
    'origin': origine.storedValue,
    'template_step_key': ?cleEtapeModele,
  };
}

/// Journée résolue d'un brassin.
@immutable
class JourneeDeroulee {
  const JourneeDeroulee({
    required this.key,
    required this.name,
    required this.offsetDays,
    required this.sourceEcart,
    required this.role,
    required this.etapes,
    this.cleJourneeModele,
  });

  final String key;
  final String name;

  /// Écart en jours depuis le début du brassage.
  final int offsetDays;
  final SourceEcart sourceEcart;
  final RoleJournee role;
  final List<EtapeDeroulee> etapes;

  /// Journée du modèle dont elle vient.
  final String? cleJourneeModele;

  /// Lignes de chronologie de la journée, dans l'ordre.
  List<BrewStepLine> get lignes => [for (final e in etapes) e.ligne];

  /// Date de la journée depuis le départ [depart] (`brewed_at`, sinon
  /// `planned_for`), calculée par `brewing/` ; `null` sans départ.
  DateTime? date(DateTime? depart) => depart == null
      ? null
      : processSessionDate(start: depart, offsetDays: offsetDays);

  /// Même journée à l'écart [offset], de source [source].
  JourneeDeroulee avecEcart(int offset, SourceEcart source) => JourneeDeroulee(
    key: key,
    name: name,
    offsetDays: offset,
    sourceEcart: source,
    role: role,
    etapes: etapes,
    cleJourneeModele: cleJourneeModele,
  );

  Map<String, Object?> toFirestore() => {
    'key': key,
    'name': name.trim(),
    'offset_days': offsetDays,
    'offset_source': sourceEcart.storedValue,
    'role': role.storedValue,
    'template_session_key': ?cleJourneeModele,
    'steps': [for (final e in etapes) e.toFirestore()],
  };
}

/// Déroulé d'un brassin, lu de `process` ou tiré de la chronologie de la recette
/// figée. Illisible, il n'a aucune journée et porte [probleme] : l'écran affiche la
/// panne, sans repli sur la chronologie de la recette.
@immutable
class Deroule {
  const Deroule({
    required this.journees,
    this.templateId,
    this.templateName,
    this.resolu = true,
  }) : probleme = null;

  const Deroule.illisible(String this.probleme, {required this.resolu})
    : journees = const [],
      templateId = null,
      templateName = null;

  /// Journée de brassage unique d'un brassin sans `process`, tirée de
  /// `recipe_snapshot.brew_steps` (lecture tolérante, ADR-009). Une chronologie
  /// illisible rend le déroulé illisible.
  factory Deroule.depuisRecette(RecipeContent recipe) {
    final problem = recipe.brewStepsProblem;
    if (problem != null) return Deroule.illisible(problem, resolu: false);
    return Deroule(
      resolu: false,
      journees: [
        JourneeDeroulee(
          key: kCleJourneeRecette,
          name: kNomJourneeBrassage,
          offsetDays: 0,
          sourceEcart: SourceEcart.modele,
          role: RoleJournee.brassage,
          etapes: [
            for (final s in recipe.brewSteps)
              EtapeDeroulee(ligne: s, origine: OrigineEtape.chronologieRecette),
          ],
        ),
      ],
    );
  }

  final List<JourneeDeroulee> journees;
  final String? templateId;
  final String? templateName;

  /// Vrai si le déroulé vient de `process`, faux s'il est tiré de la recette.
  final bool resolu;

  /// Raison de l'illisibilité, ou `null`.
  final String? probleme;

  /// Journée de brassage, la première ; `null` si le déroulé est illisible.
  JourneeDeroulee? get brassage => journees.firstOrNull;

  /// Lignes de toutes les journées, dans l'ordre.
  List<BrewStepLine> get lignes => [for (final j in journees) ...j.lignes];

  /// Journée de clé [key], ou `null` si le déroulé n'en a pas.
  JourneeDeroulee? journee(String key) {
    for (final j in journees) {
      if (j.key == key) return j;
    }
    return null;
  }

  /// Étape de clé [key] et sa journée, ou `null` pour une clé inconnue.
  ({JourneeDeroulee journee, BrewStepLine ligne})? etape(String key) {
    for (final j in journees) {
      for (final l in j.lignes) {
        if (l.key == key) return (journee: j, ligne: l);
      }
    }
    return null;
  }

  /// Journée d'embouteillage, ou `null` si le déroulé n'en a pas.
  JourneeDeroulee? get embouteillage {
    for (final j in journees) {
      if (j.role == RoleJournee.embouteillage) return j;
    }
    return null;
  }

  /// Même déroulé, la journée [key] à l'écart [offset] de source [source].
  /// Les journées se rangent de nouveau par `processSessionOrder` de `brewing/` :
  /// la journée de brassage en tête, les suivantes par écart, à égalité dans
  /// leur ordre précédent. Lève [StateError] pour un déroulé illisible, ou pour
  /// la journée de brassage, toujours à J+0 ; `BrewingInputException` pour un
  /// écart hors de 0 à 365 jours.
  Deroule avecEcart(String key, int offset, SourceEcart source) {
    if (probleme != null) throw StateError('déroulé illisible');
    if (brassage?.key == key) throw StateError('journée de brassage à J+0');
    final changees = [
      for (final j in journees) j.key == key ? j.avecEcart(offset, source) : j,
    ];
    // Ordre de `brewing/`, celui de la résolution (P3).
    final ordre = processSessionOrder([for (final j in changees) j.offsetDays]);
    return Deroule(
      journees: List.unmodifiable([for (final i in ordre) changees[i]]),
      templateId: templateId,
      templateName: templateName,
    );
  }

  /// Valeur de `process`. Lève [StateError] pour un déroulé illisible.
  Map<String, Object?> toFirestore() {
    if (probleme != null) throw StateError('déroulé illisible');
    return {
      'format_version': kDerouleFormatVersion,
      'template_id': templateId,
      'template_name': templateName?.trim(),
      'sessions': [for (final j in journees) j.toFirestore()],
    };
  }
}

/// Lit la valeur de `process`. Un champ inconnu est ignoré ; un format inconnu, une
/// clé en double ou une borne dépassée rend le déroulé illisible, avec sa raison.
Deroule lireDeroule(Object? raw) {
  Deroule illisible(String reason) =>
      Deroule.illisible('déroulé, $reason', resolu: true);
  if (raw is! Map) return illisible('map attendue');
  if (raw['format_version'] != kDerouleFormatVersion) {
    return illisible('format inconnu');
  }
  final templateId = raw['template_id'];
  if (templateId != null &&
      (templateId is! String || templateId.length > kTemplateIdMaxLength)) {
    return illisible('modèle d\'origine illisible');
  }
  final templateName = raw['template_name'];
  if (templateName != null &&
      (templateName is! String || templateName.length > kNomJourneeMaxLength)) {
    return illisible('nom du modèle illisible');
  }
  final sessions = raw['sessions'];
  if (sessions is! List ||
      sessions.isEmpty ||
      sessions.length > maxProcessSessions) {
    return illisible('de 1 à $maxProcessSessions journées attendues');
  }
  final journeeKeys = <String>{};
  final stepKeys = <String>{};
  final journees = <JourneeDeroulee>[];
  for (final (i, s) in sessions.indexed) {
    final rang = 'journée ${i + 1}';
    if (s is! Map) return illisible('$rang illisible');
    final key = s['key'];
    if (key is! String ||
        key.isEmpty ||
        key.length > kCleJourneeMaxLength ||
        !journeeKeys.add(key)) {
      return illisible('$rang : clé invalide');
    }
    final name = s['name'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > kNomJourneeMaxLength) {
      return illisible('$rang : nom invalide');
    }
    final offset = s['offset_days'];
    if (offset is! int || offset < 0 || offset > maxProcessOffsetDays) {
      return illisible('$rang : écart hors limites');
    }
    final source = _valeur(
      SourceEcart.values,
      s['offset_source'],
      (v) => v.storedValue,
    );
    if (source == null) return illisible('$rang : source de l\'écart inconnue');
    final role = _valeur(RoleJournee.values, s['role'], (v) => v.storedValue);
    if (role == null || (role == RoleJournee.brassage) != (i == 0)) {
      return illisible('$rang : rôle invalide');
    }
    final sessionKey = s['template_session_key'];
    if (sessionKey != null &&
        (sessionKey is! String || sessionKey.length > kCleJourneeMaxLength)) {
      return illisible('$rang : journée du modèle illisible');
    }
    final steps = s['steps'];
    if (steps is! List || steps.length > kMaxEtapesJournee) {
      return illisible('$rang : $kMaxEtapesJournee étapes au plus');
    }
    final etapes = <EtapeDeroulee>[];
    for (final (k, step) in steps.indexed) {
      final where = '$rang, étape ${k + 1}';
      if (step is! Map) return illisible('$where illisible');
      // Mêmes bornes qu'une étape de brew_steps (readBrewSteps).
      final lue = readBrewSteps([step]);
      final problem = lue.problem;
      if (problem != null) {
        return illisible('$where : ${problem.replaceAll(' (0)', '')}');
      }
      final ligne = lue.steps.single;
      if (!stepKeys.add(ligne.key)) {
        return illisible('$where : clé en double');
      }
      final origine = _valeur(
        OrigineEtape.values,
        step['origin'],
        (v) => v.storedValue,
      );
      if (origine == null) return illisible('$where : origine inconnue');
      final templateStep = step['template_step_key'];
      if (templateStep != null &&
          (templateStep is! String ||
              templateStep.length > kBrewStepKeyMaxLength)) {
        return illisible('$where : étape du modèle illisible');
      }
      etapes.add(
        EtapeDeroulee(
          ligne: ligne,
          origine: origine,
          cleEtapeModele: templateStep as String?,
        ),
      );
    }
    journees.add(
      JourneeDeroulee(
        key: key,
        name: name,
        offsetDays: offset,
        sourceEcart: source,
        role: role,
        cleJourneeModele: sessionKey as String?,
        etapes: List.unmodifiable(etapes),
      ),
    );
  }
  if (journees.where((j) => j.role == RoleJournee.embouteillage).length > 1) {
    return illisible('deux journées d\'embouteillage');
  }
  return Deroule(
    journees: List.unmodifiable(journees),
    templateId: templateId as String?,
    templateName: templateName as String?,
  );
}

T? _valeur<T>(List<T> values, Object? stored, String Function(T) storedOf) {
  for (final v in values) {
    if (storedOf(v) == stored) return v;
  }
  return null;
}

/// Première erreur d'un déroulé à enregistrer, ou `null` : le dépôt n'écrit
/// `process` qu'à cette condition (les règles ne lisent pas les journées). Clés
/// d'étapes uniques sur toutes les journées (P37).
String? erreurDeroule(Deroule deroule) {
  if (deroule.probleme != null) return 'Déroulé illisible.';
  final journees = deroule.journees;
  if (journees.isEmpty || journees.length > maxProcessSessions) {
    return 'De 1 à $maxProcessSessions journées.';
  }
  final templateId = deroule.templateId;
  if (templateId != null && templateId.length > kTemplateIdMaxLength) {
    return 'Modèle d\'origine invalide.';
  }
  final templateName = deroule.templateName;
  if (templateName != null &&
      templateName.trim().length > kNomJourneeMaxLength) {
    return 'Nom du modèle trop long.';
  }
  final journeeKeys = <String>{};
  final stepKeys = <String>{};
  for (final (i, j) in journees.indexed) {
    final rang = 'Journée ${i + 1}';
    if (j.key.isEmpty ||
        j.key.length > kCleJourneeMaxLength ||
        !journeeKeys.add(j.key)) {
      return '$rang : clé invalide.';
    }
    if (j.name.trim().isEmpty || j.name.trim().length > kNomJourneeMaxLength) {
      return '$rang : nom invalide.';
    }
    if (j.offsetDays < 0 || j.offsetDays > maxProcessOffsetDays) {
      return '$rang : écart hors de 0 à $maxProcessOffsetDays jours.';
    }
    if ((j.role == RoleJournee.brassage) != (i == 0)) {
      return '$rang : rôle invalide.';
    }
    final etapes = erreurChronologie(j.lignes, maxSteps: kMaxEtapesJournee);
    if (etapes != null) {
      return '$rang, ${etapes[0].toLowerCase()}${etapes.substring(1)}';
    }
    for (final e in j.etapes) {
      if (!stepKeys.add(e.ligne.key)) return '$rang : clé d\'étape en double.';
      final templateStep = e.cleEtapeModele;
      if (templateStep != null &&
          (templateStep.isEmpty ||
              templateStep.length > kBrewStepKeyMaxLength)) {
        return '$rang : étape du modèle invalide.';
      }
    }
  }
  if (journees.where((j) => j.role == RoleJournee.embouteillage).length > 1) {
    return 'Une seule journée d\'embouteillage.';
  }
  return null;
}
