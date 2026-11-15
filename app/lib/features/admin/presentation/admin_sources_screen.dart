import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/ligne_liste.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../library/data/library_repository.dart' show CurseurPage;
import '../data/sources_repository.dart';
import '../domain/ingestion.dart';
import 'libelles_sources.dart';

Duration? _sansNouvelEssai(int retryCount, Object error) => null;

/// Dernière exécution de l'ingestion, lue par `get()` à l'ouverture de
/// l'écran ; « Actualiser » et « Réessayer » relancent la lecture.
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
  static const sousTitre =
      'Dernière mise à jour de la Bibliothèque et noms non reconnus';
  static const intro =
      'Mise à jour de la Bibliothèque depuis les sources externes '
      '(Brewtarget, BJCP, DIY Dog).';
  static const actualiser = 'Actualiser';
  static const lectureEnCours = 'Lecture en cours';
  static const runTitle = 'Dernière mise à jour';
  static const runLoading = 'Chargement de la dernière mise à jour';
  static const runUnresolvedTitle =
      'Noms non reconnus lors de cette mise à jour';
  static const unresolvedTitle = 'Tous les noms non reconnus';
  static const unresolvedHelp =
      "Noms qu'aucune source n'a rattachés à un ingrédient de la "
      'Bibliothèque, du plus fréquent au moins fréquent.';
  static const unresolvedLoading = 'Chargement des noms non reconnus';
  static const sourcesLabel = 'Sources des données';
  static const emptyRun =
      'Aucune mise à jour enregistrée. Lancez-la depuis votre poste : son '
      "compte rendu s'affichera ici.";
  static const emptyUnresolved = 'Aucun nom non reconnu.';
  static const runError = 'Impossible de lire la dernière mise à jour.';
  static const runRefreshError =
      'Impossible de relire la dernière mise à jour. Le compte rendu affiché '
      'peut ne plus être à jour.';
  static const unresolvedError = 'Impossible de lire les noms non reconnus.';
  static const unresolvedListError =
      'Lecture impossible. Les noms déjà affichés restent visibles.';
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
  static const chargerSuite = 'Charger la suite';
  static const fin = 'Fin des noms non reconnus.';

  /// « 1 nom affiché », « 12 noms affichés ».
  static String compte(int n) => n <= 1 ? '$n nom affiché' : '$n noms affichés';

  static String refusedNote(int refused) =>
      '${refused == 1 ? '1 document refusé' : '$refused documents refusés'}. '
      'Le détail est dans le rapport local.';

  /// Chemin du rapport local d'une exécution, depuis la racine du dépôt.
  static String reportPath(String runId) =>
      'import/ingest/rapports/$runId.json';

  @override
  ConsumerState<AdminSourcesScreen> createState() => _AdminSourcesScreenState();
}

/// Ce qui a lancé une lecture : bouton de l'en-tête, geste « tirer pour
/// actualiser », « Réessayer » du compte rendu, « Réessayer » d'une panne ou de
/// l'état hors ligne de la liste sans ligne, « Réessayer » d'un encadré posé
/// avec les lignes (en tête ou dans le pied), « Charger la suite ». Seul ce
/// bouton montre l'attente ; les autres sont désactivés.
enum _Origine { entete, tirage, execution, liste, avecLignes, suite }

class _AdminSourcesScreenState extends ConsumerState<AdminSourcesScreen> {
  final _documents = <DocumentLu<IngredientNonResolu>>[];
  CurseurPage? _suite;
  bool _fromCache = false;

  /// Au moins une page lue : la liste s'affiche, une panne passe dans un
  /// encadré au-dessus d'elle, ou dans le pied pour la page suivante.
  bool _lue = false;
  bool _chargement = true;
  Object? _erreur;

  /// Lecture qui a échoué : page suivante (encadré dans le pied, à la place de
  /// « Charger la suite ») ou première page (encadré en tête de la liste).
  bool _erreurSurSuite = false;

  _Origine? _origine;

  /// Numéro de la lecture en cours : une réponse d'une lecture remplacée est
  /// ignorée.
  int _lecture = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_lire(apres: null));
  }

  /// « Actualiser » ou geste : dernière mise à jour et première page des noms
  /// non reconnus. Ce qui est affiché reste visible jusqu'à la réponse.
  Future<void> _actualiser(_Origine origine) async {
    setState(() {
      _chargement = true;
      _origine = origine;
    });
    final execution = ref.refresh(derniereExecutionProvider.future);
    await Future.wait([_attendre(execution), _lire(apres: null)]);
  }

  /// Fin de la relecture du compte rendu, pour l'indicateur du geste.
  static Future<void> _attendre(Future<LectureExecution> lecture) async {
    try {
      await lecture;
    } on Object {
      // Déjà rapportée par le dépôt de données : le bloc affiche la panne.
    }
  }

  void _relireExecution() {
    setState(() => _origine = _Origine.execution);
    ref.invalidate(derniereExecutionProvider);
  }

  void _relireListe(_Origine origine) {
    setState(() {
      _chargement = true;
      _origine = origine;
    });
    unawaited(_lire(apres: null));
  }

  void _chargerSuite(_Origine origine) {
    setState(() {
      _chargement = true;
      _origine = origine;
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
        _erreurSurSuite = apres != null;
        _chargement = false;
      });
      return;
    }
    if (!mounted || lecture != _lecture) return;
    setState(() {
      if (apres == null) {
        _documents
          ..clear()
          ..addAll(page.documents);
        _fromCache = page.fromCache;
      } else {
        _documents.addAll(page.documents);
        _fromCache = _fromCache || page.fromCache;
      }
      _suite = page.suite;
      _erreur = null;
      _lue = true;
      _chargement = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final execution = ref.watch(derniereExecutionProvider);
    final occupe = execution.isLoading || _chargement;
    final theme = Theme.of(context);
    // Aucune ligne à garder : une panne s'affiche seule dans le bloc, au lieu
    // d'un encadré au-dessus de l'état vide.
    final listeAffichee = _lue && !(_documents.isEmpty && _erreur != null);
    final lignes = listeAffichee
        ? _documents
        : const <DocumentLu<IngredientNonResolu>>[];

    final head = <Widget>[
      _entete(theme, occupe),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: CarteSection(
          titre: AdminSourcesScreen.runTitle,
          children: [
            ..._execution(execution, offline: offline, occupe: occupe),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      unawaited(context.push(AppRoutes.dataSources)),
                  icon: const Icon(Icons.info_outline),
                  label: const Text(AdminSourcesScreen.sourcesLabel),
                ),
              ),
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: TitreSection(AdminSourcesScreen.unresolvedTitle),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          AdminSourcesScreen.unresolvedHelp,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      ..._nonResolus(
        theme,
        offline: offline,
        occupe: occupe,
        listeAffichee: listeAffichee,
      ),
    ];

    final foot = <Widget>[
      if (lignes.isNotEmpty && _erreur != null && _erreurSurSuite)
        _Marge(
          _EncadreAction(
            ton: TonEncadre.erreur,
            icone: Icons.error_outline,
            liveRegion: true,
            message: AdminSourcesScreen.unresolvedListError,
            action: _BoutonReessayer(
              attente: occupe && _origine == _Origine.avecLignes,
              actif: !occupe,
              onPressed: () => _chargerSuite(_Origine.avecLignes),
            ),
          ),
        )
      else if (lignes.isNotEmpty && _erreur == null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _suite == null
                ? Text(
                    AdminSourcesScreen.fin,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : OutlinedButton(
                    onPressed: occupe
                        ? null
                        : () => _chargerSuite(_Origine.suite),
                    child: occupe && _origine == _Origine.suite
                        ? const IndicateurBouton(
                            label: AdminSourcesScreen.lectureEnCours,
                          )
                        : const Text(AdminSourcesScreen.chargerSuite),
                  ),
          ),
        ),
    ];

    return RefreshIndicator(
      // Le geste a son propre indicateur : l'en-tête n'en ajoute pas.
      onRefresh: () => _actualiser(_Origine.tirage),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: head.length + lignes.length + foot.length,
        itemBuilder: (context, i) {
          if (i < head.length) return head[i];
          final j = i - head.length;
          if (j >= lignes.length) return foot[j - lignes.length];
          final d = lignes[j];
          return switch (d) {
            DocumentValide(:final value) => _LigneNonResolu(
              key: ValueKey(d.id),
              ingredient: value,
            ),
            DocumentInvalide() => LigneListe(
              key: ValueKey(d.id),
              icone: Icons.error_outline,
              erreur: true,
              titre: AdminSourcesScreen.rowUnreadable,
              details: const [Text(AdminSourcesScreen.rowUnreadableDetail)],
            ),
          };
        },
      ),
    );
  }

  /// Texte d'introduction et « Actualiser » : un bouton de 48 px, remplacé par
  /// un indicateur de même taille pendant la lecture qu'il a lancée.
  Widget _entete(ThemeData theme, bool occupe) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
    child: Row(
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
        if (occupe && _origine == _Origine.entete)
          Semantics(
            // Nœud propre : l'indicateur n'est pas lu avec le texte d'intro.
            container: true,
            label: AdminSourcesScreen.lectureEnCours,
            liveRegion: true,
            child: const SizedBox.square(
              dimension: 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AdminSourcesScreen.actualiser,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: occupe
                ? null
                : () => unawaited(_actualiser(_Origine.entete)),
          ),
      ],
    ),
  );

  // ---------------------------------------------------------- dernière exécution

  /// Contenu de la carte « Dernière mise à jour ». Riverpod garde la valeur
  /// pendant une relecture et après son échec : le compte rendu reste affiché,
  /// sous un encadré quand la relecture a échoué.
  List<Widget> _execution(
    AsyncValue<LectureExecution> async, {
    required bool offline,
    required bool occupe,
  }) {
    final reessayer = _BoutonReessayer(
      attente: occupe && _origine == _Origine.execution,
      actif: !occupe,
      onPressed: _relireExecution,
    );
    final value = async.value;
    if (value == null) {
      if (!async.hasError) {
        return const [
          Padding(
            padding: EdgeInsets.all(24),
            child: EtatChargement(label: AdminSourcesScreen.runLoading),
          ),
        ];
      }
      return [
        offline
            ? _EncadreAction(
                ton: TonEncadre.avertissement,
                icone: Icons.cloud_off,
                message: AdminSourcesScreen.runOffline,
                action: reessayer,
              )
            : _EncadreAction(
                ton: TonEncadre.erreur,
                icone: Icons.error_outline,
                liveRegion: true,
                message: AdminSourcesScreen.runError,
                action: reessayer,
              ),
      ];
    }
    final theme = Theme.of(context);
    return [
      if (async.hasError) ...[
        _EncadreAction(
          ton: TonEncadre.erreur,
          icone: Icons.error_outline,
          liveRegion: true,
          message: AdminSourcesScreen.runRefreshError,
          action: reessayer,
        ),
        const SizedBox(height: 16),
      ],
      ...switch (value.execution) {
        DocumentTrouve(value: final run) => [
          if (value.fromCache) ...[
            const Encadre(
              ton: TonEncadre.avertissement,
              icone: Icons.cloud_off,
              child: Text(AdminSourcesScreen.runFromCache),
            ),
            const SizedBox(height: 8),
          ],
          _Execution(run: run),
        ],
        DocumentAbsent() => [
          Text(AdminSourcesScreen.emptyRun, style: theme.textTheme.bodyMedium),
        ],
        DocumentAbsentDuCache() => [
          _EncadreAction(
            ton: TonEncadre.avertissement,
            icone: Icons.cloud_off,
            message: AdminSourcesScreen.runOffline,
            // Un seul « Réessayer » : celui de l'encadré d'échec, s'il est là.
            action: async.hasError ? null : reessayer,
          ),
        ],
        DocumentIllisibleTrouve() => const [
          Encadre(
            ton: TonEncadre.erreur,
            icone: Icons.error_outline,
            child: Text(AdminSourcesScreen.runUnreadable),
          ),
        ],
      },
    ];
  }

  // ---------------------------------------------------------- non résolus

  /// États de la liste, au-dessus des lignes : chargement, panne, encadrés,
  /// compte, liste vide.
  List<Widget> _nonResolus(
    ThemeData theme, {
    required bool offline,
    required bool occupe,
    required bool listeAffichee,
  }) {
    Widget reessayer(_Origine origine) => _BoutonReessayer(
      attente: occupe && _origine == origine,
      actif: !occupe,
      onPressed: () => _relireListe(origine),
    );
    if (!listeAffichee) {
      if (_erreur == null) {
        return const [
          Padding(
            padding: EdgeInsets.all(24),
            child: EtatChargement(label: AdminSourcesScreen.unresolvedLoading),
          ),
        ];
      }
      return [
        _Marge(
          offline
              ? _EncadreAction(
                  ton: TonEncadre.avertissement,
                  icone: Icons.cloud_off,
                  message: AdminSourcesScreen.unresolvedOffline,
                  action: reessayer(_Origine.liste),
                )
              : _EncadreAction(
                  ton: TonEncadre.erreur,
                  icone: Icons.error_outline,
                  liveRegion: true,
                  message: AdminSourcesScreen.unresolvedError,
                  action: reessayer(_Origine.liste),
                ),
        ),
      ];
    }
    return [
      // Panne d'« Actualiser » en tête ; celle de la page suivante va dans le
      // pied, à la place de « Charger la suite ».
      if (_erreur != null && !_erreurSurSuite)
        _Marge(
          _EncadreAction(
            ton: TonEncadre.erreur,
            icone: Icons.error_outline,
            liveRegion: true,
            message: AdminSourcesScreen.unresolvedListError,
            action: reessayer(_Origine.avecLignes),
          ),
        )
      else if (_fromCache && _documents.isNotEmpty)
        _Marge(
          _EncadreAction(
            ton: TonEncadre.avertissement,
            icone: Icons.cloud_off,
            message: AdminSourcesScreen.unresolvedFromCache,
            action: reessayer(_Origine.avecLignes),
          ),
        ),
      if (_documents.isEmpty)
        _Marge(
          _fromCache
              ? _EncadreAction(
                  ton: TonEncadre.avertissement,
                  icone: Icons.cloud_off,
                  message: AdminSourcesScreen.unresolvedOffline,
                  action: reessayer(_Origine.liste),
                )
              : const TexteAbsent(AdminSourcesScreen.emptyUnresolved),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Semantics(
            liveRegion: true,
            child: Text(
              AdminSourcesScreen.compte(_documents.length),
              style: theme.textTheme.titleSmall,
            ),
          ),
        ),
    ];
  }
}

/// Marge d'un état de la liste, posé dans une liste sans marge latérale.
class _Marge extends StatelessWidget {
  const _Marge(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: child);
}

/// Encadré d'un état (panne, hors ligne) : message, puis l'action au besoin.
class _EncadreAction extends StatelessWidget {
  const _EncadreAction({
    required this.ton,
    required this.icone,
    required this.message,
    this.action,
    this.liveRegion = false,
  });

  final TonEncadre ton;
  final IconData icone;
  final String message;
  final Widget? action;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Encadre(
      ton: ton,
      icone: icone,
      liveRegion: liveRegion,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          if (action != null) ...[const SizedBox(height: 8), action],
        ],
      ),
    );
  }
}

/// « Réessayer » d'un bloc : indicateur pendant la lecture qu'il a lancée,
/// désactivé pendant une autre.
class _BoutonReessayer extends StatelessWidget {
  const _BoutonReessayer({
    required this.attente,
    required this.actif,
    required this.onPressed,
  });

  final bool attente;
  final bool actif;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: actif ? onPressed : null,
    child: attente
        ? const IndicateurBouton(label: AdminSourcesScreen.lectureEnCours)
        : const Text('Réessayer'),
  );
}

/// Compte rendu d'une exécution : date, cible, rapport, comptes par
/// collection, sources et noms non reconnus par nature, sur la largeur de la
/// carte.
class _Execution extends StatelessWidget {
  const _Execution({required this.run});

  final ExecutionIngestion run;

  @override
  Widget build(BuildContext context) {
    final fin = run.finishedAt;
    final refused = run.counts.fold(0, (t, c) => t + c.refused);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LigneFiche(
          label: 'Terminée le',
          value: '${formatDateLongue(fin)} à ${formatHeure(fin)}',
        ),
        LigneFiche(label: 'Cible', value: libelleCible(run.target)),
        LigneFiche(
          label: 'Rapport local',
          value: AdminSourcesScreen.reportPath(run.id),
          selectionnable: true,
        ),
        const TitreSection('Documents', niveau: NiveauTitre.sousSection),
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
            child: Encadre(
              ton: TonEncadre.erreur,
              icone: Icons.error_outline,
              child: Text(AdminSourcesScreen.refusedNote(refused)),
            ),
          ),
        const TitreSection('Sources lues', niveau: NiveauTitre.sousSection),
        if (run.sources.isEmpty)
          const TexteAbsent('Aucune source.')
        else
          for (final s in run.sources)
            LigneFiche(
              label: libelleSourceExecution(s.source),
              value: s.version,
            ),
        const TitreSection(
          AdminSourcesScreen.runUnresolvedTitle,
          niveau: NiveauTitre.sousSection,
        ),
        if (run.unresolved.isEmpty)
          const TexteAbsent('Aucun nom non reconnu.')
        else
          for (final n in nonResolusOrdonnes(run.unresolved))
            LigneFiche(
              label: libelleNatures(n.nature),
              value: libelleNoms(n.count),
            ),
      ],
    );
  }
}

/// Nom non reconnu : nom, puis nature, origine, nombre de fois et date.
class _LigneNonResolu extends StatelessWidget {
  const _LigneNonResolu({super.key, required this.ingredient});

  final IngredientNonResolu ingredient;

  @override
  Widget build(BuildContext context) {
    final date = ingredient.updatedAt;
    return LigneListe(
      icone: Icons.link_off,
      titre: ingredient.name,
      titreMaxLignes: 2,
      details: [
        Text(
          [
            libelleNature(ingredient.nature),
            libelleOrigine(ingredient.source),
            libelleFois(ingredient.count),
            if (date != null) 'le ${formatDateCourte(date)}',
          ].join(' · '),
        ),
      ],
    );
  }
}
