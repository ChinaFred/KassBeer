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
