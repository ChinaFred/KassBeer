import 'alias.dart';
import 'cles.dart';
import 'lecture_sources.dart';

/// Fusion des entrées des sources en documents de référentiel, et recherche
/// d'un nom (spécification de L3 : « Identifiants » ; `DATA_SOURCES.md`,
/// décision 4). Deux entrées de même clé fusionnent : la plus prioritaire
/// donne les valeurs, chaque entrée ajoute sa ligne de `provenance[]` et son
/// nom aux `aliases`.

/// Clé d'un producteur de levure, après [kProducteursEquivalents].
String cleProducteur(String producteur) {
  final cle = cleNormalisee(producteur);
  return kProducteursEquivalents[cle] ?? cle;
}

/// Clé d'une référence de levure chez son producteur : normalisée, sans
/// tiret (`W-34/70` et `W34/70` donnent `w3470`). Wyeast écrit `WY1056` ou
/// `1056` : le `wy` est retiré. White Labs écrit `WLP001` ou `001` : le `wlp`
/// est ajouté.
String cleProduit(String cleDuProducteur, String produit) {
  final cle = cleNormalisee(produit).replaceAll('-', '');
  if (cleDuProducteur == 'wyeast' && RegExp(r'^wy\d+$').hasMatch(cle)) {
    return cle.substring(2);
  }
  if (cleDuProducteur == 'white-labs' && RegExp(r'^\d+$').hasMatch(cle)) {
    return 'wlp$cle';
  }
  return cle;
}

/// Clé d'une culture : producteur, référence et nom, quand ils existent
/// (`wyeast-1056-american-ale`). Le producteur et la référence répétés en tête
/// du nom (`WLP001 - California Ale Yeast`) et le mot `yeast` en fin de nom
/// sont retirés du nom, pour qu'une même souche écrite de deux façons ne donne
/// qu'une clé. Le nom du document reste celui de la source.
String cleCulture(String nom, String? producteur, String? produit) {
  final p = producteur == null ? '' : cleProducteur(producteur);
  final r = produit == null ? '' : cleProduit(p, produit);
  var segments = cleNormalisee(nom).split('-');
  final origine = segments;
  if (p.isNotEmpty) {
    final ps = p.split('-');
    if (segments.length > ps.length &&
        segments.take(ps.length).join('-') == p) {
      segments = segments.sublist(ps.length);
    }
  }
  if (r.isNotEmpty) {
    for (var n = 1; n <= 4 && n < segments.length; n++) {
      if (segments.take(n).join() == r) {
        segments = segments.sublist(n);
        break;
      }
    }
  }
  if (segments.length > 1 && segments.last == 'yeast') {
    segments = segments.sublist(0, segments.length - 1);
  }
  if (segments.isEmpty || segments.join().isEmpty) segments = origine;
  return cleNormalisee(
    [p, r, ...segments].where((s) => s.isNotEmpty).join('-'),
  );
}

/// Identifiant d'une entrée lue.
String idDe(EntreeBrute e) => idEntree(
  e.nature,
  e.nature == NatureReferentiel.culture
      ? cleCulture(e.nom, e.producteur, e.produit)
      : cleNormalisee(e.nom),
);

/// Clé de souche d'une culture qui porte un producteur et une référence, ou
/// `null`.
String? _cleSouche(EntreeBrute e) {
  final p = e.producteur;
  final r = e.produit;
  if (e.nature != NatureReferentiel.culture || p == null || r == null) {
    return null;
  }
  final cp = cleProducteur(p);
  final cr = cleProduit(cp, r);
  return cp.isEmpty || cr.isEmpty ? null : '$cp|$cr';
}

/// Entrée fusionnée : un document de référentiel.
class EntreeFusionnee {
  EntreeFusionnee._(this.id, this.entrees);

  /// Identifiant du document.
  final String id;

  /// Entrées fusionnées, la plus prioritaire en tête.
  final List<EntreeBrute> entrees;

  /// Noms ajoutés par la table d'alias.
  final Set<String> aliasAjoutes = {};

  /// Libellé français, posé par la table d'alias.
  String? labelFr;

  /// Entrée qui donne les valeurs.
  EntreeBrute get principale => entrees.first;

  /// Nature.
  NatureReferentiel get nature => principale.nature;

  /// Nom du document.
  String get nom => principale.nom;

  /// Autres noms : ceux des entrées fusionnées, puis ceux de la table d'alias,
  /// sans le nom du document, triés.
  List<String> get aliases {
    final noms = {for (final e in entrees.skip(1)) e.nom, ...aliasAjoutes}
      ..remove(nom);
    return noms.toList()..sort();
  }

  /// Document sans `content_sha256` ni `updated_at`.
  Map<String, Object?> document() {
    final lignes = <Map<String, Object>>[];
    final vues = <String>{};
    for (final e in entrees) {
      final ligne = e.provenanceLigne;
      if (vues.add('${ligne['source']}|${ligne['source_id']}')) {
        lignes.add(ligne);
      }
    }
    return {
      'name': nom,
      'aliases': aliases,
      if (labelFr != null && nature != NatureReferentiel.culture)
        'label_fr': labelFr,
      ...principale.valeurs,
      'provenance': lignes,
    };
  }

  /// Entrée de `beer_index/{nature}` : nombres nus.
  Map<String, Object?> entreeIndex() {
    final v = principale.valeurs;
    final a = aliases;
    double? nombre(Object? couple) =>
        couple is Map ? (couple['value'] as num?)?.toDouble() : null;
    return {
      'id': id,
      'name': nom,
      if (a.isNotEmpty) 'aliases': a,
      ...switch (nature) {
        NatureReferentiel.fermentable => {
          if (labelFr != null) 'label_fr': labelFr,
          'type': ?v['type'],
          'yield': ?nombre((v['yield'] as Map?)?['fine_grind']),
          'color': ?nombre(v['color']),
        },
        NatureReferentiel.hop => {
          'form': ?v['form'],
          'alpha': ?nombre(v['alpha_acid']),
        },
        NatureReferentiel.culture => {
          'producer': ?v['producer'],
          'product_id': ?v['product_id'],
          'type': ?v['type'],
          'form': ?v['form'],
          'attenuation': ?milieuDePlage(v['attenuation']),
        },
        NatureReferentiel.misc => {
          if (labelFr != null) 'label_fr': labelFr,
          'type': ?v['type'],
        },
      },
    };
  }
}

/// Milieu d'une plage `{minimum, maximum}`, arrondi au dixième, ou `null`.
double? milieuDePlage(Object? plage) {
  if (plage is! Map) return null;
  final min = (plage['minimum'] as Map?)?['value'] as num?;
  final max = (plage['maximum'] as Map?)?['value'] as num?;
  if (min == null || max == null) return null;
  return ((min + max) / 2 * 10).roundToDouble() / 10;
}

/// Référentiels fusionnés et index de recherche.
class Referentiel {
  /// Fusionne [entrees] (dans l'ordre de lecture) : par identifiant, la plus
  /// prioritaire ([Source.rang]) en tête, puis l'ordre de lecture.
  ///
  /// Une culture qui porte un producteur et une référence se regroupe d'abord
  /// avec celles de même producteur et de même référence : c'est la même
  /// souche, quel que soit le nom écrit (`SafAle S-04` et `SafAle English
  /// Ale`). Son identifiant prend le nom de l'entrée la plus prioritaire.
  factory Referentiel.fusionner(List<EntreeBrute> entrees) {
    int ordre((int, EntreeBrute) a, (int, EntreeBrute) b) {
      final rang = a.$2.source.rang.compareTo(b.$2.source.rang);
      return rang != 0 ? rang : a.$1.compareTo(b.$1);
    }

    final souches = <String, List<(int, EntreeBrute)>>{};
    for (var i = 0; i < entrees.length; i++) {
      final cle = _cleSouche(entrees[i]);
      if (cle != null) souches.putIfAbsent(cle, () => []).add((i, entrees[i]));
    }
    final idSouche = <String, String>{};
    for (final MapEntry(:key, :value) in souches.entries) {
      idSouche[key] = idDe((value..sort(ordre)).first.$2);
    }
    final groupes = <String, List<(int, EntreeBrute)>>{};
    for (var i = 0; i < entrees.length; i++) {
      final souche = _cleSouche(entrees[i]);
      final id = souche == null ? idDe(entrees[i]) : idSouche[souche]!;
      groupes.putIfAbsent(id, () => []).add((i, entrees[i]));
    }
    final parNature = {
      for (final n in NatureReferentiel.values) n: <String, EntreeFusionnee>{},
    };
    for (final MapEntry(key: id, value: groupe) in groupes.entries) {
      groupe.sort(ordre);
      final fusion = EntreeFusionnee._(id, [for (final (_, e) in groupe) e]);
      parNature[fusion.nature]![id] = fusion;
    }
    return Referentiel._(parNature);
  }

  Referentiel._(this.parNature) {
    for (final MapEntry(key: nature, value: entrees) in parNature.entries) {
      final parNom = <String, Set<String>>{};
      for (final f in entrees.values) {
        for (final e in f.entrees) {
          parNom.putIfAbsent(cleNormalisee(e.nom), () => {}).add(f.id);
        }
        if (nature == NatureReferentiel.culture) {
          for (final e in f.entrees) {
            final p = e.producteur;
            final r = e.produit;
            if (p == null || r == null) continue;
            final cp = cleProducteur(p);
            final cle = '$cp|${cleProduit(cp, r)}';
            final ids = _parSouche.putIfAbsent(cle, () => []);
            if (!ids.contains(f.id)) ids.add(f.id);
          }
        }
      }
      _parNom[nature] = parNom;
    }
  }

  /// Documents par nature, par identifiant.
  final Map<NatureReferentiel, Map<String, EntreeFusionnee>> parNature;

  final Map<NatureReferentiel, Map<String, Set<String>>> _parNom = {};

  final Map<String, List<String>> _parSouche = {};

  /// Entrée d'identifiant [id], ou `null`.
  EntreeFusionnee? entree(String id) {
    for (final entrees in parNature.values) {
      final e = entrees[id];
      if (e != null) return e;
    }
    return null;
  }

  /// Identifiant de l'entrée de [nature] dont un nom (nom du document ou nom
  /// fusionné) a la clé normalisée de [nom], ou dont l'identifiant est
  /// `<nature>-<clé de nom>` ; `null` si aucune ou plusieurs.
  String? parNomExact(NatureReferentiel nature, String nom) {
    final cle = cleNormalisee(nom);
    if (cle.isEmpty) return null;
    final direct = idEntree(nature, cle);
    if (parNature[nature]!.containsKey(direct)) return direct;
    final ids = _parNom[nature]![cle];
    return ids != null && ids.length == 1 ? ids.single : null;
  }

  /// Identifiant de la culture de [producteur] et de référence [produit] :
  /// la plus prioritaire si plusieurs entrées non fusionnées la portent (même
  /// souche, noms écrits autrement) ; `null` si aucune.
  String? parSouche(String producteur, String produit) {
    final cp = cleProducteur(producteur);
    final ids = _parSouche['$cp|${cleProduit(cp, produit)}'];
    if (ids == null || ids.isEmpty) return null;
    final cultures = parNature[NatureReferentiel.culture]!;
    var meilleur = ids.first;
    for (final id in ids.skip(1)) {
      if (cultures[id]!.principale.source.rang <
          cultures[meilleur]!.principale.source.rang) {
        meilleur = id;
      }
    }
    return meilleur;
  }

  /// Nombre de fusions de [nature] : entrées lues moins documents.
  int fusions(NatureReferentiel nature) {
    final docs = parNature[nature]!;
    final lues = docs.values.fold(0, (n, f) => n + f.entrees.length);
    return lues - docs.length;
  }
}
