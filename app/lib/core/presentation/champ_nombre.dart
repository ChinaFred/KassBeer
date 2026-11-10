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
    this.min = 0,
    this.minExclu = false,
    this.entier = false,
    this.erreurPropre,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onSubmitted,
    this.style,
    this.autofocus = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;

  /// Texte d'aide sous le champ.
  final String? aide;

  /// Avertissement non bloquant (U6), affiché à la place de l'aide.
  final String? avertissement;

  final bool obligatoire;
  final double? max;

  /// Minimum accepté, inclus sauf avec [minExclu].
  final double min;

  /// Zéro refusé (volume strictement positif).
  final bool minExclu;

  /// Nombre entier (nombre de bouteilles) : clavier sans décimale.
  final bool entier;

  /// Erreur propre au champ, vérifiée avant les règles communes ; `null` si le
  /// texte la passe.
  final String? Function(String texte)? erreurPropre;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Style du texte saisi ; celui du thème s'il est nul.
  final TextStyle? style;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = avertissement;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      style: style,
      // Un minimum négatif (température du grain) demande la touche « - ».
      keyboardType: TextInputType.numberWithOptions(
        decimal: !entier,
        signed: min < 0,
      ),
      textInputAction: textInputAction,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        helperText: warning ?? aide,
        // Une aide ou une erreur longue (whirlpool) n'est pas coupée, même à
        // grande taille de texte.
        helperMaxLines: 8,
        errorMaxLines: 8,
        helperStyle: warning == null
            ? null
            : theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
        border: const OutlineInputBorder(),
      ),
      validator: (text) =>
          erreurPropre?.call(text ?? '') ??
          erreurNombre(
            text ?? '',
            obligatoire: obligatoire,
            max: max,
            min: min,
            minExclu: minExclu,
            entier: entier,
          ),
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
    );
  }
}
