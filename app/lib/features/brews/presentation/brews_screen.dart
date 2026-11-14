import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/ligne_liste.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../brew_day/domain/plan_du_jour.dart';
import '../../brew_day/presentation/chronologie_jour.dart';
import '../domain/brew.dart';
import '../domain/deroule.dart';
import 'brews_providers.dart';

/// Brassins du groupe : en cours d'abord, puis prévus, puis les autres ; filtre
/// « Tous » / « Les miens », état de l'écran, jamais écrit en base.
class BrewsScreen extends ConsumerStatefulWidget {
  const BrewsScreen({super.key});

  static const loadError = 'Impossible de lire les brassins.';
  static const emptyTitle = 'Aucun brassin';
  static const mineEmptyTitle = 'Vous n\'avez pas encore de brassin';

  /// Message des deux états vides, sous [emptyTitle] ou [mineEmptyTitle].
  static const emptyMessage =
      'Ouvrez une recette et appuyez sur Nouveau brassin.';

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
            titre: _mineOnly
                ? BrewsScreen.mineEmptyTitle
                : BrewsScreen.emptyTitle,
            message: BrewsScreen.emptyMessage,
            action: _mineOnly
                ? null
                : TextButton(
                    onPressed: () => context.go(AppRoutes.recipes),
                    child: const Text('Voir les recettes'),
                  ),
          ),
        for (final b in shown) _Row(brew: b, readerUid: readerUid, now: now),
        for (final d in invalid)
          LigneListe(
            icone: Icons.error_outline,
            erreur: true,
            titre: 'Brassin illisible',
            details: const [
              Text(
                'Mettez l\'application à jour, ou prévenez l\'administrateur.',
              ),
            ],
            onTap: () => context.go(AppRoutes.brew(d.id)),
          ),
      ],
    );
  }
}

/// Date affichée dans la ligne d'un brassin. En fermentation et en
/// conditionnement, la prochaine journée du déroulé quand elle existe
/// (« Prochaine journée : Houblonnage à cru, mer. 25 nov. »), choisie par
/// [prochaineJourneeAnnoncee] (ADR-010) : même règle que la fiche quand
/// [planDe] est connu (événements lus), avec « en cours » pour une journée
/// commencée et « en retard (prévue le …) » pour une date passée ; d'après les
/// dates seules sinon.
String ligneDateBrassin(
  Brew brew,
  DateTime now, {
  PlanDuJour? Function(JourneeDeroulee journee)? planDe,
}) {
  final brewed = brew.brewedAt;
  final planned = brew.plannedFor;
  final prochaine = prochaineJourneeAnnoncee(brew, now, planDe: planDe);
  if (prochaine != null) {
    final date = prochaine.date;
    final aujourdhui = DateTime(now.year, now.month, now.day);
    final quand = prochaine.commencee
        ? 'en cours'
        : date == aujourdhui
        ? "aujourd'hui"
        : date.isBefore(aujourdhui)
        ? 'en retard (prévue le ${formatJourMois(date)})'
        : formatJourMois(date);
    return 'Prochaine journée : ${prochaine.journee.name.trim()}, $quand';
  }
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

class _Row extends ConsumerWidget {
  const _Row({required this.brew, required this.readerUid, required this.now});

  final Brew brew;
  final String? readerUid;
  final DateTime now;

  /// Plan d'une journée d'après les événements du brassin, lus depuis le cache
  /// comme sur la fiche, chaque plan calculé une fois ; `null` tant qu'ils ne
  /// sont pas lus ([evenementsLus] : chargement, panne rapportée par le dépôt,
  /// hors ligne sans cache) : la ligne garde alors la règle des dates. Seuls les
  /// brassins de [listeLitEvenements] les lisent.
  PlanDuJour? Function(JourneeDeroulee)? _planDe(WidgetRef ref) {
    if (!listeLitEvenements(brew, readerUid)) return null;
    final events = evenementsLus(ref.watch(brewEventsProvider(brew.id)).value);
    if (events == null) return null;
    final plans = <String, PlanDuJour?>{};
    return (j) => plans.putIfAbsent(
      j.key,
      () => switch (evaluerPlan(
        brew: brew,
        events: events,
        now: now,
        errors: ref.read(errorReportServiceProvider),
        reported: ref.read(planReportsProvider),
        journee: j,
      )) {
        PlanObtenu(:final plan) => plan,
        PlanImpossible() => null,
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ligneDateBrassin(brew, now, planDe: _planDe(ref));
    return LigneListe(
      icone: Icons.science_outlined,
      titre: brew.name,
      details: [
        Text(
          [
            brew.equipment.name,
            libelleAuteur(
              ownerUid: brew.ownerUid,
              ownerName: brew.ownerName,
              readerUid: readerUid,
            ),
          ].join(' · '),
        ),
        if (date.isNotEmpty) Text(date),
      ],
      etiquettes: [
        Etiquette(label: brew.status.label, ton: _tonStatut(brew.status)),
        if (brew.hasPendingWrites)
          const Etiquette(label: 'En attente du réseau'),
      ],
      onTap: () => context.go(AppRoutes.brew(brew.id)),
    );
  }
}

/// Ton de l'étiquette du statut d'un brassin dans la liste : neutre avant et
/// hors du travail, tertiaire pendant, primaire une fois terminé.
TonEtiquette _tonStatut(BrewStatus status) => switch (status) {
  BrewStatus.planned || BrewStatus.abandoned => TonEtiquette.neutre,
  BrewStatus.brewing ||
  BrewStatus.fermenting ||
  BrewStatus.conditioning => TonEtiquette.tertiaire,
  BrewStatus.done => TonEtiquette.primaire,
};
