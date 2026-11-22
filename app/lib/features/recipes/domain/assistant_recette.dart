import 'dart:math';

import 'package:brewing/brewing.dart';
import 'package:exchange/exchange.dart'
    show Proposition, PropositionIllisible, PropositionLue, lireProposition;
import 'package:flutter/foundation.dart';

import '../../equipment/domain/equipment.dart';
import '../../library/domain/aromes_houblon.dart';
import '../../library/domain/referentiel.dart';
import 'recipe.dart';

/// Assistant de recette (ADR-015, lot A1) : conversation en mémoire, données
/// envoyées à la callable `recipeAssistantTurn`, lecture de sa réponse et de
/// ses refus. Aucune formule : les calculs envoyés sont ceux de
/// `computeRecipe` (P3). Aucune borne du serveur recopiée : la taille d'une
/// conversation et les plafonds sont contrôlés par le serveur, qui refuse avec
/// `details.reason` (P59, P60).

/// Message de la personne : 1 500 caractères au plus (ADR-015, section 4).
/// Le champ l'affiche ; le serveur le refuse aussi.
const kAssistantMessageMax = 1500;

/// Arômes joints : 20 houblons distincts au plus (ADR-015, section 4, U17).
const kAssistantAromesMax = 20;

/// Raccourcis : ils remplissent le champ, sans rien envoyer.
const kRaccourciAnalyser =
    'Analyse cette recette : équilibre des malts, amertume, couleur, levure et '
    'empâtage. Signale ce qui paraît incohérent avec le style.';
const kRaccourciAmeliorer =
    'Propose des améliorations à cette recette, en expliquant chacune. Je les '
    'appliquerai moi-même.';

/// Auteur d'un message de la conversation.
enum AuteurMessage {
  personne('user'),
  assistant('assistant');

  const AuteurMessage(this.role);

  /// Rôle envoyé dans `history`.
  final String role;
}

@immutable
class MessageConversation {
  const MessageConversation(this.auteur, this.texte);

  final AuteurMessage auteur;
  final String texte;

  Map<String, Object?> versArgument() => {'role': auteur.role, 'text': texte};
}

const _alphabetId =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';

/// Identifiant d'une conversation, tiré à l'ouverture du panneau et à chaque
/// nouvelle conversation : 22 caractères de `^[A-Za-z0-9_-]{8,64}$`.
String nouvelIdConversation([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 22; i++)
      _alphabetId.codeUnitAt(r.nextInt(_alphabetId.length)),
  ]);
}

/// Mode d'un appel : un tour, ou le résumé de la conversation (amendement
/// « cadrage du lot A1 »).
enum ModeAssistant { tour, resume }

/// Données de la recette envoyées avec chaque tour (ADR-015, section 5).
@immutable
class ContexteAssistant {
  const ContexteAssistant({
    required this.recette,
    required this.calculs,
    this.equipement,
    this.style,
    this.aromes = const [],
  });

  /// Sous-arbre `recipe` en BeerJSON partiel, sans `author`.
  final Map<String, Object?> recette;

  /// Valeurs de `computeRecipe` ([calculsPourAssistant]).
  final Map<String, Object?> calculs;
  final Map<String, Object?>? equipement;
  final Map<String, Object?>? style;
  final List<Map<String, Object?>> aromes;
}

/// Argument de `recipeAssistantTurn`, en liste blanche (P59) : `message` en
/// mode tour seulement, `mode` absent pour un tour, `summary` quand la
/// conversation part d'un résumé.
Map<String, Object?> argumentsAssistant({
  required String idConversation,
  required List<MessageConversation> historique,
  required ModeAssistant mode,
  String? message,
  String? resume,
  required ContexteAssistant contexte,
}) => {
  'conversationId': idConversation,
  'history': [for (final m in historique) m.versArgument()],
  if (mode == ModeAssistant.tour) 'message': message,
  if (mode == ModeAssistant.resume) 'mode': 'summary',
  'summary': ?resume,
  'recipe': contexte.recette,
  'calculs': contexte.calculs,
  'equipment': ?contexte.equipement,
  'style': ?contexte.style,
  if (contexte.aromes.isNotEmpty) 'aromas': contexte.aromes,
};

/// Recette envoyée : le sous-arbre `recipe` du document, sans `author` (nom
/// d'une personne, que l'utilisateur exclut ; le serveur le retire aussi).
/// Rien de l'enveloppe : ni propriétaire, ni dates, ni prix (P5). Lève
/// [ArgumentError] ou [BrewingInputException] comme
/// [RecipeContent.toFirestore].
Map<String, Object?> recettePourAssistant(RecipeContent content) {
  final recipe = Map<String, Object?>.from(
    content.toFirestore(creation: true)['recipe']! as Map,
  )..remove('author');
  return recipe;
}

Map<String, Object?>? _resultat(CalculationResult r, String unit) =>
    switch (r) {
      CalculationComputed(:final value) => {'value': value, 'unit': unit},
      CalculationUnavailable() => null,
    };

/// Calculs envoyés, tirés de `computeRecipe` sur le brouillon (U14) : une
/// valeur indisponible part absente, et `missing_inputs` nomme ce qui manque.
/// [champRefuse] : `brewing/` a refusé une valeur, aucun calcul ne part.
Map<String, Object?> calculsPourAssistant(
  RecipeCalculation? calcul, {
  String? champRefuse,
  double? rendementEmpatage,
}) {
  if (calcul == null) {
    return {'refused_field': ?champRefuse};
  }
  return {
    'original_gravity': ?_resultat(calcul.originalGravity, 'sg'),
    'final_gravity': ?_resultat(calcul.finalGravity, 'sg'),
    'abv': ?_resultat(calcul.alcoholByVolume, '%'),
    'ibu': ?_resultat(calcul.bitternessIbu, 'IBU'),
    'color': ?_resultat(calcul.colorEbc, 'EBC'),
    'mash_efficiency_pct': ?rendementEmpatage,
    if (calcul.hopBitterness.isNotEmpty)
      'hop_ibu': [
        for (final h in calcul.hopBitterness)
          {'index': h.hop.index, 'name': h.hop.name, 'ibu': h.ibu},
      ],
    if (calcul.hopsLongerThanBoil.isNotEmpty)
      'hops_longer_than_boil': [
        for (final h in calcul.hopsLongerThanBoil) h.name,
      ],
    if (calcul.missingInputs.isNotEmpty)
      'missing_inputs': [for (final m in calcul.missingInputs) m.kind.name],
  };
}

/// Profil d'équipement envoyé : volumes, rendement, pertes, évaporation, nom,
/// notes (ADR-015, section 5). Ni propriétaire ni dates.
Map<String, Object?> equipementPourAssistant(EquipmentContent content) => {
  for (final e in content.toFirestore(creation: true).entries)
    if (e.value != null) e.key: e.value,
};

Map<String, Object?>? _plage(Plage? p, String unit) => p == null
    ? null
    : {'minimum': ?p.minimum, 'maximum': ?p.maximum, 'unit': unit};

/// Style de la Bibliothèque envoyé : nom, code, catégorie et plages chiffrées
/// (ADR-015, section 5).
Map<String, Object?> stylePourAssistant(FicheStyle style) => {
  'name': style.name,
  'code': ?style.styleId,
  'category': ?style.category,
  'original_gravity': ?_plage(style.og, 'sg'),
  'final_gravity': ?_plage(style.fg, 'sg'),
  'ibu': ?_plage(style.ibu, 'IBU'),
  'color': ?_plage(style.color, 'EBC'),
  'abv': ?_plage(style.abv, '%'),
};

/// Description aromatique d'un houblon de la recette, textes tels qu'en base.
Map<String, Object?> aromesPourAssistant(String houblon, AromesHoublon a) =>
    switch (a) {
      AromesInconnus() => {'hop': houblon, 'status': 'unknown'},
      AromesDecrits(:final descripteurs, :final usages, :final confiance) => {
        'hop': houblon,
        'status': 'described',
        'confidence': switch (confiance) {
          ConfianceArome.haute => 'high',
          ConfianceArome.moyenne => 'medium',
          ConfianceArome.faible => 'low',
        },
        'descriptors': [for (final d in descripteurs) d.label],
        'uses': {for (final e in usages.entries) e.key.cle: e.value},
      },
    };

/// Noms distincts des houblons de [content], dans l'ordre de la recette,
/// [kAssistantAromesMax] au plus (U17).
List<String> houblonsDistincts(RecipeContent content) {
  final noms = <String>[];
  for (final h in content.hops) {
    final nom = h.name.trim();
    if (nom.isEmpty || noms.contains(nom)) continue;
    noms.add(nom);
    if (noms.length == kAssistantAromesMax) break;
  }
  return noms;
}

/// Tours restants rendus par le serveur (`quota` de la réponse, ou
/// `details.quota` d'un refus après réservation).
typedef QuotaRendu = ({int limite, int restants, DateTime? repriseLe});

QuotaRendu? _lireQuota(Object? quota) {
  if (quota is! Map) return null;
  final limite = quota['limit'];
  final restants = quota['remaining'];
  final reprise = quota['resets_at'];
  if (limite is! int || restants is! int) return null;
  return (
    limite: limite,
    restants: restants,
    repriseLe: reprise is String ? DateTime.tryParse(reprise)?.toLocal() : null,
  );
}

/// Réponse de `recipeAssistantTurn` : `{reponse, proposition, turn, quota}`
/// (ADR-015, section 3). Au lot A2, `proposition` est relue par
/// `lireProposition` (`exchange/`) : une proposition hors format n'est pas
/// proposée.
@immutable
class ReponseAssistant {
  const ReponseAssistant({
    required this.texte,
    this.tour,
    this.quota,
    this.proposition,
    this.propositionEcartee = false,
  });

  /// Markdown du modèle (ou résumé, en mode résumé).
  final String texte;

  /// Numéro du tour dans la conversation, s'il est rendu.
  final int? tour;
  final QuotaRendu? quota;

  /// Proposition du modèle, relue, ou `null`.
  final Proposition? proposition;

  /// Vrai si le modèle a rendu une proposition écartée : par le serveur
  /// (`proposition_rejected`, hors format ou plus de 30 opérations) ou par
  /// la relecture du client.
  final bool propositionEcartee;

  /// Lève [FormatException] sur une réponse sans texte.
  factory ReponseAssistant.lire(Object? data) {
    if (data is! Map) throw const FormatException('réponse : map attendue');
    final texte = data['reponse'];
    if (texte is! String || texte.trim().isEmpty) {
      throw const FormatException('réponse : texte absent');
    }
    final tour = data['turn'];
    final brute = data['proposition'];
    final lue = brute == null ? null : lireProposition(brute);
    return ReponseAssistant(
      texte: texte,
      tour: tour is int ? tour : null,
      quota: _lireQuota(data['quota']),
      proposition: lue is PropositionLue ? lue.proposition : null,
      propositionEcartee:
          data['proposition_rejected'] == true || lue is PropositionIllisible,
    );
  }
}

/// Raison d'un refus ou d'un échec d'un tour, lue dans `details.reason`.
enum CauseEchecAssistant {
  /// `ai_policy_unavailable` : réglages absents ou illisibles, rien compté.
  reglagesAbsents,

  /// `ai_feature_closed` : poste fermé aux membres, rien compté.
  posteFerme,

  /// `quota_exhausted` : plafond du jour atteint, rien compté.
  plafondJour,

  /// `conversation_full` : conversation trop longue ou trop de tours.
  conversationPleine,

  /// Une donnée dépasse sa borne (`details.field`), rien compté.
  tropLong,

  /// `ai_credit_exhausted` : crédit de l'espace de travail épuisé, rendu.
  creditEpuise,

  /// `ai_rate_limited` : limite de débit d'Anthropic (429), rendu.
  tropDemande,

  /// `ai_no_answer` : refus `refusal` ou `max_tokens` du modèle, compté.
  reponseIllisible,

  /// `ai_timeout`, `ai_failed` : délai dépassé, 5xx ou 529, compté.
  delaiDepasse,

  /// `ai_request_rejected`, `ai_unreachable`, `ai_unavailable`,
  /// `ai_cost_center_unknown` : autre 4xx d'Anthropic, connexion impossible
  /// avant l'envoi, panne ou poste inconnu du serveur avant la réservation ;
  /// rien compté.
  envoiImpossible,

  /// `ai_key_invalid`, `ai_model_unavailable` : réglage à corriger par
  /// l'administrateur ; rien compté. Le message du serveur s'affiche.
  reglageACorriger,

  /// Aucune réponse du serveur (coupure du réseau, délai de l'appareil) :
  /// le tour a peut-être été compté.
  resultatInconnu,

  /// `invalid_argument` ou autre refus du serveur, rien compté.
  refus,

  /// Le brouillon n'a pas pu être lu pour l'envoi (valeur refusée) : rien
  /// n'est parti.
  recetteIllisible,
}

/// Valeurs de `details.reason` rendues par `recipeAssistantTurn` et le socle
/// (`functions/src/assistant/`, `functions/src/ai/run.ts`).
const Map<String, CauseEchecAssistant> kRaisonsAssistant = {
  'ai_policy_unavailable': CauseEchecAssistant.reglagesAbsents,
  'ai_feature_closed': CauseEchecAssistant.posteFerme,
  'quota_exhausted': CauseEchecAssistant.plafondJour,
  'conversation_full': CauseEchecAssistant.conversationPleine,
  'too_long': CauseEchecAssistant.tropLong,
  'ai_credit_exhausted': CauseEchecAssistant.creditEpuise,
  'ai_rate_limited': CauseEchecAssistant.tropDemande,
  'ai_no_answer': CauseEchecAssistant.reponseIllisible,
  'ai_timeout': CauseEchecAssistant.delaiDepasse,
  'ai_failed': CauseEchecAssistant.delaiDepasse,
  'ai_request_rejected': CauseEchecAssistant.envoiImpossible,
  'ai_unreachable': CauseEchecAssistant.envoiImpossible,
  'ai_unavailable': CauseEchecAssistant.envoiImpossible,
  'ai_cost_center_unknown': CauseEchecAssistant.envoiImpossible,
  'invalid_argument': CauseEchecAssistant.refus,
  'ai_key_invalid': CauseEchecAssistant.reglageACorriger,
  'ai_model_unavailable': CauseEchecAssistant.reglageACorriger,
};

/// Échec d'un tour, déjà rapporté par le dépôt.
@immutable
class EchecAssistant implements Exception {
  const EchecAssistant(
    this.cause, {
    this.champ,
    this.quota,
    this.raison,
    this.message,
  });

  final CauseEchecAssistant cause;

  /// `details.field` d'un refus de taille.
  final String? champ;

  /// `details.quota` : tours restants après le refus, quand le serveur les
  /// connaît.
  final QuotaRendu? quota;

  /// `details.reason` tel que reçu.
  final String? raison;

  /// Message du serveur, affiché pour [CauseEchecAssistant.reglageACorriger]
  /// seulement. Jamais rapporté.
  final String? message;

  /// Lecture d'une erreur de la callable. Une raison connue décide ; sans
  /// raison, `unavailable`, `deadline-exceeded` et `internal` laissent le
  /// résultat inconnu.
  factory EchecAssistant.depuis({
    required String code,
    Object? details,
    String? message,
  }) {
    final reason = details is Map ? details['reason'] : null;
    final field = details is Map ? details['field'] : null;
    final connue = reason is String ? kRaisonsAssistant[reason] : null;
    final cause =
        connue ??
        switch (code) {
          'unavailable' ||
          'deadline-exceeded' ||
          'internal' => CauseEchecAssistant.resultatInconnu,
          _ => CauseEchecAssistant.refus,
        };
    return EchecAssistant(
      cause,
      champ: field is String ? field : null,
      quota: details is Map ? _lireQuota(details['quota']) : null,
      raison: reason is String ? reason : null,
      message: message,
    );
  }
}
