import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../tickets/presentation/bandeau_tickets_admin.dart';

/// Accueil de l'administration : réservé au rôle `admin` (le routeur le vérifie).
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        // Jeton GitHub et tickets bloqués (ADR-006) ; rien quand tout va bien.
        const BandeauTicketsAdmin(),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.group_outlined),
          title: const Text('Membres'),
          subtitle: const Text('Inviter et retirer les comptes'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(AppRoutes.adminMembers),
        ),
        const ListTile(
          enabled: false,
          leading: Icon(Icons.upload_file_outlined),
          title: Text('Import'),
          subtitle: Text('Disponible dans une prochaine version'),
        ),
      ],
    );
  }
}
