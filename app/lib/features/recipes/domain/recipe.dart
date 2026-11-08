import 'package:brewing/brewing.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import 'chronologie.dart';

/// Conversion entre un document `recipes/{id}` et les types de `brewing/`, écrite
/// ici seulement. Les valeurs stockées des natures, moments et formes passent par
/// `fromStored` / `storedValue` de `brewing/` (arbitrage A5) ; la clé de chaque
/// ingrédient par `ingredientKey` (A12). Masses en grammes, durées en minutes.

/// Longueur maximale du nom et du style (`firestore.rules`).
const kRecipeNameMaxLength = 120;

/// Longueur maximale des notes (`firestore.rules`).
const kRecipeNotesMaxLength = 10000;

/// Longueur maximale du nom d'un ingrédient ou d'un palier saisi.
const kIngredientNameMaxLength = 120;

/// Plafonds des listes (`firestore.rules`, I7). Les levures (10 dans les règles) n'en
/// ont pas ici : l'éditeur en écrit une au plus (A3).
const kMaxFermentables = 50;
const kMaxHops = 50;
const kMaxOthers = 50;
const kMaxMashSteps = 20;

/// Seuils de l'avertissement « Quantité inhabituelle » (U6, arbitrage A8).
const kUnusualHopGrams = 1000.0;
const kUnusualOtherGrams = 1000.0;
const kUnusualFermentableGrams = 30000.0;
const kUnusualVolumeLitres = 200.0;

/// Moment d'un autre ajout (`others[].use`).
enum OtherUse {
  mash('mash', 'Empâtage'),
  boil('boil', 'Ébullition'),
  afterBoil('after_boil', 'Après ébullition'),
  fermentation('fermentation', 'Fermentation'),
  bottling('bottling', 'Embouteillage');

  const OtherUse(this.storedValue, this.label);

  final String storedValue;
  final String label;

  /// Moment de la valeur stockée [value] ; la valeur, écrite par un autre membre,
  /// n'entre pas dans l'erreur rapportée.
  static OtherUse fromStored(String value, String field) {
    for (final use in values) {
      if (use.storedValue == value) return use;
    }
    throw DocumentIllisible(
      field,
      'moment inconnu (${value.length} caractères)',
    );
  }
}

/// Forme d'une levure (`yeasts[].form`).
enum YeastForm {
  dry('dry', 'Sèche'),
  liquid('liquid', 'Liquide');

  const YeastForm(this.storedValue, this.label);

  final String storedValue;
  final String label;

  static YeastForm fromStored(String value, String field) {
    for (final form in values) {
      if (form.storedValue == value) return form;
    }
    throw DocumentIllisible(
      field,
      'forme inconnue (${value.length} caractères)',
    );
  }
}

/// Valeur stockée d'un champ texte facultatif d'un élément, lue par [parse].
T? _optEnum<T>(LecteurChamps read, String key, T Function(String value) parse) {
  final value = read.texteFacultatif(key);
  return value == null ? null : parse(value);
}

/// Valeur stockée obligatoire, lue par [parse].
T _enum<T>(LecteurChamps read, String key, T Function(String value) parse) =>
    parse(read.texte(key));

/// Malt ou sucre d'une recette.
@immutable
class FermentableLine {
  const FermentableLine({
    required this.name,
    required this.kind,
    required this.weightG,
    this.ebc,
    this.yieldPct,
  });

  final String name;
  final FermentableKind kind;

  /// Masse en grammes ; saisie et affichée en kilogrammes (A9).
  final double weightG;
  final double? ebc;
  final double? yieldPct;

  factory FermentableLine.fromFirestore(LecteurChamps read) => FermentableLine(
    name: read.texte('name'),
    kind: _enum(read, 'kind', FermentableKind.fromStored),
    weightG: read.nombre('weight_g'),
    ebc: read.nombreFacultatif('ebc'),
    yieldPct: read.nombreFacultatif('yield_pct'),
  );

  Map<String, Object?> toFirestore() => {
    'key': ingredientKey(IngredientNature.ofFermentable(kind), name),
    'name': name.trim(),
    'kind': kind.storedValue,
    'weight_g': weightG,
    if (ebc != null) 'ebc': ebc,
    if (yieldPct != null) 'yield_pct': yieldPct,
  };

  FermentableInput toInput() => FermentableInput(
    name: name,
    kind: kind,
    massGrams: weightG,
    colorEbc: ebc,
    yieldPercent: yieldPct,
  );
}

/// Houblon d'une recette.
@immutable
class HopLine {
  const HopLine({
    required this.name,
    required this.weightG,
    required this.use,
    required this.form,
    this.alphaPct,
    this.timeMin,
  });

  final String name;

  /// Masse en grammes.
  final double weightG;
  final HopUse use;
  final HopForm form;
  final double? alphaPct;

  /// Durée en minutes ; pour un houblon à cru, jours saisis × 1 440.
  final double? timeMin;

  factory HopLine.fromFirestore(LecteurChamps read) => HopLine(
    name: read.texte('name'),
    weightG: read.nombre('weight_g'),
    use: _enum(read, 'use', HopUse.fromStored),
    form: _enum(read, 'form', HopForm.fromStored),
    alphaPct: read.nombreFacultatif('alpha_pct'),
    timeMin: read.nombreFacultatif('time_min'),
  );

  Map<String, Object?> toFirestore() => {
    'key': ingredientKey(IngredientNature.hop, name),
    'name': name.trim(),
    'weight_g': weightG,
    if (alphaPct != null) 'alpha_pct': alphaPct,
    'use': use.storedValue,
    if (timeMin != null) 'time_min': timeMin,
    'form': form.storedValue,
  };

  HopInput toInput() => HopInput(
    name: name,
    massGrams: weightG,
    use: use,
    form: form,
    alphaPercent: alphaPct,
    minutes: timeMin,
  );
}

/// Autre ajout (épice, fruit, sel) : aucun calcul.
@immutable
class OtherLine {
  const OtherLine({
    required this.name,
    required this.weightG,
    this.use,
    this.timeMin,
  });

  final String name;
  final double weightG;
  final OtherUse? use;
  final double? timeMin;

  factory OtherLine.fromFirestore(LecteurChamps read) => OtherLine(
    name: read.texte('name'),
    weightG: read.nombre('weight_g'),
    use: _optEnum(
      read,
      'use',
      (v) => OtherUse.fromStored(v, '${read.prefix}use'),
    ),
    timeMin: read.nombreFacultatif('time_min'),
  );

  Map<String, Object?> toFirestore() => {
    'key': ingredientKey(IngredientNature.addition, name),
    'name': name.trim(),
    'weight_g': weightG,
    if (use != null) 'use': use!.storedValue,
    if (timeMin != null) 'time_min': timeMin,
  };
}

/// Levure : l'éditeur en écrit une au plus (A3).
@immutable
class YeastLine {
  const YeastLine({required this.name, this.attenuationPct, this.form});

  final String name;
  final double? attenuationPct;
  final YeastForm? form;

  factory YeastLine.fromFirestore(LecteurChamps read) => YeastLine(
    name: read.texte('name'),
    attenuationPct: read.nombreFacultatif('attenuation_pct'),
    form: _optEnum(
      read,
      'form',
      (v) => YeastForm.fromStored(v, '${read.prefix}form'),
    ),
  );

  Map<String, Object?> toFirestore() => {
    'key': ingredientKey(IngredientNature.yeast, name),
    'name': name.trim(),
    if (attenuationPct != null) 'attenuation_pct': attenuationPct,
    if (form != null) 'form': form!.storedValue,
  };

  YeastInput toInput() =>
      YeastInput(name: name, attenuationPercent: attenuationPct);
}

/// Palier d'empâtage.
@immutable
class MashStep {
  const MashStep({
    required this.name,
    required this.tempC,
    required this.durationMin,
  });

  final String name;
  final double tempC;
  final double durationMin;

  factory MashStep.fromFirestore(LecteurChamps read) => MashStep(
    name: read.texte('name'),
    tempC: read.nombre('temp_c'),
    durationMin: read.nombre('duration_min'),
  );

  Map<String, Object?> toFirestore() => {
    'name': name.trim(),
    'temp_c': tempC,
    'duration_min': durationMin,
  };
}

/// Champs saisis d'une recette, sans propriétaire ni dates. Aucun prix ni stock
/// (P5).
@immutable
class RecipeContent {
  const RecipeContent({
    required this.name,
    this.style,
    this.notes,
    this.batchVolumeL,
    this.boilTimeMin,
    this.equipmentId,
    this.fermentables = const [],
    this.hops = const [],
    this.others = const [],
    this.yeasts = const [],
    this.mashSteps = const [],
    this.brewSteps = const [],
    this.brewStepsProblem,
    this.importedFrom,
  });

  final String name;
  final String? style;
  final String? notes;

  /// Volume visé en fermenteur, en litres.
  final double? batchVolumeL;
  final double? boilTimeMin;

  /// Équipement prévu ; il peut avoir été supprimé depuis.
  final String? equipmentId;
  final List<FermentableLine> fermentables;
  final List<HopLine> hops;
  final List<OtherLine> others;
  final List<YeastLine> yeasts;
  final List<MashStep> mashSteps;

  /// Chronologie du jour, dans l'ordre.
  final List<BrewStepLine> brewSteps;

  /// Raison pour laquelle `brew_steps` est illisible, ou `null` (CH8).
  final String? brewStepsProblem;

  /// Fiche Excel d'origine ; vide pour une recette saisie ou dupliquée.
  final String? importedFrom;

  /// Lit les champs saisis ; lève [DocumentIllisible] ou [BrewingInputException]
  /// (valeur stockée inconnue) sans jamais remplacer une valeur absente.
  factory RecipeContent.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    final chronologie = readBrewSteps(data['brew_steps']);
    return RecipeContent(
      name: read.texte('name'),
      style: read.texteFacultatif('style'),
      notes: read.texteFacultatif('notes'),
      batchVolumeL: read.nombreFacultatif('batch_volume_l'),
      boilTimeMin: read.nombreFacultatif('boil_time_min'),
      equipmentId: read.texteFacultatif('equipment_id'),
      fermentables: List.unmodifiable(
        read.liste('fermentables').map(FermentableLine.fromFirestore),
      ),
      hops: List.unmodifiable(read.liste('hops').map(HopLine.fromFirestore)),
      others: List.unmodifiable(
        read.liste('others').map(OtherLine.fromFirestore),
      ),
      yeasts: List.unmodifiable(
        read.liste('yeasts').map(YeastLine.fromFirestore),
      ),
      mashSteps: List.unmodifiable(
        read.liste('mash_steps').map(MashStep.fromFirestore),
      ),
      brewSteps: chronologie.steps,
      brewStepsProblem: chronologie.problem,
      importedFrom: read.texteFacultatif('imported_from'),
    );
  }

  /// Champs à écrire. Un champ vide est absent à la création et retiré à la
  /// modification ([creation] faux). Lève [BrewingInputException] si un nom
  /// d'ingrédient n'a ni lettre ni chiffre (`ingredientKey`).
  Map<String, Object?> toFirestore({required bool creation}) {
    Map<String, Object?> opt(String key, Object? value) =>
        champFacultatif(key, value, creation: creation);
    String? text(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    List<Map<String, Object?>>? list<T>(
      List<T> items,
      Map<String, Object?> Function(T) write,
    ) => items.isEmpty ? null : [for (final i in items) write(i)];
    return {
      'name': name.trim(),
      ...opt('style', text(style)),
      ...opt('notes', text(notes)),
      ...opt('batch_volume_l', batchVolumeL),
      ...opt('boil_time_min', boilTimeMin),
      ...opt('equipment_id', equipmentId),
      ...opt('fermentables', list(fermentables, (f) => f.toFirestore())),
      ...opt('hops', list(hops, (h) => h.toFirestore())),
      ...opt('others', list(others, (o) => o.toFirestore())),
      ...opt('yeasts', list(yeasts, (y) => y.toFirestore())),
      ...opt('mash_steps', list(mashSteps, (m) => m.toFirestore())),
      // Modifier une recette n'écrit pas la chronologie : l'éditeur de la
      // chronologie a sa propre écriture, seule à la toucher.
      if (creation && brewSteps.isNotEmpty)
        'brew_steps': [for (final b in brewSteps) b.toFirestore()],
      ...opt('imported_from', text(importedFrom)),
    };
  }

  /// Entrée de `computeRecipe`. Lève [BrewingInputException] sur une valeur hors
  /// limites (masse négative, pourcentage au-delà de 100).
  RecipeInput toInput() => RecipeInput(
    fermentables: [for (final f in fermentables) f.toInput()],
    hops: [for (final h in hops) h.toInput()],
    yeasts: [for (final y in yeasts) y.toInput()],
    batchVolumeLitres: batchVolumeL,
    boilMinutes: boilTimeMin,
  );

  /// Copie pour « Dupliquer » (R7) : « Copie de {nom} » coupé à 120 caractères,
  /// mêmes ingrédients, paliers, chronologie (mêmes clés) et équipement, sans fiche
  /// d'origine.
  RecipeContent duplicate() => RecipeContent(
    name: truncateName('Copie de ${name.trim()}', kRecipeNameMaxLength),
    style: style,
    notes: notes,
    batchVolumeL: batchVolumeL,
    boilTimeMin: boilTimeMin,
    equipmentId: equipmentId,
    fermentables: fermentables,
    hops: hops,
    others: others,
    yeasts: yeasts,
    mashSteps: mashSteps,
    brewSteps: brewSteps,
  );
}

/// [value] coupé à [max] unités UTF-16 sans couper un caractère en deux. Les
/// règles comptent des caractères : une chaîne coupée ainsi ne les dépasse jamais.
String truncateName(String value, int max) {
  if (value.length <= max) return value;
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (buffer.length + char.length > max) break;
    buffer.write(char);
  }
  return buffer.toString();
}

/// Document `recipes/{id}`.
@immutable
class Recipe {
  const Recipe({
    required this.id,
    required this.ownerUid,
    this.ownerName,
    required this.content,
    this.updatedAt,
    this.hasPendingWrites = false,
  });

  final String id;

  /// Uid de l'auteur : seule base des droits et du filtre « Les miennes ».
  final String ownerUid;

  /// Nom déclaré par l'auteur, pour l'affichage seul.
  final String? ownerName;
  final RecipeContent content;

  /// `null` tant qu'une écriture locale attend le serveur.
  final DateTime? updatedAt;
  final bool hasPendingWrites;

  String get name => content.name;

  factory Recipe.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    final read = LecteurChamps(data);
    return Recipe(
      id: id,
      ownerUid: read.texte('owner_uid'),
      ownerName: read.texteFacultatif('owner_name'),
      content: RecipeContent.fromFirestore(data),
      updatedAt: read.date('updated_at'),
      hasPendingWrites: hasPendingWrites,
    );
  }
}

/// Tri de la liste : dernière modification d'abord ; une écriture en attente du
/// serveur (date encore nulle) passe en tête.
int compareRecipes(Recipe a, Recipe b) {
  final da = a.updatedAt;
  final db = b.updatedAt;
  if (da == null || db == null) {
    if (da == db) return a.name.compareTo(b.name);
    return da == null ? -1 : 1;
  }
  return db.compareTo(da);
}

/// Malts et sucres par masse décroissante (tri automatique de l'éditeur). Le tri
/// est stable : deux masses égales gardent leur ordre.
List<FermentableLine> sortFermentables(List<FermentableLine> lines) =>
    _stableSort(lines, (a, b) => b.weightG.compareTo(a.weightG));

/// Houblons par moment d'ajout : ébullition de la plus longue à la plus courte
/// (durée inconnue en dernier), puis whirlpool, puis à cru. Tri stable.
List<HopLine> sortHops(List<HopLine> lines) => _stableSort(lines, (a, b) {
  final byUse = a.use.index.compareTo(b.use.index);
  if (byUse != 0) return byUse;
  if (a.use != HopUse.boil) return 0;
  final ta = a.timeMin;
  final tb = b.timeMin;
  if (ta == null || tb == null) {
    if (ta == tb) return 0;
    return ta == null ? 1 : -1;
  }
  return tb.compareTo(ta);
});

List<T> _stableSort<T>(List<T> items, int Function(T, T) compare) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((x, y) {
    final c = compare(x.$2, y.$2);
    return c != 0 ? c : x.$1.compareTo(y.$1);
  });
  return List.unmodifiable(indexed.map((e) => e.$2));
}
