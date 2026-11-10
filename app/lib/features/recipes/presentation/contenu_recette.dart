import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';

import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../domain/beerjson.dart';
import '../domain/chronologie.dart';
import '../domain/recipe.dart';
import 'ingredient_forms.dart';

/// Quantité d'une ligne : « 22,4 g », « 5 ml », « 1,5 L ».
String formatQuantiteRecette(Quantite q) =>
    q.enLitres ? formatVolumeLigne(q.valeur) : formatGrammes(q.valeur);

/// Moment d'un houblon et sa durée : « Ébullition 60 min », « Whirlpool 20 min »,
/// « À cru 3 jours », « Empâtage 60 min ».
String libelleMomentHoublon(HopLine h) {
  final t = h.timeMin;
  final label = libelleUtilisationHoublon(h.use);
  if (t == null) return label;
  return h.use == HopUse.dryHop
      ? '$label ${formatJours(t)}'
      : '$label ${formatMinutes(t)}';
}

/// En-tête de la section Houblons de l'éditeur : « 3 · 45 g », « 3 dont 1 en
/// volume · 25 g », « 1 en volume » ; la masse ne compte que les houblons pesés,
/// et disparaît si aucun ne l'est. `null` sans houblon.
String? enteteHoublons(List<HopLine> hops) {
  if (hops.isEmpty) return null;
  final pesees = [
    for (final h in hops)
      if (h.amount.grammes case final double g) g,
  ];
  final enVolume = hops.length - pesees.length;
  final nombre = switch (enVolume) {
    0 => '${hops.length}',
    _ when pesees.isEmpty => '${hops.length} en volume',
    _ => '${hops.length} dont $enVolume en volume',
  };
  if (pesees.isEmpty) return nombre;
  return '$nombre · ${formatGrammes(pesees.fold(0.0, (s, g) => s + g))}';
}

/// Détails d'un houblon, dans la fiche et dans l'éditeur : « Ébullition 60 min ·
/// 30 g · 10 % alpha · Pellets · 31 IBU ». [fiche] vrai : l'alpha absent est
/// nommé. [ibu] : IBU apporté par ce houblon, s'il est calculé.
List<String> detailsHoublon(HopLine h, {required bool fiche, double? ibu}) => [
  libelleMomentHoublon(h),
  if (h.dayMin != null)
    'ajout au jour ${formatNombre(h.dayMin! / minutesParJour, decimales: 1)}',
  formatQuantiteRecette(h.amount),
  if (h.alphaPct != null)
    '${formatPourcent(h.alphaPct!)} alpha'
  else if (fiche)
    'alpha non renseigné',
  formesHoublon.libelle(h.form),
  if (h.amount.enLitres) kHoublonEnVolume else if (ibu != null) formatIbu(ibu),
];

/// Détails d'un malt ou d'un sucre : « Malt · 4,5 kg · 4 EBC · rendement
/// 80 % ». [fiche] vrai : couleur et rendement absents sont nommés.
List<String> detailsFermentescible(
  FermentableLine f, {
  required bool fiche,
}) => [
  typesFermentable.libelle(f.type),
  formatKilogrammes(f.weightG),
  if (f.ebc != null) formatEbc(f.ebc!) else if (fiche) 'couleur non renseignée',
  if (f.yieldPct != null)
    'rendement ${formatPourcent(f.yieldPct!)}'
  else if (fiche)
    'rendement non renseigné',
];

/// Détails d'un autre ajout, dans la fiche et dans l'éditeur : « Correction de
/// l'eau · 5 g · Empâtage · 60 min ».
List<String> detailsAjout(OtherLine o) => [
  if (o.type != null) typesAjout.libelle(o.type!),
  formatQuantiteRecette(o.amount),
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
  if (y.amount != null) formatQuantiteRecette(y.amount!),
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
            details: detailsFermentescible(f, fiche: true),
          ),
        const TitreSection('Houblons'),
        if (c.hops.isEmpty) const TexteAbsent('Aucun houblon.'),
        for (final (i, h) in c.hops.indexed)
          LigneDeuxNiveaux(
            title: h.name,
            details: detailsHoublon(h, fiche: true, ibu: hopIbu[i]),
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
