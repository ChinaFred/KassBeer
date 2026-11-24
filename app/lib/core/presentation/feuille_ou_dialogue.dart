import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// Ouvre un formulaire court : feuille du bas sous [kCompactMaxWidth], dialogue de
/// [kDialogMaxWidth] au-delà. Rend la valeur passée à `Navigator.pop`.
///
/// [fermetureProtegee] : ni un appui hors du formulaire ni un glissement ne le
/// ferment, pour une saisie qu'un geste égaré ferait perdre.
Future<T?> showFeuilleOuDialogue<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool fermetureProtegee = false,
}) {
  final compact = MediaQuery.sizeOf(context).width < kCompactMaxWidth;
  if (compact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: !fermetureProtegee,
      isDismissible: !fermetureProtegee,
      enableDrag: !fermetureProtegee,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          // Sans poignée, le formulaire a besoin de sa propre marge haute.
          fermetureProtegee ? 24 : 0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(child: builder(context)),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: !fermetureProtegee,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: builder(context),
        ),
      ),
    ),
  );
}

/// Variante de [showFeuilleOuDialogue] pour un formulaire long dont les boutons
/// restent visibles : [builder] rend un [CorpsAPied], dont seul le corps défile.
/// Feuille du bas sous [kCompactMaxWidth], dialogue de [kDialogMaxWidth]
/// au-delà, fermés par un appui à côté, un glissement ou le retour.
Future<T?> showFeuilleOuDialogueAPied<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final compact = MediaQuery.sizeOf(context).width < kCompactMaxWidth;
  if (compact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: builder(context),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
        child: builder(context),
      ),
    ),
  );
}

/// Contenu de [showFeuilleOuDialogueAPied] : titre en tête (lu comme
/// en-tête), [corps] qui défile, [pied] fixé en bas, hors du défilement. Dans
/// le dialogue (à partir de [kCompactMaxWidth]), un bouton « Fermer » suit le
/// titre ; la feuille du bas a sa poignée. Sous [kCompactMaxHeight] de
/// hauteur, le pied défile avec le corps.
class CorpsAPied extends StatelessWidget {
  const CorpsAPied({
    super.key,
    required this.titre,
    required this.corps,
    required this.pied,
  });

  final String titre;
  final List<Widget> corps;
  final Widget pied;

  /// Libellé et infobulle du bouton de fermeture du dialogue.
  static const fermer = 'Fermer';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taille = MediaQuery.sizeOf(context);
    final dialogue = taille.width >= kCompactMaxWidth;
    final entete = Padding(
      padding: EdgeInsets.fromLTRB(24, dialogue ? 16 : 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(titre, style: theme.textTheme.headlineSmall),
            ),
          ),
          if (dialogue)
            IconButton(
              tooltip: fermer,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
    // Hauteur réduite (téléphone en paysage, ou clavier ouvert) : un pied fixe
    // ne laisserait presque rien au corps ; tout défile, pied compris.
    final hauteurLibre =
        taille.height - MediaQuery.viewInsetsOf(context).bottom;
    if (hauteurLibre < kCompactMaxHeight) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            entete,
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...corps, const SizedBox(height: 16), pied],
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        entete,
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: corps,
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: pied,
        ),
      ],
    );
  }
}
