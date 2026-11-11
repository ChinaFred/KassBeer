import 'package:brewing/brewing.dart' show normalizeName;
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../recipes/domain/beerjson.dart';

/// Référentiels de la Bibliothèque (ADR-005, L4) : styles et ingrédients écrits par
/// le script d'ingestion, lus par tout membre, jamais écrits par l'application.
///
/// Lecture typée et tolérante : un champ inconnu est ignoré ; un champ attendu
/// mal typé, ou dans une autre unité que l'unité canonique, rend l'entrée
/// illisible ([DocumentIllisible]). Aucune valeur n'est remplacée par une
/// constante.

/// Unité d'une densité dans un référentiel (`sg`).
const kUniteDensite = 'sg';

/// Unité d'une amertume dans un référentiel (`IBUs`).
const kUniteIbu = 'IBUs';

/// Nature d'un référentiel : document de `beer_index/` et collection de ses fiches.
enum NatureReferentiel {
  styles('styles', 'beer_styles'),
  fermentables('fermentables', 'beer_fermentables'),
  hops('hops', 'beer_hops'),
  cultures('cultures', 'beer_cultures'),
  miscs('miscs', 'beer_miscs');

  const NatureReferentiel(this.indexId, this.collection);

  /// Identifiant du document `beer_index/{indexId}`.
  final String indexId;

  /// Collection des fiches (`beer_hops`…).
  final String collection;
}

/// Plage chiffrée ; une borne peut manquer, jamais les deux.
@immutable
class Plage {
  const Plage({this.minimum, this.maximum})
    : assert(minimum != null || maximum != null);

  final double? minimum;
  final double? maximum;

  @override
  bool operator ==(Object other) =>
      other is Plage && other.minimum == minimum && other.maximum == maximum;

  @override
  int get hashCode => Object.hash(minimum, maximum);
}

/// Ligne de `provenance[]` : source, version, licence et date du relevé.
/// `source_id` n'est pas lu : l'écran ne l'affiche pas.
@immutable
class Provenance {
  const Provenance({
    required this.source,
    required this.version,
    required this.licence,
    required this.retrieved,
  });

  /// `brewtarget-001` à `brewtarget-005`, `diydog`.
  final String source;

  /// `v5.2.3 ea10908`, `e6c12ab`.
  final String version;

  /// `GPL-3.0`, `CC BY-SA 4.0`, `BJCP (noms et plages)`, `DIY Dog (usage privé)`.
  final String licence;

  /// Date du relevé, telle qu'écrite (`2026-11-08`).
  final String retrieved;

  factory Provenance.fromFirestore(LecteurChamps read) => Provenance(
    source: read.texte('source'),
    version: read.texte('version'),
    licence: read.texte('licence'),
    retrieved: read.texte('retrieved'),
  );
}

/// `provenance` d'un document : liste, vide si elle est absente.
List<Provenance> lireProvenance(LecteurChamps read) =>
    List.unmodifiable(read.liste('provenance').map(Provenance.fromFirestore));

/// Liste de textes [key] ; absente rend une liste vide.
List<String> _textes(LecteurChamps read, String key) {
  final value = read.data[key];
  if (value == null) return const [];
  if (value is! List) {
    throw DocumentIllisible('${read.prefix}$key', 'liste attendue');
  }
  return List.unmodifiable([
    for (var i = 0; i < value.length; i++)
      if (value[i] is String)
        value[i] as String
      else
        throw DocumentIllisible('${read.prefix}$key[$i]', 'texte attendu'),
  ]);
}

/// Code facultatif écrit en texte ou en entier (`21`, `1056`), rendu en texte.
String? _code(LecteurChamps read, String key) {
  final value = read.data[key];
  if (value == null) return null;
  if (value is int) return '$value';
  return read.texteFacultatif(key);
}

/// Plage d'un index : `[min, max]`, deux nombres finis.
Plage? _paire(LecteurChamps read, String key) {
  final value = read.data[key];
  if (value == null) return null;
  if (value is List &&
      value.length == 2 &&
      value.every((v) => v is num && v.isFinite)) {
    return Plage(
      minimum: (value[0] as num).toDouble(),
      maximum: (value[1] as num).toDouble(),
    );
  }
  throw DocumentIllisible('${read.prefix}$key', 'paire de nombres attendue');
}

/// Plage d'une fiche : `{minimum: {value, unit}, maximum: {value, unit}}` dans
/// l'unité [unit].
Plage? _plage(LecteurChamps read, String key, String unit) {
  final range = read.objetFacultatif(key);
  if (range == null) return null;
  final min = range.mesure('minimum', unit);
  final max = range.mesure('maximum', unit);
  if (min == null && max == null) {
    throw DocumentIllisible('${range.prefix}minimum', 'plage sans borne');
  }
  return Plage(minimum: min, maximum: max);
}

/// Texte de recherche : minuscules, sans accents. La recherche de la
/// Bibliothèque compare ces formes.
String normaliserRecherche(String text) {
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    buffer.write(_sansAccent[char] ?? char);
  }
  return buffer.toString();
}

/// Forme de `search_name` d'une recette publique, celle qu'écrit l'ingestion
/// (`nomDeRecherche` de `exchange/`, réservé au script) : `normalizeName` de
/// `brewing/` (minuscules, accents retirés, tout autre caractère qu'une lettre
/// ou un chiffre devenu séparateur), 100 caractères au plus, séparateurs
/// remplacés par une espace. « Punk IPA 2007 - 2010 » donne « punk ipa 2007
/// 2010 ». Vide si [text] n'a ni lettre ni chiffre.
String normaliserNomRecherche(String text) {
  var cle = normalizeName(text);
  if (cle.length > 100) {
    cle = cle.substring(0, 100).replaceAll(RegExp(r'-+$'), '');
  }
  return cle.replaceAll('-', ' ');
}

const _sansAccent = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ß': 'ss',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

// ------------------------------------------------------------------ index

/// Entrée de `beer_index/{nature}.entries[]` : nombres nus, unités implicites
/// (`%`, `EBC`).
@immutable
sealed class EntreeIndex {
  const EntreeIndex({
    required this.id,
    required this.name,
    this.aliases = const [],
  });

  /// Identifiant de la fiche dans la collection de sa nature.
  final String id;
  final String name;
  final List<String> aliases;

  /// Textes comparés par la recherche, en plus du nom et des alias.
  List<String> get autresTextes => const [];

  /// Vrai si [requete] (déjà normalisée par [normaliserRecherche]) est contenue
  /// dans le nom, un alias ou [autresTextes]. Une requête vide correspond.
  bool correspond(String requete) {
    if (requete.isEmpty) return true;
    return [
      name,
      ...aliases,
      ...autresTextes,
    ].any((t) => normaliserRecherche(t).contains(requete));
  }

  static EntreeIndex fromFirestore(
    NatureReferentiel nature,
    LecteurChamps read,
  ) {
    final id = read.texte('id');
    final name = read.texte('name');
    final aliases = _textes(read, 'aliases');
    return switch (nature) {
      NatureReferentiel.styles => EntreeStyle(
        id: id,
        name: name,
        aliases: aliases,
        code: read.texte('code'),
        category: read.texteFacultatif('category'),
        // `og`, `fg` et `ebc` ne sont pas lus : la liste ne les affiche pas, la
        // fiche lit les plages dans `beer_styles`.
        ibu: _paire(read, 'ibu'),
        abv: _paire(read, 'abv'),
      ),
      NatureReferentiel.fermentables => EntreeFermentable(
        id: id,
        name: name,
        aliases: aliases,
        labelFr: read.texteFacultatif('label_fr'),
        type: read.texteFacultatif('type'),
        yieldPct: read.nombreFacultatif('yield'),
        colorEbc: read.nombreFacultatif('color'),
      ),
      NatureReferentiel.hops => EntreeHoublon(
        id: id,
        name: name,
        aliases: aliases,
        form: read.texteFacultatif('form'),
        alphaPct: read.nombreFacultatif('alpha'),
      ),
      NatureReferentiel.cultures => EntreeLevure(
        id: id,
        name: name,
        aliases: aliases,
        producer: read.texteFacultatif('producer'),
        productId: _code(read, 'product_id'),
        type: read.texteFacultatif('type'),
        form: read.texteFacultatif('form'),
        attenuationPct: read.nombreFacultatif('attenuation'),
      ),
      NatureReferentiel.miscs => EntreeDivers(
        id: id,
        name: name,
        aliases: aliases,
        labelFr: read.texteFacultatif('label_fr'),
        type: read.texteFacultatif('type'),
      ),
    };
  }
}

class EntreeStyle extends EntreeIndex {
  const EntreeStyle({
    required super.id,
    required super.name,
    super.aliases,
    required this.code,
    this.category,
    this.ibu,
    this.abv,
  });

  /// Code BJCP (`21A`).
  final String code;
  final String? category;
  final Plage? ibu;
  final Plage? abv;

  @override
  List<String> get autresTextes => [code];
}

class EntreeFermentable extends EntreeIndex {
  const EntreeFermentable({
    required super.id,
    required super.name,
    super.aliases,
    this.labelFr,
    this.type,
    this.yieldPct,
    this.colorEbc,
  });

  final String? labelFr;

  /// Valeur BeerJSON (`grain`, `sugar`…), affichée par `typesFermentable`.
  final String? type;
  final double? yieldPct;
  final double? colorEbc;

  @override
  List<String> get autresTextes => [?labelFr];
}

class EntreeHoublon extends EntreeIndex {
  const EntreeHoublon({
    required super.id,
    required super.name,
    super.aliases,
    this.form,
    this.alphaPct,
  });

  final String? form;
  final double? alphaPct;
}

class EntreeLevure extends EntreeIndex {
  const EntreeLevure({
    required super.id,
    required super.name,
    super.aliases,
    this.producer,
    this.productId,
    this.type,
    this.form,
    this.attenuationPct,
  });

  final String? producer;
  final String? productId;
  final String? type;
  final String? form;

  /// Milieu de la plage d'atténuation, en %.
  final double? attenuationPct;

  @override
  List<String> get autresTextes => [?producer, ?productId];
}

class EntreeDivers extends EntreeIndex {
  const EntreeDivers({
    required super.id,
    required super.name,
    super.aliases,
    this.labelFr,
    this.type,
  });

  final String? labelFr;
  final String? type;

  @override
  List<String> get autresTextes => [?labelFr];
}

/// Document `beer_index/{nature}` lu : entrées lisibles, dans l'ordre du
/// document (trié par `name` à l'écriture), et nombre d'entrées illisibles.
@immutable
class IndexReferentiel {
  const IndexReferentiel({
    required this.nature,
    required this.entrees,
    this.illisibles = 0,
    this.premiereErreur,
  });

  final NatureReferentiel nature;
  final List<EntreeIndex> entrees;

  /// Entrées écartées parce qu'un champ est mal typé.
  final int illisibles;

  /// Erreur de la première entrée écartée, pour le rapport.
  final DocumentIllisible? premiereErreur;

  /// Lit le document. Sans `entries`, ou avec un `entries` qui n'est pas une
  /// liste, lève [DocumentIllisible] ; une entrée mal typée est écartée et
  /// comptée.
  factory IndexReferentiel.fromFirestore(
    NatureReferentiel nature,
    Map<String, dynamic> data,
  ) {
    final raw = data['entries'];
    if (raw is! List) {
      throw DocumentIllisible(
        'entries',
        raw == null ? 'liste obligatoire absente' : 'liste attendue',
      );
    }
    final entrees = <EntreeIndex>[];
    var illisibles = 0;
    DocumentIllisible? premiere;
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      try {
        if (item is! Map) {
          throw DocumentIllisible('entries[$i]', 'élément illisible');
        }
        entrees.add(
          EntreeIndex.fromFirestore(
            nature,
            LecteurChamps(Map<String, dynamic>.from(item), 'entries[$i].'),
          ),
        );
      } on DocumentIllisible catch (error) {
        // Compté ici, rapporté une fois pour tout l'index par le dépôt de
        // données (`library.index_entries`), avec la première erreur.
        illisibles++;
        premiere ??= error;
      }
    }
    return IndexReferentiel(
      nature: nature,
      entrees: List.unmodifiable(entrees),
      illisibles: illisibles,
      premiereErreur: premiere,
    );
  }
}

// ------------------------------------------------------------------ fiches

/// Fiche `beer_*/{id}` : valeurs complètes et provenance.
@immutable
sealed class FicheReferentiel {
  const FicheReferentiel({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.provenance = const [],
  });

  final String id;
  final String name;
  final List<String> aliases;
  final List<Provenance> provenance;

  /// Lit la fiche [id] de [nature] ; lève [DocumentIllisible].
  static FicheReferentiel fromFirestore(
    NatureReferentiel nature,
    String id,
    Map<String, dynamic> data,
  ) {
    final read = LecteurChamps(data);
    final name = read.texte('name');
    final aliases = _textes(read, 'aliases');
    final provenance = lireProvenance(read);
    return switch (nature) {
      NatureReferentiel.styles => FicheStyle(
        id: id,
        name: name,
        aliases: aliases,
        provenance: provenance,
        category: read.texteFacultatif('category'),
        categoryId: _code(read, 'category_id'),
        styleId: _code(read, 'style_id'),
        type: read.texteFacultatif('type'),
        styleGuide: read.texteFacultatif('style_guide'),
        og: _plage(read, 'original_gravity', kUniteDensite),
        fg: _plage(read, 'final_gravity', kUniteDensite),
        ibu: _plage(read, 'international_bitterness_units', kUniteIbu),
        color: _plage(read, 'color', UniteBeerJson.ebc),
        abv: _plage(read, 'alcohol_by_volume', UniteBeerJson.pourcent),
      ),
      NatureReferentiel.fermentables => FicheFermentable(
        id: id,
        name: name,
        aliases: aliases,
        provenance: provenance,
        labelFr: read.texteFacultatif('label_fr'),
        type: read.texteFacultatif('type'),
        yieldPct: read
            .objetFacultatif('yield')
            ?.mesure('fine_grind', UniteBeerJson.pourcent),
        colorEbc: read.mesure('color', UniteBeerJson.ebc),
        producer: read.texteFacultatif('producer'),
        origin: read.texteFacultatif('origin'),
      ),
      NatureReferentiel.hops => FicheHoublon(
        id: id,
        name: name,
        aliases: aliases,
        provenance: provenance,
        labelFr: read.texteFacultatif('label_fr'),
        form: read.texteFacultatif('form'),
        alphaPct: read.mesure('alpha_acid', UniteBeerJson.pourcent),
        betaPct: read.mesure('beta_acid', UniteBeerJson.pourcent),
        origin: read.texteFacultatif('origin'),
        purpose: read.texteFacultatif('purpose'),
      ),
      NatureReferentiel.cultures => FicheLevure(
        id: id,
        name: name,
        aliases: aliases,
        provenance: provenance,
        type: read.texteFacultatif('type'),
        form: read.texteFacultatif('form'),
        producer: read.texteFacultatif('producer'),
        productId: _code(read, 'product_id'),
        attenuation: _plage(read, 'attenuation', UniteBeerJson.pourcent),
        temperature: _plage(read, 'temperature_range', UniteBeerJson.celsius),
        flocculation: read.texteFacultatif('flocculation'),
      ),
      NatureReferentiel.miscs => FicheDivers(
        id: id,
        name: name,
        aliases: aliases,
        provenance: provenance,
        labelFr: read.texteFacultatif('label_fr'),
        type: read.texteFacultatif('type'),
      ),
    };
  }
}

class FicheStyle extends FicheReferentiel {
  const FicheStyle({
    required super.id,
    required super.name,
    super.aliases,
    super.provenance,
    this.category,
    this.categoryId,
    this.styleId,
    this.type,
    this.styleGuide,
    this.og,
    this.fg,
    this.ibu,
    this.color,
    this.abv,
  });

  final String? category;
  final String? categoryId;

  /// Code BJCP (`21A`).
  final String? styleId;

  /// `beer`, `cider`, `mead`…
  final String? type;
  final String? styleGuide;
  final Plage? og;
  final Plage? fg;
  final Plage? ibu;

  /// Couleur en EBC.
  final Plage? color;
  final Plage? abv;
}

class FicheFermentable extends FicheReferentiel {
  const FicheFermentable({
    required super.id,
    required super.name,
    super.aliases,
    super.provenance,
    this.labelFr,
    this.type,
    this.yieldPct,
    this.colorEbc,
    this.producer,
    this.origin,
  });

  final String? labelFr;
  final String? type;
  final double? yieldPct;
  final double? colorEbc;
  final String? producer;
  final String? origin;
}

class FicheHoublon extends FicheReferentiel {
  const FicheHoublon({
    required super.id,
    required super.name,
    super.aliases,
    super.provenance,
    this.labelFr,
    this.form,
    this.alphaPct,
    this.betaPct,
    this.origin,
    this.purpose,
  });

  final String? labelFr;
  final String? form;
  final double? alphaPct;
  final double? betaPct;
  final String? origin;

  /// `type` BeerJSON du houblon : `aroma`, `bittering`, `dual-purpose`…
  final String? purpose;
}

class FicheLevure extends FicheReferentiel {
  const FicheLevure({
    required super.id,
    required super.name,
    super.aliases,
    super.provenance,
    this.type,
    this.form,
    this.producer,
    this.productId,
    this.attenuation,
    this.temperature,
    this.flocculation,
  });

  final String? type;
  final String? form;
  final String? producer;
  final String? productId;

  /// Atténuation en %.
  final Plage? attenuation;

  /// Température de fermentation en °C.
  final Plage? temperature;
  final String? flocculation;
}

class FicheDivers extends FicheReferentiel {
  const FicheDivers({
    required super.id,
    required super.name,
    super.aliases,
    super.provenance,
    this.labelFr,
    this.type,
  });

  final String? labelFr;
  final String? type;
}
