import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/corps_markdown.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
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
/// les analyses seules : un arrêt du développement (ADR-018) a sa carte, sans
/// compter comme une analyse. Corps en Markdown par [CorpsMarkdown].
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
      TicketAnalysisKind.developmentStop => (
        dateAnalyse('Arrêt du développement', at),
        Icons.block,
        false,
        'Arrêt tronqué, voir GitHub.',
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
          CorpsMarkdown(texte: corpsAffiche(analyse.body), accentue: accentue),
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
