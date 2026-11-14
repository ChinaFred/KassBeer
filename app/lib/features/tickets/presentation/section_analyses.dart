import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/ticket.dart';
import '../domain/ticket_analysis.dart';
import 'encadre_reponse.dart';
import 'ticket_lien_github.dart';
import 'tickets_providers.dart';

/// « Analyse du 08/11/26 à 10:02 », ou le seul nom sans date.
String dateAnalyse(String nom, DateTime? at) =>
    at == null ? nom : '$nom du ${formatDateChiffres(at)} à ${formatHeure(at)}';

/// Section « Analyses (N) » de la fiche d'Admin (ADR-008, P33) : entrées
/// relevées sur l'Issue, dans l'ordre chronologique, en Markdown. N compte
/// les analyses seules. Seul fichier qui importe `flutter_markdown_plus` et
/// `markdown`.
class SectionAnalyses extends ConsumerWidget {
  const SectionAnalyses({super.key, required this.ticket});

  final Ticket ticket;

  static const loadError = 'Impossible de lire les analyses.';
  static const horsLigne = 'Analyses non disponibles hors ligne.';
  static const illisible = 'Analyses illisibles. Mettez l\'application à jour.';
  static const pasEncoreAnalyse =
      'Pas encore analysé. Les analyses publiées sur l\'Issue s\'afficheront '
      'ici.';
  static const pasEncoreRelevee = 'Analyse pas encore relevée.';
  static const plusDeDix =
      'Seules les 10 dernières entrées sont affichées. Les autres sont sur '
      'GitHub.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final async = ref.watch(ticketAnalysisProvider(ticket.id));
    final lecture = async.value;
    final doc = switch (lecture) {
      DocumentTrouve(:final value) => value,
      _ => null,
    };
    final number = ticket.issueNumber;
    final issueLink = lienGithub(ticket.issueUrl);
    Widget? ouvrirIssue() => issueLink == null
        ? null
        : BoutonVoirSurGithub(
            uri: issueLink,
            label: number == null
                ? 'Ouvrir l\'Issue'
                : 'Ouvrir l\'Issue #$number',
            contexte: 'Issue d\'un ticket',
          );
    Widget phrase(String text, {bool erreur = false}) => Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: erreur ? scheme.error : null,
        ),
      ),
    );
    const progression = LinearProgressIndicator(
      semanticsLabel: 'Lecture des analyses',
    );

    final List<Widget> corps;
    // Après une panne, Riverpod garde la valeur précédente : seul un document
    // trouvé avec des entrées reste affiché, tout autre état cède la place à
    // la panne.
    if (async.hasError &&
        (lecture is! DocumentTrouve<TicketAnalysisDoc> ||
            lecture.value.analyses.isEmpty)) {
      corps = [
        phrase(loadError, erreur: true),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonal(
            onPressed: async.isLoading
                ? null
                : () => ref.invalidate(ticketAnalysisProvider(ticket.id)),
            child: async.isLoading
                ? const IndicateurBouton(label: 'Lecture en cours')
                : const Text('Réessayer'),
          ),
        ),
      ];
    } else {
      corps = switch (lecture) {
        null => const [progression],
        // En ligne, le cache répond d'abord : le serveur va répondre.
        DocumentAbsentDuCache() =>
          offline ? [phrase(horsLigne)] : const [progression],
        DocumentIllisibleTrouve() => [phrase(illisible, erreur: true)],
        DocumentAbsent() => _vide(phrase, ouvrirIssue, documentExiste: false),
        DocumentTrouve(:final value) when value.analyses.isEmpty => _vide(
          phrase,
          ouvrirIssue,
          documentExiste: true,
        ),
        DocumentTrouve(:final value) => [
          for (var i = 0; i < value.analyses.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _CarteAnalyse(
              analyse: value.analyses[i],
              ouvrirIssue: ouvrirIssue(),
            ),
          ],
          if (value.skippedCount > 0) ...[
            const SizedBox(height: 12),
            Text(
              plusDeDix,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (ouvrirIssue() case final bouton?) ...[
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerStart, child: bouton),
            ],
          ],
        ],
      };
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TitreSection(
          doc == null ? 'Analyses' : 'Analyses (${doc.analysisCount})',
        ),
        ...corps,
      ],
    );
  }

  List<Widget> _vide(
    Widget Function(String text, {bool erreur}) phrase,
    Widget? Function() ouvrirIssue, {
    required bool documentExiste,
  }) {
    switch (vueAnalysesVide(
      status: ticket.status,
      documentExiste: documentExiste,
    )) {
      case VueAnalysesVide.pasEncoreAnalyse:
        return [phrase(pasEncoreAnalyse)];
      case VueAnalysesVide.pasEncoreRelevee:
        final bouton = ouvrirIssue();
        return [
          phrase(pasEncoreRelevee),
          if (bouton != null) ...[
            const SizedBox(height: 8),
            Align(alignment: AlignmentDirectional.centerStart, child: bouton),
          ],
        ];
    }
  }
}

/// Carte d'une entrée : titre daté, corps Markdown, ligne « tronquée ».
class _CarteAnalyse extends StatelessWidget {
  const _CarteAnalyse({required this.analyse, required this.ouvrirIssue});

  final TicketAnalysis analyse;
  final Widget? ouvrirIssue;

  static const nonPubliee = 'Non publiée depuis l\'application.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = analyse.createdAt;
    final (titre, icone, accentue, tronquee) = switch (analyse.kind) {
      TicketAnalysisKind.analysis => (
        dateAnalyse('Analyse', at),
        Icons.manage_search,
        false,
        'Analyse tronquée, voir GitHub.',
      ),
      TicketAnalysisKind.reply => (
        dateAnalyse('Votre réponse', at),
        Icons.reply,
        true,
        'Réponse tronquée, voir GitHub.',
      ),
      TicketAnalysisKind.unverifiedReply => (
        dateAnalyse('Précisions', at),
        Icons.chat_bubble_outline,
        false,
        'Précisions tronquées, voir GitHub.',
      ),
    };
    final bouton = ouvrirIssue;
    return EncadreReponse.contenu(
      titre: titre,
      icone: icone,
      accentue: accentue,
      sousTitre: analyse.kind == TicketAnalysisKind.unverifiedReply
          ? nonPubliee
          : null,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CorpsAnalyse(texte: corpsAffiche(analyse.body), accentue: accentue),
          if (analyse.truncated) ...[
            const SizedBox(height: 8),
            Text(tronquee, style: theme.textTheme.bodyMedium),
            if (bouton != null) ...[
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerStart, child: bouton),
            ],
          ],
        ],
      ),
    );
  }
}

/// Corps Markdown d'une entrée (P33) : GitHub Flavored Markdown, aucune
/// image chargée (texte alternatif à la place), liens `http` et `https` seuls
/// ouverts hors de l'application, aucun HTML rendu (`encodeHtml: false` du
/// paquet : une balise reste du texte). Styles du thème seuls.
class CorpsAnalyse extends ConsumerWidget {
  const CorpsAnalyse({
    super.key,
    required this.texte,
    this.accentue = false,
    this.encre,
  });

  final String texte;

  /// Texte sur `secondaryContainer` (réponse de l'administrateur).
  final bool accentue;

  /// Couleur du texte et des liens imposée par le fond de la carte (blocage
  /// de livraison sur `errorContainer`) ; sinon celle du thème.
  final Color? encre;

  static const lienImpossible = 'Impossible d\'ouvrir le lien.';

  Future<void> _ouvrir(BuildContext context, WidgetRef ref, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ref.read(errorReportServiceProvider);
    Object? error;
    StackTrace? stackTrace;
    var opened = false;
    try {
      opened = await ref.read(ouvrirLienProvider)(uri);
    } catch (e, st) {
      error = e;
      stackTrace = st;
    }
    if (opened) return;
    errors.reportError(
      feature: 'tickets.open_analysis_link',
      error: error ?? StateError('ouverture refusée par le système'),
      stackTrace: stackTrace ?? StackTrace.current,
      // Ni l'adresse ni le texte de l'analyse (P33).
      context: 'lien d\'une analyse',
    );
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text(lienImpossible)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final forcee = this.encre;
    final encre =
        forcee ?? (accentue ? scheme.onSecondaryContainer : scheme.onSurface);
    final liens = forcee != null || accentue ? encre : scheme.primary;
    final text = theme.textTheme;
    TextStyle? teinte(TextStyle? style) => style?.copyWith(color: encre);
    final code = text.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      color: encre,
      backgroundColor: scheme.surfaceContainerHighest,
    );
    return MarkdownBody(
      data: texte,
      // La fiche est déjà dans une SelectionArea : deux sélections
      // imbriquées se contrarient.
      selectable: false,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: teinte(text.bodyLarge),
        a: text.bodyLarge?.copyWith(
          color: liens,
          decoration: TextDecoration.underline,
          decorationColor: liens,
        ),
        h1: teinte(text.titleLarge),
        h2: teinte(text.titleMedium),
        h3: teinte(text.titleSmall),
        h4: teinte(text.titleSmall),
        h5: teinte(text.titleSmall),
        h6: teinte(text.titleSmall),
        em: const TextStyle(fontStyle: FontStyle.italic),
        strong: const TextStyle(fontWeight: FontWeight.bold),
        listBullet: teinte(text.bodyLarge),
        blockquote: teinte(text.bodyLarge),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: scheme.outlineVariant, width: 4),
          ),
        ),
        code: code,
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        tableHead: teinte(
          text.bodyMedium,
        )?.copyWith(fontWeight: FontWeight.w600),
        tableBody: teinte(text.bodyMedium),
        tableBorder: TableBorder.all(color: scheme.outlineVariant),
        // Colonnes à leur largeur propre : le paquet place alors le tableau
        // dans un défilement horizontal au lieu de l'écraser.
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableScrollbarThumbVisibility: true,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        checkbox: teinte(text.bodyLarge),
      ),
      onTapLink: (_, href, _) {
        final uri = lienAnalyseOuvrable(href);
        if (uri == null) return;
        _ouvrir(context, ref, uri);
      },
      // Aucune image n'est chargée : le texte alternatif la remplace.
      imageBuilder: (_, _, alt) => Text(
        imageNonAffichee(alt),
        style: text.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
          color: forcee != null || accentue ? encre : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
