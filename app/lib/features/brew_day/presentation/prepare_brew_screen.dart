import 'dart:async';

import 'package:brewing/brewing.dart' show StepEventKind;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/services/screen_wakelock.dart';
import '../../auth/presentation/access_providers.dart';
import '../../brews/domain/brew.dart';
import '../../brews/domain/brew_event.dart';
import '../../brews/domain/deroule.dart';
import '../../brews/presentation/brews_providers.dart';
import '../../costs/presentation/costs_providers.dart';
import '../../recipes/domain/chronologie.dart';
import '../domain/plan_du_jour.dart';
import 'brew_day_screen.dart';
import 'chronologie_jour.dart';

/// Textes des états de cet écran ; un brassin illisible a le texte et le bouton
/// de sa fiche : le relire rendrait le même document.
final textesPreparation = TextesDocument(
  chargement: 'Chargement du brassin',
  lectureImpossible: 'Impossible de lire les brassins.',
  absent: 'Ce brassin n\'existe pas ou a été supprimé.',
  horsLigne:
      'Indisponible hors ligne. Reconnectez le téléphone pour charger le '
      'brassin.',
  illisible: textesBrassin.illisible,
  retour: 'Réessayer',
  retourIllisible: textesBrassin.retour,
);

/// « Préparer le brassage » : vérifie que le téléphone a ce qu'il faut pour le jour
/// J, sans rien écrire (PR4), puis commence le brassage. Avec [journee], la clé
/// d'une journée 2 ou suivante du déroulé : « Préparer la journée » (ADR-010).
class PrepareBrewScreen extends ConsumerWidget {
  const PrepareBrewScreen({super.key, required this.id, this.journee});

  final String id;

  /// Clé de la journée ; `null` (ou la clé de la journée de brassage) pour le
  /// brassage.
  final String? journee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(grantedAccessProvider);
    return PageDocument<Brew>(
      async: ref.watch(brewsListProvider),
      id: id,
      offline: access?.offline ?? false,
      textes: textesPreparation,
      onRetry: () => ref.invalidate(brewsListProvider),
      onBack: () => ref.invalidate(brewsListProvider),
      onBackIllisible: () => context.go(AppRoutes.brews),
      builder: (context, brew) {
        final cle = journee;
        if (cle != null) {
          if (brew.ownerUid != access?.user.uid) {
            return _Refus(
              icon: Icons.lock_outline,
              message: TextesJournee.notOwner,
              id: id,
            );
          }
          final suivie = journeeASuivre(brew, cle);
          final refus = suivie.refus;
          if (refus != null) {
            return _Refus(icon: refus.icon, message: refus.message, id: id);
          }
          final j = suivie.journee;
          if (j != null) {
            return _Preparation(
              key: ValueKey('$id/$cle'),
              brew: brew,
              journee: j,
            );
          }
        }
        if (brew.ownerUid != access?.user.uid) {
          return _Refus(
            icon: Icons.lock_outline,
            message: BrewDayScreen.notOwner,
            id: id,
          );
        }
        // Seul un brassin prévu commence : relancer un brassin en fermentation
        // écraserait son statut et sa date de brassage.
        if (brew.status != BrewStatus.planned &&
            brew.status != BrewStatus.brewing) {
          return _Refus(
            icon: Icons.check_circle_outline,
            message: kBrassageTermine,
            id: id,
          );
        }
        return _Preparation(key: ValueKey(id), brew: brew);
      },
    );
  }
}

class _Refus extends StatelessWidget {
  const _Refus({required this.icon, required this.message, required this.id});

  final IconData icon;
  final String message;
  final String id;

  @override
  Widget build(BuildContext context) => EtatVide(
    icon: icon,
    message: message,
    action: FilledButton(
      onPressed: () => context.go(AppRoutes.brew(id)),
      child: const Text('Voir le brassin'),
    ),
  );
}

class _Preparation extends ConsumerStatefulWidget {
  const _Preparation({super.key, required this.brew, this.journee});

  final Brew brew;

  /// Journée 2 ou suivante à préparer ; `null` pour le brassage.
  final JourneeDeroulee? journee;

  @override
  ConsumerState<_Preparation> createState() => _PreparationState();
}

class _PreparationState extends ConsumerState<_Preparation>
    with KeepScreenAwake<_Preparation> {
  late final Future<String?> _tokenName;
  bool _verifying = true;
  bool _fromServer = false;
  bool _starting = false;

  Brew get _brew => widget.brew;
  JourneeDeroulee? get _journee => widget.journee;

  @override
  void initState() {
    super.initState();
    // Le nom du jeton est lu une fois, à l'ouverture (3 s au plus) : le bouton
    // ne l'attend pas à chaque appui.
    _tokenName = ref.read(authRepositoryProvider).currentTokenName();
    unawaited(_verify());
  }

  Future<void> _verify() async {
    final offline = ref.read(grantedAccessProvider)?.offline ?? false;
    final ok = offline
        ? false
        : await ref.read(brewsRepositoryProvider).attendreServeur(_brew.id);
    if (!mounted) return;
    if (ok) ref.read(preparedBrewsProvider).add(_brew.id);
    setState(() {
      _verifying = false;
      _fromServer = ok;
    });
  }

  /// Un déroulé résolu illisible ne se suit pas (ADR-010) : aucun repli sur la
  /// chronologie de la recette.
  bool get _derouleIllisible =>
      _brew.deroule.resolu && _brew.deroule.probleme != null;

  /// « Commencer la journée » : démarre la première étape si elle a une durée,
  /// par une écriture simple, sans changer le statut (ADR-010), puis ouvre
  /// l'écran de la journée.
  void _commencerJournee(JourneeDeroulee journee) {
    if (_starting) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _starting = true);
    // Sur le web, le son de fin de minuteur exige un geste préalable.
    ref.read(alerteMinuteurProvider).preparer();
    final first = journee.lignes.firstOrNull;
    // Une étape de 0 min se fait sur l'écran de la journée (« Fait »).
    if (first != null && first.durationMin > 0) {
      final written = ref
          .read(brewsRepositoryProvider)
          .writeSteps(
            brewId: _brew.id,
            ownerUid: _brew.ownerUid,
            writes: [(kind: StepEventKind.started, stepKey: first.key)],
            at: ref.read(horlogeProvider)(),
          );
      unawaited(
        written.catchError((Object _) {
          // Déjà rapportée par le dépôt de données.
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Le début de « ${first.name} » a été refusé par le serveur.',
              ),
            ),
          );
        }),
      );
    }
    router.go(AppRoutes.journee(_brew.id, journee.key));
  }

  Future<void> _start() async {
    if (_starting || _brew.status != BrewStatus.planned || _derouleIllisible) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _starting = true);
    final ownerName = await _tokenName;
    if (!mounted) return;
    // Sur le web, le son de fin de minuteur exige un geste préalable.
    ref.read(alerteMinuteurProvider).preparer();
    final repo = ref.read(brewsRepositoryProvider);
    final at = ref.read(horlogeProvider)();
    final first = _brew.deroule.brassage?.lignes.firstOrNull;
    final written = repo.start(
      brewId: _brew.id,
      ownerUid: _brew.ownerUid,
      at: at,
      // Une étape de 0 min se fait sur l'écran du jour (« Fait »).
      firstStepKey: first == null || first.durationMin == 0 ? null : first.key,
      ownerName: ownerName,
    );
    unawaited(
      written.catchError((Object _) {
        // Déjà rapportée par le dépôt de données.
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Le début du brassage a été refusé par le serveur.'),
          ),
        );
      }),
    );
    router.go(AppRoutes.brewDay(_brew.id));
  }

  @override
  Widget build(BuildContext context) {
    final suivie = _journee;
    if (suivie != null) return _buildJournee(context, suivie);
    final theme = Theme.of(context);
    final brew = _brew;
    final deroule = brew.deroule;
    final brassage = deroule.brassage;
    final steps = brassage?.lignes ?? const <BrewStepLine>[];
    final now = ref.read(horlogeProvider)();
    final evalue = evaluerPlan(
      brew: brew,
      events: const [],
      now: now,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(planReportsProvider),
    );
    final planned = brew.plannedFor;
    final illisible = messageDerouleIllisible(deroule);
    // Avec un processus : « Brassage : 18 étapes · … », puis les journées
    // suivantes et leurs dates (ADR-010).
    final journee = brew.process == null || brassage == null
        ? ''
        : '${brassage.name.trim()} : ';
    final ensuite = [
      for (final j in deroule.journees.skip(1))
        switch (j.date(brew.departDeroule)) {
          final DateTime date => '${j.name.trim()} le ${formatJourMois(date)}',
          null => '${j.name.trim()} à J+${j.offsetDays}',
        },
    ];
    final chrono = switch (evalue) {
      _ when illisible != null => (
        icon: Icons.error_outline,
        titre: 'Chronologie',
        detail: illisible,
      ),
      PlanImpossible() => (
        icon: Icons.error_outline,
        titre: 'Chronologie',
        detail: kCalculChronologieImpossible,
      ),
      PlanObtenu(:final plan) when plan.lignes.isEmpty => (
        icon: Icons.warning_amber,
        titre: 'Aucune étape',
        detail: 'Vous pourrez saisir des mesures, sans minuteur.',
      ),
      PlanObtenu(:final plan) => (
        icon: Icons.check_circle_outline,
        titre: 'Chronologie',
        detail:
            '$journee${formatEtapes(steps.length)} · '
            '${formatDuree(dureeChronologie(steps))}'
            '${plan.finPrevue == null ? '' : ' · fin vers ${formatHeure(plan.finPrevue!)}'}',
      ),
    };
    final brewing = brew.status == BrewStatus.brewing;
    final peutCommencer = !_verifying && !_starting && !_derouleIllisible;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kBrewDayActionsMaxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  planned == null
                      ? brew.name
                      : '${brew.name} · prévu ${formatDate(planned)}',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Préparez le brassage sur le téléphone qui servira ce jour-là.',
              ),
              const SizedBox(height: 16),
              if (_verifying)
                const _Attente()
              else ...[
                _ligneBrassin('Brassin et recette figée'),
                _LigneVerif(
                  icon: Icons.check_circle_outline,
                  titre: 'Équipement',
                  detail: brew.equipment.name,
                ),
                _LigneVerif(
                  icon: chrono.icon,
                  titre: chrono.titre,
                  detail: [
                    chrono.detail,
                    if (illisible == null && ensuite.isNotEmpty)
                      'Ensuite : ${ensuite.join(', ')}',
                  ].join('\n'),
                ),
                ..._lignesAppareil(theme),
              ],
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(72),
                ),
                onPressed: brewing
                    ? () => context.go(AppRoutes.brewDay(brew.id))
                    : (peutCommencer ? _start : null),
                child: Text(
                  brewing ? 'Reprendre le brassage' : 'Commencer le brassage',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lignes et « Préparer la journée » d'une journée 2 ou suivante (ADR-010).
extension on _PreparationState {
  /// Lignes communes au brassage et aux journées suivantes : compte, écran,
  /// minuteurs, navigateur, et « Tout est prêt » après la réponse du serveur.
  List<Widget> _lignesAppareil(ThemeData theme) => [
    const _LigneVerif(
      icon: Icons.check_circle_outline,
      titre: 'Compte',
      detail: 'Connexion gardée sur l\'appareil',
    ),
    ValueListenableBuilder<bool>(
      valueListenable: wakelock.failed,
      builder: (context, refuse, _) => _LigneVerif(
        icon: refuse ? Icons.warning_amber : Icons.info_outline,
        titre: 'Écran',
        detail: refuse
            ? 'L\'appareil refuse de le garder allumé. Réglez la '
                  'mise en veille.'
            : 'Il restera allumé. Branchez le téléphone sur secteur.',
      ),
    ),
    const _LigneVerif(
      icon: Icons.info_outline,
      titre: 'Minuteurs',
      detail:
          'Aucune alarme ne sonne écran verrouillé : gardez l\'écran '
          'visible.',
    ),
    if (kIsWeb)
      const _LigneVerif(
        icon: Icons.warning_amber,
        titre: 'Navigateur',
        detail:
            'Gardez cet onglet ouvert. Une page rechargée sans '
            'réseau ne s\'ouvre plus.',
      ),
    if (_fromServer)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Tout est prêt. Vous pouvez couper le réseau.',
          style: theme.textTheme.titleMedium,
        ),
      ),
  ];

  /// Ligne « Brassin et … » : réponse du serveur, ou écriture en attente.
  _LigneVerif _ligneBrassin(String titre) {
    final brew = _brew;
    return _LigneVerif(
      icon: brew.hasPendingWrites || _fromServer
          ? Icons.check_circle_outline
          : Icons.info_outline,
      titre: titre,
      detail: brew.hasPendingWrites
          ? 'Enregistré sur l\'appareil, envoi au retour du réseau'
          : _fromServer
          ? 'Enregistrés sur l\'appareil'
          : 'Préparation impossible sans réseau. Le brassin est '
                'lisible sur cet appareil, mais peut ne pas être à jour.',
    );
  }

  /// Plan de [journee] avec les saisies lues, ou `null` si le calcul est refusé.
  PlanDuJour? _plan(JourneeDeroulee journee, List<BrewEvent> events) =>
      switch (evaluerPlan(
        brew: _brew,
        events: events,
        now: ref.read(horlogeProvider)(),
        errors: ref.read(errorReportServiceProvider),
        reported: ref.read(planReportsProvider),
        journee: journee,
      )) {
        PlanObtenu(:final plan) => plan,
        PlanImpossible() => null,
      };

  /// « Préparer la journée » : brassin et déroulé, étapes de la journée, prix et
  /// frais pour l'embouteillage, appareil.
  Widget _buildJournee(BuildContext context, JourneeDeroulee journee) {
    final theme = Theme.of(context);
    final brew = _brew;
    final now = ref.read(horlogeProvider)();
    final eventsAsync = ref.watch(brewEventsProvider(brew.id));
    final lues = eventsAsync.value;
    final events = lues == null ? null : [...lues.valides];
    final packaging = journee.role == RoleJournee.embouteillage;
    // Prix, frais et coût figé du propriétaire : lus ici et gardés ouverts par
    // l'écran de la journée, capturés à l'embouteillage (P2, CB5).
    final prices = packaging ? ref.watch(pricesProvider(brew.ownerUid)) : null;
    final fees = packaging ? ref.watch(feesProvider(brew.ownerUid)) : null;
    final cout = packaging
        ? ref.watch(brewCostProvider((uid: brew.ownerUid, brewId: brew.id)))
        : null;
    final nom = journee.name.trim();
    final date = journee.date(brew.departDeroule);
    final aujourdhui = date != null && memeJour(date, now);
    final plan = events == null ? null : _plan(journee, events);
    final steps = journee.lignes;
    final etapes = switch ((events, plan)) {
      (null, _) when eventsAsync.hasError => (
        icon: Icons.error_outline,
        detail: TextesJournee.saisiesIllisibles,
      ),
      (null, _) => (icon: Icons.info_outline, detail: 'Chargement des saisies'),
      (_, null) => (
        icon: Icons.error_outline,
        detail: kCalculChronologieImpossible,
      ),
      (_, final PlanDuJour p) when p.lignes.isEmpty => (
        icon: Icons.warning_amber,
        detail: 'Aucune étape. Vous pourrez saisir des mesures, sans minuteur.',
      ),
      (_, final PlanDuJour p) => (
        icon: Icons.check_circle_outline,
        detail:
            '${formatEtapes(steps.length)} · '
            '${formatDuree(dureeChronologie(steps))}'
            '${p.finPrevue == null ? '' : ' · fin vers ${formatHeure(p.finPrevue!)}'}',
      ),
    };
    // Journées précédentes, après le brassage, pas encore terminées.
    final ouvertes = [
      if (events != null)
        for (final j in brew.deroule.journees.skip(1))
          if (_avant(brew, j, journee) &&
              !journeeTerminee(brew: brew, journee: j, plan: _plan(j, events)))
            j.name.trim(),
    ];
    final reprendre = plan?.commencee ?? false;
    final peutCommencer = !_verifying && !_starting && plan != null;
    final prixLus =
        prices?.value != null && fees?.value != null && cout?.value != null;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kBrewDayActionsMaxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  [
                    brew.name,
                    nom,
                    if (date != null)
                      aujourdhui
                          ? 'prévue aujourd\'hui'
                          : 'prévue le ${formatJourMois(date)}',
                  ].join(' · '),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 4),
              const Text(TextesJournee.preparerSurTelephone),
              const SizedBox(height: 16),
              if (_verifying)
                const _Attente()
              else ...[
                _ligneBrassin('Brassin et déroulé figé'),
                _LigneVerif(
                  icon: etapes.icon,
                  titre: 'Étapes',
                  detail: etapes.detail,
                ),
                if (packaging)
                  _LigneVerif(
                    icon: prixLus
                        ? Icons.check_circle_outline
                        : Icons.warning_amber,
                    titre: 'Prix et frais',
                    detail: prixLus
                        ? TextesJournee.prixLus
                        : TextesJournee.prixIndisponibles,
                  ),
                ..._lignesAppareil(theme),
                if (date != null && !aujourdhui)
                  _Info(TextesJournee.prevueLe(date)),
                for (final o in ouvertes) _Info(TextesJournee.nonTerminee(o)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(72),
                ),
                onPressed: !peutCommencer
                    ? null
                    : reprendre
                    ? () => context.go(AppRoutes.journee(brew.id, journee.key))
                    : () => _commencerJournee(journee),
                child: Text(
                  reprendre ? TextesJournee.reprendre : TextesJournee.commencer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vrai si [j] vient avant [cible] dans le déroulé de [brew].
bool _avant(Brew brew, JourneeDeroulee j, JourneeDeroulee cible) {
  for (final x in brew.deroule.journees) {
    if (x.key == cible.key) return false;
    if (x.key == j.key) return true;
  }
  return false;
}

/// Ligne d'information de « Préparer la journée ».
class _Info extends StatelessWidget {
  const _Info(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: 12),
        Expanded(child: Text(texte)),
      ],
    ),
  );
}

class _Attente extends StatelessWidget {
  const _Attente();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: IndicateurBouton(label: 'Vérification en cours'),
    );
  }
}

class _LigneVerif extends StatelessWidget {
  const _LigneVerif({
    required this.icon,
    required this.titre,
    required this.detail,
  });

  final IconData icon;
  final String titre;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: theme.textTheme.titleMedium),
                Text(detail, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
