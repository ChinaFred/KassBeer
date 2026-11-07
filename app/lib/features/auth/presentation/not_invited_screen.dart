import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'access_providers.dart';
import 'sign_out.dart';

/// Compte Google connecté, sans document `members/{email}` sur le serveur.
class NotInvitedScreen extends ConsumerWidget {
  const NotInvitedScreen({super.key});

  Future<void> _copy(BuildContext context, WidgetRef ref, String email) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: email));
      messenger.showSnackBar(const SnackBar(content: Text('Adresse copiée')));
    } catch (error, stackTrace) {
      ref
          .read(errorReportServiceProvider)
          .reportError(
            feature: 'auth.copy_email',
            error: error,
            stackTrace: stackTrace,
          );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Copie impossible. Sélectionnez l\'adresse à la main.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final refreshing = ref.watch(accessRefreshingProvider);
    final access = ref.watch(accessStateProvider);
    // Adresse du compte Google, telle que Google la rend.
    final email =
        (access is AccessNotInvited ? access.user.email : null) ??
        'Adresse inconnue';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      "Ce compte n'a pas accès à Kass'Beer",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Vous êtes connecté avec :',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    email,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Transmettez cette adresse à l\'administrateur. Une fois invité, '
                    'appuyez sur Vérifier à nouveau.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.tonalIcon(
                    onPressed: () => _copy(context, ref, email),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copier l\'adresse'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: refreshing ? null : () => retryAccess(ref),
                    child: refreshing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Vérifier à nouveau'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => signOutFrom(context, ref),
                    child: const Text('Se déconnecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
