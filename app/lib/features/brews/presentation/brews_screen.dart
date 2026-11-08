import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/brew.dart';
import 'brews_providers.dart';

/// Brassins du groupe : en cours d'abord, puis prévus, puis les autres ; filtre
/// « Tous » / « Les miens », état de l'écran, jamais écrit en base.
class BrewsScreen extends ConsumerStatefulWidget {
  const BrewsScreen({super.key});

  static const loadError = 'Impossible de lire les brassins.';
  static const emptyMessage =
      'Aucun brassin. Ouvrez une recette et appuyez sur Nouveau brassin.';
  static const mineEmptyMessage =
      'Vous n\'avez pas encore de brassin. Ouvrez une recette et appuyez sur '
      'Nouveau brassin.';

  @override
  ConsumerState<BrewsScreen> createState() => _BrewsScreenState();
}

class _BrewsScreenState extends ConsumerState<BrewsScreen> {
  bool _mineOnly = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(brewsListProvider);
    final readerUid = ref.watch(grantedAccessProvider)?.user.uid;
    final list = async.value;
    if (list == null) {
      return async.hasError
          ? EtatErreur(
              message: BrewsScreen.loadError,
              retrying: async.isLoading,
              retryingLabel: 'Lecture en cours',
              onRetry: () => ref.invalidate(brewsListProvider),
            )
          : const EtatChargement(label: 'Chargement des brassins');
    }
    final shown = [
      for (final b in list.valides..sort(compareBrews))
        if (!_mineOnly || b.ownerUid == readerUid) b,
    ];
    final invalid = _mineOnly
        ? const <DocumentInvalide<Brew>>[]
        : list.documents.whereType<DocumentInvalide<Brew>>().toList();
    final now = ref.read(horlogeProvider)();
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        if (async.hasError)
          BandeauListePerimee(
            retrying: async.isLoading,
            onRetry: () => ref.invalidate(brewsListProvider),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Tous')),
              ButtonSegment(value: true, label: Text('Les miens')),
            ],
            selected: {_mineOnly},
            onSelectionChanged: (s) => setState(() => _mineOnly = s.single),
          ),
        ),
        if (shown.isEmpty && invalid.isEmpty)
          EtatVide(
            icon: Icons.science_outlined,
            message: _mineOnly
                ? BrewsScreen.mineEmptyMessage
                : BrewsScreen.emptyMessage,
            action: _mineOnly
                ? null
                : TextButton(
                    onPressed: () => context.go(AppRoutes.recipes),
                    child: const Text('Voir les recettes'),
                  ),
          ),
        for (final b in shown) _Row(brew: b, readerUid: readerUid, now: now),
        for (final d in invalid)
          ListTile(
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Brassin illisible'),
            subtitle: const Text('Le document contient une valeur inattendue.'),
            onTap: () => context.go(AppRoutes.brew(d.id)),
          ),
      ],
    );
  }
}

/// Date affichée dans la ligne d'un brassin.
String ligneDateBrassin(Brew brew, DateTime now) {
  final brewed = brew.brewedAt;
  final planned = brew.plannedFor;
  if (brew.status == BrewStatus.planned) {
    return planned == null
        ? 'Date non fixée'
        : 'Prévu le ${formatDate(planned)}';
  }
  if (brew.status == BrewStatus.conditioning && brew.bottledAt != null) {
    return 'Embouteillé le ${formatDateCourte(brew.bottledAt!)}';
  }
  if (brewed == null) return '';
  if (brew.status == BrewStatus.brewing &&
      brewed.year == now.year &&
      brewed.month == now.month &&
      brewed.day == now.day) {
    return 'Commencé aujourd\'hui à ${formatHeure(brewed)}';
  }
  return 'Brassé le ${formatDateCourte(brewed)}';
}

class _Row extends StatelessWidget {
  const _Row({required this.brew, required this.readerUid, required this.now});

  final Brew brew;
  final String? readerUid;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = ligneDateBrassin(brew, now);
    return InkWell(
      onTap: () => context.go(AppRoutes.brew(brew.id)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(brew.name, style: theme.textTheme.titleMedium),
                    Text(
                      [
                        brew.status.label,
                        brew.equipment.name,
                        libelleAuteur(
                          ownerUid: brew.ownerUid,
                          ownerName: brew.ownerName,
                          readerUid: readerUid,
                        ),
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (date.isNotEmpty)
                      Text(date, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (brew.hasPendingWrites)
                const Etiquette(label: 'En attente du réseau'),
            ],
          ),
        ),
      ),
    );
  }
}
