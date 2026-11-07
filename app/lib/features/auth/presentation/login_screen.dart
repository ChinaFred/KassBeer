import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/logo_kass_beer.dart';
import '../../../core/providers.dart';
import '../domain/session_user.dart';

/// Connexion par compte Google.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const networkError =
      'Connexion impossible. Vérifiez le réseau et réessayez.';
  static const otherError = 'La connexion a échoué. Réessayez.';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      // Fenêtre fermée : retour sans message.
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on SignInFailure catch (failure) {
      // Déjà rapportée par le dépôt de données.
      error = failure.network
          ? LoginScreen.networkError
          : LoginScreen.otherError;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  const LogoKassBeer(headerSemantics: true),
                  const SizedBox(height: 8),
                  Text(
                    'Recettes et brassins du groupe',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 40),
                  ConstrainedBox(
                    // 56 px au moins ; le bouton grandit avec la taille du texte.
                    constraints: const BoxConstraints(minHeight: 56),
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _signIn,
                      icon: _busy ? null : const Icon(Icons.login),
                      label: _busy
                          ? const IndicateurBouton(label: 'Connexion en cours')
                          : const Text('Se connecter avec Google'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Accès réservé aux comptes invités.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
