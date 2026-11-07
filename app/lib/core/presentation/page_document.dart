import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lecture_document.dart';
import 'etats.dart';

/// Textes des états d'une page de document (recette, équipement).
class TextesDocument {
  const TextesDocument({
    required this.chargement,
    required this.lectureImpossible,
    required this.absent,
    required this.horsLigne,
    required this.illisible,
    required this.retour,
  });

  /// « Chargement de la recette ».
  final String chargement;

  /// « Impossible de lire les recettes. »
  final String lectureImpossible;

  /// Absent d'une réponse du serveur.
  final String absent;

  /// Absent du cache, appareil hors ligne.
  final String horsLigne;

  /// Document illisible.
  final String illisible;

  /// Bouton de retour à la liste.
  final String retour;
}

/// Affiche le document [id] de la liste [async], ou l'état qui le remplace :
/// chargement, panne, absent du serveur, absent du cache hors ligne, illisible.
///
/// Un document absent du cache seul n'est jamais annoncé supprimé (comme
/// `watchMember`) : en ligne, la page attend la réponse du serveur ; hors ligne,
/// elle dit qu'il n'est pas disponible.
class PageDocument<T> extends StatelessWidget {
  const PageDocument({
    super.key,
    required this.async,
    required this.id,
    required this.offline,
    required this.textes,
    required this.onRetry,
    required this.onBack,
    required this.builder,
    this.frame,
  });

  final AsyncValue<ListeLue<T>> async;
  final String id;
  final bool offline;
  final TextesDocument textes;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final Widget Function(BuildContext context, T value) builder;

  /// Cadre des états autres que le document (éditeur plein écran, hors de la
  /// coquille) ; `null` dans la coquille.
  final Widget Function(Widget state)? frame;

  @override
  Widget build(BuildContext context) {
    final list = async.value;
    final framed = frame ?? (Widget state) => state;
    if (list == null) {
      return framed(
        async.hasError
            ? EtatErreur(
                message: textes.lectureImpossible,
                retrying: async.isLoading,
                retryingLabel: 'Lecture en cours',
                onRetry: onRetry,
              )
            : EtatChargement(label: textes.chargement),
      );
    }
    final back = FilledButton(onPressed: onBack, child: Text(textes.retour));
    return switch (list.chercher(id)) {
      DocumentTrouve<T>(:final value) => builder(context, value),
      DocumentIllisibleTrouve<T>() => framed(
        EtatVide(
          icon: Icons.error_outline,
          message: textes.illisible,
          action: back,
        ),
      ),
      DocumentAbsent<T>() => framed(
        EtatVide(icon: Icons.search_off, message: textes.absent, action: back),
      ),
      DocumentAbsentDuCache<T>() => framed(
        offline
            ? EtatVide(
                icon: Icons.cloud_off,
                message: textes.horsLigne,
                action: back,
              )
            : EtatChargement(label: textes.chargement),
      ),
    };
  }
}
