import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'tickets_providers.dart';

/// Adresse de la modification livrée, si elle est en `https` sur `github.com`
/// sans identifiants ni port ; `null` sinon. Le serveur n'écrit que
/// `https://github.com/ChinaFred/KassBeer/pull/N` ; toute autre valeur n'est
/// pas ouverte.
Uri? lienGithub(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    return null;
  }
  return uri;
}

/// « Voir la modification sur GitHub » : ouvre [uri] hors de l'application.
class BoutonVoirSurGithub extends ConsumerWidget {
  const BoutonVoirSurGithub({super.key, required this.uri});

  final Uri uri;

  static const label = 'Voir la modification sur GitHub';
  static const failure = 'Impossible d\'ouvrir GitHub.';

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ref.read(errorReportServiceProvider);
    Object? error;
    StackTrace? stackTrace;
    var opened = false;
    try {
      opened = await ref.read(ouvrirLienProvider)(uri);
    } catch (e, st) {
      error = e;
      stackTrace = st;
    }
    if (opened) return;
    errors.reportError(
      feature: 'tickets.open_github',
      error: error ?? StateError('ouverture refusée par le système'),
      stackTrace: stackTrace ?? StackTrace.current,
      context: 'lien de la modification livrée',
    );
    messenger.showSnackBar(const SnackBar(content: Text(failure)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton.icon(
    onPressed: () => _open(context, ref),
    icon: const Icon(Icons.open_in_new),
    label: const Text(label),
  );
}
