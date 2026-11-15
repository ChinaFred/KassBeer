import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/ligne_liste.dart';
import '../../../core/presentation/menu_compte.dart';
import '../../../core/router/routes.dart';
import '../../ai/presentation/ai_providers.dart';
import '../../tickets/presentation/admin_tickets_screen.dart';
import '../../tickets/presentation/bandeau_tickets_admin.dart';
import 'admin_sources_screen.dart';
import 'couts_ia_screen.dart';
import 'error_reports_screen.dart';
import 'logs_screen.dart';
import 'moteur_ia_screen.dart';

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
    // Grille absente ou illisible, poste sans réglage lisible : lus par
    // `get()` à l'ouverture de l'accueil Admin.
    final alertesIa = alertesMoteurIa(
      grille: ref.watch(grilleIaProvider).value,
      politique: ref.watch(politiqueIaProvider).value,
    );
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
          icone: Icons.smart_toy_outlined,
          titre: TextesMoteurIa.titre,
          details: const [Text(TextesMoteurIa.sousTitre)],
          trailing: alertesIa > 0
              ? Badge(
                  label: Text(textePastille(alertesIa)),
                  backgroundColor: scheme.error,
                  textColor: scheme.onError,
                )
              : null,
          chevron: true,
          semanticsLabel: alertesIa == 0
              ? null
              : '${TextesMoteurIa.titre}, '
                    '${alertesIa == 1 ? '1 alerte' : '$alertesIa alertes'}, '
                    '${TextesMoteurIa.sousTitre}',
          onTap: () => context.go(AppRoutes.adminAiEngine),
        ),
        LigneListe(
          icone: Icons.payments_outlined,
          titre: CoutsIaScreen.titre,
          details: const [Text(CoutsIaScreen.sousTitre)],
          chevron: true,
          onTap: () => context.go(AppRoutes.adminAiCosts),
        ),
        LigneListe(
          icone: Icons.source_outlined,
          titre: AdminSourcesScreen.titre,
          details: const [Text(AdminSourcesScreen.sousTitre)],
          chevron: true,
          onTap: () => context.go(AppRoutes.adminSources),
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
