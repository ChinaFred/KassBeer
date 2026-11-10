import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';

import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../domain/beerjson.dart';
import '../domain/chronologie.dart';
import '../domain/recipe.dart';
import 'ingredient_forms.dart';

/// Détails d'un autre ajout, dans la fiche et dans l'éditeur : « Correction de
/// l'eau · 5 g · Empâtage · 60 min ».
List<String> detailsAjout(OtherLine o) => [
  if (o.type != null) typesAjout.libelle(o.type!),
  formatGrammes(o.weightG),
  if (o.use != null) o.use!.label,
  if (o.timeMin != null) formatMinutes(o.timeMin!),
];

/// Détails d'un palier : « Infusion · 65 °C · 60 min ».
List<String> detailsPalier(MashStep s) => [
  if (s.type != null) typesPalier.libelle(s.type!),
  formatCelsius(s.tempC),
  formatMinutes(s.durationMin),
];

/// Détails d'une levure : « Haute fermentation (ale) · 11 g · atténuation 75 % ·
/// Sèche ». [fiche] vrai : l'atténuation absente est nommée.
List<String> detailsLevure(YeastLine y, {required bool fiche}) => [
  if (y.type != null) typesLevure.libelle(y.type!),
  if (y.amountG != null) formatGrammes(y.amountG!),
  if (y.attenuationPct != null)
    'atténuation ${formatPourcent(y.attenuationPct!)}'
  else if (fiche)
    'atténuation non renseignée',
  if (y.form != null) formesLevure.libelle(y.form!),
];

/// Lignes d'une chronologie : nom, durée (ou « Action » à 0 min), température.
List<Widget> listeEtapes(List<BrewStepLine> steps) => [
  for (final s in steps)
    LigneDeuxNiveaux(
      title: s.name,
      details: [
        s.durationMin == 0 ? 'Action' : formatMinutes(s.durationMin),
        if (s.tempC != null) formatCelsius(s.tempC!),
      ],
    ),
];

/// Sections d'une recette, de la fiche et de la copie figée d'un brassin : malts,
/// houblons, ajouts, levure, paliers, chronologie, notes.
class ContenuRecette extends StatelessWidget {
  const ContenuRecette({
    super.key,
    required this.content,
    this.hopIbu = const {},
    this.chronologie,
  });

  final RecipeContent content;

  /// IBU apporté par chaque houblon, par rang.
  final Map<int, double> hopIbu;

  /// Section de chronologie, après les paliers ; nulle pour ne pas l'afficher.
  final Widget? chronologie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = content;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TitreSection(
          'Malts et sucres',
          trailing: c.fermentables.isEmpty
              ? null
              : '${c.fermentables.length} · ${formatKilogrammes(c.fermentables.fold(0.0, (s, f) => s + f.weightG))}',
        ),
        if (c.fermentables.isEmpty) const TexteAbsent('Aucun malt ni sucre.'),
        for (final f in c.fermentables)
          LigneDeuxNiveaux(
            title: f.name,
            details: [
              f.kind == FermentableKind.malt ? 'Malt' : 'Sucre',
              formatKilogrammes(f.weightG),
              f.ebc == null ? 'couleur non renseignée' : formatEbc(f.ebc!),
              f.yieldPct == null
                  ? 'rendement non renseigné'
                  : 'rendement ${formatPourcent(f.yieldPct!)}',
            ],
          ),
        const TitreSection('Houblons'),
        if (c.hops.isEmpty) const TexteAbsent('Aucun houblon.'),
        for (final (i, h) in c.hops.indexed)
          LigneDeuxNiveaux(
            title: h.name,
            details: [
              switch (h.use) {
                HopUse.boil =>
                  h.timeMin == null
                      ? 'Ébullition'
                      : 'Ébullition ${formatMinutes(h.timeMin!)}',
                HopUse.afterBoil =>
                  h.timeMin == null
                      ? 'Whirlpool'
                      : 'Whirlpool ${formatMinutes(h.timeMin!)}',
                HopUse.dryHop =>
                  h.timeMin == null
                      ? 'À cru'
                      : 'À cru ${formatJours(h.timeMin!)}',
              },
              formatGrammes(h.weightG),
              h.alphaPct == null
                  ? 'alpha non renseigné'
                  : '${formatPourcent(h.alphaPct!)} alpha',
              libelleFormeHoublon(h.form),
              if (hopIbu[i] != null) formatIbu(hopIbu[i]!),
            ],
          ),
        const TitreSection('Autres ajouts'),
        if (c.others.isEmpty) const TexteAbsent('Aucun ajout.'),
        for (final o in c.others)
          LigneDeuxNiveaux(title: o.name, details: detailsAjout(o)),
        const TitreSection('Levure'),
        if (c.yeasts.isEmpty) const TexteAbsent('Aucune levure.'),
        for (final y in c.yeasts)
          LigneDeuxNiveaux(
            title: y.name,
            details: detailsLevure(y, fiche: true),
          ),
        const TitreSection('Paliers d\'empâtage'),
        if (c.grainTempC != null)
          LigneFiche(
            label: 'Température du grain',
            value: formatCelsius(c.grainTempC!),
          ),
        if (c.mashSteps.isEmpty) const TexteAbsent('Aucun palier.'),
        for (final s in c.mashSteps)
          LigneDeuxNiveaux(title: s.name, details: detailsPalier(s)),
        ?chronologie,
        const TitreSection('Notes'),
        Text(
          c.notes ?? 'Non renseigné',
          style: c.notes == null
              ? muted?.copyWith(fontStyle: FontStyle.italic)
              : theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}
