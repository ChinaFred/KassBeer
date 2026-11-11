import 'dart:async';

import 'package:brewing/brewing.dart' show FeeBasis;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/fee.dart';

/// Textes du formulaire de frais et de ses annonces (FR1, FR2).
abstract final class TextesFrais {
  static const nouveau = 'Nouveau frais';
  static const modifier = 'Modifier le frais';
  static const choisirBase = 'Choisissez une base.';
  static const abandon = 'Le frais saisi ne sera pas enregistré.';
  static const enregistre = 'Frais enregistré.';
  static const enregistreHorsLigne =
      'Frais enregistré sur l\'appareil. Il partira au retour du réseau.';
  static String refus(String name) =>
      'L\'enregistrement du frais « $name » a échoué.';
  static String supprime(String name) => 'Frais « $name » supprimé.';
  static String suppressionRefusee(String name) =>
      'La suppression du frais « $name » a échoué.';
}

/// Ouvre le formulaire de frais de [uid] ; [initial] nul pour un nouveau frais.
Future<void> ouvrirFormulaireFrais(
  BuildContext context, {
  required String uid,
  Fee? initial,
  // ticket: /prix/fenetre/frais
}) => showFeuilleOuDialogue<void>(
  context: context,
  fermetureProtegee: true,
  builder: (_) => FormulaireFrais(uid: uid, initial: initial),
);

/// Formulaire « Nouveau frais » / « Modifier le frais » : nom, montant, base.
/// Aucun montant ni aucune base préremplis (FR3).
class FormulaireFrais extends ConsumerStatefulWidget {
  const FormulaireFrais({super.key, required this.uid, this.initial});

  final String uid;
  final Fee? initial;

  @override
  ConsumerState<FormulaireFrais> createState() => _FormulaireFraisState();
}

class _FormulaireFraisState extends ConsumerState<FormulaireFrais> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  FeeBasis? _basis;
  String? _basisError;
  bool _modifie = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _amount = TextEditingController(
      text: initial == null ? '' : texteSaisi(initial.amountEur, decimales: 4),
    );
    _basis = initial?.basis;
    _name.addListener(_changement);
    _amount.addListener(_changement);
  }

  void _changement() => setState(() => _modifie = true);

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _quitter() async {
    final navigator = Navigator.of(context);
    if (!_modifie) {
      navigator.pop();
      return;
    }
    // ticket: aucun (confirmation)
    final abandon = await confirmerAbandon(context, TextesFrais.abandon);
    if (abandon && mounted) navigator.pop();
  }

  void _save() {
    final basis = _basis;
    setState(
      () => _basisError = basis == null ? TextesFrais.choisirBase : null,
    );
    final valid = _form.currentState?.validate() ?? false;
    final amount = lireNombre(_amount.text).valeur;
    if (!valid || basis == null || amount == null) return;
    final repo = ref.read(costsRepositoryProvider);
    final name = _name.text.trim();
    final fee = Fee(
      id: widget.initial?.id ?? repo.newFeeId(widget.uid),
      name: name,
      amountEur: amount,
      basis: basis,
    );
    final offline = ref.read(grantedAccessProvider)?.offline ?? false;
    suivreEcriture(
      messenger: ScaffoldMessenger.of(context),
      written: repo.saveFee(uid: widget.uid, fee: fee),
      succes: offline
          ? TextesFrais.enregistreHorsLigne
          : TextesFrais.enregistre,
      refus: TextesFrais.refus(name),
    );
    Navigator.of(context).pop();
  }

  void _delete(Fee initial) {
    final repo = ref.read(costsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final uid = widget.uid;
    unawaited(
      repo.deleteFee(uid: uid, id: initial.id).catchError((Object _) {
        // Déjà rapportée par le dépôt de données.
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text(TextesFrais.suppressionRefusee(initial.name))),
        );
      }),
    );
    annoncerAvecAnnulation(
      messenger,
      TextesFrais.supprime(initial.name),
      onAnnuler: () => suivreEcriture(
        messenger: messenger,
        written: repo.saveFee(uid: uid, fee: initial),
        succes: TextesFrais.enregistre,
        refus: TextesFrais.refus(initial.name),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = widget.initial;
    return PopScope(
      canPop: !_modifie,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_quitter());
      },
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              initial == null ? TextesFrais.nouveau : TextesFrais.modifier,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              maxLength: kFeeNameMaxLength,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nom',
                border: OutlineInputBorder(),
              ),
              validator: (text) => text == null || text.trim().isEmpty
                  ? ErreursNombre.obligatoire
                  : null,
            ),
            const SizedBox(height: 8),
            ChampNombre(
              controller: _amount,
              label: 'Montant (€)',
              obligatoire: true,
              max: kFeeMaxEur,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text('Base', style: theme.textTheme.labelLarge),
            ),
            RadioGroup<FeeBasis>(
              groupValue: _basis,
              onChanged: (b) => setState(() {
                _basis = b;
                _basisError = null;
                _modifie = true;
              }),
              child: const Column(
                children: [
                  RadioListTile<FeeBasis>(
                    value: FeeBasis.perBrew,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Par brassin'),
                  ),
                  RadioListTile<FeeBasis>(
                    value: FeeBasis.perBottle,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Par bouteille'),
                  ),
                ],
              ),
            ),
            if (_basisError != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _basisError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (initial != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () => _delete(initial),
                    child: const Text('Supprimer'),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => unawaited(_quitter()),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      onPressed: _save,
                      child: const Text('Enregistrer'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
