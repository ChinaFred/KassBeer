import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../recipes/presentation/recipes_providers.dart';
import '../domain/equipment.dart';
import 'equipment_providers.dart';

/// Textes des états de la fiche et de l'éditeur d'un équipement.
const textesEquipement = TextesDocument(
  chargement: 'Chargement de l\'équipement',
  lectureImpossible: 'Impossible de lire les équipements.',
  absent: 'Cet équipement n\'existe pas ou a été supprimé.',
  horsLigne: 'Équipement indisponible hors ligne.',
  illisible:
      'Cet équipement est illisible : une valeur enregistrée est '
      'inattendue.',
  retour: 'Revenir aux équipements',
);

/// Fiche d'un équipement : une colonne bornée à [kDialogMaxWidth].
class EquipmentDetailScreen extends ConsumerWidget {
  const EquipmentDetailScreen({super.key, required this.id});

  final String id;

  static String deleteTitle(String name) => 'Supprimer « $name » ?';
  static const deleteGroup = 'L\'équipement disparaît pour tout le groupe.';
  static String usedBy(List<String> names) {
    final n = names.length;
    final noun = n == 1 ? 'recette' : 'recettes';
    final verb = n == 1 ? 'Son calcul affichera' : 'Leurs calculs afficheront';
    return 'Utilisé par $n $noun : ${names.join(', ')}. $verb Équipement '
        'supprimé.';
  }

  static const recipesUnknown =
      'Les recettes qui l\'utilisent n\'ont pas pu être lues. Leurs calculs '
      'afficheront Équipement supprimé.';
  static const deletedMessage = 'Équipement supprimé.';
  static String deleteRejected(String name) =>
      'La suppression de « $name » a échoué.';

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Equipment equipment,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final recipes = ref.read(recipesListProvider).value;
    final users = recipes == null
        ? null
        : [
            for (final r in recipes.valides)
              if (r.content.equipmentId == equipment.id) r.name,
          ];
    final confirmed = await confirmerSuppression(
      context,
      titre: deleteTitle(equipment.name),
      paragraphes: [
        deleteGroup,
        if (users == null)
          recipesUnknown
        else if (users.isNotEmpty)
          usedBy(users),
      ],
    );
    if (!confirmed || !context.mounted) return;
    // L'écriture locale est faite à l'appel : la fiche se ferme sans attendre le
    // serveur. Les recettes qui citent l'équipement ne sont pas écrites (E9).
    final write = ref.read(equipmentRepositoryProvider).delete(equipment.id);
    suivreEcriture(
      messenger: messenger,
      written: write,
      succes: deletedMessage,
      refus: deleteRejected(equipment.name),
    );
    context.go(AppRoutes.equipment);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(equipmentListProvider);
    // Lu pour annoncer, avant une suppression, les recettes qui l'utilisent.
    ref.watch(recipesListProvider);
    final access = ref.watch(grantedAccessProvider);
    return PageDocument<Equipment>(
      async: listAsync,
      id: id,
      offline: access?.offline ?? false,
      textes: textesEquipement,
      onRetry: () => ref.invalidate(equipmentListProvider),
      onBack: () => context.go(AppRoutes.equipment),
      builder: (context, equipment) => _Fiche(
        equipment: equipment,
        readerUid: access?.user.uid,
        onEdit: () => context.push(AppRoutes.editEquipment(equipment.id)),
        onDelete: () => _delete(context, ref, equipment),
      ),
    );
  }
}

class _Fiche extends StatelessWidget {
  const _Fiche({
    required this.equipment,
    required this.readerUid,
    required this.onEdit,
    required this.onDelete,
  });

  final Equipment equipment;
  final String? readerUid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = equipment.content;
    final mine = equipment.ownerUid == readerUid;
    final allInOne = c.kind == EquipmentKind.allInOne;
    String? litres(double? v) => v == null ? null : formatLitres(v);
    final efficiency = c.mashEfficiencyPct;
    final boilOff = c.boilOffLPerH;
    final absorption = c.grainAbsorptionLPerKg;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Semantics(
              header: true,
              child: Text(c.name, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: 4),
            Text(
              mine
                  ? c.kind.label
                  : '${c.kind.label} · Équipement de '
                        '${libelleAuteur(ownerUid: equipment.ownerUid, ownerName: equipment.ownerName, readerUid: readerUid)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (equipment.hasPendingWrites) ...[
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Etiquette(label: 'En attente du réseau'),
              ),
            ],
            if (mine) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                  ),
                ],
              ),
            ],
            const TitreSection('Rendement'),
            LigneFiche(
              label: 'Rendement d\'empâtage',
              value: efficiency == null ? null : formatPourcent(efficiency),
            ),
            LigneFiche(
              label: 'Évaporation',
              value: boilOff == null ? null : formatLitresParHeure(boilOff),
            ),
            LigneFiche(
              label: 'Absorption du grain',
              value: absorption == null ? null : formatLitresParKg(absorption),
            ),
            const TitreSection('Volumes'),
            if (allInOne)
              LigneFiche(
                label: 'Volume de la cuve',
                value: litres(c.mashTunVolumeL),
              )
            else ...[
              LigneFiche(
                label: 'Cuve d\'empâtage',
                value: litres(c.mashTunVolumeL),
              ),
              LigneFiche(
                label: 'Cuve d\'ébullition',
                value: litres(c.kettleVolumeL),
              ),
            ],
            const TitreSection('Pertes'),
            LigneFiche(
              label: allInOne
                  ? 'Volume mort de la cuve'
                  : 'Volume mort de la cuve d\'empâtage',
              value: litres(c.mashTunDeadSpaceL),
            ),
            if (!allInOne)
              LigneFiche(
                label: 'Volume mort de la cuve d\'ébullition',
                value: litres(c.kettleDeadSpaceL),
              ),
            LigneFiche(label: 'Pertes au trub', value: litres(c.trubLossL)),
            LigneFiche(
              label: 'Pertes au fermenteur',
              value: litres(c.fermenterLossL),
            ),
            const TitreSection('Notes'),
            Text(
              c.notes ?? 'Non renseigné',
              style: c.notes == null
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    )
                  : theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
