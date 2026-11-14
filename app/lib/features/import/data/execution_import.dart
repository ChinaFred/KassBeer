import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/foundation.dart';

import '../../../core/services/error_report_service.dart';
import '../../costs/data/costs_repository.dart';
import 'import_fiches_repository.dart';
import '../domain/fiches_a_importer.dart';

/// Exécution d'Admin › Import (v0.6) : les fiches cochées, l'une après
/// l'autre, chaque écriture après l'accusé du serveur de la précédente (CR3).
/// Aucune transaction. Avec le cache hors ligne, un accusé ne revient jamais
/// sans réseau : chaque écriture attend au plus [kDelaiEcriture], et la perte
/// de la connexion arrête l'import (EC9). L'écriture laissée en file part au
/// retour du réseau, sans doublon : les identifiants viennent du fichier
/// (ID1), et la fiche passe « À compléter » au prochain import (ID3).

/// Attente maximale de l'accusé d'une écriture.
const kDelaiEcriture = Duration(seconds: 30);

/// Issue d'une fiche.
@immutable
sealed class IssueFiche {
  const IssueFiche();
}

/// Toutes les écritures acceptées, marque de fin comprise.
class FicheEcrite extends IssueFiche {
  const FicheEcrite();
}

/// Écriture refusée : la fiche est passée, les suivantes continuent.
class FicheEnErreur extends IssueFiche {
  const FicheEnErreur(this.etape, this.lot, this.code);

  final EtapeEcriture etape;

  /// Rang du lot d'événements, ou `null`.
  final int? lot;

  /// Code Firestore (`permission-denied`, `unavailable`…), ou type d'erreur.
  final String code;
}

/// Écriture sans accusé dans le délai, ou connexion perdue : l'import s'arrête.
class FicheInterrompue extends IssueFiche {
  const FicheInterrompue();
}

/// Fiche non traitée : import arrêté avant elle.
class FicheNonTraitee extends IssueFiche {
  const FicheNonTraitee();
}

/// Progression de l'écriture (EC7).
typedef ProgressionImport = ({
  int fiche,
  int fiches,
  String nom,
  int ecritures,
  int total,
});

/// Écrit [fiches] (cochées, dans l'ordre du fichier) sous [uid], d'après
/// [etat] lu à l'analyse. Rend l'issue de chaque fiche, dans le même ordre.
///
/// [perteConnexion] se termine quand l'appareil passe hors ligne ;
/// [arret] vaut vrai quand l'administrateur arrête l'import. Une erreur est
/// rapportée (`import.fiches`) avec le rang de la fiche, l'étape et le code
/// Firestore, sans valeur ni texte de la fiche (EC10, P13).
Future<List<IssueFiche>> executerImport({
  required List<FicheAImporter> fiches,
  required EtatServeur etat,
  required String uid,
  required String? ownerName,
  required ImportFichesRepository depot,
  required CostsRepository couts,
  required ErrorReportService errors,
  required Future<void> perteConnexion,
  bool Function() arret = _jamais,
  Duration delai = kDelaiEcriture,
  void Function(ProgressionImport)? surProgression,
}) async {
  final recettes = {...etat.recettes.keys};
  List<EcritureImport> plan(FicheAImporter f, Set<String> presentes) =>
      planDeFiche(
        f,
        existant: etat.brassins[f.brewId],
        recetteAbsente: !presentes.contains(f.fiche!.recipeDocId),
        coutFige: etat.coutsFiges.contains(f.brewId),
      );
  // Total annoncé : chaque recette créée une fois, par la première fiche.
  final prevues = {...recettes};
  var total = 0;
  for (final f in fiches) {
    total += plan(f, prevues).length;
    prevues.add(f.fiche!.recipeDocId);
  }
  var connexionPerdue = false;
  unawaited(perteConnexion.then((_) => connexionPerdue = true));
  // Une perte déjà connue (hors ligne au départ) est lue avant la première
  // écriture.
  await Future<void>.value();

  final issues = <IssueFiche>[];
  var faites = 0;
  for (final (n, f) in fiches.indexed) {
    if (connexionPerdue || arret()) {
      issues.add(const FicheNonTraitee());
      continue;
    }
    final ecritures = plan(f, recettes);
    IssueFiche issue = const FicheEcrite();
    for (final e in ecritures) {
      if (arret()) {
        issue = const FicheInterrompue();
        break;
      }
      surProgression?.call((
        fiche: n + 1,
        fiches: fiches.length,
        nom: f.fiche!.brassin.name,
        ecritures: faites,
        total: total,
      ));
      final reponse = await _attendre(
        _ecrire(e, depot, couts, uid, ownerName),
        perteConnexion,
        delai,
        errors,
        n + 1,
        e,
      );
      switch (reponse) {
        case _Acceptee():
          faites++;
          if (e is CreationRecette) recettes.add(e.recipeId);
        case _Refusee(:final error, :final stackTrace):
          final code = error is FirebaseException
              ? error.code
              : '${error.runtimeType}';
          errors.reportError(
            feature: 'import.fiches',
            error: error,
            stackTrace: stackTrace,
            context: _contexte(n + 1, e, code),
          );
          issue = FicheEnErreur(
            e.etape,
            e is LotEvenements ? e.numero : null,
            code,
          );
        case _SansReponse():
          connexionPerdue = true;
          issue = const FicheInterrompue();
      }
      if (issue is! FicheEcrite) break;
    }
    issues.add(issue);
  }
  surProgression?.call((
    fiche: fiches.length,
    fiches: fiches.length,
    nom: '',
    ecritures: faites,
    total: total,
  ));
  return issues;
}

bool _jamais() => false;

String _contexte(int rang, EcritureImport e, String code) =>
    'fiche n° $rang, étape ${e.etape.name}'
    '${e is LotEvenements ? ', lot ${e.numero}' : ''}, code $code';

Future<void> _ecrire(
  EcritureImport e,
  ImportFichesRepository depot,
  CostsRepository couts,
  String uid,
  String? ownerName,
) => switch (e) {
  CreationRecette(:final recipeId, :final content) => depot.creerRecette(
    id: recipeId,
    content: content,
    ownerUid: uid,
    ownerName: ownerName,
  ),
  final CreationBrassin c => depot.creerBrassin(
    c,
    ownerUid: uid,
    ownerName: ownerName,
  ),
  final ModificationBrassin m => depot.modifierBrassin(m, ownerName: ownerName),
  final LotEvenements lot => depot.ecrireEvenements(lot),
  FigeageCout(:final cout) => couts.saveBrewCost(uid: uid, cost: cout),
};

sealed class _Reponse {
  const _Reponse();
}

class _Acceptee extends _Reponse {
  const _Acceptee();
}

class _Refusee extends _Reponse {
  const _Refusee(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class _SansReponse extends _Reponse {
  const _SansReponse();
}

/// Accusé de [ecriture], ou [_SansReponse] après [delai] ou à la perte de la
/// connexion. Une erreur arrivée après l'arrêt est rapportée.
Future<_Reponse> _attendre(
  Future<void> ecriture,
  Future<void> perteConnexion,
  Duration delai,
  ErrorReportService errors,
  int rang,
  EcritureImport e,
) {
  final reponse = Completer<_Reponse>();
  void finir(_Reponse r) {
    if (!reponse.isCompleted) reponse.complete(r);
  }

  final minuterie = Timer(delai, () => finir(const _SansReponse()));
  unawaited(perteConnexion.then((_) => finir(const _SansReponse())));
  unawaited(
    ecriture.then(
      (_) => finir(const _Acceptee()),
      onError: (Object error, StackTrace stackTrace) {
        if (reponse.isCompleted) {
          // Refus reçu après l'arrêt de l'import : la fiche reste « À
          // compléter », et l'erreur est rapportée.
          errors.reportError(
            feature: 'import.fiches',
            error: error,
            stackTrace: stackTrace,
            context: _contexte(rang, e, 'refus après arrêt'),
          );
        }
        finir(_Refusee(error, stackTrace));
      },
    ),
  );
  return reponse.future.whenComplete(minuterie.cancel);
}
