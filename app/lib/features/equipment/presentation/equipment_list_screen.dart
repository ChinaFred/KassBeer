import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/equipment.dart';
import 'equipment_providers.dart';

/// Équipements : liste du groupe, les miens d'abord puis par nom (E1).
class EquipmentListScreen extends ConsumerWidget {
  const EquipmentListScreen({super.key});

  static const loadError = 'Impossible de lire les équipements.';
  static const emptyMessage =
      'Aucun équipement. Appuyez sur Nouvel équipement pour décrire votre '
      'installation.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(equipmentListProvider);
    final readerUid = ref.watch(grantedAccessProvider)?.user.uid;
    final compact = MediaQuery.sizeOf(context).width < kCompactMaxWidth;
    final list = listAsync.value;
    void create() => context.push(AppRoutes.newEquipment);

    final Widget body = switch (listAsync) {
      AsyncError() when list == null => EtatErreur(
        message: loadError,
        retrying: listAsync.isLoading,
        retryingLabel: 'Lecture en cours',
        onRetry: () => ref.invalidate(equipmentListProvider),
      ),
      _ when list == null => const EtatChargement(
        label: 'Chargement des équipements',
      ),
      _ => _List(
        list: list,
        readerUid: readerUid,
        compact: compact,
        stale: listAsync.hasError,
        retrying: listAsync.isLoading,
        onRetry: () => ref.invalidate(equipmentListProvider),
        onCreate: create,
      ),
    };

    return Scaffold(
      body: body,
      floatingActionButton: compact && list != null
          ? FloatingActionButton.extended(
              onPressed: create,
              icon: const Icon(Icons.add),
              label: const Text('Nouvel équipement'),
            )
          : null,
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.list,
    required this.readerUid,
    required this.compact,
    required this.stale,
    required this.retrying,
    required this.onRetry,
    required this.onCreate,
  });

  final ListeLue<Equipment> list;
  final String? readerUid;
  final bool compact;
  final bool stale;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final items = list.valides..sort(compareEquipment(readerUid));
    final invalid = list.documents.whereType<DocumentInvalide<Equipment>>();
    return ListView(
      padding: EdgeInsets.only(top: 8, bottom: compact ? 96 : 24),
      children: [
        if (stale) BandeauListePerimee(retrying: retrying, onRetry: onRetry),
        if (!compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Nouvel équipement'),
              ),
            ),
          ),
        if (items.isEmpty && invalid.isEmpty)
          const EtatVide(
            icon: Icons.kitchen_outlined,
            message: EquipmentListScreen.emptyMessage,
          ),
        for (final e in items) _Row(equipment: e, readerUid: readerUid),
        for (final d in invalid)
          ListTile(
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Équipement illisible'),
            subtitle: const Text('Le document contient une valeur inattendue.'),
            onTap: () => context.go(AppRoutes.equipmentItem(d.id)),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.equipment, required this.readerUid});

  final Equipment equipment;
  final String? readerUid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = equipment.content;
    final efficiency = c.mashEfficiencyPct;
    final details = [
      c.kind.label,
      efficiency == null
          ? 'Rendement non renseigné'
          : 'Rendement ${formatPourcent(efficiency)}',
      libelleAuteur(
        ownerUid: equipment.ownerUid,
        ownerName: equipment.ownerName,
        readerUid: readerUid,
      ),
    ].join(' · ');
    return InkWell(
      onTap: () => context.go(AppRoutes.equipmentItem(equipment.id)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, style: theme.textTheme.titleMedium),
              Text(
                details,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (equipment.hasPendingWrites) ...[
                const SizedBox(height: 8),
                const Etiquette(label: 'En attente du réseau'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
