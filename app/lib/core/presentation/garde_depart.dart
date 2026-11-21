import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Confirmation de départ d'une page de la coquille qui a des changements non
/// enregistrés (Admin › Moteur d'IA). La coquille l'appelle avant le bouton
/// retour de sa barre du haut, la barre ou le rail de navigation, et les
/// entrées du menu du compte qui quittent la page ; `false` : rester.
class GardeDepart {
  Object? _proprietaire;
  Future<bool> Function()? _confirmer;

  /// Pose la confirmation de [proprietaire] ; une seule page à la fois.
  void poser(Object proprietaire, Future<bool> Function() confirmer) {
    _proprietaire = proprietaire;
    _confirmer = confirmer;
  }

  /// Retire la confirmation, si [proprietaire] l'a posée.
  void retirer(Object proprietaire) {
    if (!identical(_proprietaire, proprietaire)) return;
    _proprietaire = null;
    _confirmer = null;
  }

  /// Vrai si la page peut être quittée.
  Future<bool> peutQuitter() async {
    final confirmer = _confirmer;
    return confirmer == null || await confirmer();
  }
}

/// [GardeDepart] de la coquille.
final gardeDepartProvider = Provider<GardeDepart>((ref) => GardeDepart());
