import 'alcohol.dart';
import 'bitterness.dart';
import 'color.dart';
import 'errors.dart';
import 'fermentables.dart';
import 'yeast.dart';

/// Un fermentescible tel qu'il est saisi : couleur et rendement d'extrait
/// peuvent manquer.
class FermentableInput {
  /// Crée la ligne. [massGrams] en grammes, [colorEbc] en EBC,
  /// [yieldPercent] : rendement d'extrait, de 0 à 100 % du saccharose.
  FermentableInput({
    required this.name,
    required this.kind,
    required this.massGrams,
    this.colorEbc,
    this.yieldPercent,
  }) {
    requireNonNegative('massGrams', massGrams);
    final color = colorEbc;
    if (color != null) requireNonNegative('colorEbc', color);
    final yieldValue = yieldPercent;
    if (yieldValue != null) requireRange('yieldPercent', yieldValue, 0, 100);
  }

  /// Nom affiché.
  final String name;

  /// Malt ou sucre.
  final FermentableKind kind;

  /// Masse en grammes.
  final double massGrams;

  /// Couleur en EBC, ou nulle si elle n'est pas renseignée.
  final double? colorEbc;

  /// Rendement d'extrait en %, ou nul s'il n'est pas renseigné.
  final double? yieldPercent;
}

/// Un houblon tel qu'il est saisi : acides alpha et durée peuvent manquer.
class HopInput {
  /// Crée la ligne. [massGrams] en grammes, [alphaPercent] de 0 à 100 %,
  /// [minutes] : durée en minutes (d'ébullition pour [HopUse.boil]).
  HopInput({
    required this.name,
    required this.massGrams,
    required this.use,
    required this.form,
    this.alphaPercent,
    this.minutes,
  }) {
    requireNonNegative('massGrams', massGrams);
    final alpha = alphaPercent;
    if (alpha != null) requireRange('alphaPercent', alpha, 0, 100);
    final duration = minutes;
    if (duration != null) requireNonNegative('minutes', duration);
  }

  /// Nom affiché.
  final String name;

  /// Masse en grammes.
  final double massGrams;

  /// Moment d'ajout.
  final HopUse use;

  /// Cônes ou pellets.
  final HopForm form;

  /// Acides alpha en %, ou nuls s'ils ne sont pas renseignés.
  final double? alphaPercent;

  /// Durée en minutes, ou nulle si elle n'est pas renseignée.
  final double? minutes;
}

/// Une levure telle qu'elle est saisie : l'atténuation peut manquer.
class YeastInput {
  /// Crée la ligne. [attenuationPercent] de 0 à 100 %.
  YeastInput({required this.name, this.attenuationPercent}) {
    final attenuation = attenuationPercent;
    if (attenuation != null) {
      requireRange('attenuationPercent', attenuation, 0, 100);
    }
  }

  /// Nom affiché.
  final String name;

  /// Atténuation apparente en %, ou nulle si elle n'est pas renseignée.
  final double? attenuationPercent;
}

/// Une recette telle qu'elle est saisie, dans les unités de `brewing/`.
class RecipeInput {
  /// Crée la description. [batchVolumeLitres] : volume visé en fermenteur ;
  /// [boilMinutes] : durée d'ébullition de la recette. Seule la première levure
  /// de [yeasts] compte pour la densité finale.
  RecipeInput({
    required this.fermentables,
    required this.hops,
    required this.yeasts,
    this.batchVolumeLitres,
    this.boilMinutes,
  }) {
    final volume = batchVolumeLitres;
    if (volume != null) requirePositive('batchVolumeLitres', volume);
    final boil = boilMinutes;
    if (boil != null) requireNonNegative('boilMinutes', boil);
  }

  /// Malts et sucres, dans l'ordre de la recette.
  final List<FermentableInput> fermentables;

  /// Houblons, dans l'ordre de la recette.
  final List<HopInput> hops;

  /// Levures ; la première sert au calcul.
  final List<YeastInput> yeasts;

  /// Volume visé en fermenteur, en litres, ou nul s'il n'est pas renseigné.
  final double? batchVolumeLitres;

  /// Durée d'ébullition en minutes, ou nulle si elle n'est pas renseignée.
  final double? boilMinutes;
}

/// Une ligne de la recette désignée par sa place et son nom.
class IngredientRef {
  /// Crée la référence.
  const IngredientRef(this.index, this.name);

  /// Place dans sa liste (fermentescibles, houblons ou levures), à partir de 0.
  final int index;

  /// Nom de la ligne.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is IngredientRef && other.index == index && other.name == name;

  @override
  int get hashCode => Object.hash(index, name);

  @override
  String toString() => 'IngredientRef($index, $name)';
}

/// Donnée qui manque à un calcul. Le texte affiché est choisi par l'écran.
enum MissingInputKind {
  /// Volume en fermenteur non renseigné : aucun calcul.
  batchVolume,

  /// Aucun malt ni sucre : pas de densité initiale ni de couleur.
  fermentables,

  /// Rendement d'empâtage absent alors que la recette contient un malt.
  /// L'appelant en connaît la cause : aucun équipement choisi, équipement
  /// supprimé ou indisponible hors ligne, rendement non renseigné.
  mashEfficiency,

  /// Rendement d'extrait non renseigné ([MissingInput.items] : les lignes).
  extractYield,

  /// Couleur non renseignée ([MissingInput.items] : les lignes).
  color,

  /// Acides alpha non renseignés d'un houblon d'ébullition.
  hopAlpha,

  /// Durée non renseignée d'un houblon d'ébullition.
  hopBoilTime,

  /// Aucune levure.
  yeast,

  /// Atténuation non renseignée ([MissingInput.items] : la levure).
  yeastAttenuation,

  /// Le calcul dépend de la densité initiale, elle-même indisponible.
  originalGravity,
}

/// Une donnée manquante et les lignes qu'elle concerne.
class MissingInput {
  /// Crée la donnée manquante.
  const MissingInput(this.kind, [this.items = const []]);

  /// Nature de la donnée.
  final MissingInputKind kind;

  /// Lignes concernées, dans l'ordre de la recette ; vide quand la donnée
  /// porte sur la recette entière.
  final List<IngredientRef> items;

  @override
  String toString() => 'MissingInput(${kind.name}, $items)';
}

/// Résultat d'un indicateur de la recette.
sealed class CalculationResult {
  const CalculationResult();
}

/// Indicateur calculé.
class CalculationComputed extends CalculationResult {
  /// Crée le résultat.
  const CalculationComputed(this.value);

  /// Valeur, dans l'unité de l'indicateur (SG, % vol, IBU, EBC).
  final double value;
}

/// Indicateur indisponible : des données manquent.
class CalculationUnavailable extends CalculationResult {
  /// Crée le résultat.
  const CalculationUnavailable(this.missing);

  /// Données manquantes, jamais vide. [MissingInputKind.originalGravity]
  /// signale la dépendance à une densité initiale indisponible.
  final List<MissingInput> missing;
}

/// IBU apportés par un houblon, pour le détail des calculs.
class HopBitterness {
  /// Crée la ligne.
  const HopBitterness(this.hop, this.ibu);

  /// Houblon concerné.
  final IngredientRef hop;

  /// IBU de Tinseth ; 0 hors ébullition.
  final double ibu;
}

/// Calculs d'une recette : chaque indicateur est une valeur ou la liste de ce
/// qui lui manque.
class RecipeCalculation {
  /// Crée le résultat.
  const RecipeCalculation({
    required this.originalGravity,
    required this.finalGravity,
    required this.alcoholByVolume,
    required this.bitternessIbu,
    required this.colorEbc,
    required this.hopBitterness,
    required this.hopsLongerThanBoil,
  });

  /// Densité initiale prévue (SG).
  final CalculationResult originalGravity;

  /// Densité finale prévue (SG).
  final CalculationResult finalGravity;

  /// Degré (% vol), avant refermentation en bouteille.
  final CalculationResult alcoholByVolume;

  /// Amertume (IBU de Tinseth).
  final CalculationResult bitternessIbu;

  /// Couleur (EBC de Morey).
  final CalculationResult colorEbc;

  /// IBU de chaque houblon, dans l'ordre de la recette ; vide quand
  /// l'amertume est indisponible.
  final List<HopBitterness> hopBitterness;

  /// Houblons d'ébullition dont la durée dépasse celle de la recette.
  final List<IngredientRef> hopsLongerThanBoil;

  /// Densité d'ébullition retenue pour l'IBU : la densité initiale prévue,
  /// ou nulle si elle est indisponible.
  double? get boilGravity => switch (originalGravity) {
    CalculationComputed(:final value) => value,
    CalculationUnavailable() => null,
  };

  /// Données à compléter, sans doublon, dans l'ordre des indicateurs. La
  /// dépendance à la densité initiale ([MissingInputKind.originalGravity])
  /// n'y figure pas : ce qui manque à la densité initiale y figure déjà.
  List<MissingInput> get missingInputs {
    final seen = <MissingInputKind>{};
    final result = <MissingInput>[];
    for (final indicator in [
      originalGravity,
      finalGravity,
      alcoholByVolume,
      bitternessIbu,
      colorEbc,
    ]) {
      if (indicator is! CalculationUnavailable) continue;
      for (final m in indicator.missing) {
        if (m.kind == MissingInputKind.originalGravity) continue;
        if (seen.add(m.kind)) result.add(m);
      }
    }
    return List.unmodifiable(result);
  }
}

/// Calcule la densité initiale, la densité finale, le degré, l'IBU et l'EBC
/// d'une recette, ou ce qui manque à chacun.
///
/// [mashEfficiencyPercent] : rendement d'empâtage de l'équipement, nul s'il
/// n'est pas connu. Aucune valeur par défaut ne remplace une donnée absente.
/// Règles :
/// - densité initiale : volume, au moins un fermentescible, le rendement
///   d'extrait de chacun, et le rendement d'empâtage si un malt est présent ;
/// - densité finale et degré : densité initiale et atténuation de la première
///   levure ;
/// - IBU : volume ; sans houblon d'ébullition, 0 IBU ; sinon densité initiale
///   (densité d'ébullition), acides alpha et durée de chaque houblon
///   d'ébullition ;
/// - EBC : volume, au moins un fermentescible et la couleur de chacun ;
///   l'équipement n'y entre pas.
///
/// Une valeur hors limites lève [BrewingInputException], ici ou à la
/// construction des lignes ; le paquet ne la rattrape pas.
RecipeCalculation computeRecipe({
  required RecipeInput recipe,
  double? mashEfficiencyPercent,
}) {
  final efficiency = mashEfficiencyPercent;
  if (efficiency != null) {
    requireRange('mashEfficiencyPercent', efficiency, 0, 100);
  }
  final og = _originalGravity(recipe, efficiency);
  final fg = _finalGravity(recipe, og);
  final abv = og is CalculationComputed && fg is CalculationComputed
      ? CalculationComputed(
          alcoholByVolume(originalGravity: og.value, finalGravity: fg.value),
        )
      : fg;
  final (ibu, perHop) = _bitterness(recipe, og);

  final boil = recipe.boilMinutes;
  final hops = recipe.hops;
  final longer = boil == null
      ? const <IngredientRef>[]
      : _refs(
          hops,
          (h) => h.use == HopUse.boil && (h.minutes ?? 0) > boil,
          (h) => h.name,
        );

  return RecipeCalculation(
    originalGravity: og,
    finalGravity: fg,
    alcoholByVolume: abv,
    bitternessIbu: ibu,
    colorEbc: _color(recipe),
    hopBitterness: List.unmodifiable(perHop),
    hopsLongerThanBoil: List.unmodifiable(longer),
  );
}

const MissingInput _missingVolume = MissingInput(MissingInputKind.batchVolume);

const MissingInput _missingFermentables = MissingInput(
  MissingInputKind.fermentables,
);

const MissingInput _dependsOnOriginalGravity = MissingInput(
  MissingInputKind.originalGravity,
);

/// Lignes de [items] qui vérifient [lacks], dans l'ordre.
List<IngredientRef> _refs<T>(
  List<T> items,
  bool Function(T) lacks,
  String Function(T) nameOf,
) => List.unmodifiable([
  for (var i = 0; i < items.length; i++)
    if (lacks(items[i])) IngredientRef(i, nameOf(items[i])),
]);

/// [CalculationUnavailable] si [missing] n'est pas vide, sinon [compute].
CalculationResult _resultOf(
  List<MissingInput> missing,
  double Function() compute,
) => missing.isEmpty
    ? CalculationComputed(compute())
    : CalculationUnavailable(List.unmodifiable(missing));

CalculationResult _originalGravity(RecipeInput recipe, double? efficiency) {
  final volume = recipe.batchVolumeLitres;
  final fermentables = recipe.fermentables;
  final hasMalt = fermentables.any((f) => f.kind == FermentableKind.malt);
  final withoutYield = _refs(
    fermentables,
    (f) => f.yieldPercent == null,
    (f) => f.name,
  );
  return _resultOf(
    [
      if (volume == null) _missingVolume,
      if (fermentables.isEmpty) _missingFermentables,
      if (hasMalt && efficiency == null)
        const MissingInput(MissingInputKind.mashEfficiency),
      if (withoutYield.isNotEmpty)
        MissingInput(MissingInputKind.extractYield, withoutYield),
    ],
    () => predictedOriginalGravity(
      fermentables: [
        for (final f in fermentables)
          Fermentable(
            name: f.name,
            kind: f.kind,
            massGrams: f.massGrams,
            // La couleur n'entre pas dans la densité initiale : une couleur
            // absente ne change pas le résultat.
            colorEbc: f.colorEbc ?? 0,
            potential: ExtractPotential.yieldPercent(f.yieldPercent!),
          ),
      ],
      // Sans malt, le rendement d'empâtage n'entre pas dans le calcul (les
      // sucres comptent à 100 %) : le 0 ne change pas le résultat.
      mashEfficiencyPercent: efficiency ?? 0,
      volumeLitres: volume!,
    ),
  );
}

CalculationResult _finalGravity(RecipeInput recipe, CalculationResult og) {
  final yeast = recipe.yeasts.isEmpty ? null : recipe.yeasts.first;
  final attenuation = yeast?.attenuationPercent;
  return _resultOf(
    [
      if (og is CalculationUnavailable) _dependsOnOriginalGravity,
      if (yeast == null)
        const MissingInput(MissingInputKind.yeast)
      else if (attenuation == null)
        MissingInput(MissingInputKind.yeastAttenuation, [
          IngredientRef(0, yeast.name),
        ]),
    ],
    () => predictedFinalGravity(
      originalGravity: (og as CalculationComputed).value,
      attenuationPercent: attenuation!,
    ),
  );
}

(CalculationResult, List<HopBitterness>) _bitterness(
  RecipeInput recipe,
  CalculationResult og,
) {
  final volume = recipe.batchVolumeLitres;
  final hops = recipe.hops;
  bool isBoil(HopInput h) => h.use == HopUse.boil;
  final withoutAlpha = _refs(
    hops,
    (h) => isBoil(h) && h.alphaPercent == null,
    (h) => h.name,
  );
  final withoutTime = _refs(
    hops,
    (h) => isBoil(h) && h.minutes == null,
    (h) => h.name,
  );
  final missing = [
    if (volume == null) _missingVolume,
    if (hops.any(isBoil) && og is CalculationUnavailable)
      _dependsOnOriginalGravity,
    if (withoutAlpha.isNotEmpty)
      MissingInput(MissingInputKind.hopAlpha, withoutAlpha),
    if (withoutTime.isNotEmpty)
      MissingInput(MissingInputKind.hopBoilTime, withoutTime),
  ];
  if (missing.isNotEmpty) {
    return (CalculationUnavailable(List.unmodifiable(missing)), const []);
  }
  final perHop = <HopBitterness>[
    for (var i = 0; i < hops.length; i++)
      HopBitterness(
        IngredientRef(i, hops[i].name),
        // Hors ébullition, un houblon apporte 0 IBU (tinsethIbuForHop) : ses
        // acides alpha peuvent manquer, et la densité initiale n'est pas lue.
        isBoil(hops[i])
            ? tinsethIbuForHop(
                hop: Hop(
                  name: hops[i].name,
                  alphaPercent: hops[i].alphaPercent!,
                  massGrams: hops[i].massGrams,
                  use: hops[i].use,
                  form: hops[i].form,
                  boilMinutes: hops[i].minutes!,
                ),
                volumeLitres: volume!,
                boilGravity: (og as CalculationComputed).value,
              )
            : 0.0,
      ),
  ];
  final total = perHop.fold(0.0, (sum, h) => sum + h.ibu);
  return (CalculationComputed(total), perHop);
}

CalculationResult _color(RecipeInput recipe) {
  final volume = recipe.batchVolumeLitres;
  final fermentables = recipe.fermentables;
  final withoutColor = _refs(
    fermentables,
    (f) => f.colorEbc == null,
    (f) => f.name,
  );
  return _resultOf(
    [
      if (volume == null) _missingVolume,
      if (fermentables.isEmpty) _missingFermentables,
      if (withoutColor.isNotEmpty)
        MissingInput(MissingInputKind.color, withoutColor),
    ],
    () => moreyColorEbcOfGrist(
      grist: [
        for (final f in fermentables)
          (massGrams: f.massGrams, colorEbc: f.colorEbc!),
      ],
      volumeLitres: volume!,
    ),
  );
}
