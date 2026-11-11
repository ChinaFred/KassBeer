import '../../../core/presentation/formats.dart';
import '../../recipes/domain/beerjson.dart';
import '../domain/referentiel.dart';

/// Libellés de la Bibliothèque. Affichage seulement : aucune conversion d'unité,
/// les valeurs sont déjà en unités canoniques (CLAUDE.md, P3).

/// Plage : « 1044,0 à 1052,0 », « à partir de 20 IBU », « jusqu'à 8 EBC ».
String? formatPlage(Plage? plage, String Function(double) format) {
  if (plage == null) return null;
  final min = plage.minimum;
  final max = plage.maximum;
  if (min != null && max != null) return '${format(min)} à ${format(max)}';
  if (min != null) return 'à partir de ${format(min)}';
  return 'jusqu\'à ${format(max!)}';
}

/// Nom court d'une source de `provenance[]` : « Brewtarget », « DIY Dog ».
/// Le fichier et le commit restent dans « Sources des données ». Une source
/// inconnue s'affiche telle quelle.
String libelleSource(String source) {
  if (RegExp(r'^brewtarget-\d{3}$').hasMatch(source)) return 'Brewtarget';
  if (source == 'diydog') return 'DIY Dog';
  return source;
}

/// Numéro de version d'une source (`v5.2.3 ea10908` donne `5.2.3`), ou `null`
/// quand la version n'est qu'un commit (`e6c12ab`).
String? versionCourte(String version) =>
    RegExp(r'^v?(\d+(?:\.\d+)+)\b').firstMatch(version.trim())?.group(1);

/// Date d'un relevé (`2026-11-08`) : « 8 novembre 2026 » ; telle quelle si elle
/// n'est pas une date.
String libelleReleve(String retrieved) {
  final date = DateTime.tryParse(retrieved);
  return date == null ? retrieved : formatDateLongue(date);
}

/// Ligne de provenance d'une fiche : « Brewtarget 5.2.3 · licence GPL-3.0 ·
/// relevé le 8 novembre 2026 ».
String ligneProvenance(Provenance p) {
  final version = versionCourte(p.version);
  final source = libelleSource(p.source);
  return [
    version == null ? source : '$source $version',
    'licence ${p.licence}',
    'relevé le ${libelleReleve(p.retrieved)}',
  ].join(' · ');
}

/// Lignes de provenance d'une fiche, sans doublon : deux fichiers de
/// Brewtarget sous la même licence donnent la même ligne.
List<String> lignesProvenance(List<Provenance> provenance) =>
    List.unmodifiable({for (final p in provenance) ligneProvenance(p)});

/// Type d'un style (`type` BeerJSON). Une valeur inconnue s'affiche telle
/// quelle.
String libelleTypeStyle(String type) => switch (type) {
  'beer' => 'Bière',
  'cider' => 'Cidre',
  'mead' => 'Hydromel',
  'kombucha' => 'Kombucha',
  'soda' => 'Soda',
  'wine' => 'Vin',
  'other' => 'Autre',
  _ => type,
};

/// Moment d'origine d'un houblon (`source_hop_timing[].label`), traduit, avec
/// la valeur de la source entre parenthèses : « début d'ébullition (start) ».
/// La casse ne compte pas ; une valeur inconnue s'affiche telle quelle.
String libelleMomentOrigine(String label) {
  final traduit = switch (label.trim().toLowerCase()) {
    'start' => 'début d\'ébullition',
    'middle' => 'milieu d\'ébullition',
    'end' => 'fin d\'ébullition',
    'dry hop' => 'houblonnage à cru',
    'whirlpool' => 'whirlpool',
    _ => null,
  };
  return traduit == null ? label : '$traduit ($label)';
}

/// Usage d'un houblon (`type` BeerJSON, `purpose` en base).
String libelleUsageHoublon(String purpose) => switch (purpose) {
  'aroma' => 'Aromatique',
  'bittering' => 'Amérisant',
  'dual-purpose' => 'Double usage',
  'aroma/bittering' => 'Aromatique et amérisant',
  'flavor' => 'Goût',
  _ => purpose,
};

/// Floculation d'une levure.
String libelleFloculation(String value) => switch (value) {
  'very low' => 'Très faible',
  'low' => 'Faible',
  'medium low' => 'Moyenne à faible',
  'medium' => 'Moyenne',
  'medium high' => 'Moyenne à forte',
  'high' => 'Forte',
  'very high' => 'Très forte',
  _ => value,
};

/// Producteur et référence d'une levure : « Wyeast 1056 ».
String? producteurLevure(String? producer, String? productId) {
  final parts = [?producer, ?productId];
  return parts.isEmpty ? null : parts.join(' ');
}

/// Titre d'une entrée d'index : « 21A · American IPA » pour un style, le nom
/// sinon.
String titreEntree(EntreeIndex e) =>
    e is EntreeStyle ? '${e.code} · ${e.name}' : e.name;

/// Détails d'une entrée d'index, sous son titre dans la liste.
List<String> detailsEntree(EntreeIndex e) => switch (e) {
  EntreeStyle(:final category, :final abv, :final ibu) => [
    ?category,
    ?formatPlage(abv, formatDegre),
    ?formatPlage(ibu, formatIbu),
  ],
  EntreeFermentable(
    :final labelFr,
    :final type,
    :final colorEbc,
    :final yieldPct,
  ) =>
    [
      ?labelFr,
      if (type != null) typesFermentable.libelle(type),
      if (colorEbc != null) formatEbc(colorEbc),
      if (yieldPct != null) 'rendement ${formatPourcent(yieldPct)}',
    ],
  EntreeHoublon(:final form, :final alphaPct) => [
    if (form != null) formesHoublon.libelle(form),
    if (alphaPct != null) '${formatPourcent(alphaPct)} alpha',
  ],
  EntreeLevure(
    :final producer,
    :final productId,
    :final type,
    :final form,
    :final attenuationPct,
  ) =>
    [
      ?producteurLevure(producer, productId),
      if (type != null) typesLevure.libelle(type),
      if (form != null) formesLevure.libelle(form),
      if (attenuationPct != null)
        'atténuation ${formatPourcent(attenuationPct)}',
    ],
  EntreeDivers(:final labelFr, :final type) => [
    ?labelFr,
    if (type != null) typesAjout.libelle(type),
  ],
};
