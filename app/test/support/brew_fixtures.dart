import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/deroule.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/recipes/domain/chronologie.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

const palier = BrewStepLine(
  key: 'k-palier',
  name: 'Palier 68',
  durationMin: 45,
  tempC: 68,
);
const ebullition = BrewStepLine(
  key: 'k-ebullition',
  name: 'Ébullition',
  durationMin: 60,
);
const ajout = BrewStepLine(
  key: 'k-ajout',
  name: 'Ajouter Cascade',
  durationMin: 0,
);

/// Document `recipes/` ou copie figée au format BeerJSON partiel, réduit au nom ;
/// [extra] ajoute des champs à l'enveloppe.
Map<String, dynamic> recetteMinimale(
  String name, {
  Map<String, dynamic> extra = const {},
}) => {
  'format_version': 1,
  'recipe': <String, dynamic>{'name': name, 'ingredients': <String, dynamic>{}},
  ...extra,
};

const equipementTest = EquipmentContent(
  name: 'Grainfather',
  kind: EquipmentKind.allInOne,
  mashEfficiencyPct: 72,
);

Brew unBrassin({
  String id = 'b1',
  String owner = 'uid-brasseur',
  BrewStatus status = BrewStatus.brewing,
  List<BrewStepLine> steps = const [palier, ebullition],
  DateTime? brewedAt,
  DateTime? plannedFor,
  DateTime? bottledAt,
  int? bottlesCount,
  double? packagedVolumeL,
  double? primingSugarG,
  String? primingSugarName,
  String? ogEventId,
  String? fgEventId,
  bool? sugarsInWort,
  RecipeContent? recipe,
  Deroule? process,
}) => Brew(
  id: id,
  ownerUid: owner,
  ownerName: 'Bruno Brasseur',
  name: 'Blonde du jour',
  status: status,
  recipeId: 'r1',
  recipe: recipe ?? RecipeContent(name: 'Blonde', brewSteps: steps),
  equipment: equipementTest,
  plannedFor: plannedFor,
  brewedAt: brewedAt,
  bottledAt: bottledAt,
  bottlesCount: bottlesCount,
  packagedVolumeL: packagedVolumeL,
  primingSugarG: primingSugarG,
  primingSugarName: primingSugarName,
  ogEventId: ogEventId,
  fgEventId: fgEventId,
  sugarsInWort: sugarsInWort,
  process: process,
);

/// Relevé de fermentation (phase `fermentation`, sans étape).
BrewEvent releve(
  String id,
  MeasureType type,
  double value,
  DateTime at, {
  String? note,
  bool pending = false,
}) => BrewEvent(
  id: id,
  ownerUid: 'uid-brasseur',
  kind: BrewEventKind.measurement,
  measureType: type,
  value: value,
  note: note,
  measuredAt: at,
  phase: PhaseEvenement.fermentation,
  hasPendingWrites: pending,
);

/// Note de fermentation seule.
BrewEvent noteDeReleve(String id, String note, DateTime at) => BrewEvent(
  id: id,
  ownerUid: 'uid-brasseur',
  kind: BrewEventKind.note,
  note: note,
  measuredAt: at,
  phase: PhaseEvenement.fermentation,
);

BrewEvent debut(String id, String stepKey, DateTime at) => BrewEvent(
  id: id,
  ownerUid: 'uid-brasseur',
  kind: BrewEventKind.started,
  stepKey: stepKey,
  measuredAt: at,
);

BrewEvent fin(String id, String stepKey, DateTime at) => BrewEvent(
  id: id,
  ownerUid: 'uid-brasseur',
  kind: BrewEventKind.ended,
  stepKey: stepKey,
  measuredAt: at,
);

BrewEvent saut(String id, String stepKey, DateTime at) => BrewEvent(
  id: id,
  ownerUid: 'uid-brasseur',
  kind: BrewEventKind.skipped,
  stepKey: stepKey,
  measuredAt: at,
);

BrewEvent mesure(
  String id,
  String? stepKey,
  MeasureType type,
  double value,
  DateTime at, {
  bool pending = false,
}) => BrewEvent(
  id: id,
  ownerUid: 'uid-brasseur',
  kind: BrewEventKind.measurement,
  stepKey: stepKey,
  measureType: type,
  value: value,
  measuredAt: at,
  hasPendingWrites: pending,
);
