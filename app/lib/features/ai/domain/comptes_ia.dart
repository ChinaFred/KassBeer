import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import 'reglages_ia.dart';

/// Comptes de l'IA écrits par le serveur seul (ADR-016, section 6) :
/// `ai_quotas/{uid}` (tours du jour, par poste) et `ai_usage/{AAAA-MM}_{uid}`
/// (comptes du mois, par poste). Le client affiche les montants tels que
/// stockés et ne les recalcule jamais (P60).

/// Clé des comptes par poste dans les deux documents.
const kChampPostesComptes = 'features';

/// Compteur du jour d'un poste, `ai_quotas/{uid}.features.<poste>`.
@immutable
class QuotaPoste {
  const QuotaPoste({required this.compte, required this.repriseLe});

  /// `count` : tours réservés ce jour de Paris.
  final int compte;

  /// `resets_at` : minuit suivant à Paris.
  final DateTime repriseLe;

  /// Tours comptés à [now] : 0 quand `resets_at` est passé, sans calcul de jour
  /// de Paris (ADR-016, section 6).
  int compteA(DateTime now) => now.isBefore(repriseLe) ? compte : 0;

  factory QuotaPoste.lire(LecteurChamps read) {
    final compte = read.nombre('count');
    final reprise = read.date('resets_at');
    if (compte < 0 || compte != compte.roundToDouble()) {
      throw DocumentIllisible('${read.prefix}count', 'entier attendu');
    }
    if (reprise == null) {
      throw DocumentIllisible('${read.prefix}resets_at', 'date attendue');
    }
    return QuotaPoste(compte: compte.toInt(), repriseLe: reprise);
  }
}

/// Document `ai_quotas/{uid}`.
@immutable
class QuotasIa {
  const QuotasIa(this.postes);

  final Map<String, QuotaPoste> postes;

  factory QuotasIa.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data).objetFacultatif(kChampPostesComptes);
    if (read == null) return const QuotasIa({});
    return QuotasIa(
      Map.unmodifiable({
        for (final cle in read.data.keys) cle: QuotaPoste.lire(read.objet(cle)),
      }),
    );
  }
}

/// Comptes d'un poste pour un mois.
@immutable
class ComptesPoste {
  const ComptesPoste({
    required this.appels,
    required this.echecs,
    required this.sansMontant,
    required this.jetonsEntree,
    required this.jetonsCacheEcrits,
    required this.jetonsCacheLus,
    required this.jetonsSortie,
    required this.montantUsd,
  });

  /// `calls` : tours comptés, échecs gardés compris.
  final int appels;

  /// `failed_calls` : délai dépassé, 5xx ou 529.
  final int echecs;

  /// `unpriced_calls` : appels sans montant (tarifs en panne).
  final int sansMontant;
  final int jetonsEntree;
  final int jetonsCacheEcrits;
  final int jetonsCacheLus;
  final int jetonsSortie;

  /// `cost_usd` tel que stocké ; jamais recalculé.
  final double montantUsd;

  static const vide = ComptesPoste(
    appels: 0,
    echecs: 0,
    sansMontant: 0,
    jetonsEntree: 0,
    jetonsCacheEcrits: 0,
    jetonsCacheLus: 0,
    jetonsSortie: 0,
    montantUsd: 0,
  );

  /// Tous les appels sont sans montant : le montant est inconnu.
  bool get montantInconnu => appels > 0 && sansMontant >= appels;

  ComptesPoste operator +(ComptesPoste o) => ComptesPoste(
    appels: appels + o.appels,
    echecs: echecs + o.echecs,
    sansMontant: sansMontant + o.sansMontant,
    jetonsEntree: jetonsEntree + o.jetonsEntree,
    jetonsCacheEcrits: jetonsCacheEcrits + o.jetonsCacheEcrits,
    jetonsCacheLus: jetonsCacheLus + o.jetonsCacheLus,
    jetonsSortie: jetonsSortie + o.jetonsSortie,
    montantUsd: montantUsd + o.montantUsd,
  );

  /// Un compteur absent vaut 0 : le serveur n'écrit que ce qui a bougé.
  factory ComptesPoste.lire(LecteurChamps read) {
    int entier(String key) {
      final v = read.nombreFacultatif(key) ?? 0;
      if (v < 0 || v != v.roundToDouble()) {
        throw DocumentIllisible('${read.prefix}$key', 'entier attendu');
      }
      return v.toInt();
    }

    final montant = read.nombreFacultatif('cost_usd') ?? 0;
    if (montant < 0) {
      throw DocumentIllisible('${read.prefix}cost_usd', 'montant négatif');
    }
    return ComptesPoste(
      appels: entier('calls'),
      echecs: entier('failed_calls'),
      sansMontant: entier('unpriced_calls'),
      jetonsEntree: entier('input_tokens'),
      jetonsCacheEcrits: entier('cache_write_tokens'),
      jetonsCacheLus: entier('cache_read_tokens'),
      jetonsSortie: entier('output_tokens'),
      montantUsd: montant,
    );
  }
}

/// Document `ai_usage/{AAAA-MM}_{uid}`.
@immutable
class CompteMoisIa {
  const CompteMoisIa({
    required this.id,
    required this.mois,
    required this.uid,
    required this.email,
    required this.postes,
  });

  final String id;

  /// `AAAA-MM`.
  final String mois;
  final String uid;

  /// `member_email`, en minuscules, écrit par le serveur depuis le jeton
  /// vérifié ; `null` sur un document qui ne le porte pas.
  final String? email;
  final Map<String, ComptesPoste> postes;

  ComptesPoste get total =>
      postes.values.fold(ComptesPoste.vide, (a, b) => a + b);

  factory CompteMoisIa.fromFirestore(String id, Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    final postes = read.objetFacultatif(kChampPostesComptes);
    final email = read.texteFacultatif('member_email');
    return CompteMoisIa(
      id: id,
      mois: read.texte('month'),
      uid: read.texte('uid'),
      email: email?.toLowerCase(),
      postes: Map.unmodifiable({
        if (postes != null)
          for (final cle in postes.data.keys)
            cle: ComptesPoste.lire(postes.objet(cle)),
      }),
    );
  }
}

/// Mois `AAAA-MM` de [date], heure de l'appareil.
String cleMois(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';

/// Identifiant du compte du mois [mois] de [uid].
String idCompteMois(String mois, String uid) => '${mois}_$uid';

/// [n] mois avant le mois de [date] : (année, mois).
({int annee, int mois}) moisAvant(DateTime date, int n) {
  final index = date.year * 12 + (date.month - 1) - n;
  return (annee: index ~/ 12, mois: index % 12 + 1);
}

/// Date d'un `Timestamp` Firestore lu hors de [LecteurChamps].
DateTime? dateDe(Object? value) => value is Timestamp ? value.toDate() : null;

/// Tours restants du jour pour un poste.
sealed class ToursRestants {
  const ToursRestants();
}

/// Politique ou compteur illisible : « Tours restants : inconnu ».
class ToursInconnus extends ToursRestants {
  const ToursInconnus();
}

class ToursConnus extends ToursRestants {
  const ToursConnus({
    required this.restants,
    required this.limite,
    this.repriseLe,
  });

  final int restants;
  final int limite;

  /// Fin du jour de Paris, quand elle est connue.
  final DateTime? repriseLe;
}

/// Tours restants avant le premier tour d'une conversation (ADR-015,
/// section 8) : limite lue dans la politique pour le profil, compte lu dans
/// `ai_quotas/{uid}` (0 si `resets_at` est passé, 0 sans document). Sans
/// réglage ou sans compteur lisible : [ToursInconnus]. Aucune constante de
/// plafond (P60).
ToursRestants toursRestants({
  required PolitiqueIa? politique,
  required RechercheDocument<QuotasIa>? quotas,
  required String poste,
  required bool fondateur,
  required DateTime now,
}) {
  final reglage = politique?.reglage(poste);
  if (reglage == null) return const ToursInconnus();
  final limite = reglage.limiteDuJour(fondateur: fondateur);
  final QuotaPoste? quota;
  switch (quotas) {
    case DocumentTrouve(:final value):
      quota = value.postes[poste];
    case DocumentAbsent():
      quota = null;
    case null || DocumentAbsentDuCache() || DocumentIllisibleTrouve():
      return const ToursInconnus();
  }
  final compte = quota?.compteA(now) ?? 0;
  final reprise = quota != null && now.isBefore(quota.repriseLe)
      ? quota.repriseLe
      : null;
  return ToursConnus(
    restants: limite > compte ? limite - compte : 0,
    limite: limite,
    repriseLe: reprise,
  );
}
