import 'package:brewing/brewing.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import 'beerjson.dart';
import 'chronologie.dart';

/// Conversion entre un document `recipes/{id}` et les types de `brewing/`, écrite
/// ici seulement. Le document est une enveloppe Kass'Beer (`format_version`,
/// propriétaire, équipement, chronologie, dates) et un sous-arbre `recipe` en
/// BeerJSON partiel (ADR-005, `beerjson.dart`). Le type d'un malt et la forme
/// d'un houblon gardent leur valeur BeerJSON ; leur nature et leur forme de
/// calcul viennent de `brewing/` (`FermentableKind.ofType`, `HopForm.ofBeerJson`).
/// La clé d'un ingrédient n'est pas stockée : `ingredientKey` la dérive du nom et
/// de la nature. Masses en grammes, volumes en litres, durées en minutes
/// entières.

/// Longueur maximale du nom et du style (`firestore.rules`).
const kRecipeNameMaxLength = 120;

/// Longueur maximale de l'auteur (`recipe.author`, `firestore.rules`).
const kRecipeAuthorMaxLength = 120;

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

/// Seuil de l'avertissement « Quantité inhabituelle » d'une ligne mesurée en
/// volume (houblon, ajout) : 1 L.
const kUnusualLineLitres = 1.0;

/// Moment d'un autre ajout, écrit dans `timing` (voir [OtherLine]).
enum OtherUse {
  mash('Empâtage'),
  boil('Ébullition'),
  afterBoil('Après ébullition'),
  fermentation('Fermentation'),
  bottling('Embouteillage');

  const OtherUse(this.label);

  final String label;
}

/// Quantité d'un houblon, d'un ajout ou d'une levure : masse en grammes, ou
/// volume en litres (décision du 2026-11-10 : acide lactique, extrait de
/// houblon, levure liquide). Enregistrée telle quelle, dans son unité.
@immutable
class Quantite {
  const Quantite.grammes(this.valeur) : enLitres = false;
  const Quantite.litres(this.valeur) : enLitres = true;

  final double valeur;

  /// Vrai pour un volume en litres, faux pour une masse en grammes.
  final bool enLitres;

  /// Masse en grammes, ou `null` pour un volume.
  double? get grammes => enLitres ? null : valeur;

  Map<String, Object> toFirestore() => mesureBeerJson(
    valeur,
    enLitres ? UniteBeerJson.litre : UniteBeerJson.gramme,
  );

  @override
  bool operator ==(Object other) =>
      other is Quantite && other.valeur == valeur && other.enLitres == enLitres;

  @override
  int get hashCode => Object.hash(valeur, enLitres);
}

/// Quantité [key] en grammes ou en litres, ou `null` si elle est absente. Une
/// autre unité lève [DocumentIllisible].
Quantite? _quantiteFacultative(LecteurChamps read, String key) {
  final value = read.mesureParmi(key, const {
    UniteBeerJson.gramme,
    UniteBeerJson.litre,
  });
  if (value == null) return null;
  return value.unit == UniteBeerJson.litre
      ? Quantite.litres(value.value)
      : Quantite.grammes(value.value);
}

/// Quantité obligatoire `amount`, en grammes ou en litres.
Quantite _quantite(LecteurChamps read) =>
    _quantiteFacultative(read, 'amount') ??
    (throw DocumentIllisible('${read.prefix}amount', 'quantité absente'));

/// `timing` d'un ajout : `use`, et `time` ou `duration` en minutes.
Map<String, Object> _timing(String use, {int? time, int? duration}) => {
  'use': use,
  if (time != null) 'time': mesureBeerJson(time, UniteBeerJson.minute),
  if (duration != null)
    'duration': mesureBeerJson(duration, UniteBeerJson.minute),
};

/// `timing` lu : `null` s'il est absent.
typedef _Moment = ({String use, int? time, int? duration, String path});

_Moment? _lireMoment(LecteurChamps read) {
  final timing = read.objetFacultatif('timing');
  if (timing == null) return null;
  return (
    use: timing.texte('use'),
    time: timing.duree('time'),
    duration: timing.duree('duration'),
    path: timing.prefix,
  );
}

/// Ajout à l'ébullition (`add_to_boil`). `time` porte les minutes d'ébullition.
/// `time` à 0 avec `duration` : ajout après l'arrêt du feu (whirlpool), pour
/// `duration` minutes. Toute autre `duration` lève [DocumentIllisible] : elle serait
/// perdue au prochain enregistrement.
({bool afterBoil, int? minutes}) _lireEbullition(_Moment m) {
  if (m.duration == null) return (afterBoil: false, minutes: m.time);
  if (m.time == 0) return (afterBoil: true, minutes: m.duration);
  throw DocumentIllisible('${m.path}duration', 'durée inattendue');
}

/// Ajout hors ébullition : seule `duration` est écrite.
int? _lireDuree(_Moment m) {
  if (m.time == null) return m.duration;
  throw DocumentIllisible('${m.path}time', 'heure d\'ajout inattendue');
}

DocumentIllisible _usageInconnu(_Moment m) => DocumentIllisible(
  '${m.path}use',
  'moment non pris en charge (${m.use.length} caractères)',
);

/// Masse obligatoire `amount`, en grammes.
double _masse(LecteurChamps read) =>
    read.mesure('amount', UniteBeerJson.gramme) ??
    (throw DocumentIllisible('${read.prefix}amount', 'quantité absente'));

/// Nom écrit d'un ingrédient. La clé n'est pas stockée, mais elle se dérive du nom
/// (prix, stock) : un nom sans lettre ni chiffre lève [BrewingInputException]
/// (`ingredientKey`, K3), comme avant la v0.1.15.
String _nom(IngredientNature nature, String name) {
  ingredientKey(nature, name);
  return name.trim();
}

Map<String, Object>? _pourcent(double? value) =>
    value == null ? null : mesureBeerJson(value, UniteBeerJson.pourcent);

/// Malt ou sucre d'une recette (`fermentable_additions[]`).
@immutable
class FermentableLine {
  const FermentableLine({
    required this.name,
    required this.type,
    required this.weightG,
    this.ebc,
    this.yieldPct,
  });

  final String name;

  /// Valeur de [typesFermentable], gardée telle quelle : `grain`, `sugar`, ou
  /// une valeur importée (`extract`, `honey`, `other`…).
  final String type;

  /// Masse en grammes ; saisie et affichée en kilogrammes (A9).
  final double weightG;
  final double? ebc;
  final double? yieldPct;

  /// Nature de calcul (`brewing/`) : un extrait, un miel, un fruit ou un jus se
  /// calcule comme un sucre ; `null` pour `other` (nature à préciser).
  FermentableKind? get kind => FermentableKind.ofType(type);

  /// Nature de la clé d'ingrédient (prix, stock) : malt pour un malt, sucre pour
  /// tout le reste, `other` compris. Le calcul de brassage ne la lit pas.
  IngredientNature get nature => IngredientNature.ofFermentable(kind);

  factory FermentableLine.fromFirestore(LecteurChamps read) => FermentableLine(
    name: read.texte('name'),
    type:
        read.valeurDe('type', typesFermentable) ??
        (throw DocumentIllisible('${read.prefix}type', 'type absent')),
    weightG: _masse(read),
    ebc: read.mesure('color', UniteBeerJson.ebc),
    yieldPct: read
        .objetFacultatif('yield')
        ?.mesure('fine_grind', UniteBeerJson.pourcent),
  );

  Map<String, Object?> toFirestore() => {
    'name': _nom(nature, name),
    'type': type,
    'amount': mesureBeerJson(weightG, UniteBeerJson.gramme),
    if (ebc != null) 'color': mesureBeerJson(ebc!, UniteBeerJson.ebc),
    if (yieldPct != null) 'yield': {'fine_grind': _pourcent(yieldPct)},
  };

  FermentableInput toInput() => FermentableInput(
    name: name,
    kind: kind,
    massGrams: weightG,
    colorEbc: ebc,
    yieldPercent: yieldPct,
  );
}

/// Houblon d'une recette (`hop_additions[]`).
@immutable
class HopLine {
  const HopLine({
    required this.name,
    required this.amount,
    required this.use,
    required this.form,
    this.alphaPct,
    this.timeMin,
    this.dayMin,
  });

  final String name;

  /// Masse en grammes, ou volume en litres pour un extrait liquide : il ne
  /// compte pas dans l'IBU.
  final Quantite amount;
  final HopUse use;

  /// Valeur de [formesHoublon], gardée telle quelle (`pellet`, `leaf`, ou une
  /// valeur importée : `plug`, `powder`, `extract`, `leaf (wet)`), ou `null`
  /// quand la source ne la donne pas (recette publique DIY Dog et sa copie).
  /// Aucune forme n'est inventée : l'éditeur la demande à la modification de
  /// la ligne.
  final String? form;
  final double? alphaPct;

  /// Durée en minutes entières : ébullition, infusion d'un whirlpool, jours à
  /// cru × 1 440 arrondis à la minute, ou durée à l'empâtage ou au
  /// conditionnement.
  final int? timeMin;

  /// Jour d'ajout d'un houblon à cru, en minutes depuis le début de la
  /// fermentation (`timing.time`), conservé d'un import ; `brewing/` ne le lit
  /// pas. Toujours `null` hors de [HopUse.dryHop].
  final int? dayMin;

  /// Forme de calcul (`brewing/`) : `plug` se calcule comme des cônes ; `null`
  /// pour une forme sans facteur d'utilisation, ou pour une forme absente. Dans
  /// les deux cas, un houblon d'ébullition rend l'IBU indisponible
  /// (`MissingInputKind.hopForm`) ; l'écran les distingue par [form].
  HopForm? get calcForm {
    final f = form;
    return f == null ? null : HopForm.ofBeerJson(f);
  }

  /// Moments lus : `add_to_boil` (ébullition, ou whirlpool à `time` 0 avec
  /// `duration`), `add_to_fermentation` (à cru, `duration`, et `time` : jour
  /// d'ajout), `add_to_mash` et `add_to_package` (`duration`). L'empâtage et le
  /// conditionnement se lisent et s'affichent ; le calcul de l'IBU ne les prend
  /// pas en charge.
  factory HopLine.fromFirestore(LecteurChamps read) {
    final m =
        _lireMoment(read) ??
        (throw DocumentIllisible('${read.prefix}timing', 'moment absent'));
    final (HopUse use, int? minutes, int? day) = switch (m.use) {
      UsageBeerJson.boil => switch (_lireEbullition(m)) {
        (afterBoil: true, :final minutes) => (HopUse.afterBoil, minutes, null),
        (afterBoil: false, :final minutes) => (HopUse.boil, minutes, null),
      },
      UsageBeerJson.fermentation => (HopUse.dryHop, m.duration, m.time),
      UsageBeerJson.mash => (HopUse.mash, _lireDuree(m), null),
      UsageBeerJson.package => (HopUse.package, _lireDuree(m), null),
      _ => throw _usageInconnu(m),
    };
    return HopLine(
      name: read.texte('name'),
      amount: _quantite(read),
      use: use,
      form: read.valeurDe('form', formesHoublon),
      alphaPct: read.mesure('alpha_acid', UniteBeerJson.pourcent),
      timeMin: minutes,
      dayMin: day,
    );
  }

  /// Lève [ArgumentError] pour un whirlpool sans durée : relu, il deviendrait un
  /// ajout à 0 minute d'ébullition. L'éditeur rend cette durée obligatoire. Lève
  /// [BrewingInputException] pour un nom sans lettre ni chiffre.
  Map<String, Object?> toFirestore() => {
    'name': _nom(IngredientNature.hop, name),
    'form': ?form,
    if (alphaPct != null) 'alpha_acid': _pourcent(alphaPct),
    'amount': amount.toFirestore(),
    'timing': switch (use) {
      HopUse.mash => _timing(UsageBeerJson.mash, duration: timeMin),
      HopUse.boil => _timing(UsageBeerJson.boil, time: timeMin),
      HopUse.afterBoil => _timing(
        UsageBeerJson.boil,
        time: 0,
        duration: timeMin ?? (throw ArgumentError('whirlpool sans durée')),
      ),
      HopUse.dryHop => _timing(
        UsageBeerJson.fermentation,
        time: dayMin,
        duration: timeMin,
      ),
      HopUse.package => _timing(UsageBeerJson.package, duration: timeMin),
    },
  };

  HopInput toInput() => HopInput(
    name: name,
    massGrams: amount.grammes,
    use: use,
    form: calcForm,
    alphaPercent: alphaPct,
    minutes: timeMin?.toDouble(),
  );
}

/// Autre ajout (épice, fruit, sel ; `miscellaneous_additions[]`) : aucun calcul.
@immutable
class OtherLine {
  const OtherLine({
    required this.name,
    required this.amount,
    this.type,
    this.use,
    this.timeMin,
  });

  final String name;

  /// Masse en grammes, ou volume en litres (acide lactique).
  final Quantite amount;

  /// Valeur de [typesAjout], ou `null`.
  final String? type;
  final OtherUse? use;

  /// Durée en minutes entières ; sans [use], elle n'existe pas.
  final int? timeMin;

  /// Moments lus : `add_to_mash`, `add_to_fermentation` et `add_to_package` avec
  /// `duration` ; `add_to_boil` comme pour un houblon (`time`, ou `time` à 0 avec
  /// `duration` après l'ébullition). Un ajout « Après ébullition » sans durée a été
  /// écrit à 0 minute d'ébullition : il se relit ainsi.
  factory OtherLine.fromFirestore(LecteurChamps read) {
    final m = _lireMoment(read);
    final (OtherUse? use, int? minutes) = switch (m?.use) {
      null => (null, null),
      UsageBeerJson.boil => switch (_lireEbullition(m!)) {
        (afterBoil: true, :final minutes) => (OtherUse.afterBoil, minutes),
        (afterBoil: false, :final minutes) => (OtherUse.boil, minutes),
      },
      UsageBeerJson.mash => (OtherUse.mash, _lireDuree(m!)),
      UsageBeerJson.fermentation => (OtherUse.fermentation, _lireDuree(m!)),
      UsageBeerJson.package => (OtherUse.bottling, _lireDuree(m!)),
      _ => throw _usageInconnu(m!),
    };
    return OtherLine(
      name: read.texte('name'),
      type: read.valeurDe('type', typesAjout),
      amount: _quantite(read),
      use: use,
      timeMin: minutes,
    );
  }

  /// Lève [ArgumentError] pour une durée sans utilisation, que l'éditeur refuse, et
  /// [BrewingInputException] pour un nom sans lettre ni chiffre.
  Map<String, Object?> toFirestore() {
    final minutes = timeMin;
    if (use == null && minutes != null) {
      throw ArgumentError('durée d\'ajout sans utilisation');
    }
    return {
      'name': _nom(IngredientNature.addition, name),
      if (type != null) 'type': type,
      'amount': amount.toFirestore(),
      if (use != null)
        'timing': switch (use!) {
          OtherUse.mash => _timing(UsageBeerJson.mash, duration: minutes),
          OtherUse.boil => _timing(UsageBeerJson.boil, time: minutes),
          OtherUse.afterBoil => _timing(
            UsageBeerJson.boil,
            time: 0,
            duration: minutes,
          ),
          OtherUse.fermentation => _timing(
            UsageBeerJson.fermentation,
            duration: minutes,
          ),
          OtherUse.bottling => _timing(
            UsageBeerJson.package,
            duration: minutes,
          ),
        },
    };
  }
}

/// Levure (`culture_additions[]`) : l'éditeur en écrit une au plus (A3).
@immutable
class YeastLine {
  const YeastLine({
    required this.name,
    this.type,
    this.form,
    this.attenuationPct,
    this.amount,
  });

  final String name;

  /// Valeur de [typesLevure], ou `null`.
  final String? type;

  /// Valeur de [formesLevure], ou `null`.
  final String? form;
  final double? attenuationPct;

  /// Quantité ensemencée, facultative : grammes, ou litres pour une levure
  /// liquide.
  final Quantite? amount;

  factory YeastLine.fromFirestore(LecteurChamps read) => YeastLine(
    name: read.texte('name'),
    type: read.valeurDe('type', typesLevure),
    form: read.valeurDe('form', formesLevure),
    attenuationPct: read.mesure('attenuation', UniteBeerJson.pourcent),
    amount: _quantiteFacultative(read, 'amount'),
  );

  Map<String, Object?> toFirestore() => {
    'name': _nom(IngredientNature.yeast, name),
    if (type != null) 'type': type,
    if (form != null) 'form': form,
    if (attenuationPct != null) 'attenuation': _pourcent(attenuationPct),
    if (amount != null) 'amount': amount!.toFirestore(),
  };

  YeastInput toInput() =>
      YeastInput(name: name, attenuationPercent: attenuationPct);
}

/// Palier d'empâtage (`mash.mash_steps[]`).
@immutable
class MashStep {
  const MashStep({
    required this.name,
    required this.tempC,
    required this.durationMin,
    this.type,
  });

  final String name;
  final double tempC;

  /// Durée en minutes entières.
  final int durationMin;

  /// Valeur de [typesPalier], ou `null`.
  final String? type;

  factory MashStep.fromFirestore(LecteurChamps read) => MashStep(
    name: read.texte('name'),
    type: read.valeurDe('type', typesPalier),
    tempC:
        read.mesure('step_temperature', UniteBeerJson.celsius) ??
        (throw DocumentIllisible(
          '${read.prefix}step_temperature',
          'température absente',
        )),
    durationMin:
        read.duree('step_time') ??
        (throw DocumentIllisible('${read.prefix}step_time', 'durée absente')),
  );

  Map<String, Object?> toFirestore() => {
    'name': name.trim(),
    if (type != null) 'type': type,
    'step_temperature': mesureBeerJson(tempC, UniteBeerJson.celsius),
    'step_time': mesureBeerJson(durationMin, UniteBeerJson.minute),
  };
}

/// Champs saisis d'une recette, sans propriétaire ni dates. Aucun prix ni stock
/// (P5).
@immutable
class RecipeContent {
  const RecipeContent({
    required this.name,
    this.type,
    this.author,
    this.style,
    this.notes,
    this.batchVolumeL,
    this.boilTimeMin,
    this.grainTempC,
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

  /// Valeur de [typesRecette], ou `null`.
  final String? type;

  /// Auteur de la recette (`recipe.author`), conservé d'un import ; 120
  /// caractères au plus. L'éditeur ne le saisit pas et le garde à
  /// l'enregistrement. Distinct de `owner_name`, nom du membre qui l'a créée.
  final String? author;
  final String? style;
  final String? notes;

  /// Volume visé en fermenteur, en litres.
  final double? batchVolumeL;

  /// Durée d'ébullition en minutes entières.
  final int? boilTimeMin;

  /// Température des malts à l'empâtage, en °C.
  final double? grainTempC;

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

  /// Origine d'une recette importée (200 caractères au plus) : format et
  /// empreinte du contenu du fichier (`BeerJSON · sha256:…`, `exchange/`),
  /// qui repère un second import du même contenu. Vide pour une recette saisie
  /// ou dupliquée.
  final String? importedFrom;

  /// Lit l'enveloppe et le sous-arbre `recipe` ; lève [DocumentIllisible] (version
  /// de format, unité ou valeur hors du schéma, type de malt et forme de houblon
  /// compris) sans jamais remplacer une valeur absente.
  factory RecipeContent.fromFirestore(Map<String, dynamic> data) {
    verifierVersionFormat(data);
    final envelope = LecteurChamps(data);
    final read = envelope.objet('recipe');
    final ingredients = read.objet('ingredients');
    final mash = read.objetFacultatif('mash');
    final chronologie = readBrewSteps(data['brew_steps']);
    return RecipeContent(
      name: read.texte('name'),
      type: read.valeurDe('type', typesRecette),
      author: read.texteFacultatif('author'),
      style: read.objetFacultatif('style')?.texte('name'),
      notes: read.texteFacultatif('notes'),
      batchVolumeL: read.mesure('batch_size', UniteBeerJson.litre),
      boilTimeMin: read.objetFacultatif('boil')?.duree('boil_time'),
      grainTempC: mash?.mesure('grain_temperature', UniteBeerJson.celsius),
      equipmentId: envelope.texteFacultatif('equipment_id'),
      fermentables: List.unmodifiable(
        ingredients
            .liste('fermentable_additions')
            .map(FermentableLine.fromFirestore),
      ),
      hops: List.unmodifiable(
        ingredients.liste('hop_additions').map(HopLine.fromFirestore),
      ),
      others: List.unmodifiable(
        ingredients
            .liste('miscellaneous_additions')
            .map(OtherLine.fromFirestore),
      ),
      yeasts: List.unmodifiable(
        ingredients.liste('culture_additions').map(YeastLine.fromFirestore),
      ),
      mashSteps: List.unmodifiable(
        mash?.liste('mash_steps').map(MashStep.fromFirestore) ??
            const <MashStep>[],
      ),
      brewSteps: chronologie.steps,
      brewStepsProblem: chronologie.problem,
      importedFrom: envelope.texteFacultatif('imported_from'),
    );
  }

  /// Champs à écrire : `format_version`, champs de l'enveloppe, et `recipe` d'un
  /// bloc. Dans `recipe`, un champ vide est absent, et les quatre listes
  /// d'ingrédients sont toujours là. Hors de `recipe`, un champ vide est absent à la
  /// création et retiré à la modification ([creation] faux). Lève
  /// [ArgumentError] sur une ligne que l'éditeur refuse (voir [HopLine.toFirestore]
  /// et [OtherLine.toFirestore]), et [BrewingInputException] si un nom d'ingrédient
  /// n'a ni lettre ni chiffre.
  Map<String, Object?> toFirestore({required bool creation}) {
    Map<String, Object?> opt(String key, Object? value) =>
        champFacultatif(key, value, creation: creation);
    String? text(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    final styleName = text(style);
    final authorText = text(author);
    final notesText = text(notes);
    final mash = <String, Object?>{
      if (grainTempC != null)
        'grain_temperature': mesureBeerJson(grainTempC!, UniteBeerJson.celsius),
      // Absent sans palier, jamais une liste vide (ADR-005).
      if (mashSteps.isNotEmpty)
        'mash_steps': [for (final m in mashSteps) m.toFirestore()],
    };
    return {
      'format_version': kRecipeFormatVersion,
      ...opt('equipment_id', equipmentId),
      // Modifier une recette n'écrit pas la chronologie : l'éditeur de la
      // chronologie a sa propre écriture, seule à la toucher.
      if (creation && brewSteps.isNotEmpty)
        'brew_steps': [for (final b in brewSteps) b.toFirestore()],
      ...opt('imported_from', text(importedFrom)),
      'recipe': {
        'name': name.trim(),
        if (type != null) 'type': type,
        'author': ?authorText,
        if (styleName != null) 'style': {'name': styleName},
        'notes': ?notesText,
        if (batchVolumeL != null)
          'batch_size': mesureBeerJson(batchVolumeL!, UniteBeerJson.litre),
        if (boilTimeMin != null)
          'boil': {
            'boil_time': mesureBeerJson(boilTimeMin!, UniteBeerJson.minute),
          },
        if (mash.isNotEmpty) 'mash': {'name': kNomEmpatage, ...mash},
        'ingredients': {
          'fermentable_additions': [
            for (final f in fermentables) f.toFirestore(),
          ],
          'hop_additions': [for (final h in hops) h.toFirestore()],
          'miscellaneous_additions': [for (final o in others) o.toFirestore()],
          'culture_additions': [for (final y in yeasts) y.toFirestore()],
        },
      },
    };
  }

  /// Entrée de `computeRecipe`. Lève [BrewingInputException] sur une valeur hors
  /// limites (masse négative, pourcentage au-delà de 100).
  RecipeInput toInput() => RecipeInput(
    fermentables: [for (final f in fermentables) f.toInput()],
    hops: [for (final h in hops) h.toInput()],
    yeasts: [for (final y in yeasts) y.toInput()],
    batchVolumeLitres: batchVolumeL,
    boilMinutes: boilTimeMin?.toDouble(),
  );

  /// Copie pour « Dupliquer » (R7) : « Copie de {nom} » coupé à 120 caractères,
  /// mêmes ingrédients, paliers, chronologie (mêmes clés), équipement et auteur
  /// de la recette d'origine, sans fiche d'origine.
  RecipeContent duplicate() => RecipeContent(
    name: truncateName('Copie de ${name.trim()}', kRecipeNameMaxLength),
    type: type,
    author: author,
    style: style,
    notes: notes,
    batchVolumeL: batchVolumeL,
    boilTimeMin: boilTimeMin,
    grainTempC: grainTempC,
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
    this.createdAt,
    this.updatedAt,
    this.hasPendingWrites = false,
  });

  final String id;

  /// Uid de l'auteur : seule base des droits et du filtre « Les miennes ».
  final String ownerUid;

  /// Nom déclaré par l'auteur, pour l'affichage seul.
  final String? ownerName;
  final RecipeContent content;

  /// Date de création ; `null` tant que la création attend le serveur. Sert à
  /// « Déjà importée le … » de l'import.
  final DateTime? createdAt;

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
      createdAt: read.date('created_at'),
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
