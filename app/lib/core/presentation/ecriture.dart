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
}) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 10),
      persist: false,
      content: Text(message),
      action: SnackBarAction(label: 'Annuler', onPressed: onAnnuler),
    ),
  );
}

/// « Abandonner les modifications ? » : vrai si l'utilisateur abandonne.
Future<bool> confirmerAbandon(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Abandonner les modifications ?'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Continuer la saisie'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Abandonner'),
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
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(libelle),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
