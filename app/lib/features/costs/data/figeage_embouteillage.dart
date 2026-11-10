import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../../brews/data/brews_repository.dart';
import '../../brews/domain/brew.dart';
import '../domain/brew_cost.dart';
import '../domain/cost_evaluation.dart';
import '../domain/fee.dart';
import '../domain/price.dart';
import 'costs_repository.dart';

/// Coût lancé avec un enregistrement d'embouteillage.
@immutable
sealed class FigeageAuPremierEmbouteillage {
  const FigeageAuPremierEmbouteillage();
}

/// CB3 faux : modification, embouteillage déjà daté, ou coût déjà figé. Rien
/// n'est écrit sous `users/`.
class FigeageNonDemande extends FigeageAuPremierEmbouteillage {
  const FigeageNonDemande();
}

/// Premier embouteillage sans figeage : le bloc Coût recalcule les raisons à
/// l'affichage et le bouton « Figer le coût » sert au rattrapage (CB8, CB10).
class CoutNonFige extends FigeageAuPremierEmbouteillage {
  const CoutNonFige();
}

/// Coût figé envoyé : [written] se termine quand le serveur l'a accepté, ou
/// échoue s'il le refuse seul (CB7, déjà rapporté `costs.freeze_rejected`).
class CoutFigeEnvoye extends FigeageAuPremierEmbouteillage {
  const CoutFigeEnvoye(this.cout, this.written);

  final BrewCost cout;
  final Future<void> written;
}

/// Enregistrement de l'embouteillage et du coût qui l'accompagne.
typedef EmbouteillageEnvoye = ({
  Future<void> embouteillage,
  FigeageAuPremierEmbouteillage cout,
});

/// Enregistre l'embouteillage de [brew] (état lu avant l'écriture) et, au
/// premier embouteillage, fige son coût avec [prices] et [fees] capturés à
/// l'envoi du formulaire (CB3 à CB9).
///
/// L'embouteillage n'est jamais bloqué : le calcul se fait avant, sans lever
/// (CB8). `saveBottling` ne change pas, et le coût ne part pas dans son lot : un
/// refus sur `brew_costs` annulerait le statut, l'embouteillage et le relevé de
/// densité finale (CB6). Le `set` du coût part juste après l'appel de
/// `saveBottling`, sans attente entre les deux : la file de Firestore garde
/// l'ordre, hors ligne compris. Aucune transaction, aucune lecture du serveur.
///
/// [coutLu] : coût figé lu sur la fiche, ou `null` s'il ne l'est pas encore ;
/// les règles refusent un second premier figeage (HL5). [now] : heure de
/// l'appareil, qui date le figeage (HL3).
EmbouteillageEnvoye enregistrerEmbouteillage({
  required BrewsRepository brews,
  required CostsRepository costs,
  required ErrorReportService errors,
  required Set<String> reported,
  required Brew brew,
  required Embouteillage embouteillage,
  required double? finalGravity,
  required bool modification,
  required String? ownerName,
  required ListeLue<Price>? prices,
  required ListeLue<Fee>? fees,
  required RechercheDocument<BrewCost>? coutLu,
  required DateTime now,
}) {
  final evaluation =
      doitFigerAuPremierEmbouteillage(
        modification: modification,
        bottledAtAvant: brew.bottledAt,
        coutLu: coutLu,
      )
      ? evaluerFigeage(
          brewId: brew.id,
          recipe: brew.recipe,
          bottlesCount: embouteillage.bottlesCount,
          packagedVolumeL: embouteillage.packagedVolumeL,
          primingSugarG: embouteillage.primingSugarG,
          primingSugarName: embouteillage.primingSugarName,
          prices: prices,
          fees: fees,
          kind: FreezeKind.initial,
          now: now,
          errors: errors,
          reported: reported,
        )
      : null;
  final written = brews.saveBottling(
    brewId: brew.id,
    ownerUid: brew.ownerUid,
    embouteillage: embouteillage,
    nouveauStatut: modification ? null : BrewStatus.conditioning,
    finalGravity: finalGravity,
    ownerName: ownerName,
  );
  final cout = switch (evaluation) {
    null => const FigeageNonDemande(),
    FigeageImpossible() => const CoutNonFige(),
    FigeagePossible(:final cout) => CoutFigeEnvoye(
      cout,
      costs.saveBrewCost(uid: brew.ownerUid, cost: cout),
    ),
  };
  return (embouteillage: written, cout: cout);
}
