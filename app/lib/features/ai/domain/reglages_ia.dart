import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

/// Réglages de l'IA (ADR-016, sections 4 et 5) : `ai_config/policy` et
/// `ai_config/pricing`, écrits par `saveAiSettings` seule. Le client les lit
/// pour l'affichage et le formulaire de Moteur d'IA. Aucune borne de plafond,
/// aucune liste de modèles ni d'efforts, aucun tarif en Dart (P60) : le
/// serveur valide et refuse avec `details.field`.

/// Version des deux documents lue par cette application.
const kVersionReglagesIa = 1;

/// Réglage d'un poste dans `ai_config/policy.features.<poste>`.
@immutable
class ReglagePosteIa {
  const ReglagePosteIa({
    required this.modele,
    required this.effort,
    required this.ouvertAuxMembres,
    required this.toursParJour,
    required this.toursFondateurParJour,
    required this.toursParConversation,
  });

  /// Clé de la grille (`claude-sonnet-5-5`).
  final String modele;

  /// Valeur de `efforts` du modèle, ou `null` pour un modèle sans effort.
  final String? effort;

  /// `members_enabled` : faux, l'administrateur seul utilise le poste.
  final bool ouvertAuxMembres;
  final int toursParJour;
  final int toursFondateurParJour;
  final int toursParConversation;

  /// Plafond du jour pour le compte qui lit : celui du fondateur
  /// (`Member.founder`, P31) ou celui de chaque membre.
  int limiteDuJour({required bool fondateur}) =>
      fondateur ? toursFondateurParJour : toursParJour;

  /// Lecture stricte : types seuls. Les bornes (1 à `AI_MAX_TURNS`) sont
  /// vérifiées par le serveur, jamais recopiées ici (P60).
  factory ReglagePosteIa.lire(LecteurChamps read) {
    final effort = read.data['effort'];
    if (effort != null && effort is! String) {
      throw DocumentIllisible('${read.prefix}effort', 'texte ou null attendu');
    }
    final ouvert = read.boolFacultatif('members_enabled');
    if (ouvert == null) {
      throw DocumentIllisible(
        '${read.prefix}members_enabled',
        'booléen obligatoire absent',
      );
    }
    return ReglagePosteIa(
      modele: read.texte('model'),
      effort: effort as String?,
      ouvertAuxMembres: ouvert,
      toursParJour: _entier(read, 'turns_per_day'),
      toursFondateurParJour: _entier(read, 'founder_turns_per_day'),
      toursParConversation: _entier(read, 'turns_per_conversation'),
    );
  }

  /// Valeur envoyée à `saveAiSettings` pour ce poste.
  Map<String, Object?> versArgument() => {
    'model': modele,
    'effort': effort,
    'members_enabled': ouvertAuxMembres,
    'turns_per_day': toursParJour,
    'founder_turns_per_day': toursFondateurParJour,
    'turns_per_conversation': toursParConversation,
  };

  @override
  bool operator ==(Object other) =>
      other is ReglagePosteIa &&
      other.modele == modele &&
      other.effort == effort &&
      other.ouvertAuxMembres == ouvertAuxMembres &&
      other.toursParJour == toursParJour &&
      other.toursFondateurParJour == toursFondateurParJour &&
      other.toursParConversation == toursParConversation;

  @override
  int get hashCode => Object.hash(
    modele,
    effort,
    ouvertAuxMembres,
    toursParJour,
    toursFondateurParJour,
    toursParConversation,
  );
}

/// Entier positif ou nul ; un nombre à virgule ou un texte rend le réglage
/// illisible.
int _entier(LecteurChamps read, String key) {
  final value = read.data[key];
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    if (value >= 0) return value.toInt();
  }
  throw DocumentIllisible('${read.prefix}$key', 'entier attendu');
}

/// État du réglage d'un poste.
sealed class EtatReglagePoste {
  const EtatReglagePoste();
}

/// Poste absent de `features` : il refuse tout appel.
class ReglagePosteAbsent extends EtatReglagePoste {
  const ReglagePosteAbsent();
}

/// Réglage du poste illisible (type inattendu) : il refuse tout appel.
class ReglagePosteIllisible extends EtatReglagePoste {
  const ReglagePosteIllisible(this.erreur);

  final DocumentIllisible erreur;
}

class ReglagePosteLu extends EtatReglagePoste {
  const ReglagePosteLu(this.reglage);

  final ReglagePosteIa reglage;
}

/// Document `ai_config/policy`.
@immutable
class PolitiqueIa {
  const PolitiqueIa(this.postes);

  /// Réglage de chaque poste présent dans `features`.
  final Map<String, EtatReglagePoste> postes;

  /// Réglage de [cle] ; absent du document : [ReglagePosteAbsent].
  EtatReglagePoste poste(String cle) =>
      postes[cle] ?? const ReglagePosteAbsent();

  /// Valeur envoyée à `saveAiSettings` (`kind: "policy"`) : [postes] lisibles
  /// parmi [connus], et [cle] remplacé par [reglage]. Le serveur refuse un
  /// poste inconnu de lui.
  static Map<String, Object?> argument({
    required PolitiqueIa? actuelle,
    required Iterable<String> connus,
    required String cle,
    required ReglagePosteIa reglage,
  }) => {
    'version': kVersionReglagesIa,
    'features': {
      for (final c in connus)
        if (c == cle)
          c: reglage.versArgument()
        else if (actuelle?.reglage(c) case final r?)
          c: r.versArgument(),
    },
  };

  /// Réglage lisible de [cle], ou `null`.
  ReglagePosteIa? reglage(String cle) => switch (poste(cle)) {
    ReglagePosteLu(:final reglage) => reglage,
    _ => null,
  };

  /// Lève [DocumentIllisible] si la version ou `features` est illisible ; un
  /// poste illisible n'empêche pas de lire les autres.
  factory PolitiqueIa.fromFirestore(Map<String, dynamic> data) {
    _verifierVersion(data);
    final features = LecteurChamps(data).objet('features');
    final postes = <String, EtatReglagePoste>{};
    for (final cle in features.data.keys) {
      try {
        final read = features.objet(cle);
        postes[cle] = ReglagePosteLu(ReglagePosteIa.lire(read));
      } on DocumentIllisible catch (erreur) {
        postes[cle] = ReglagePosteIllisible(erreur);
      }
    }
    return PolitiqueIa(Map.unmodifiable(postes));
  }
}

void _verifierVersion(Map<String, dynamic> data) {
  if (data['version'] != kVersionReglagesIa) {
    throw const DocumentIllisible('version', 'version 1 attendue');
  }
}

/// Ligne d'un modèle dans la grille, en dollars par million de jetons.
@immutable
class ModeleTarife {
  const ModeleTarife({
    required this.id,
    required this.libelle,
    required this.entree,
    required this.sortie,
    required this.ecritureCache,
    required this.lectureCache,
    required this.efforts,
  });

  /// Identifiant de l'API (`claude-sonnet-5-5`).
  final String id;
  final String libelle;
  final double entree;
  final double sortie;
  final double ecritureCache;
  final double lectureCache;

  /// Efforts acceptés, tels que l'administrateur les a saisis ; vide : modèle
  /// sans réglage d'effort.
  final List<String> efforts;

  factory ModeleTarife.lire(String id, LecteurChamps read) {
    final raw = read.data['efforts'];
    if (raw is! List || raw.any((e) => e is! String)) {
      throw DocumentIllisible('${read.prefix}efforts', 'liste de textes');
    }
    return ModeleTarife(
      id: id,
      libelle: read.texte('label'),
      entree: read.nombre('input_usd_per_mtok'),
      sortie: read.nombre('output_usd_per_mtok'),
      ecritureCache: read.nombre('cache_write_usd_per_mtok'),
      lectureCache: read.nombre('cache_read_usd_per_mtok'),
      efforts: List.unmodifiable(raw.cast<String>()),
    );
  }

  Map<String, Object?> versArgument() => {
    'label': libelle,
    'input_usd_per_mtok': entree,
    'output_usd_per_mtok': sortie,
    'cache_write_usd_per_mtok': ecritureCache,
    'cache_read_usd_per_mtok': lectureCache,
    'efforts': efforts,
  };

  @override
  bool operator ==(Object other) =>
      other is ModeleTarife &&
      other.id == id &&
      other.libelle == libelle &&
      other.entree == entree &&
      other.sortie == sortie &&
      other.ecritureCache == ecritureCache &&
      other.lectureCache == lectureCache &&
      listEquals(other.efforts, efforts);

  @override
  int get hashCode => Object.hash(
    id,
    libelle,
    entree,
    sortie,
    ecritureCache,
    lectureCache,
    Object.hashAll(efforts),
  );
}

/// Ancienneté au-delà de laquelle Moteur d'IA affiche « Tarifs à revérifier »
/// (ADR-016, section 5). Les appels restent chiffrés : seul l'affichage la lit.
const kTarifsAReverifierApres = Duration(days: 90);

/// Document `ai_config/pricing`.
@immutable
class GrilleTarifaire {
  const GrilleTarifaire({
    required this.verifieeLe,
    required this.source,
    required this.modeles,
  });

  /// `checked_on` (`AAAA-MM-JJ`), date du calendrier.
  final DateTime verifieeLe;

  /// `source`, 200 caractères au plus ; vide si l'administrateur n'a rien
  /// saisi.
  final String source;

  /// Modèles, dans l'ordre du document.
  final List<ModeleTarife> modeles;

  ModeleTarife? modele(String id) {
    for (final m in modeles) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Vérifiée il y a plus de [kTarifsAReverifierApres] à la date de [now].
  bool aReverifier(DateTime now) =>
      DateTime(now.year, now.month, now.day).difference(verifieeLe) >
      kTarifsAReverifierApres;

  factory GrilleTarifaire.fromFirestore(Map<String, dynamic> data) {
    _verifierVersion(data);
    final read = LecteurChamps(data);
    final models = read.objet('models');
    return GrilleTarifaire(
      verifieeLe: lireDateCalendrier(read.texte('checked_on'), 'checked_on'),
      source: _texteOuVide(read, 'source'),
      modeles: List.unmodifiable([
        for (final id in models.data.keys)
          ModeleTarife.lire(id, models.objet(id)),
      ]),
    );
  }

  /// Valeur envoyée à `saveAiSettings` (`kind: "pricing"`).
  Map<String, Object?> versArgument() => {
    'version': kVersionReglagesIa,
    'checked_on': texteDateCalendrier(verifieeLe),
    'source': source,
    'models': {for (final m in modeles) m.id: m.versArgument()},
  };
}

String _texteOuVide(LecteurChamps read, String key) {
  final value = read.data[key];
  if (value is String) return value;
  throw DocumentIllisible(key, 'texte attendu');
}

/// Date `AAAA-MM-JJ` d'un calendrier ; lève [DocumentIllisible] sinon.
DateTime lireDateCalendrier(String value, String field) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match != null) {
    final annee = int.parse(match.group(1)!);
    final mois = int.parse(match.group(2)!);
    final jour = int.parse(match.group(3)!);
    final date = DateTime(annee, mois, jour);
    if (date.year == annee && date.month == mois && date.day == jour) {
      return date;
    }
  }
  throw DocumentIllisible(field, 'date AAAA-MM-JJ attendue');
}

/// « 2026-11-15 ».
String texteDateCalendrier(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
