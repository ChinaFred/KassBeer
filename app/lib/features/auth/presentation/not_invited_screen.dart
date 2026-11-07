import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/providers.dart';
import 'access_providers.dart';
import 'sign_out.dart';

/// Compte Google connecté, sans document `members/{email}` sur le serveur.
class NotInvitedScreen extends ConsumerStatefulWidget {
  const NotInvitedScreen({super.key});

  static const copied = 'Adresse copiée';
  static const copyFailed =
      'Copie impossible. Sélectionnez l\'adresse à la main.';
  static const noEmail =
      'Adresse du compte indisponible. Déconnectez-vous et reconnectez-vous.';
  static const stillNotInvited = 'Ce compte n\'est toujours pas invité.';

  @override
  ConsumerState<NotInvitedScreen> createState() => _NotInvitedScreenState();
}

class _NotInvitedScreenState extends ConsumerState<NotInvitedScreen> {
  bool _checking = false;

  Future<void> _copy(String email) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: email));
      messenger.showSnackBar(
        const SnackBar(content: Text(NotInvitedScreen.copied)),
      );
    } catch (error, stackTrace) {
      ref
          .read(errorReportServiceProvider)
          .reportError(
            feature: 'auth.copy_email',
            error: error,
            stackTrace: stackTrace,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text(NotInvitedScreen.copyFailed)),
      );
    }
  }

  /// Relit le document du compte ; s'il est toujours absent, le dit.
  Future<void> _checkAgain(String? key) async {
    if (key == null || key.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    try {
      final lookup = await ref.refresh(memberLookupProvider(key).future);
      if (lookup.member == null) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text(NotInvitedScreen.stillNotInvited)),
        );
      }
    } on Object {
      // Déjà rapportée par le dépôt de données (members.watch_member) ; le routeur
      // affiche l'écran Erreur.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final access = ref.watch(accessStateProvider);
    final user = access is AccessNotInvited ? access.user : null;
    // Adresse du compte Google, telle que Google la rend.
    final email = user?.email?.trim();
    final hasEmail = email != null && email.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
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
                  if (hasEmail) ...[
                    const Text(
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
                    const Text(
                      'Transmettez cette adresse à l\'administrateur. Une fois invité, '
                      'appuyez sur Vérifier à nouveau.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    FilledButton.tonalIcon(
                      onPressed: () => _copy(email),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copier l\'adresse'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _checking
                          ? null
                          : () => _checkAgain(user?.memberKey),
                      child: _checking
                          ? const IndicateurBouton(
                              label: 'Vérification en cours',
                            )
                          : const Text('Vérifier à nouveau'),
                    ),
                  ] else ...[
                    const Text(
                      NotInvitedScreen.noEmail,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                  ],
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
