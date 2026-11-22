import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../../library/domain/referentiel.dart';
import '../../recipes/domain/import_recettes.dart' show indexBibliotheque;

/// Plage de température de la levure d'une recette, lue dans la Bibliothèque
/// pour la courbe de fermentation de la fiche du brassin. La levure se résout
/// par son nom, comme à l'import (`IndexBibliotheque.resoudre` d'`exchange/` :
/// nom ou alias exact après normalisation, puis souche, référence, producteur
/// et référence, puis référence lue dans le nom, sans correspondance floue). Lectures par `get()` seul (P22) : l'index `beer_index/cultures`,
/// gardé par le dépôt pour la session, puis la fiche `beer_cultures/{id}`.
/// L'écran du jour et les journées ne la lisent jamais (P2).
sealed class EtatPlageLevure {
  const EtatPlageLevure();
}

/// Plage lue, bornes en °C.
class PlageLevureConnue extends EtatPlageLevure {
  const PlageLevureConnue(this.minimum, this.maximum);

  final double minimum;
  final double maximum;
}

/// Aucune entrée de la Bibliothèque ne correspond au nom de la levure.
class LevureAbsenteDeLaBibliotheque extends EtatPlageLevure {
  const LevureAbsenteDeLaBibliotheque(this.nom);

  /// Nom de la levure dans la recette.
  final String nom;
}

/// L'entrée existe, sans plage de température complète.
class LevureSansPlage extends EtatPlageLevure {
  const LevureSansPlage(this.nom);

  /// Nom de la levure dans la recette.
  final String nom;
}

Duration? _sansNouvelEssai(int retryCount, Object error) => null;

/// État de la plage de la levure [cle.nom] ; `null` quand rien ne se dit :
/// hors ligne sans copie sur l'appareil ([cle.cacheSeul] : cache seul, sans
/// rapport), ou index et fiche illisibles (rapportés par le dépôt). Une panne
/// de lecture est rapportée par le dépôt puis rendue en erreur : l'écran
/// n'affiche alors rien.
final plageLevureProvider = FutureProvider.autoDispose
    .family<EtatPlageLevure?, ({String nom, bool cacheSeul})>((ref, cle) async {
      final repository = ref.watch(libraryRepositoryProvider);
      final index = await repository.lireIndex(
        NatureReferentiel.cultures,
        cacheSeul: cle.cacheSeul,
      );
      final IndexReferentiel cultures;
      switch (index) {
        case DocumentTrouve(:final value):
          cultures = value;
        case DocumentAbsent():
          return LevureAbsenteDeLaBibliotheque(cle.nom);
        case DocumentAbsentDuCache() || DocumentIllisibleTrouve():
          return null;
      }
      final entree = indexBibliotheque(cultures).resoudre(cle.nom);
      if (entree == null) return LevureAbsenteDeLaBibliotheque(cle.nom);
      final fiche = await repository.lireFiche(
        NatureReferentiel.cultures,
        entree.id,
        cacheSeul: cle.cacheSeul,
      );
      return switch (fiche) {
        DocumentTrouve(value: final FicheLevure levure) =>
          switch (levure.temperature) {
            Plage(:final double minimum, :final double maximum) =>
              PlageLevureConnue(minimum, maximum),
            _ => LevureSansPlage(cle.nom),
          },
        DocumentTrouve() ||
        DocumentAbsent() => LevureAbsenteDeLaBibliotheque(cle.nom),
        DocumentAbsentDuCache() || DocumentIllisibleTrouve() => null,
      };
    }, retry: _sansNouvelEssai);
