import 'dart:async';

import 'package:brewing/brewing.dart' show GravityRead, readGravity;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/editeur_plein_ecran.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../brew_day/presentation/mesure_form.dart';
import '../../costs/data/figeage_embouteillage.dart';
import '../../costs/presentation/costs_providers.dart';
import '../data/brews_repository.dart';
import '../domain/brew.dart';
import '../domain/brew_event.dart';

/// Refus du formulaire d'embouteillage (EM2).
const kDateFutureRefusee = 'La date ne peut pas être dans le futur.';
const kDateAvantBrassage = 'La date ne peut pas précéder le brassage.';

/// Seuils d'avertissement (EM2) : au-delà, la saisie reste possible.
const _seuilBouteilles = 200.0;
const _seuilVolume = 200.0;
const _seuilSucre = 1000.0;

/// Section « Embouteillage » de la fiche : cinq lignes, « Non renseigné » si vide.
class SectionEmbouteillage extends StatelessWidget {
  const SectionEmbouteillage({
    super.key,
    required this.brew,
    required this.onModifier,
  });

  final Brew brew;

  /// « Modifier l'embouteillage », pour le propriétaire seul.
  final VoidCallback? onModifier;

  @override
  Widget build(BuildContext context) {
    final bottles = brew.bottlesCount;
    final volume = brew.packagedVolumeL;
    final sugar = brew.primingSugarG;
    final bottled = brew.bottledAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSection('Embouteillage'),
        LigneFiche(
          label: 'Date d\'embouteillage',
          value: bottled == null ? null : formatDateCourte(bottled),
        ),
        LigneFiche(
          label: 'Nombre de bouteilles',
          value: bottles == null ? null : '$bottles',
        ),
        LigneFiche(
          label: 'Volume conditionné',
          value: volume == null ? null : formatLitres(volume),
        ),
        LigneFiche(
          label: 'Sucre de resucrage',
          value: sugar == null ? null : formatGrammes(sugar),
        ),
        LigneFiche(label: 'Nature du sucre', value: brew.primingSugarName),
        if (onModifier != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onModifier,
              child: const Text('Modifier l\'embouteillage'),
            ),
          ),
      ],
    );
  }
}

/// Formulaire « Embouteiller ». [modification] : pas de densité finale, statut
/// inchangé (EM4).
class FormulaireEmbouteillage extends StatefulWidget {
  const FormulaireEmbouteillage({
    super.key,
    required this.brew,
    required this.modification,
    required this.fermentationMesuree,
    required this.now,
    required this.onSubmit,
  });

  final Brew brew;
  final bool modification;

  /// Vrai si une densité de fermentation existe déjà : l'information ne s'affiche pas.
  final bool fermentationMesuree;
  final DateTime Function() now;
  final void Function(Embouteillage embouteillage, double? finalGravity)
  onSubmit;

  @override
  State<FormulaireEmbouteillage> createState() =>
      _FormulaireEmbouteillageState();
}

class _FormulaireEmbouteillageState extends State<FormulaireEmbouteillage> {
  final _formKey = GlobalKey<FormState>();
  final _densite = TextEditingController();
  final _bouteilles = TextEditingController();
  final _volume = TextEditingController();
  final _sucre = TextEditingController();
  final _nature = TextEditingController();
  final _densiteFocus = FocusNode();
  late DateTime _date;
  String? _erreurDate;
  bool _dirty = false;
  bool _envoye = false;

  @override
  void initState() {
    super.initState();
    final brew = widget.brew;
    final now = widget.now();
    _date = brew.bottledAt ?? DateTime(now.year, now.month, now.day);
    final b = brew.bottlesCount;
    if (b != null) _bouteilles.text = '$b';
    _volume.text = texteSaisi(brew.packagedVolumeL);
    _sucre.text = texteSaisi(brew.primingSugarG);
    _nature.text = brew.primingSugarName ?? '';
    _densite.addListener(_densiteChangee);
  }

  /// La ligne d'information dépend du champ : l'écran se redessine à chaque frappe.
  void _densiteChangee() => setState(() {
    if (_densite.text.isNotEmpty) _dirty = true;
  });

  @override
  void dispose() {
    _densite.dispose();
    _bouteilles.dispose();
    _volume.dispose();
    _sucre.dispose();
    _nature.dispose();
    _densiteFocus.dispose();
    super.dispose();
  }

  /// Les avertissements « inhabituel » suivent chaque frappe.
  void _modifie() => setState(() => _dirty = true);

  Future<void> _choisirDate() async {
    final now = widget.now();
    final aujourdhui = DateTime(now.year, now.month, now.day);
    final brewed = widget.brew.brewedAt;
    final debut = brewed == null
        ? DateTime(aujourdhui.year - 5)
        : DateTime(brewed.year, brewed.month, brewed.day);
    // ticket: aucun (sélecteur du système)
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(debut) ? debut : _date,
      firstDate: debut.isAfter(aujourdhui) ? aujourdhui : debut,
      lastDate: aujourdhui,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _erreurDate = null;
      _date = picked;
      _dirty = true;
    });
  }

  /// `bottled_at` : date choisie, avec l'heure de l'appareil (EM3). À la modification
  /// d'une date inchangée, l'heure d'origine est gardée.
  DateTime _bottledAt() {
    final avant = widget.brew.bottledAt;
    if (avant != null &&
        avant.year == _date.year &&
        avant.month == _date.month &&
        avant.day == _date.day) {
      return avant;
    }
    final now = widget.now();
    return DateTime(
      _date.year,
      _date.month,
      _date.day,
      now.hour,
      now.minute,
      now.second,
    );
  }

  void _soumettre() {
    if (_envoye) return;
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      unawaited(montrerChamp(invalid.first.context));
      return;
    }
    final now = widget.now();
    if (DateTime(_date.year, _date.month, _date.day).isAfter(now)) {
      setState(() => _erreurDate = kDateFutureRefusee);
      return;
    }
    final brewed = widget.brew.brewedAt;
    if (brewed != null &&
        DateTime(
          _date.year,
          _date.month,
          _date.day,
        ).isBefore(DateTime(brewed.year, brewed.month, brewed.day))) {
      setState(() => _erreurDate = kDateAvantBrassage);
      return;
    }
    final bouteilles = lireNombre(_bouteilles.text).valeur;
    final nature = _nature.text.trim();
    final double? finalGravity =
        widget.modification || _densite.text.trim().isEmpty
        ? null
        : switch (readGravity(_densite.text)) {
            GravityRead(:final sg) => sg,
            _ => null,
          };
    _envoye = true;
    Navigator.of(context).pop();
    widget.onSubmit(
      Embouteillage(
        bottledAt: _bottledAt(),
        bottlesCount: bouteilles?.toInt(),
        packagedVolumeL: lireNombre(_volume.text).valeur,
        primingSugarG: lireNombre(_sucre.text).valeur,
        primingSugarName: nature.isEmpty ? null : nature,
      ),
      finalGravity,
    );
  }

  Future<void> _quitter() async {
    final navigator = Navigator.of(context);
    if (!_dirty) {
      navigator.pop();
      return;
    }
    // ticket: aucun (confirmation)
    final abandon = await confirmerAbandon(
      context,
      'La saisie de cet embouteillage ne sera pas enregistrée.',
    );
    if (abandon && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modification = widget.modification;
    final bouteilles = lireNombre(_bouteilles.text).valeur;
    final volume = lireNombre(_volume.text).valeur;
    final sucre = lireNombre(_sucre.text).valeur;
    final sansDensite =
        !modification &&
        !widget.fermentationMesuree &&
        _densite.text.trim().isEmpty;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_quitter());
      },
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Embouteiller', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 16),
            ExcludeSemantics(
              child: Text(
                'Date d\'embouteillage',
                style: theme.textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 4),
            Semantics(
              label: 'Date d\'embouteillage',
              child: OutlinedButton(
                onPressed: () => unawaited(_choisirDate()),
                child: Text(formatDate(_date)),
              ),
            ),
            if (_erreurDate != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _erreurDate!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            if (!modification) ...[
              ChampDensite(
                controller: _densite,
                focusNode: _densiteFocus,
                autofocus: false,
                label: 'Densité finale (facultatif)',
                textInputAction: TextInputAction.next,
                obligatoire: false,
                grand: false,
                onSubmit: () => FocusScope.of(context).nextFocus(),
              ),
              const SizedBox(height: 12),
            ],
            ChampNombre(
              controller: _bouteilles,
              label: 'Nombre de bouteilles (facultatif)',
              entier: true,
              min: 1,
              max: 9999,
              avertissement: bouteilles != null && bouteilles > _seuilBouteilles
                  ? 'Nombre inhabituel : ${formatNombre(bouteilles, decimales: 0)} bouteilles. Vérifiez la saisie.'
                  : null,
              onChanged: (_) => _modifie(),
            ),
            const SizedBox(height: 12),
            ChampNombre(
              controller: _volume,
              label: 'Volume conditionné (L) (facultatif)',
              minExclu: true,
              max: 1000,
              avertissement: volume != null && volume > _seuilVolume
                  ? 'Volume inhabituel : ${formatLitres(volume)}. Vérifiez la saisie.'
                  : null,
              onChanged: (_) => _modifie(),
            ),
            const SizedBox(height: 12),
            ChampNombre(
              controller: _sucre,
              label: 'Sucre de resucrage (g) (facultatif)',
              max: 100000,
              avertissement: sucre != null && sucre > _seuilSucre
                  ? 'Masse inhabituelle : ${formatGrammes(sucre)}. Vérifiez la saisie.'
                  : null,
              onChanged: (_) => _modifie(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nature,
              maxLength: kPrimingSugarNameMaxLength,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nature du sucre (facultatif)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _modifie(),
              onFieldSubmitted: (_) => _soumettre(),
            ),
            if (!modification) ...[
              const Text('Le brassin passera En conditionnement.'),
              const SizedBox(height: 4),
            ],
            if (sansDensite) ...[
              const Text(
                'Aucune densité mesurée en fermentation : le degré restera indisponible.',
              ),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: _soumettre,
              child: Text(
                modification ? 'Enregistrer' : 'Enregistrer l\'embouteillage',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => unawaited(_quitter()),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vrai si une densité de fermentation existe parmi [events].
bool densiteDeFermentationMesuree(List<BrewEvent> events) =>
    events.any((e) => e.isGravity && e.isFermentation);

/// Envoi d'un embouteillage préparé par [capturerEmbouteillage].
typedef EnvoiEmbouteillage =
    EmbouteillageEnvoye Function({
      required Embouteillage embouteillage,
      required double? finalGravity,
      required bool modification,
      required String? ownerName,
    });

/// Capture les dépôts et les lectures ouvertes du propriétaire de [brew] (prix,
/// frais, coût figé) à l'envoi du formulaire, avant l'attente du nom du jeton
/// (CB5). L'envoi rendu n'utilise plus `ref` : il ne lit rien et n'attend rien,
/// hors ligne compris (P2). La fiche lit ces valeurs pour son bloc Coût ; la
/// journée d'embouteillage (ADR-009) les a ouvertes à « Préparer la journée ».
EnvoiEmbouteillage capturerEmbouteillage(WidgetRef ref, Brew brew) {
  final brews = ref.read(brewsRepositoryProvider);
  final costs = ref.read(costsRepositoryProvider);
  final errors = ref.read(errorReportServiceProvider);
  final reported = ref.read(costReportsProvider);
  final horloge = ref.read(horlogeProvider);
  final uid = brew.ownerUid;
  final prices = ref.read(pricesProvider(uid)).value;
  final fees = ref.read(feesProvider(uid)).value;
  final coutLu = ref.read(brewCostProvider((uid: uid, brewId: brew.id))).value;
  return ({
    required Embouteillage embouteillage,
    required double? finalGravity,
    required bool modification,
    required String? ownerName,
  }) => enregistrerEmbouteillage(
    brews: brews,
    costs: costs,
    errors: errors,
    reported: reported,
    brew: brew,
    embouteillage: embouteillage,
    finalGravity: finalGravity,
    modification: modification,
    ownerName: ownerName,
    prices: prices,
    fees: fees,
    coutLu: coutLu,
    now: horloge(),
  );
}
