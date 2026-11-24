import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../library/presentation/couleur_ebc.dart';
import '../domain/filtres_recettes.dart';

/// Textes de la boîte « Filtrer les recettes » et de ses filtres actifs.
abstract final class TextesFiltresRecettes {
  static const titre = 'Filtrer les recettes';
  static const styles = 'Styles';
  static const sansStyle = 'Sans style';
  static const degre = 'Degré d\'alcool';
  static const couleur = 'Couleur';
  static const aromes = 'Arômes';
  static const motsLabel = 'Mots de la description';
  static const motsAide =
      'Séparez les mots par une virgule : la recette doit les contenir tous.';
  static const aucunResultat =
      'Aucune recette ne correspond à ces filtres. Élargissez un curseur, '
      'retirez un style ou un mot.';
  static const retirerFiltre = 'Retirer ce filtre';
  static String filtreEnCours(String plage) => 'Filtre en cours : $plage';
  static const reinitialiser = 'Réinitialiser';
  static const aucune = 'Aucune recette';
  static const effacer = 'Effacer les filtres';
  static const aucunDegre = 'Aucune recette n\'a de degré calculé.';
  static const aucuneCouleur = 'Aucune recette n\'a de couleur calculée.';

  /// Nombre de styles affichés avant « Afficher les N styles ».
  static const stylesVisibles = 12;

  static String afficherStyles(int n) => 'Afficher les $n styles';

  static String afficher(int n) =>
      n == 1 ? 'Afficher 1 recette' : 'Afficher $n recettes';

  /// Plage du degré : « 5,0 à 9,0 % vol ».
  static String plageDegre(Intervalle i) =>
      '${formatNombre(i.min, decimales: 1, fixe: true)} à ${formatDegre(i.max)}';

  /// Plage de la couleur : « 8 à 40 EBC ».
  static String plageEbc(Intervalle i) =>
      '${formatNombre(i.min, decimales: 0)} à ${formatEbc(i.max)}';

  static String degreUnique(double v) =>
      'Toutes les recettes ont le même degré calculé : ${formatDegre(v)}.';

  static String couleurUnique(double v) =>
      'Toutes les recettes ont la même couleur calculée : ${formatEbc(v)}.';

  static String sansDegre(int n) => n == 1
      ? '1 recette sans degré calculé ne s\'affiche pas avec ce filtre.'
      : '$n recettes sans degré calculé ne s\'affichent pas avec ce filtre.';

  static String sansCouleur(int n) => n == 1
      ? '1 recette sans couleur calculée ne s\'affiche pas avec ce filtre.'
      : '$n recettes sans couleur calculée ne s\'affichent pas avec ce filtre.';

  static const retirerDegre = 'Retirer le filtre Degré';
  static const retirerCouleur = 'Retirer le filtre Couleur';
  static String retirerStyle(String style) => 'Retirer le style $style';
  static String retirerMot(String mot) => 'Retirer l\'arôme $mot';

  /// Lecture de l'icône du champ de recherche.
  static String boutonLu(int actifs) => switch (actifs) {
    0 => titre,
    1 => '$titre, 1 filtre actif',
    _ => '$titre, $actifs filtres actifs',
  };
}

/// Bornes d'un curseur : [bornes] des valeurs calculées, élargies au pas
/// ([pas] : 0,1 pour le degré, 1 pour l'EBC) pour que les valeurs du curseur
/// tombent sur un pas. `null` si toutes les valeurs sont égales à ce pas.
({Intervalle bornes, int divisions})? curseurDe(
  Intervalle? bornes,
  double pas,
) {
  if (bornes == null) return null;
  final bas = (bornes.min / pas).floorToDouble();
  final haut = (bornes.max / pas).ceilToDouble();
  final divisions = (haut - bas).round();
  if (divisions <= 0) return null;
  return (bornes: Intervalle(bas * pas, haut * pas), divisions: divisions);
}

/// Boîte « Filtrer les recettes ». Rend les filtres choisis par « Afficher
/// N recettes », ou `null` si elle est fermée sans valider.
class BoiteFiltresRecettes extends ConsumerStatefulWidget {
  const BoiteFiltresRecettes({
    super.key,
    required this.initial,
    required this.styles,
    required this.degres,
    required this.couleurs,
    required this.compter,
  });

  final FiltresRecettes initial;

  /// Styles des recettes de l'origine choisie, comptés.
  final List<StyleCompte> styles;

  /// Degrés calculés des recettes de l'origine choisie (`null` : non calculé).
  final List<double?> degres;

  /// Couleurs calculées des recettes de l'origine choisie.
  final List<double?> couleurs;

  /// Nombre de recettes affichées avec ces filtres (origine et recherche
  /// comprises).
  final int Function(FiltresRecettes) compter;

  @override
  ConsumerState<BoiteFiltresRecettes> createState() =>
      _BoiteFiltresRecettesState();
}

class _BoiteFiltresRecettesState extends ConsumerState<BoiteFiltresRecettes> {
  late FiltresRecettes _filtres = widget.initial;
  late final _mots = TextEditingController(text: widget.initial.aromes);
  bool _tousStyles = false;
  bool _degradeSignale = false;

  @override
  void dispose() {
    _mots.dispose();
    super.dispose();
  }

  void _reinitialiser() => setState(() {
    _filtres = FiltresRecettes.vide;
    _mots.clear();
  });

  /// Valeur du curseur aux deux bornes : aucun filtre.
  static Intervalle? _retenu(RangeValues v, Intervalle bornes) =>
      v.start <= bornes.min && v.end >= bornes.max
      ? null
      : Intervalle(v.start, v.end);

  List<int>? _degrade(Intervalle bornes) {
    try {
      return degradeEbc(bornes.min, bornes.max);
    } on BrewingInputException catch (error, stackTrace) {
      if (!_degradeSignale) {
        _degradeSignale = true;
        ref
            .read(errorReportServiceProvider)
            .reportError(
              feature: 'recipes.filter_gradient',
              error: error,
              stackTrace: stackTrace,
              context: 'plage de couleur refusée par brewing : ${error.field}',
            );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final petit = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final n = widget.compter(_filtres);
    final empiles =
        MediaQuery.textScalerOf(context).scale(1) >= kGrandTexteMinScale;
    final reinitialiser = TextButton(
      onPressed: _reinitialiser,
      child: const Text(TextesFiltresRecettes.reinitialiser),
    );
    final afficher = FilledButton(
      onPressed: n == 0 ? null : () => Navigator.of(context).pop(_filtres),
      child: Text(
        n == 0
            ? TextesFiltresRecettes.aucune
            : TextesFiltresRecettes.afficher(n),
      ),
    );

    Widget titreSection(String texte) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(texte, style: theme.textTheme.titleMedium),
      ),
    );

    return CorpsAPied(
      titre: TextesFiltresRecettes.titre,
      corps: [
        if (widget.styles.isNotEmpty) ...[
          titreSection(TextesFiltresRecettes.styles),
          _styles(),
        ],
        titreSection(TextesFiltresRecettes.degre),
        ..._curseur(
          libelle: TextesFiltresRecettes.degre,
          valeurs: widget.degres,
          pas: 0.1,
          retenu: _filtres.degre,
          aucune: TextesFiltresRecettes.aucunDegre,
          unique: TextesFiltresRecettes.degreUnique,
          plage: (i) => 'De ${TextesFiltresRecettes.plageDegre(i)}',
          enCours: TextesFiltresRecettes.plageDegre,
          lue: formatDegre,
          sans: TextesFiltresRecettes.sansDegre,
          onChanged: (i) => setState(() => _filtres = _filtres.avecDegre(i)),
          petit: petit,
        ),
        titreSection(TextesFiltresRecettes.couleur),
        ..._curseur(
          libelle: TextesFiltresRecettes.couleur,
          valeurs: widget.couleurs,
          pas: 1,
          retenu: _filtres.ebc,
          aucune: TextesFiltresRecettes.aucuneCouleur,
          unique: TextesFiltresRecettes.couleurUnique,
          plage: (i) => 'De ${TextesFiltresRecettes.plageEbc(i)}',
          enCours: TextesFiltresRecettes.plageEbc,
          lue: formatEbc,
          sans: TextesFiltresRecettes.sansCouleur,
          onChanged: (i) => setState(() => _filtres = _filtres.avecEbc(i)),
          petit: petit,
          bande: (bornes) {
            final teintes = _degrade(bornes);
            if (teintes == null) return null;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: BandeTeintes(teintes: teintes),
            );
          },
          mention: TextesCouleurEbc.mention,
        ),
        titreSection(TextesFiltresRecettes.aromes),
        TextField(
          controller: _mots,
          decoration: const InputDecoration(
            labelText: TextesFiltresRecettes.motsLabel,
            helperText: TextesFiltresRecettes.motsAide,
            helperMaxLines: 3,
          ),
          onChanged: (v) => setState(() => _filtres = _filtres.avecAromes(v)),
        ),
      ],
      pied: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (n == 0) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                TextesFiltresRecettes.aucunResultat,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (empiles) ...[
            afficher,
            const SizedBox(height: 8),
            reinitialiser,
          ] else
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              overflowAlignment: OverflowBarAlignment.end,
              children: [reinitialiser, afficher],
            ),
        ],
      ),
    );
  }

  Widget _styles() {
    final tous = widget.styles;
    final choisis = _filtres.styles;
    final limite = TextesFiltresRecettes.stylesVisibles;
    final visibles = _tousStyles || tous.length <= limite
        ? tous
        : [
            for (final (i, s) in tous.indexed)
              if (i < limite || choisis.contains(s.cle)) s,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in visibles)
              FilterChip(
                label: Text(
                  '${s.libelle ?? TextesFiltresRecettes.sansStyle} '
                  '(${s.nombre})',
                ),
                selected: choisis.contains(s.cle),
                onSelected: (oui) => setState(() {
                  final styles = {...choisis};
                  oui ? styles.add(s.cle) : styles.remove(s.cle);
                  _filtres = _filtres.avecStyles(styles);
                }),
              ),
          ],
        ),
        if (visibles.length < tous.length)
          TextButton(
            onPressed: () => setState(() => _tousStyles = true),
            child: Text(TextesFiltresRecettes.afficherStyles(tous.length)),
          ),
      ],
    );
  }

  List<Widget> _curseur({
    required String libelle,
    required List<double?> valeurs,
    required double pas,
    required Intervalle? retenu,
    required String aucune,
    required String Function(double) unique,
    required String Function(Intervalle) plage,
    required String Function(Intervalle) enCours,
    required String Function(double) lue,
    required String Function(int) sans,
    required ValueChanged<Intervalle?> onChanged,
    required TextStyle? petit,
    Widget? Function(Intervalle bornes)? bande,
    String? mention,
  }) {
    final bornes = bornesDe(valeurs);
    final curseur = curseurDe(bornes, pas);
    if (bornes == null || curseur == null) {
      // Pas de curseur : un filtre gardé reste visible et se retire ici.
      return [
        Text(bornes == null ? aucune : unique(bornes.min), style: petit),
        if (retenu != null) ...[
          const SizedBox(height: 8),
          Text(TextesFiltresRecettes.filtreEnCours(enCours(retenu))),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => onChanged(null),
              child: const Text(TextesFiltresRecettes.retirerFiltre),
            ),
          ),
        ],
      ];
    }
    final b = curseur.bornes;
    // Un filtre gardé d'une autre origine peut sortir des bornes de celle-ci.
    final debut = (retenu?.min ?? b.min).clamp(b.min, b.max);
    final fin = (retenu?.max ?? b.max).clamp(debut, b.max);
    final affiche = Intervalle(debut, fin);
    final manquantes = valeurs.where((v) => v == null).length;
    final bandeau = bande?.call(b);
    return [
      Text(plage(affiche)),
      ?bandeau,
      Semantics(
        label: libelle,
        child: RangeSlider(
          values: RangeValues(debut, fin),
          min: b.min,
          max: b.max,
          divisions: curseur.divisions,
          semanticFormatterCallback: (v) => '$libelle : ${lue(v)}',
          onChanged: (v) => onChanged(_retenu(v, b)),
        ),
      ),
      if (mention != null) Text(mention, style: petit),
      if (retenu != null && manquantes > 0)
        Text(sans(manquantes), style: petit),
    ];
  }
}
