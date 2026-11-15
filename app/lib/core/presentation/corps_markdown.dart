import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import '../../features/tickets/domain/ticket_analysis.dart'
    show imageNonAffichee, lienAnalyseOuvrable;
import '../../features/tickets/presentation/tickets_providers.dart'
    show ouvrirLienProvider;
import '../providers.dart';

/// Corps Markdown (P33) d'une analyse de ticket, d'un compte rendu de
/// livraison ou d'une réponse de l'assistant de recette : GitHub Flavored
/// Markdown, aucune image chargée (texte alternatif à la place), liens `http`
/// et `https` seuls ouverts hors de l'application, aucun HTML rendu
/// (`encodeHtml: false` du paquet : une balise reste du texte). Styles du
/// thème seuls. Seul fichier qui importe `flutter_markdown_plus` et
/// `markdown`.
class CorpsMarkdown extends ConsumerWidget {
  const CorpsMarkdown({
    super.key,
    required this.texte,
    this.accentue = false,
    this.encre,
    this.avantOuverture,
    this.featureLien = 'tickets.open_analysis_link',
    this.contexteLien = 'lien d\'une analyse',
  });

  final String texte;

  /// Texte sur `secondaryContainer` (réponse de l'administrateur).
  final bool accentue;

  /// Couleur du texte et des liens imposée par le fond de la carte (blocage
  /// de livraison sur `errorContainer`) ; sinon celle du thème.
  final Color? encre;

  /// Appelé avant d'ouvrir un lien `http` ou `https` ; `false` : le lien
  /// n'est pas ouvert (l'assistant montre d'abord l'adresse complète, P59).
  final Future<bool> Function(BuildContext context, Uri uri)? avantOuverture;

  /// Rapport d'un lien que le système n'ouvre pas : ni l'adresse ni le texte
  /// (P33).
  final String featureLien;
  final String contexteLien;

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
      feature: featureLien,
      error: error ?? StateError('ouverture refusée par le système'),
      stackTrace: stackTrace ?? StackTrace.current,
      // Ni l'adresse ni le texte de l'analyse (P33).
      context: contexteLien,
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
      onTapLink: (_, href, _) async {
        final uri = lienAnalyseOuvrable(href);
        if (uri == null) return;
        final avant = avantOuverture;
        if (avant != null && !await avant(context, uri)) return;
        if (!context.mounted) return;
        await _ouvrir(context, ref, uri);
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
