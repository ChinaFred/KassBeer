import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/providers.dart';
import '../data/error_reports_repository.dart';
import '../domain/error_report.dart';

/// Admin › Rapports d'erreur (ADR-011, J1) : `error_reports/` du plus récent au
/// plus ancien, par pages de [kTaillePageRapports], en lecture seule. Aucune
/// suppression depuis l'écran (choix de l'utilisateur du 2026-11-14), aucun
/// écouteur (P49).
class ErrorReportsScreen extends ConsumerStatefulWidget {
  const ErrorReportsScreen({super.key});

  static const titre = 'Rapports d\'erreur';
  static const sousTitre =
      'Pannes rencontrées dans l\'application par les membres';
  static const chargement = 'Chargement des rapports';
  static const vide =
      'Aucun rapport d\'erreur. Une panne rencontrée par un membre apparaîtra '
      'ici, avec son contexte.';
  static const videHorsLigne =
      'Aucun rapport lu sur cet appareil. Réessayez avec le réseau.';
  static const erreurLecture = 'Impossible de lire les rapports d\'erreur.';
  static const erreurListe =
      'Lecture impossible. Les rapports déjà affichés restent visibles.';
  static const horsLigne =
      'Hors ligne. Rapports lus sur cet appareil : la liste peut être '
      'incomplète.';
  static const fin = 'Fin des rapports.';
  static const chargerSuite = 'Charger la suite';
  static const actualiser = 'Actualiser';
  static const lectureEnCours = 'Lecture en cours';
  static const copier = 'Copier le rapport';
  static const copie = 'Rapport copié.';
  static const copieImpossible = 'Impossible de copier le rapport.';

  /// « 1 rapport affiché », « 12 rapports affichés ».
  static String compte(int n) =>
      n <= 1 ? '$n rapport affiché' : '$n rapports affichés';

  @override
  ConsumerState<ErrorReportsScreen> createState() => _ErrorReportsScreenState();
}

class _ErrorReportsScreenState extends ConsumerState<ErrorReportsScreen> {
  final _rapports = <ErrorReport>[];
  CurseurRapports? _suite;
  bool _fromCache = false;

  /// Une première page a été lue : la liste s'affiche, une panne passe en
  /// bandeau au-dessus d'elle.
  bool _lue = false;
  bool _chargement = true;
  Object? _erreur;

  /// Lecture qui a échoué, rejouée par « Réessayer » du bandeau.
  bool _erreurSurSuite = false;

  /// La lecture en cours est une relecture de la première page (« Actualiser »,
  /// « Réessayer ») : l'en-tête montre l'attente, « Charger la suite » attend
  /// sans libellé.
  bool _actualisation = false;

  /// Numéro de la dernière lecture : une réponse plus ancienne est ignorée.
  int _lecture = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_lire(apres: null));
  }

  /// Relit la première page ; la liste affichée, et une panne affichée, restent
  /// visibles jusqu'à la réponse.
  Future<void> _actualiser() {
    setState(() {
      _chargement = true;
      _actualisation = true;
    });
    return _lire(apres: null);
  }

  void _chargerSuite() {
    setState(() {
      _chargement = true;
      _actualisation = false;
    });
    unawaited(_lire(apres: _suite));
  }

  void _reessayer() {
    if (_erreurSurSuite) {
      _chargerSuite();
    } else {
      unawaited(_actualiser());
    }
  }

  Future<void> _lire({required CurseurRapports? apres}) async {
    final lecture = ++_lecture;
    final PageRapports page;
    try {
      page = await ref.read(errorReportsRepositoryProvider).page(apres: apres);
    } catch (error) {
      // Déjà rapportée par le dépôt de données : l'écran affiche la panne.
      if (!mounted || lecture != _lecture) return;
      setState(() {
        _erreur = error;
        _erreurSurSuite = apres != null;
        _chargement = false;
        _actualisation = false;
      });
      return;
    }
    if (!mounted || lecture != _lecture) return;
    setState(() {
      if (apres == null) {
        _rapports
          ..clear()
          ..addAll(page.rapports);
        _fromCache = page.fromCache;
      } else {
        _rapports.addAll(page.rapports);
        _fromCache = _fromCache || page.fromCache;
      }
      _suite = page.suite;
      _erreur = null;
      _lue = true;
      _chargement = false;
      _actualisation = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Aucune liste à garder : une panne s'affiche seule, avec un seul
    // « Réessayer », au lieu d'un bandeau au-dessus de l'état vide.
    if (!_lue || (_rapports.isEmpty && _erreur != null)) {
      return _erreur == null
          ? const EtatChargement(label: ErrorReportsScreen.chargement)
          : EtatErreur(
              message: ErrorReportsScreen.erreurLecture,
              retrying: _chargement,
              retryingLabel: ErrorReportsScreen.lectureEnCours,
              onRetry: () => unawaited(_actualiser()),
            );
    }

    final theme = Theme.of(context);
    final head = <Widget>[
      if (_erreur != null)
        BandeauListePerimee(
          message: ErrorReportsScreen.erreurListe,
          retrying: _chargement,
          onRetry: _reessayer,
        )
      else if (_fromCache && _rapports.isNotEmpty)
        BandeauListePerimee(
          message: ErrorReportsScreen.horsLigne,
          retrying: _chargement,
          onRetry: () => unawaited(_actualiser()),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  ErrorReportsScreen.compte(_rapports.length),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            if (_actualisation)
              Semantics(
                label: ErrorReportsScreen.lectureEnCours,
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
                tooltip: ErrorReportsScreen.actualiser,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _chargement ? null : () => unawaited(_actualiser()),
              ),
          ],
        ),
      ),
      if (_rapports.isEmpty)
        _fromCache
            ? EtatVide(
                icon: Icons.cloud_off,
                message: ErrorReportsScreen.videHorsLigne,
                action: TextButton(
                  onPressed: _chargement
                      ? null
                      : () => unawaited(_actualiser()),
                  child: const Text('Réessayer'),
                ),
              )
            : const EtatVide(
                icon: Icons.task_alt,
                message: ErrorReportsScreen.vide,
              ),
    ];

    final foot = <Widget>[
      if (_rapports.isNotEmpty && _erreur == null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _suite == null
                ? Text(
                    ErrorReportsScreen.fin,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : OutlinedButton(
                    onPressed: _chargement ? null : _chargerSuite,
                    child: _chargement && !_actualisation
                        ? const IndicateurBouton(
                            label: ErrorReportsScreen.lectureEnCours,
                          )
                        : const Text(ErrorReportsScreen.chargerSuite),
                  ),
          ),
        ),
    ];

    return RefreshIndicator(
      onRefresh: _actualiser,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: head.length + _rapports.length + foot.length,
        itemBuilder: (context, i) {
          if (i < head.length) return head[i];
          final j = i - head.length;
          if (j >= _rapports.length) return foot[j - _rapports.length];
          final rapport = _rapports[j];
          return _LigneRapport(key: ValueKey(rapport.id), rapport: rapport);
        },
      ),
    );
  }
}

/// Un rapport : replié sur sa première ligne, déplié sur ses sections.
class _LigneRapport extends ConsumerStatefulWidget {
  const _LigneRapport({super.key, required this.rapport});

  final ErrorReport rapport;

  @override
  ConsumerState<_LigneRapport> createState() => _LigneRapportState();
}

class _LigneRapportState extends ConsumerState<_LigneRapport> {
  bool _ouvert = false;

  Future<void> _copier() async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ref.read(errorReportServiceProvider);
    var texte = ErrorReportsScreen.copie;
    try {
      await Clipboard.setData(ClipboardData(text: widget.rapport.texteCopie));
    } catch (error, stackTrace) {
      // Aucun texte du rapport dans le contexte (P13).
      errors.reportError(
        feature: 'admin.error_reports.copy',
        error: error,
        stackTrace: stackTrace,
      );
      texte = ErrorReportsScreen.copieImpossible;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(texte)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = widget.rapport;
    final etiquette = Etiquette(
      label: r.libellePlateforme,
      ton: r.platform == null ? TonEtiquette.neutre : TonEtiquette.normal,
    );
    // L'étiquette passe à droite sur une ligne large, sous le résumé sinon
    // (téléphone, texte agrandi) : le titre garde sa largeur.
    final grandTexte =
        MediaQuery.textScalerOf(context).scale(1) > kGrandTexteMinScale;
    final fleche = ExcludeSemantics(
      child: Icon(_ouvert ? Icons.expand_less : Icons.expand_more),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final aDroite = !grandTexte && constraints.maxWidth >= kCompactMaxWidth;
        return _tuile(r, scheme, etiquette, fleche, aDroite: aDroite);
      },
    );
  }

  Widget _tuile(
    ErrorReport r,
    ColorScheme scheme,
    Widget etiquette,
    Widget fleche, {
    required bool aDroite,
  }) {
    final resume = r.resume;
    return ExpansionTile(
      leading: ExcludeSemantics(
        child: Icon(Icons.bug_report_outlined, color: scheme.error),
      ),
      title: Text(
        r.premiereLigne,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: !aDroite
          ? Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [if (resume.isNotEmpty) Text(resume), etiquette],
            )
          : (resume.isEmpty ? null : Text(resume)),
      trailing: !aDroite
          ? fleche
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [etiquette, const SizedBox(width: 8), fleche],
            ),
      onExpansionChanged: (ouvert) => setState(() => _ouvert = ouvert),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _Section(
          titre: 'Erreur',
          contenu: r.error.isEmpty ? ErrorReport.erreurSansMessage : r.error,
        ),
        if (r.context case final contexte?)
          _Section(titre: 'Contexte', contenu: contexte),
        if (r.stackTrace case final pile?)
          _Section(titre: 'Pile d\'appels', contenu: pile, monospace: true),
        if (r.uid case final uid?) _Section(titre: 'Compte', contenu: uid),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => unawaited(_copier()),
          icon: const Icon(Icons.copy),
          label: const Text(ErrorReportsScreen.copier),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.titre,
    required this.contenu,
    this.monospace = false,
  });

  final String titre;
  final String contenu;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          SelectableText(
            contenu,
            style: monospace
                ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
