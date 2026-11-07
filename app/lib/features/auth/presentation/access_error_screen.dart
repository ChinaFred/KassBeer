import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/etats.dart';
import 'access_providers.dart';
import 'sign_out.dart';

/// La session ou `members/{email}` n'a pas pu être lu. Jamais « non invité » sur
/// une panne : l'écran le dit et propose de réessayer.
class AccessErrorScreen extends ConsumerWidget {
  const AccessErrorScreen({super.key});

  static const message =
      'Impossible de vérifier votre accès. Vérifiez le réseau et réessayez.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionUserProvider).value != null;
    return Scaffold(
      body: SafeArea(
        child: EtatErreur(
          message: message,
          retrying: ref.watch(accessRefreshingProvider),
          onRetry: () => retryAccess(ref),
          secondaryAction: signedIn
              ? TextButton(
                  onPressed: () => signOutFrom(context, ref),
                  child: const Text('Se déconnecter'),
                )
              : null,
        ),
      ),
    );
  }
}
