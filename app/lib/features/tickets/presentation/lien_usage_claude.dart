import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/ticket_launch.dart';
import 'tickets_providers.dart';

/// Page d'usage de l'abonnement Claude (fenêtre de 5 h et semaine). Aucune
/// API ne rend ce pourcentage : l'application ouvre la page, sans chiffre.
/// Relue par [lienSessionOuvrable] (`https`, hôte `claude.ai`) avant
/// l'ouverture.
const kAdresseUsageClaude = 'https://claude.ai/settings/usage';

/// Lien « Usage Claude (5 h et semaine) : voir sur claude.ai », dans la boîte
/// de lancement et le bandeau d'Admin › Tickets. Un appui ouvre la page dans
/// le navigateur externe ; il ne lance rien et ne compte rien.
class LienUsageClaude extends ConsumerWidget {
  const LienUsageClaude({super.key, this.onEchec});

  /// Message d'échec affiché par l'appelant (la boîte de lancement, sous son
  /// voile), ou `null` après une ouverture réussie, qui l'efface. Sans
  /// [onEchec] : message en bas de l'écran.
  final void Function(String? message)? onEchec;

  static const libelle = 'Usage Claude (5 h et semaine) : voir sur claude.ai';
  static const description =
      'Ouvre la page d\'usage de claude.ai dans le navigateur';
  static const echec = 'Impossible d\'ouvrir claude.ai.';

  Future<void> _ouvrir(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errors = ref.read(errorReportServiceProvider);
    final ouvrir = ref.read(ouvrirLienProvider);
    final uri = lienSessionOuvrable(kAdresseUsageClaude);
    Object? error;
    StackTrace? stackTrace;
    var opened = false;
    if (uri != null) {
      try {
        opened = await ouvrir(uri);
      } catch (e, st) {
        error = e;
        stackTrace = st;
      }
    }
    if (opened) {
      onEchec?.call(null);
      return;
    }
    errors.reportError(
      feature: 'tickets.open_claude_usage',
      error:
          error ??
          StateError(
            uri == null
                ? 'adresse d\'usage refusée'
                : 'ouverture refusée par le système',
          ),
      stackTrace: stackTrace ?? StackTrace.current,
      context: 'lien d\'usage Claude',
    );
    final signaler = onEchec;
    if (signaler != null) {
      signaler(echec);
    } else {
      messenger?.showSnackBar(const SnackBar(content: Text(echec)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
    alignment: AlignmentDirectional.centerStart,
    // L'info-bulle donne aussi l'indication lue par le lecteur d'écran ; le
    // nom accessible reste le libellé visible.
    child: Tooltip(
      message: description,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        onPressed: () => _ouvrir(context, ref),
        icon: const Icon(Icons.open_in_new),
        label: const Text(libelle),
      ),
    ),
  );
}
