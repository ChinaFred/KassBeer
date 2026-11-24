import 'package:flutter/foundation.dart';

import '../../library/domain/referentiel.dart' show normaliserRecherche;

/// Origine des recettes affichées par la liste : un état de l'écran, jamais
/// écrit en base.
enum OrigineRecettes {
  toutes('Toutes'),
  miennes('Les miennes'),
  autres('Autres');

  const OrigineRecettes(this.label);

  final String label;

  /// Vrai si une recette de [ownerUid] s'affiche pour le lecteur [readerUid].
  /// « Autres » : toute recette dont l'auteur n'est pas le lecteur (membre
  /// retiré et import de l'administrateur compris).
  bool contient(String ownerUid, String? readerUid) => switch (this) {
    OrigineRecettes.toutes => true,
    OrigineRecettes.miennes => ownerUid == readerUid,
    OrigineRecettes.autres => ownerUid != readerUid,
  };

  /// Les recettes illisibles s'affichent dans « Toutes » et « Autres » : leur
  /// auteur ne se lit pas.
  bool get montreIllisibles => this != OrigineRecettes.miennes;
}

/// Intervalle fermé [min, max] d'un curseur.
@immutable
class Intervalle {
  const Intervalle(this.min, this.max);

  final double min;
  final double max;

  bool contient(double value) => value >= min && value <= max;

  @override
  bool operator ==(Object other) =>
      other is Intervalle && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// Bornes des valeurs de [values] (valeurs nulles ignorées), ou `null` sans
/// aucune valeur : jamais une constante à la place des données.
Intervalle? bornesDe(Iterable<double?> values) {
  double? bas;
  double? haut;
  for (final v in values) {
    if (v == null) continue;
    if (bas == null || v < bas) bas = v;
    if (haut == null || v > haut) haut = v;
  }
  return bas == null ? null : Intervalle(bas, haut!);
}

/// [plage] ramenée dans [bornes] : une plage qui couvrait toutes les bornes
/// avant la réduction ne filtre plus (`null`) ; sinon chaque extrémité est
/// bornée, et une plage hors des bornes devient (v, v), toujours active. Sans
/// [bornes] (aucune valeur calculée), [plage] reste telle quelle.
Intervalle? ramener(Intervalle? plage, Intervalle? bornes) {
  if (plage == null || bornes == null) return plage;
  if (plage.min <= bornes.min && plage.max >= bornes.max) return null;
  final min = plage.min.clamp(bornes.min, bornes.max);
  final max = plage.max.clamp(min, bornes.max);
  return Intervalle(min, max);
}

/// Clé du groupe « Sans style ».
const kSansStyle = '';

/// Clé de comparaison d'un style : sans casse ni accents, espaces de bord
/// retirées ; [kSansStyle] pour un style absent ou vide.
String cleStyle(String? style) =>
    style == null ? kSansStyle : normaliserRecherche(style.trim());

/// Mots d'un texte « Arômes » : séparés par une virgule, sans casse ni
/// accents, vides retirés.
List<String> motsAromes(String texte) => [
  for (final m in texte.split(','))
    if (normaliserRecherche(m.trim()) case final mot when mot.isNotEmpty) mot,
];

/// Filtres de la liste des recettes : styles (« ou »), degré, couleur, mots
/// de la description aromatique, combinés en « et ». En mémoire pour la
/// session, jamais en base ni sur l'appareil.
@immutable
class FiltresRecettes {
  const FiltresRecettes({
    this.styles = const {},
    this.degre,
    this.ebc,
    this.aromes = '',
  });

  /// Clés de style ([cleStyle]) retenues ; vide : tous les styles.
  final Set<String> styles;

  /// Degré retenu (% vol) ; `null` : aucun filtre.
  final Intervalle? degre;

  /// Couleur retenue (EBC) ; `null` : aucun filtre.
  final Intervalle? ebc;

  /// Texte saisi dans « Mots de la description ».
  final String aromes;

  static const vide = FiltresRecettes();

  /// Groupes actifs, de 0 à 4 (styles, degré, couleur, arômes).
  int get groupesActifs =>
      (styles.isEmpty ? 0 : 1) +
      (degre == null ? 0 : 1) +
      (ebc == null ? 0 : 1) +
      (motsAromes(aromes).isEmpty ? 0 : 1);

  bool get actifs => groupesActifs > 0;

  FiltresRecettes avecStyles(Set<String> styles) =>
      FiltresRecettes(styles: styles, degre: degre, ebc: ebc, aromes: aromes);

  /// [degre] nul retire le filtre du degré.
  FiltresRecettes avecDegre(Intervalle? degre) =>
      FiltresRecettes(styles: styles, degre: degre, ebc: ebc, aromes: aromes);

  /// [ebc] nul retire le filtre de la couleur.
  FiltresRecettes avecEbc(Intervalle? ebc) =>
      FiltresRecettes(styles: styles, degre: degre, ebc: ebc, aromes: aromes);

  FiltresRecettes avecAromes(String aromes) =>
      FiltresRecettes(styles: styles, degre: degre, ebc: ebc, aromes: aromes);

  /// Filtres dont le degré et la couleur sont ramenés ([ramener]) dans les
  /// bornes d'une origine : la boîte et les puces montrent alors la même plage.
  FiltresRecettes dansLesBornes({Intervalle? degres, Intervalle? couleurs}) =>
      FiltresRecettes(
        styles: styles,
        degre: ramener(degre, degres),
        ebc: ramener(ebc, couleurs),
        aromes: aromes,
      );

  /// Mots du texte « Arômes » tels que saisis (sans espaces de bord), pour
  /// les puces des filtres actifs.
  List<String> get motsSaisis => [
    for (final m in aromes.split(','))
      if (m.trim().isNotEmpty && motsAromes(m).isNotEmpty) m.trim(),
  ];

  /// Filtres sans le mot saisi [mot] (une occurrence).
  FiltresRecettes sansMot(String mot) {
    final mots = [...motsSaisis]..remove(mot);
    return avecAromes(mots.join(', '));
  }

  /// Vrai si une recette de style [style], de degré [degre] et de couleur
  /// [ebc] calculés, de description [description], passe ces filtres. Un
  /// degré ou une couleur absents excluent la recette dès que leur filtre est
  /// actif.
  bool accepte({
    required String? style,
    required double? degre,
    required double? ebc,
    required String? description,
  }) {
    if (styles.isNotEmpty && !styles.contains(cleStyle(style))) return false;
    final d = this.degre;
    if (d != null && (degre == null || !d.contient(degre))) return false;
    final e = this.ebc;
    if (e != null && (ebc == null || !e.contient(ebc))) return false;
    final mots = motsAromes(aromes);
    if (mots.isNotEmpty) {
      if (description == null) return false;
      final texte = normaliserRecherche(description);
      if (!mots.every(texte.contains)) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is FiltresRecettes &&
      setEquals(other.styles, styles) &&
      other.degre == degre &&
      other.ebc == ebc &&
      other.aromes == aromes;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(styles), degre, ebc, aromes);
}

/// Vrai si [query] (déjà en minuscules et sans espaces de bord) est vide, ou
/// contenu dans le nom ou le style : recherche de la liste.
bool correspondRecherche(String query, String name, String? style) =>
    query.isEmpty ||
    name.toLowerCase().contains(query) ||
    (style?.toLowerCase().contains(query) ?? false);

/// Style proposé par la boîte de filtres : clé, libellé et nombre de recettes.
@immutable
class StyleCompte {
  const StyleCompte(this.cle, this.libelle, this.nombre);

  /// [kSansStyle] pour « Sans style ».
  final String cle;

  /// Graphie de la première recette rencontrée ; `null` pour « Sans style ».
  final String? libelle;
  final int nombre;
}

/// Styles de [styles] regroupés par [cleStyle], du plus fréquent au moins
/// fréquent, puis par libellé ; « Sans style » en dernier.
List<StyleCompte> stylesComptes(Iterable<String?> styles) {
  final libelles = <String, String>{};
  final nombres = <String, int>{};
  for (final s in styles) {
    final cle = cleStyle(s);
    if (cle != kSansStyle) libelles.putIfAbsent(cle, () => s!.trim());
    nombres[cle] = (nombres[cle] ?? 0) + 1;
  }
  final avec =
      [
        for (final MapEntry(:key, :value) in nombres.entries)
          if (key != kSansStyle) StyleCompte(key, libelles[key], value),
      ]..sort((a, b) {
        final n = b.nombre.compareTo(a.nombre);
        return n != 0 ? n : a.cle.compareTo(b.cle);
      });
  return [
    ...avec,
    if (nombres[kSansStyle] case final n?) StyleCompte(kSansStyle, null, n),
  ];
}
