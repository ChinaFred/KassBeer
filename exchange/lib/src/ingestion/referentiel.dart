import '../bornes.dart';
import '../texte.dart';
import 'cles.dart';
import 'fusions.dart';
import 'lecture_sources.dart';
import 'origines.dart';
import 'sources.dart';

/// Fusion des entrées des sources en documents de référentiel, et recherche
/// d'un nom (spécification de L3 : « Identifiants » ; `DATA_SOURCES.md`,
/// décision 4). Deux entrées de même clé fusionnent : la plus prioritaire
/// donne les valeurs, chaque entrée ajoute sa ligne de `provenance[]` et son
/// nom aux `aliases`. Les tables de fusion (`fusions.dart`) rattachent en
/// plus des entrées de noms différents à un même document de houblon
/// (ADR-014) ou de culture.
/// `cleProducteur` et `cleProduit` vivent dans `noms.dart`, partagés avec la
/// résolution d'un import.

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

  /// Noms ajoutés par la table d'alias et par la table de fusion.
  final Set<String> aliasAjoutes = {};

  /// Noms écartés des `aliases` par [AliasEcarteCulture].
  final Set<String> aliasEcartes = {};

  /// Ligne de la table de fusion qui nomme ce document, ou `null`.
  Fusion? ligne;

  /// Libellé français, posé par la table d'alias.
  String? labelFr;

  /// Entrée qui donne les valeurs.
  EntreeBrute get principale => entrees.first;

  /// Nature.
  NatureReferentiel get nature => principale.nature;

  /// Nom du document : celui de sa ligne de fusion, sinon celui de l'entrée
  /// qui donne les valeurs.
  String get nom => ligne?.nom ?? principale.nom;

  /// Autres noms : ceux des entrées fusionnées, puis ceux des tables d'alias
  /// et de fusion, sans le nom du document ni les noms écartés par la ligne de
  /// fusion, triés.
  List<String> get aliases {
    final ecartes = {
      for (final n in ligne?.ecartes ?? const <String>[]) cleNormalisee(n),
      for (final n in aliasEcartes) cleNormalisee(n),
    };
    final noms = {for (final e in entrees) e.nom, ...aliasAjoutes}
      ..remove(nom)
      ..removeWhere((n) => ecartes.contains(cleNormalisee(n)));
    return noms.toList()..sort();
  }

  /// Valeurs du document : celles de l'entrée principale, origine imposée par
  /// la ligne de fusion, et nom français du pays (`origin_fr`) quand le
  /// document a une origine.
  Map<String, Object> get _valeurs {
    final origine = ligne?.origine ?? principale.valeurs['origin'] as String?;
    return {
      ...principale.valeurs,
      if (origine != null) ...{
        'origin': origine,
        'origin_fr': paysEnFrancais(origine),
      },
    };
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
      ..._valeurs,
      'provenance': lignes,
    };
  }

  /// Entrée de `beer_index/{nature}` : nombres nus ; pour un houblon, usage
  /// (`purpose`), origine (`origin`) et son nom français (`origin_fr`) du
  /// document quand il les a.
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
          'purpose': ?v['purpose'],
          // Origine du document, celle de la ligne de fusion comprise.
          'origin': ?_valeurs['origin'],
          'origin_fr': ?_valeurs['origin_fr'],
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
  /// Une entrée désignée par une ligne de [fusions] rejoint le document de
  /// cette ligne (`hop-<clé du nom de la ligne>`). Une ligne qui ne désigne
  /// aucune entrée, une ligne sans entrée (alias seul) dont le document n'est
  /// pas lu, une entrée désignée par deux lignes ou deux lignes de même
  /// identifiant lèvent [StateError] : la table est fausse.
  ///
  /// Une ligne de [fusionsCultures] rattache la fiche d'un fabricant et les
  /// entrées Brewtarget qu'elle désigne au document de cette ligne
  /// ([FusionCulture.id]) ; la fiche, prioritaire, donne les valeurs et le
  /// nom. Une ligne dont la fiche ou les entrées Brewtarget sont absentes,
  /// une entrée désignée par deux lignes, deux lignes de même identifiant, ou
  /// une entrée Brewtarget dont l'identifiant (celui de sa souche si elle
  /// porte producteur et référence) diffère de celui de la ligne lèvent
  /// [StateError].
  ///
  /// Une culture qui porte un producteur et une référence se regroupe d'abord
  /// avec celles de même producteur et de même référence : c'est la même
  /// souche, quel que soit le nom écrit (`SafAle S-04` et `SafAle English
  /// Ale`). Son identifiant prend le nom de l'entrée la plus prioritaire,
  /// hors fiches des fabricants : une souche déjà connue de Brewtarget garde
  /// l'identifiant de son document, et `ingest/ecrire.mjs`, qui n'efface
  /// rien, ne laisse pas d'ancien document à côté du nouveau. Une souche que
  /// seule une fiche connaît prend l'identifiant de la fiche.
  ///
  /// [correctionsCultures] corrige d'abord les cultures de Brewtarget
  /// (référence, nom de gamme), réunit une souche sans référence sous deux
  /// noms, puis écarte des alias ([CorrectionCulture]).
  factory Referentiel.fusionner(
    List<EntreeBrute> lues, {
    List<Fusion> fusions = const [],
    List<FusionCulture> fusionsCultures = const [],
    List<CorrectionCulture> correctionsCultures = const [],
  }) {
    final entrees = _corriger(lues, correctionsCultures);
    final lignes = <String, Fusion>{};
    final ligneDe = <int, Fusion>{};
    for (final f in fusions) {
      if (lignes.containsKey(f.id)) {
        throw StateError('fusion en double : ${f.id}');
      }
      lignes[f.id] = f;
      for (final d in f.entrees) {
        var trouvees = 0;
        for (var i = 0; i < entrees.length; i++) {
          if (!d.designe(entrees[i])) continue;
          final deja = ligneDe[i];
          if (deja != null && deja.id != f.id) {
            throw StateError('$d désignée par ${deja.id} et ${f.id}');
          }
          ligneDe[i] = f;
          trouvees++;
        }
        if (trouvees == 0) {
          throw StateError('fusion ${f.id} : aucune entrée $d');
        }
      }
    }
    final idsCultures = <String>{};
    final ligneCultureDe = <int, FusionCulture>{};
    for (final f in fusionsCultures) {
      if (!idsCultures.add(f.id)) {
        throw StateError('fusion de culture en double : ${f.id}');
      }
      var fiches = 0;
      var brewtarget = 0;
      for (var i = 0; i < entrees.length; i++) {
        final fiche = f.designeFiche(entrees[i]);
        if (!fiche && !f.designeBrewtarget(entrees[i])) continue;
        final deja = ligneCultureDe[i];
        if (deja != null) {
          throw StateError(
            '${entrees[i].source.id} « ${entrees[i].nom} » désignée par '
            '$deja et $f',
          );
        }
        ligneCultureDe[i] = f;
        fiche ? fiches++ : brewtarget++;
      }
      if (fiches == 0) {
        throw StateError('fusion ${f.id} : aucune fiche $f');
      }
      if (brewtarget == 0) {
        throw StateError('fusion ${f.id} : aucune entrée Brewtarget $f');
      }
    }

    int ordre((int, EntreeBrute) a, (int, EntreeBrute) b) {
      final rang = a.$2.source.rang.compareTo(b.$2.source.rang);
      return rang != 0 ? rang : a.$1.compareTo(b.$1);
    }

    int ordreIdentifiant((int, EntreeBrute) a, (int, EntreeBrute) b) {
      final fa = a.$2.source == Source.fabricants ? 1 : 0;
      final fb = b.$2.source == Source.fabricants ? 1 : 0;
      return fa != fb ? fa.compareTo(fb) : ordre(a, b);
    }

    final souches = <String, List<(int, EntreeBrute)>>{};
    for (var i = 0; i < entrees.length; i++) {
      final cle = _cleSouche(entrees[i]);
      if (cle != null) souches.putIfAbsent(cle, () => []).add((i, entrees[i]));
    }
    final idSouche = <String, String>{};
    for (final MapEntry(:key, :value) in souches.entries) {
      idSouche[key] = idDe((value..sort(ordreIdentifiant)).first.$2);
    }
    // Une souche sans référence sous deux noms : un document, à l'identifiant
    // de la première entrée dans l'ordre des identifiants.
    final idMemeSouche = <int, String>{};
    for (final c in correctionsCultures.whereType<MemeSoucheCulture>()) {
      final groupe = [
        for (var i = 0; i < entrees.length; i++)
          if (c.designe(entrees[i])) (i, entrees[i]),
      ];
      final noms = groupe.where((g) => c.designeNom(g.$2)).length;
      if (noms == 0 || noms == groupe.length) {
        throw StateError('correction $c : les deux noms ne sont pas lus');
      }
      final id = idDe((groupe..sort(ordreIdentifiant)).first.$2);
      for (final (i, e) in groupe) {
        if (idMemeSouche.containsKey(i) || ligneCultureDe.containsKey(i)) {
          throw StateError('${e.source.id} « ${e.nom} » désignée deux fois');
        }
        idMemeSouche[i] = id;
      }
    }
    // Une entrée Brewtarget désignée par une ligne de culture garde son
    // identifiant : sinon la ligne créerait un document à côté de l'ancien.
    for (final MapEntry(key: i, value: f) in ligneCultureDe.entries) {
      final e = entrees[i];
      if (e.source == Source.fabricants) continue;
      final souche = _cleSouche(e);
      final naturel = souche == null ? idDe(e) : idSouche[souche]!;
      if (naturel != f.id) {
        throw StateError(
          'fusion ${f.id} : ${e.source.id} « ${e.nom} » a pour identifiant '
          '$naturel',
        );
      }
    }
    final groupes = <String, List<(int, EntreeBrute)>>{};
    for (var i = 0; i < entrees.length; i++) {
      final souche = _cleSouche(entrees[i]);
      final id =
          ligneDe[i]?.id ??
          ligneCultureDe[i]?.id ??
          idMemeSouche[i] ??
          (souche == null ? idDe(entrees[i]) : idSouche[souche]!);
      groupes.putIfAbsent(id, () => []).add((i, entrees[i]));
    }
    final parNature = {
      for (final n in NatureReferentiel.values) n: <String, EntreeFusionnee>{},
    };
    for (final MapEntry(key: id, value: groupe) in groupes.entries) {
      groupe.sort(ordre);
      final fusion = EntreeFusionnee._(id, [for (final (_, e) in groupe) e]);
      final ligne = lignes[id];
      if (ligne != null && fusion.nature == NatureReferentiel.hop) {
        fusion.ligne = ligne;
        fusion.aliasAjoutes.addAll(ligne.alias);
      }
      parNature[fusion.nature]![id] = fusion;
    }
    // Une ligne sans entrée n'ajoute que ses alias : son document doit être lu.
    for (final f in fusions) {
      if (!parNature[NatureReferentiel.hop]!.containsKey(f.id)) {
        throw StateError('fusion ${f.id} : aucun document de ce nom');
      }
    }
    for (final c in correctionsCultures.whereType<AliasEcarteCulture>()) {
      final docs = [
        for (final f in parNature[NatureReferentiel.culture]!.values)
          if (f.entrees.any((e) => _cleSouche(e) == c.cleSouche)) f,
      ];
      if (docs.length != 1 ||
          !docs.single.aliases.any(
            (n) => cleNormalisee(n) == cleNormalisee(c.alias),
          )) {
        throw StateError('correction $c : aucun document qui porte cet alias');
      }
      docs.single.aliasEcartes.add(c.alias);
    }
    return Referentiel._(parNature);
  }

  /// Entrées [lues] corrigées par les lignes [ReferenceCulture] et
  /// [GammeCulture] de [corrections].
  static List<EntreeBrute> _corriger(
    List<EntreeBrute> lues,
    List<CorrectionCulture> corrections,
  ) {
    final entrees = [...lues];
    final corrigees = <int, CorrectionCulture>{};
    for (final c in corrections) {
      var trouvees = 0;
      for (var i = 0; i < entrees.length; i++) {
        final e = entrees[i];
        final EntreeBrute? nouvelle = switch (c) {
          ReferenceCulture() when c.designe(lues[i]) => e.corrigee(
            produit: c.retenue,
          ),
          GammeCulture() when c.designe(lues[i]) => e.corrigee(
            nom: couper('${c.nom} ${e.produit}', kMaxNom),
          ),
          _ => null,
        };
        if (nouvelle == null) continue;
        final deja = corrigees[i];
        if (deja != null) {
          throw StateError(
            '${e.source.id} « ${e.nom} » corrigée par $deja et $c',
          );
        }
        corrigees[i] = c;
        entrees[i] = nouvelle;
        trouvees++;
      }
      if (trouvees == 0 &&
          c is! AliasEcarteCulture &&
          c is! MemeSoucheCulture) {
        throw StateError('correction $c : aucune entrée');
      }
    }
    return entrees;
  }

  Referentiel._(this.parNature) {
    for (final MapEntry(key: nature, value: entrees) in parNature.entries) {
      final parNom = <String, Set<String>>{};
      for (final f in entrees.values) {
        for (final n in [f.nom, ...f.aliases]) {
          parNom.putIfAbsent(cleNormalisee(n), () => {}).add(f.id);
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

  /// Noms normalisés de [nature] (nom du document et alias, table d'alias
  /// comprise) portés par plusieurs documents, et leurs identifiants triés.
  Map<String, List<String>> nomsPartages(NatureReferentiel nature) {
    final parNom = <String, Set<String>>{};
    for (final f in parNature[nature]!.values) {
      for (final n in [f.nom, ...f.aliases]) {
        parNom.putIfAbsent(cleNormalisee(n), () => {}).add(f.id);
      }
    }
    return {
      for (final MapEntry(:key, :value) in parNom.entries)
        if (value.length > 1) key: value.toList()..sort(),
    };
  }

  /// Noms partagés des cultures ([nomsPartages]) dont deux documents au
  /// moins ont le même producteur (`cleProducteur`), et leurs identifiants
  /// triés (P56 : doublons hérités de Brewtarget).
  Map<String, List<String>> doublonsMemeProducteur() {
    final cultures = parNature[NatureReferentiel.culture]!;
    return {
      for (final MapEntry(:key, :value) in nomsPartages(
        NatureReferentiel.culture,
      ).entries)
        if (_memeProducteur([
          for (final id in value) cultures[id]!.principale.producteur,
        ]))
          key: value,
    };
  }

  /// Vrai si deux producteurs de [producteurs] ont la même clé ; un document
  /// sans producteur n'est rapproché d'aucun.
  static bool _memeProducteur(List<String?> producteurs) {
    final vus = <String>{};
    for (final p in producteurs) {
      if (p != null && !vus.add(cleProducteur(p))) return true;
    }
    return false;
  }

  /// Nombre de fusions de [nature] : entrées lues moins documents.
  int fusions(NatureReferentiel nature) {
    final docs = parNature[nature]!;
    final lues = docs.values.fold(0, (n, f) => n + f.entrees.length);
    return lues - docs.length;
  }
}
