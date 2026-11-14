import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/ligne_liste.dart';
import '../../../core/presentation/menu_compte.dart';
import '../../../core/router/routes.dart';
import 'error_reports_screen.dart';
import 'logs_screen.dart';
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
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        LigneListe(
          icone: Icons.group_outlined,
          titre: 'Membres',
          details: const [Text('Inviter et retirer les comptes')],
          chevron: true,
          onTap: () => context.go(AppRoutes.adminMembers),
        ),
        LigneListe(
          icone: Icons.confirmation_number_outlined,
          titre: AdminTicketsScreen.titre,
          details: const [Text(ticketsSubtitle)],
          trailing: alerts > 0
              ? Badge(
                  label: Text(textePastille(alerts)),
                  backgroundColor: scheme.error,
                  textColor: scheme.onError,
                )
              : null,
          chevron: true,
          semanticsLabel: alerts == 0
              ? null
              : '${AdminTicketsScreen.titre}, '
                    '${alerts == 1 ? '1 alerte' : '$alerts alertes'}, '
                    '$ticketsSubtitle',
          onTap: () => context.go(AppRoutes.adminTickets),
        ),
        LigneListe(
          icone: Icons.upload_file_outlined,
          titre: 'Import',
          details: const [Text(importSubtitle)],
          chevron: true,
          // `push` : le retour ramène à l'administration.
          onTap: () => context.push(AppRoutes.adminImport),
        ),
        LigneListe(
          icone: Icons.bug_report_outlined,
          titre: ErrorReportsScreen.titre,
          details: const [Text(ErrorReportsScreen.sousTitre)],
          chevron: true,
          onTap: () => context.go(AppRoutes.adminErrorReports),
        ),
        LigneListe(
          icone: Icons.receipt_long_outlined,
          titre: LogsScreen.titre,
          details: const [Text(LogsScreen.sousTitre)],
          chevron: true,
          onTap: () => context.go(AppRoutes.adminLogs),
        ),
      ],
    );
  }
}
