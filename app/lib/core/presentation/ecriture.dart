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
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
