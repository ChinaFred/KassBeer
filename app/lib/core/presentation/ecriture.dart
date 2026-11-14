import 'dart:async';

import 'package:flutter/material.dart';

/// Annonce une écriture déjà faite dans le cache local par [succes], puis, si le
/// serveur la refuse, remplace l'annonce par [refus]. L'erreur a déjà été rapportée
/// par le dépôt de données.
void suivreEcriture({
  required ScaffoldMessengerState messenger,
  required Future<void> written,
  required String succes,
  required String refus,
}) {
  messenger.showSnackBar(SnackBar(content: Text(succes)));
  unawaited(
    written.catchError((Object _) {
      // Déjà rapportée par le dépôt de données ; le refus s'affiche, à la place du
      // message de succès s'il est encore visible.
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(refus)));
    }),
  );
}

/// Texte d'une saisie refusée par le serveur (HS5).
String messageSaisieRefusee(String libelle) =>
    'Refusée par le serveur : $libelle. Elle n\'est pas enregistrée.';

/// Annonce une saisie refusée, 10 s, à la place du message en cours.
void annoncerRefus(ScaffoldMessengerState messenger, String libelle) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 10),
      content: Text(messageSaisieRefusee(libelle)),
    ),
  );
}

/// Annonce [message] avec « Annuler » pendant 10 s.
void annoncerAvecAnnulation(
  ScaffoldMessengerState messenger,
  String message, {
  required VoidCallback onAnnuler,
}) => annoncerAvecAction(
  messenger,
  message,
  action: 'Annuler',
  onAction: onAnnuler,
);

/// Annonce [message] pendant 10 s, à la place du message en cours, avec le
/// bouton [action] s'il est donné (« Voir le coût »).
void annoncerAvecAction(
  ScaffoldMessengerState messenger,
  String message, {
  String? action,
  VoidCallback? onAction,
}) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 10),
      persist: false,
      content: Text(message),
      action: action == null || onAction == null
          ? null
          : SnackBarAction(label: action, onPressed: onAction),
    ),
  );
}

/// « Abandonner les modifications ? » : vrai si l'utilisateur abandonne.
/// [titre], [continuer] et [abandonner] remplacent les libellés par défaut
/// (« Arrêter l'import ? », Admin › Import).
Future<bool> confirmerAbandon(
  BuildContext context,
  String message, {
  String titre = 'Abandonner les modifications ?',
  String continuer = 'Continuer la saisie',
  String abandonner = 'Abandonner',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titre),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(continuer),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(abandonner),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Confirmation d'une suppression : vrai si l'utilisateur confirme.
Future<bool> confirmerSuppression(
  BuildContext context, {
  required String titre,
  required List<String> paragraphes,
}) => confirmerAction(
  context,
  titre: titre,
  paragraphes: paragraphes,
  libelle: 'Supprimer',
  destructive: true,
);

/// Confirmation d'une action : vrai si l'utilisateur confirme ; le bouton porte
/// [libelle], en couleur d'erreur si [destructive].
Future<bool> confirmerAction(
  BuildContext context, {
  required String titre,
  required List<String> paragraphes,
  required String libelle,
  bool destructive = false,
}) async {
  final result = await _dialogueDeConfirmation(
    context,
    titre: titre,
    paragraphes: paragraphes,
    libelle: libelle,
    destructive: destructive,
  );
  return result == ChoixConfirmation.confirmer;
}

/// Réponse à [confirmerActionOuAlternative].
enum ChoixConfirmation { annuler, alternative, confirmer }

/// Confirmation à trois boutons : « Annuler », [alternative] (une autre action,
/// par exemple « Renseigner les bouteilles ») et [libelle]. Sans [alternative],
/// deux boutons comme [confirmerAction]. Fermer le dialogue rend
/// [ChoixConfirmation.annuler]. Les boutons passent les uns sous les autres
/// quand la largeur manque (texte à 200 %).
Future<ChoixConfirmation> confirmerActionOuAlternative(
  BuildContext context, {
  required String titre,
  required List<String> paragraphes,
  required String libelle,
  String? alternative,
}) async =>
    await _dialogueDeConfirmation(
      context,
      titre: titre,
      paragraphes: paragraphes,
      libelle: libelle,
      alternative: alternative,
    ) ??
    ChoixConfirmation.annuler;

Future<ChoixConfirmation?> _dialogueDeConfirmation(
  BuildContext context, {
  required String titre,
  required List<String> paragraphes,
  required String libelle,
  String? alternative,
  bool destructive = false,
}) => showDialog<ChoixConfirmation>(
  context: context,
  builder: (context) {
    final scheme = Theme.of(context).colorScheme;
    final navigator = Navigator.of(context);
    return AlertDialog(
      title: Text(titre),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, p) in paragraphes.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              Text(p),
            ],
          ],
        ),
      ),
      // Les actions d'un AlertDialog sont dans une OverflowBar : elles
      // s'empilent quand elles ne tiennent pas sur une ligne.
      actions: [
        TextButton(
          onPressed: () => navigator.pop(ChoixConfirmation.annuler),
          child: const Text('Annuler'),
        ),
        if (alternative != null)
          TextButton(
            onPressed: () => navigator.pop(ChoixConfirmation.alternative),
            child: Text(alternative),
          ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => navigator.pop(ChoixConfirmation.confirmer),
          child: Text(libelle),
        ),
      ],
    );
  },
);
