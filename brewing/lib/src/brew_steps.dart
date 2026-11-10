import 'bitterness.dart';
import 'errors.dart';
import 'recipe_calculation.dart';

/// Un palier d'empâtage tel qu'il est saisi : température et durée peuvent
/// manquer.
class MashStepInput {
  /// Crée le palier. [tempC] de 0 à 100 °C, [durationMinutes] positive ou nulle.
  MashStepInput({this.tempC, this.durationMinutes}) {
    final temp = tempC;
    if (temp != null) requireRange('tempC', temp, 0, 100);
    final duration = durationMinutes;
    if (duration != null) requireNonNegative('durationMinutes', duration);
  }

  /// Température en °C, ou nulle si elle n'est pas renseignée.
  final double? tempC;

  /// Durée en minutes, ou nulle si elle n'est pas renseignée.
  final double? durationMinutes;
}

/// Nature d'une étape préremplie. L'application en tire le libellé : nom du
/// palier, « Ébullition », « Ajouter {houblon} {masse} g », « Whirlpool ».
enum BrewStepKind {
  /// Palier d'empâtage `mashSteps[sourceIndex]`.
  mashStep,

  /// Tranche d'ébullition entre deux ajouts.
  boil,

  /// Ajout du houblon `hops[sourceIndex]`, 0 min.
  hopAddition,

  /// Tranche de whirlpool entre deux ajouts.
  whirlpool,
}

/// Défaut d'une étape préremplie, à corriger par le brasseur.
enum BrewStepProblem {
  /// Palier sans durée : l'étape n'a pas de durée ([BrewStepDraft.durationMinutes]
  /// nul).
  missingDuration,

  /// Houblon sans durée : placé en tête de sa section.
  missingHopTime,

  /// Houblon d'ébullition plus long que l'ébullition : placé en tête.
  hopLongerThanBoil,
}

/// Étape préremplie, sans clé : l'appelant crée la clé de chaque étape
/// (`doc().id` de Firestore) au moment de l'ajouter à la chronologie.
class BrewStepDraft {
  /// Crée l'étape.
  const BrewStepDraft({
    required this.kind,
    this.sourceIndex,
    this.durationMinutes,
    this.tempC,
    this.problem,
  });

  /// Nature de l'étape.
  final BrewStepKind kind;

  /// Place du palier ([BrewStepKind.mashStep]) ou du houblon
  /// ([BrewStepKind.hopAddition]) dans la liste reçue ; nulle sinon.
  final int? sourceIndex;

  /// Durée en minutes ; `null` pour un palier sans durée.
  final double? durationMinutes;

  /// Température visée en °C, ou nulle.
  final double? tempC;

  /// Défaut à corriger, ou nul.
  final BrewStepProblem? problem;
}

/// Chronologie préremplie depuis les paliers, l'ébullition et les houblons.
///
/// Une étape par palier, puis l'ébullition de [boilMinutes] coupée à chaque
/// ajout de houblon d'ébullition, du plus long au plus court : un houblon de
/// t min s'ajoute après [boilMinutes] − t min d'ébullition. Puis le whirlpool,
/// coupé de même aux houblons de whirlpool, sur la plus longue de leurs durées.
/// Houblons à cru, à l'empâtage et au conditionnement exclus. Un ajout dure
/// 0 min. Aucune durée n'est inventée : un palier sans durée rend une étape
/// sans durée, qui porte [BrewStepProblem.missingDuration] ; sans
/// [boilMinutes], aucune étape d'ébullition, et les ajouts se suivent du plus
/// long au plus court.
///
/// Lève [BrewingInputException] si [boilMinutes] est négative ou non finie.
List<BrewStepDraft> defaultBrewSteps({
  required List<MashStepInput> mashSteps,
  required double? boilMinutes,
  required List<HopInput> hops,
}) {
  if (boilMinutes != null) requireNonNegative('boilMinutes', boilMinutes);
  return [
    for (var i = 0; i < mashSteps.length; i++)
      BrewStepDraft(
        kind: BrewStepKind.mashStep,
        sourceIndex: i,
        durationMinutes: mashSteps[i].durationMinutes,
        tempC: mashSteps[i].tempC,
        problem: mashSteps[i].durationMinutes == null
            ? BrewStepProblem.missingDuration
            : null,
      ),
    ..._section(hops, HopUse.boil, BrewStepKind.boil, boilMinutes),
    ..._section(
      hops,
      HopUse.afterBoil,
      BrewStepKind.whirlpool,
      _longest(hops, HopUse.afterBoil),
    ),
  ];
}

/// Plus longue durée des houblons de [use], ou nulle si aucun n'en a.
double? _longest(List<HopInput> hops, HopUse use) {
  double? longest;
  for (final hop in hops) {
    final minutes = hop.minutes;
    if (hop.use != use || minutes == null) continue;
    if (longest == null || minutes > longest) longest = minutes;
  }
  return longest;
}

/// Section d'ébullition ou de whirlpool de [total] minutes, coupée aux ajouts
/// des houblons de [use].
List<BrewStepDraft> _section(
  List<HopInput> hops,
  HopUse use,
  BrewStepKind segment,
  double? total,
) {
  // Sans durée d'abord, puis du plus long au plus court ; à égalité, dans
  // l'ordre de la recette.
  final order = [
    for (var i = 0; i < hops.length; i++)
      if (hops[i].use == use) i,
  ];
  order.sort((a, b) {
    final ma = hops[a].minutes;
    final mb = hops[b].minutes;
    if (ma == null || mb == null) {
      if (ma == null && mb == null) return a.compareTo(b);
      return ma == null ? -1 : 1;
    }
    final byTime = mb.compareTo(ma);
    return byTime != 0 ? byTime : a.compareTo(b);
  });

  final steps = <BrewStepDraft>[];
  var elapsed = 0.0;
  for (final index in order) {
    final minutes = hops[index].minutes;
    final tooLong = total != null && minutes != null && minutes > total;
    // Minutes restantes avant la fin de la section au moment de l'ajout.
    final remaining = tooLong ? total : minutes;
    if (total != null && remaining != null) {
      final gap = total - remaining - elapsed;
      if (gap > 0) {
        steps.add(BrewStepDraft(kind: segment, durationMinutes: gap));
        elapsed += gap;
      }
    }
    steps.add(
      BrewStepDraft(
        kind: BrewStepKind.hopAddition,
        sourceIndex: index,
        durationMinutes: 0,
        problem: minutes == null
            ? BrewStepProblem.missingHopTime
            : tooLong
            ? BrewStepProblem.hopLongerThanBoil
            : null,
      ),
    );
  }
  if (total != null && total - elapsed > 0) {
    steps.add(BrewStepDraft(kind: segment, durationMinutes: total - elapsed));
  }
  return steps;
}
