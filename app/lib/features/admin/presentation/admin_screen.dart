import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/app_shell.dart';
import '../../../core/router/routes.dart';
import '../../tickets/presentation/admin_tickets_screen.dart';
import '../../tickets/presentation/bandeau_tickets_admin.dart';

/// Accueil de l'administration : réservé au rôle `admin` (le routeur le vérifie).
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  static const importSubtitle = 'Fiches Excel préparées en JSON';

  static const ticketsSubtitle =
      'Bugs et idées des membres, et leur suivi sur GitHub';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Alertes en ton d'erreur du bandeau d'Admin › Tickets : jeton GitHub,
    // tickets bloqués, panne de lecture. Une échéance proche ne l'allume pas.
    final alerts = ref
        .watch(messagesBandeauTicketsProvider)
        .where((m) => m.error)
        .length;
    // Material propre : l'encre des tuiles se peint sur lui, pas sous le fond
    // de la transition de page.
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Membres'),
            subtitle: const Text('Inviter et retirer les comptes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(AppRoutes.adminMembers),
          ),
          Semantics(
            label: alerts == 0
                ? null
                : '${AdminTicketsScreen.titre}, '
                      '${alerts == 1 ? '1 alerte' : '$alerts alertes'}, '
                      '$ticketsSubtitle',
            excludeSemantics: alerts > 0,
            button: alerts > 0,
            onTap: alerts > 0 ? () => context.go(AppRoutes.adminTickets) : null,
            child: ListTile(
              leading: const Icon(Icons.confirmation_number_outlined),
              title: const Text(AdminTicketsScreen.titre),
              subtitle: const Text(ticketsSubtitle),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (alerts > 0) ...[
                    Badge(
                      label: Text(textePastille(alerts)),
                      backgroundColor: scheme.error,
                      textColor: scheme.onError,
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => context.go(AppRoutes.adminTickets),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Import'),
            subtitle: const Text(importSubtitle),
            trailing: const Icon(Icons.chevron_right),
            // `push` : le retour ramène à l'administration.
            onTap: () => context.push(AppRoutes.adminImport),
          ),
        ],
      ),
    );
  }
}
