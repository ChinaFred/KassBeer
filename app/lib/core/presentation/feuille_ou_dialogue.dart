import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// Ouvre un formulaire court : feuille du bas sous [kCompactMaxWidth], dialogue de
/// [kDialogMaxWidth] au-delà. Rend la valeur passée à `Navigator.pop`.
Future<T?> showFeuilleOuDialogue<T>({
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
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(child: builder(context)),
      ),
    );
  }
  return showDialog<T>(
    context: context,
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
