import 'package:flutter/material.dart';

import 'formats.dart';

/// Champ de saisie d'un nombre (règle U1) : virgule ou point décimal, espaces
/// ignorés, clavier décimal. L'unité est dans le libellé (« Quantité (kg) »). Les
/// erreurs suivent [erreurNombre] : « Champ obligatoire. », « Nombre illisible. »,
/// « Nombre positif attendu. », « Entre 0 et 100. », « Nombre trop grand. ».
class ChampNombre extends StatelessWidget {
  const ChampNombre({
    super.key,
    required this.controller,
    required this.label,
    this.aide,
    this.avertissement,
    this.obligatoire = false,
    this.max,
    this.minExclu = false,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;

  /// Texte d'aide sous le champ.
  final String? aide;

  /// Avertissement non bloquant (U6), affiché à la place de l'aide.
  final String? avertissement;

  final bool obligatoire;
  final double? max;

  /// Zéro refusé (volume strictement positif).
  final bool minExclu;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = avertissement;
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        helperText: warning ?? aide,
        helperMaxLines: 3,
        helperStyle: warning == null
            ? null
            : theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
        border: const OutlineInputBorder(),
      ),
      validator: (text) => erreurNombre(
        text ?? '',
        obligatoire: obligatoire,
        max: max,
        minExclu: minExclu,
      ),
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
    );
  }
}
