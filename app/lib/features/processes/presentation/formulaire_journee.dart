import 'package:brewing/brewing.dart' show maxProcessOffsetDays;
import 'package:flutter/material.dart';

import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/formats.dart';
import '../domain/modele_processus.dart';

/// Nom et écart d'une journée saisis dans [FormulaireJournee].
typedef SaisieJournee = ({String name, int offsetDays});

/// Formulaire d'une journée de processus (feuille ou dialogue) : nom et écart en
/// jours, sans valeur d'avance. [offsetFixe] : journée du brassage, renommée
/// seulement (écart 0).
class FormulaireJournee extends StatefulWidget {
  const FormulaireJournee({
    super.key,
    required this.onSubmit,
    this.initialName,
    this.initialOffset,
    this.offsetFixe = false,
  });

  final ValueChanged<SaisieJournee> onSubmit;
  final String? initialName;
  final int? initialOffset;
  final bool offsetFixe;

  static const nomManquant = 'Donnez un nom à la journée.';
  static const libelleEcart = 'Écart (jours après le brassage)';
  static const aideEcart =
      'J+4 : quatre jours après le jour du brassage. Pour les houblons à cru, '
      'le jour fixé par la recette passe avant.';

  @override
  State<FormulaireJournee> createState() => _FormulaireJourneeState();
}

class _FormulaireJourneeState extends State<FormulaireJournee> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late final _offset = TextEditingController(
    text: widget.initialOffset?.toString() ?? '',
  );

  bool get _editing => widget.initialName != null;

  @override
  void dispose() {
    _name.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final offset = widget.offsetFixe
        ? 0
        : lireNombre(_offset.text).valeur!.toInt();
    widget.onSubmit((name: _name.text.trim(), offsetDays: offset));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titre = widget.offsetFixe
        ? 'Renommer la journée'
        : _editing
        ? 'Modifier la journée'
        : 'Nouvelle journée';
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(titre, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            autofocus: true,
            maxLength: kNomJourneeModeleMaxLength,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: widget.offsetFixe
                ? TextInputAction.done
                : TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nom de la journée',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? FormulaireJournee.nomManquant : null,
            onFieldSubmitted: widget.offsetFixe ? (_) => _submit() : null,
          ),
          if (!widget.offsetFixe) ...[
            const SizedBox(height: 16),
            ChampNombre(
              controller: _offset,
              label: FormulaireJournee.libelleEcart,
              aide: FormulaireJournee.aideEcart,
              obligatoire: true,
              entier: true,
              max: maxProcessOffsetDays.toDouble(),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: _submit,
                child: Text(_editing ? 'Enregistrer' : 'Ajouter'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
