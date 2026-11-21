import 'package:brewing/brewing.dart';
import 'package:exchange/exchange.dart' show MarqueIa;
import 'package:flutter/material.dart';

import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../domain/beerjson.dart';
import '../domain/chronologie.dart';
import '../domain/libelles_etapes.dart';
import '../domain/recipe.dart';
import 'ingredient_forms.dart';

/// Marque d'une valeur technique proposée par l'IA (ADR-015, lot A2), écrite
/// après la valeur : « 12 % alpha (proposée par l'IA) ». Texte et fonctions
/// ici, hors des fichiers de l'assistant : l'écran du jour importe ce fichier
/// (P2, P60).
const kProposeeParIa = '(proposée par l\'IA)';

/// Aide d'un champ du formulaire dont la valeur a été proposée par l'IA.
const kAideProposeeParIa = 'Valeur proposée par l\'IA : vérifiez-la.';

/// Encadré de la fiche quand des marques n'ont pas pu être lues.
const kMarquesIaIllisibles =
    'Marques IA illisibles : une valeur proposée par l\'IA peut ne pas être '
    'signalée.';

String _avecMarque(String texte, bool marquee) =>
    marquee ? '$texte $kProposeeParIa' : texte;

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
/// 30 g · 10 % alpha · Pellets · 31 IBU ». [fiche] vrai : l'alpha et la forme
/// absents sont nommés. [ibu] : IBU apporté par ce houblon, s'il est calculé.
List<String> detailsHoublon(
  HopLine h, {
  required bool fiche,
  double? ibu,
  List<MarqueIa> marques = const [],
}) => [
  libelleMomentHoublon(h),
  if (h.dayMin != null)
    'ajout au jour ${formatNombre(h.dayMin! / minutesParJour, decimales: 1)}',
  formatQuantiteRecette(h.amount),
  if (h.alphaPct != null)
    _avecMarque(
      '${formatPourcent(h.alphaPct!)} alpha',
      houblonProposeParIa(marques, h),
    )
  else if (fiche)
    'alpha non renseigné',
  if (h.form != null)
    formesHoublon.libelle(h.form!)
  else if (fiche)
    'forme non renseignée',
  if (h.amount.enLitres) kHoublonEnVolume else if (ibu != null) formatIbu(ibu),
];

/// Détails d'un malt ou d'un sucre : « Malt · 4,5 kg · 4 EBC · rendement
/// 80 % ». [fiche] vrai : couleur et rendement absents sont nommés. [marques] :
/// marques `ai_proposed` de la recette, écrites après la valeur.
List<String> detailsFermentescible(
  FermentableLine f, {
  required bool fiche,
  List<MarqueIa> marques = const [],
}) => [
  typesFermentable.libelle(f.type),
  formatKilogrammes(f.weightG),
  if (f.ebc != null)
    _avecMarque(formatEbc(f.ebc!), fermentableProposeParIa(marques, f, 'color'))
  else if (fiche)
    'couleur non renseignée',
  if (f.yieldPct != null)
    _avecMarque(
      'rendement ${formatPourcent(f.yieldPct!)}',
      fermentableProposeParIa(marques, f, 'yield'),
    )
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
List<String> detailsLevure(
  YeastLine y, {
  required bool fiche,
  List<MarqueIa> marques = const [],
}) => [
  if (y.type != null) typesLevure.libelle(y.type!),
  if (y.amount != null) formatQuantiteRecette(y.amount!),
  if (y.attenuationPct != null)
    _avecMarque(
      'atténuation ${formatPourcent(y.attenuationPct!)}',
      levureProposeeParIa(marques, y),
    )
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
    this.momentsOrigine = const {},
    this.chronologie,
    this.niveauTitres = NiveauTitre.section,
    this.enCartes = false,
  }) : assert(
         !enCartes || niveauTitres == NiveauTitre.section,
         'Une section en carte a un titre de section.',
       );

  final RecipeContent content;

  /// [NiveauTitre.sousSection] sous un titre « Recette » (fiche d'un brassin,
  /// recette ouverte depuis l'écran du jour).
  final NiveauTitre niveauTitres;

  /// Vrai : chaque section dans une [CarteSection] (fiche d'une recette,
  /// recette publique). Faux : les sections se suivent, sous un titre
  /// « Recette » qui les range (fiche d'un brassin, écran du jour).
  final bool enCartes;

  /// IBU apporté par chaque houblon, par rang.
  final Map<int, double> hopIbu;

  /// Libellé d'origine du moment d'un houblon, par rang (`source_hop_timing`
  /// d'une recette publique) : « moment d'origine : start ».
  final Map<int, String> momentsOrigine;

  /// Section de chronologie, après les paliers ; nulle pour ne pas l'afficher.
  final Widget? chronologie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = content;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // Une section : son titre et ses lignes, dans une carte ou à la suite.
    List<Widget> section(
      String titre,
      List<Widget> lignes, {
      String? trailing,
    }) => enCartes
        ? [CarteSection(titre: titre, trailing: trailing, children: lignes)]
        : [
            TitreSection(titre, trailing: trailing, niveau: niveauTitres),
            ...lignes,
          ];
    final chronologie = this.chronologie;
    final marques = c.aiProposed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.aiProposedIllisibles > 0) ...[
          const Encadre(
            ton: TonEncadre.avertissement,
            icone: Icons.warning_amber_outlined,
            child: Text(kMarquesIaIllisibles),
          ),
          const SizedBox(height: 8),
        ],
        ...section(
          'Malts et sucres',
          trailing: c.fermentables.isEmpty
              ? null
              : '${c.fermentables.length} · ${formatKilogrammes(c.fermentables.fold(0.0, (s, f) => s + f.weightG))}',
          [
            if (c.fermentables.isEmpty)
              const TexteAbsent('Aucun malt ni sucre.'),
            for (final f in c.fermentables)
              LigneDeuxNiveaux(
                title: f.name,
                details: detailsFermentescible(
                  f,
                  fiche: true,
                  marques: marques,
                ),
              ),
          ],
        ),
        ...section('Houblons', [
          if (c.hops.isEmpty) const TexteAbsent('Aucun houblon.'),
          for (final (i, h) in c.hops.indexed)
            LigneDeuxNiveaux(
              title: h.name,
              details: [
                ...detailsHoublon(
                  h,
                  fiche: true,
                  ibu: hopIbu[i],
                  marques: marques,
                ),
                if (momentsOrigine[i] case final moment?)
                  "moment d'origine : $moment",
              ],
            ),
        ]),
        ...section('Autres ajouts', [
          if (c.others.isEmpty) const TexteAbsent('Aucun ajout.'),
          for (final o in c.others)
            LigneDeuxNiveaux(title: o.name, details: detailsAjout(o)),
        ]),
        ...section('Levure', [
          if (c.yeasts.isEmpty) const TexteAbsent('Aucune levure.'),
          for (final y in c.yeasts)
            LigneDeuxNiveaux(
              title: y.name,
              details: detailsLevure(y, fiche: true, marques: marques),
            ),
        ]),
        ...section('Paliers d\'empâtage', [
          if (c.grainTempC != null)
            LigneFiche(
              label: 'Température du grain',
              value: formatCelsius(c.grainTempC!),
            ),
          if (c.mashSteps.isEmpty) const TexteAbsent('Aucun palier.'),
          for (final s in c.mashSteps)
            LigneDeuxNiveaux(title: s.name, details: detailsPalier(s)),
        ]),
        // La chronologie porte son titre : en carte, elle en est le premier
        // enfant.
        if (chronologie != null)
          enCartes ? CarteSection(children: [chronologie]) : chronologie,
        ...section('Notes', [
          Text(
            c.notes ?? 'Non renseigné',
            style: c.notes == null
                ? muted?.copyWith(fontStyle: FontStyle.italic)
                : theme.textTheme.bodyLarge,
          ),
        ]),
      ],
    );
  }
}
