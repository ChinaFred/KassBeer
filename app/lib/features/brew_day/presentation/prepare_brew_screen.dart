import 'dart:async';

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
import '../../brews/presentation/brews_providers.dart';
import '../../recipes/domain/chronologie.dart';
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
/// J, sans rien écrire (PR4), puis commence le brassage.
class PrepareBrewScreen extends ConsumerWidget {
  const PrepareBrewScreen({super.key, required this.id});

  final String id;

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
  const _Preparation({super.key, required this.brew});

  final Brew brew;

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

  Future<void> _start() async {
    if (_starting || _brew.status != BrewStatus.planned) return;
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
    final theme = Theme.of(context);
    final brew = _brew;
    final deroule = brew.deroule;
    final steps = deroule.brassage?.lignes ?? const <BrewStepLine>[];
    final now = ref.read(horlogeProvider)();
    final evalue = evaluerPlan(
      brew: brew,
      events: const [],
      now: now,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(planReportsProvider),
    );
    final planned = brew.plannedFor;
    final illisible = deroule.probleme;
    final chrono = switch (evalue) {
      _ when illisible != null => (
        icon: Icons.error_outline,
        titre: 'Chronologie',
        detail: messageChronologieIllisible(illisible),
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
            '${formatEtapes(steps.length)} · ${formatDuree(dureeChronologie(steps))}'
            '${plan.finPrevue == null ? '' : ' · fin vers ${formatHeure(plan.finPrevue!)}'}',
      ),
    };
    final brewing = brew.status == BrewStatus.brewing;
    final peutCommencer = !_verifying && !_starting;
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
                _LigneVerif(
                  icon: brew.hasPendingWrites
                      ? Icons.check_circle_outline
                      : (_fromServer
                            ? Icons.check_circle_outline
                            : Icons.info_outline),
                  titre: 'Brassin et recette figée',
                  detail: brew.hasPendingWrites
                      ? 'Enregistré sur l\'appareil, envoi au retour du réseau'
                      : _fromServer
                      ? 'Enregistrés sur l\'appareil'
                      : 'Préparation impossible sans réseau. Le brassin est '
                            'lisible sur cet appareil, mais peut ne pas être à jour.',
                ),
                _LigneVerif(
                  icon: Icons.check_circle_outline,
                  titre: 'Équipement',
                  detail: brew.equipment.name,
                ),
                _LigneVerif(
                  icon: chrono.icon,
                  titre: chrono.titre,
                  detail: chrono.detail,
                ),
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
