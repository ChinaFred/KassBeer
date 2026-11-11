import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../library/data/library_repository.dart' show CurseurPage;
import '../data/sources_repository.dart';
import '../domain/ingestion.dart';
import 'libelles_sources.dart';

Duration? _sansNouvelEssai(int retryCount, Object error) => null;

/// Dernière exécution de l'ingestion, lue par `get()` à l'ouverture de
/// l'écran ; « Réessayer » relance la lecture.
final derniereExecutionProvider = FutureProvider.autoDispose<LectureExecution>(
  (ref) => ref.watch(sourcesRepositoryProvider).derniereExecution(),
  retry: _sansNouvelEssai,
);

/// Admin › Sources (ADR-005, L4) : compte rendu de la dernière mise à jour de
/// la Bibliothèque (ingestion) et noms non reconnus. Lecture seule, réservée à
/// l'admin.
class AdminSourcesScreen extends ConsumerStatefulWidget {
  const AdminSourcesScreen({super.key});

  static const titre = 'Sources';
  static const intro =
      'Mise à jour de la Bibliothèque depuis les sources externes '
      '(Brewtarget, BJCP, DIY Dog).';
  static const reload = 'Relire';
  static const runTitle = 'Dernière mise à jour';
  static const unresolvedTitle = 'Tous les noms non reconnus';
  static const unresolvedHelp =
      "Noms qu'aucune source n'a rattachés à un ingrédient de la "
      'Bibliothèque, du plus fréquent au moins fréquent.';
  static const sourcesLabel = 'Sources des données';
  static const emptyRun =
      'Aucune mise à jour enregistrée. Elle se lance depuis votre poste, puis '
      "s'affiche ici.";
  static const emptyUnresolved = 'Aucun nom non reconnu.';
  static const runError = 'Impossible de lire la dernière mise à jour.';
  static const unresolvedError = 'Impossible de lire les noms non reconnus.';
  static const nextPageError = 'Impossible de lire la page suivante.';
  static const runUnreadable =
      'Le compte rendu de la dernière mise à jour est illisible. Mettez '
      "l'application à jour.";
  static const rowUnreadable = 'Nom illisible';
  static const rowUnreadableDetail = "Mettez l'application à jour.";
  static const runOffline = 'Dernière mise à jour indisponible hors ligne.';
  static const unresolvedOffline = 'Liste indisponible hors ligne.';
  static const runFromCache =
      "Hors ligne : lu sur l'appareil. Ce compte rendu peut ne plus être à "
      'jour.';
  static const unresolvedFromCache =
      "Hors ligne : lu sur l'appareil. Cette liste peut ne plus être à jour.";
  static const showMore = 'Afficher les noms suivants';

  static String refusedNote(int refused) =>
      '${refused == 1 ? '1 document refusé' : '$refused documents refusés'}. '
      'Le détail est dans le rapport local.';

  /// Chemin du rapport local d'une exécution, depuis la racine du dépôt.
  static String reportPath(String runId) =>
      'import/ingest/rapports/$runId.json';

  @override
  ConsumerState<AdminSourcesScreen> createState() => _AdminSourcesScreenState();
}

class _AdminSourcesScreenState extends ConsumerState<AdminSourcesScreen> {
  final _documents = <DocumentLu<IngredientNonResolu>>[];
  CurseurPage? _suite;
  bool _fromCache = false;

  /// Au moins une page lue.
  bool _lue = false;
  bool _chargement = true;
  Object? _erreur;

  /// Numéro de la lecture en cours : une réponse d'une lecture remplacée est
  /// ignorée.
  int _lecture = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_lire(apres: null));
  }

  void _relireNonResolus() {
    setState(() {
      _documents.clear();
      _suite = null;
      _lue = false;
      _chargement = true;
      _erreur = null;
    });
    unawaited(_lire(apres: null));
  }

  void _pageSuivante() {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    unawaited(_lire(apres: _suite));
  }

  Future<void> _lire({required CurseurPage? apres}) async {
    final lecture = ++_lecture;
    final PageNonResolus page;
    try {
      page = await ref
          .read(sourcesRepositoryProvider)
          .pageNonResolus(apres: apres);
    } catch (error) {
      // Déjà rapportée par le dépôt de données : l'écran affiche la panne.
      if (!mounted || lecture != _lecture) return;
      setState(() {
        _erreur = error;
        _chargement = false;
      });
      return;
    }
    if (!mounted || lecture != _lecture) return;
    setState(() {
      _documents.addAll(page.documents);
      _suite = page.suite;
      _fromCache = page.fromCache;
      _lue = true;
      _chargement = false;
    });
  }

  /// « Relire » : dernière exécution et première page des noms non reconnus.
  void _relire() {
    _relireExecution();
    _relireNonResolus();
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final theme = Theme.of(context);
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                AdminSourcesScreen.intro,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _relire,
              icon: const Icon(Icons.refresh),
              label: const Text(AdminSourcesScreen.reload),
            ),
          ],
        ),
      ),
      const _Titre(AdminSourcesScreen.runTitle),
      ..._execution(offline),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(context.push(AppRoutes.dataSources)),
            icon: const Icon(Icons.info_outline),
            label: const Text(AdminSourcesScreen.sourcesLabel),
          ),
        ),
      ),
      const Divider(height: 32),
      const _Titre(AdminSourcesScreen.unresolvedTitle),
      const _Note(AdminSourcesScreen.unresolvedHelp),
      ..._nonResolus(offline),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  // ---------------------------------------------------------- dernière exécution

  void _relireExecution() => ref.invalidate(derniereExecutionProvider);

  List<Widget> _execution(bool offline) {
    final async = ref.watch(derniereExecutionProvider);
    final value = async.value;
    if (value == null) {
      if (!async.hasError) {
        return const [
          EtatChargement(label: 'Chargement de la dernière mise à jour'),
        ];
      }
      if (offline) {
        return [_horsLigne(AdminSourcesScreen.runOffline, _relireExecution)];
      }
      return [
        EtatErreur(
          message: AdminSourcesScreen.runError,
          retrying: async.isLoading,
          retryingLabel: 'Lecture en cours',
          onRetry: _relireExecution,
        ),
      ];
    }
    return switch (value.execution) {
      DocumentTrouve(value: final run) => [
        if (value.fromCache) const _Note(AdminSourcesScreen.runFromCache),
        _Execution(run: run),
      ],
      DocumentAbsent() => const [
        EtatVide(
          icon: Icons.inventory_2_outlined,
          message: AdminSourcesScreen.emptyRun,
        ),
      ],
      DocumentAbsentDuCache() => [
        _horsLigne(AdminSourcesScreen.runOffline, _relireExecution),
      ],
      DocumentIllisibleTrouve() => const [
        EtatVide(
          icon: Icons.error_outline,
          message: AdminSourcesScreen.runUnreadable,
        ),
      ],
    };
  }

  // ---------------------------------------------------------- non résolus

  List<Widget> _nonResolus(bool offline) {
    if (!_lue) {
      if (_erreur == null) {
        return const [
          EtatChargement(label: 'Chargement des noms non reconnus'),
        ];
      }
      if (offline) {
        return [
          _horsLigne(AdminSourcesScreen.unresolvedOffline, _relireNonResolus),
        ];
      }
      return [
        EtatErreur(
          message: AdminSourcesScreen.unresolvedError,
          retrying: _chargement,
          retryingLabel: 'Lecture en cours',
          onRetry: _relireNonResolus,
        ),
      ];
    }
    if (_documents.isEmpty) {
      if (_fromCache) {
        return [
          _horsLigne(AdminSourcesScreen.unresolvedOffline, _relireNonResolus),
        ];
      }
      return const [
        EtatVide(
          icon: Icons.check_circle_outline,
          message: AdminSourcesScreen.emptyUnresolved,
        ),
      ];
    }
    return [
      if (_fromCache) const _Note(AdminSourcesScreen.unresolvedFromCache),
      for (final d in _documents)
        switch (d) {
          DocumentValide(:final value) => _LigneNonResolu(ingredient: value),
          DocumentInvalide() => const _LigneIllisible(),
        },
      if (_erreur != null)
        BandeauListePerimee(
          message: AdminSourcesScreen.nextPageError,
          retrying: _chargement,
          onRetry: _pageSuivante,
        )
      else if (_suite != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _chargement
                ? const OutlinedButton(
                    onPressed: null,
                    child: IndicateurBouton(label: 'Lecture en cours'),
                  )
                : OutlinedButton(
                    onPressed: _pageSuivante,
                    child: const Text(AdminSourcesScreen.showMore),
                  ),
          ),
        ),
    ];
  }

  Widget _horsLigne(String message, VoidCallback onRetry) => EtatVide(
    icon: Icons.cloud_off,
    message: message,
    action: FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
  );
}

/// Compte rendu d'une exécution : date, cible, rapport, comptes par
/// collection, sources et noms non reconnus par nature. Borné à
/// [kDialogMaxWidth] sur grand écran.
class _Execution extends StatelessWidget {
  const _Execution({required this.run});

  final ExecutionIngestion run;

  @override
  Widget build(BuildContext context) {
    final fin = run.finishedAt;
    final refused = run.counts.fold(0, (t, c) => t + c.refused);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LigneFiche(
                label: 'Terminée le',
                value: '${formatDateLongue(fin)} à ${formatHeure(fin)}',
              ),
              LigneFiche(label: 'Cible', value: libelleCible(run.target)),
              LigneFiche(
                label: 'Rapport local',
                value: AdminSourcesScreen.reportPath(run.id),
              ),
              const TitreSection('Documents'),
              if (run.counts.isEmpty)
                const TexteAbsent('Aucune collection.')
              else
                for (final c in comptesOrdonnes(run.counts))
                  LigneFiche(
                    label: libelleCollection(c.collection),
                    value: ligneComptes(c),
                  ),
              if (refused > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    AdminSourcesScreen.refusedNote(refused),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const TitreSection('Sources lues'),
              if (run.sources.isEmpty)
                const TexteAbsent('Aucune source.')
              else
                for (final s in run.sources)
                  LigneFiche(
                    label: libelleSourceExecution(s.source),
                    value: s.version,
                  ),
              const TitreSection('Noms non reconnus (cette exécution)'),
              if (run.unresolved.isEmpty)
                const TexteAbsent('Aucun nom non reconnu.')
              else
                for (final n in nonResolusOrdonnes(run.unresolved))
                  LigneFiche(
                    label: libelleNatures(n.nature),
                    value: libelleNoms(n.count),
                  ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Titre d'un bloc de l'écran, un cran au-dessus des sous-sections
/// ([TitreSection]).
class _Titre extends StatelessWidget {
  const _Titre(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

/// Ligne d'aide (hors ligne, explication de la liste).
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Nom non reconnu : nom, puis nature, origine, nombre de fois et date.
class _LigneNonResolu extends StatelessWidget {
  const _LigneNonResolu({required this.ingredient});

  final IngredientNonResolu ingredient;

  @override
  Widget build(BuildContext context) {
    final date = ingredient.updatedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LigneDeuxNiveaux(
        title: ingredient.name,
        details: [
          libelleNature(ingredient.nature),
          libelleOrigine(ingredient.source),
          libelleFois(ingredient.count),
          if (date != null) 'le ${formatDateCourte(date)}',
        ],
      ),
    );
  }
}

class _LigneIllisible extends StatelessWidget {
  const _LigneIllisible();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16),
    child: LigneDeuxNiveaux(
      title: AdminSourcesScreen.rowUnreadable,
      details: [AdminSourcesScreen.rowUnreadableDetail],
    ),
  );
}
