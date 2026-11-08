import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../equipment/domain/equipment.dart';
import '../../recipes/domain/recipe.dart';

/// Longueur maximale du nom et des notes d'un brassin (`firestore.rules`).
const kBrewNameMaxLength = 120;
const kBrewNotesMaxLength = 10000;

/// Longueur maximale de la nature du sucre de resucrage (`firestore.rules`).
const kPrimingSugarNameMaxLength = 80;

/// Statut d'un brassin (`brews/{id}.status`).
enum BrewStatus {
  planned('planned', 'Prévu'),
  brewing('brewing', 'En cours'),
  fermenting('fermenting', 'En fermentation'),
  conditioning('conditioning', 'En conditionnement'),
  done('done', 'Terminé'),
  abandoned('abandoned', 'Abandonné');

  const BrewStatus(this.storedValue, this.label);

  final String storedValue;
  final String label;

  static BrewStatus fromStored(Object? value) {
    for (final status in values) {
      if (status.storedValue == value) return status;
    }
    throw const DocumentIllisible('status', 'statut inconnu');
  }
}

/// Mesure retenue d'un brassin : un champ d'identifiant sur `brews/{id}`, nul pour
/// la dernière mesure. On écrit l'identifiant, jamais la valeur (VR4).
enum MesureRetenueChamp {
  densiteInitiale('og_event_id'),
  densiteFinale('fg_event_id'),
  volumeFermenteur('fermenter_volume_event_id');

  const MesureRetenueChamp(this.storedField);

  final String storedField;
}

/// Document `brews/{id}` : un brassin fige sa recette et son équipement à sa
/// création (CLAUDE.md, « Un brassin fige sa recette »).
@immutable
class Brew {
  const Brew({
    required this.id,
    required this.ownerUid,
    this.ownerName,
    required this.name,
    required this.status,
    this.recipeId,
    required this.recipe,
    this.recipeUpdatedAt,
    required this.equipment,
    this.equipmentOwnerUid = '',
    this.plannedFor,
    this.brewedAt,
    this.bottledAt,
    this.bottlesCount,
    this.packagedVolumeL,
    this.primingSugarG,
    this.primingSugarName,
    this.ogEventId,
    this.fgEventId,
    this.fermenterVolumeEventId,
    this.sugarsInWort,
    this.notes,
    this.createdAt,
    this.hasPendingWrites = false,
  });

  final String id;

  /// Uid du propriétaire : seule base des droits.
  final String ownerUid;

  /// Nom du brasseur, pour l'affichage seul.
  final String? ownerName;
  final String name;
  final BrewStatus status;

  /// Recette d'origine ; elle peut avoir changé ou avoir été supprimée.
  final String? recipeId;

  /// Copie figée de la recette.
  final RecipeContent recipe;

  /// `updated_at` de la recette au moment de la copie (D-Q5).
  final DateTime? recipeUpdatedAt;

  /// Copie figée de l'équipement.
  final EquipmentContent equipment;
  final String equipmentOwnerUid;
  final DateTime? plannedFor;

  /// Heure du premier début d'étape (heure de l'appareil).
  final DateTime? brewedAt;

  /// Date d'embouteillage (date choisie, heure de l'appareil). Gardée après un
  /// retour en arrière : la reprise d'un abandon se déduit de ce champ (ST5).
  final DateTime? bottledAt;
  final int? bottlesCount;
  final double? packagedVolumeL;

  /// Masse totale de sucre de resucrage, en grammes. Aucun calcul (Q4, D5).
  final double? primingSugarG;
  final String? primingSugarName;

  /// Événement choisi comme densité initiale ; nul = dernière mesure.
  final String? ogEventId;

  /// Événement choisi comme densité finale ; nul = dernière mesure.
  final String? fgEventId;

  /// Événement choisi comme volume en fermenteur ; nul = dernière mesure.
  final String? fermenterVolumeEventId;

  /// Vrai si les sucres étaient dans le moût à la mesure ; nul sans réponse (RR3).
  final bool? sugarsInWort;
  final String? notes;

  /// `null` tant qu'une écriture locale attend le serveur.
  final DateTime? createdAt;
  final bool hasPendingWrites;

  /// Lit `brews/{id}` ; lève [DocumentIllisible] si un champ obligatoire manque ou
  /// si une copie figée est illisible.
  factory Brew.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    final read = LecteurChamps(data);
    final recipe = _map(data['recipe_snapshot'], 'recipe_snapshot');
    final equipment = _map(data['equipment_snapshot'], 'equipment_snapshot');
    final recipeUpdated = LecteurChamps(recipe).date('updated_at');
    return Brew(
      id: id,
      ownerUid: read.texte('owner_uid'),
      ownerName: read.texteFacultatif('owner_name'),
      name: read.texte('name'),
      status: BrewStatus.fromStored(data['status']),
      recipeId: read.texteFacultatif('recipe_id'),
      recipe: RecipeContent.fromFirestore(recipe),
      recipeUpdatedAt: recipeUpdated,
      equipment: EquipmentContent.fromFirestore(equipment),
      equipmentOwnerUid: equipment['owner_uid'] is String
          ? equipment['owner_uid'] as String
          : '',
      plannedFor: read.date('planned_for'),
      brewedAt: read.date('brewed_at'),
      bottledAt: read.date('bottled_at'),
      bottlesCount: read.nombreFacultatif('bottles_count')?.toInt(),
      packagedVolumeL: read.nombreFacultatif('packaged_volume_l'),
      primingSugarG: read.nombreFacultatif('priming_sugar_g'),
      primingSugarName: read.texteFacultatif('priming_sugar_name'),
      ogEventId: read.texteFacultatif('og_event_id'),
      fgEventId: read.texteFacultatif('fg_event_id'),
      fermenterVolumeEventId: read.texteFacultatif('fermenter_volume_event_id'),
      sugarsInWort: read.boolFacultatif('sugars_in_wort'),
      notes: read.texteFacultatif('notes'),
      createdAt: read.date('created_at'),
      hasPendingWrites: hasPendingWrites,
    );
  }

  /// Copie figée lue comme un équipement, pour les calculs et l'affichage.
  Equipment get equipmentRead =>
      Equipment(id: '', ownerUid: equipmentOwnerUid, content: equipment);

  /// Statut après une reprise : se déduit de [bottledAt] (ST5), aucun champ ne
  /// garde le statut précédent.
  BrewStatus get statutDeReprise =>
      bottledAt != null ? BrewStatus.conditioning : BrewStatus.fermenting;
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map) throw DocumentIllisible(field, 'map attendue');
  return Map<String, dynamic>.from(value);
}

/// Copie figée de [recipe] : mêmes champs de premier niveau que `recipes/`.
Map<String, Object?> recipeSnapshot(Recipe recipe) => {
  ...recipe.content.toFirestore(creation: true),
  'owner_uid': recipe.ownerUid,
  'owner_name': ?recipe.ownerName,
  if (recipe.updatedAt != null)
    'updated_at': Timestamp.fromDate(recipe.updatedAt!),
};

/// Copie figée de [equipment].
Map<String, Object?> equipmentSnapshot(Equipment equipment) => {
  ...equipment.content.toFirestore(creation: true),
  'owner_uid': equipment.ownerUid,
  'owner_name': ?equipment.ownerName,
};

int _bucket(BrewStatus status) => switch (status) {
  BrewStatus.brewing => 0,
  BrewStatus.fermenting || BrewStatus.conditioning => 1,
  BrewStatus.planned => 2,
  BrewStatus.done || BrewStatus.abandoned => 3,
};

/// Tri de la liste (ST10) : en cours, puis en fermentation et en conditionnement, puis
/// prévus par date croissante, puis terminés et abandonnés ; le reste du plus récent au
/// plus ancien.
int compareBrews(Brew a, Brew b) {
  final byBucket = _bucket(a.status).compareTo(_bucket(b.status));
  if (byBucket != 0) return byBucket;
  if (a.status == BrewStatus.planned) {
    final pa = a.plannedFor;
    final pb = b.plannedFor;
    if (pa == null || pb == null) {
      if (pa == pb) return a.name.compareTo(b.name);
      return pa == null ? 1 : -1;
    }
    return pa.compareTo(pb);
  }
  final da = a.brewedAt ?? a.createdAt;
  final db = b.brewedAt ?? b.createdAt;
  if (da == null || db == null) {
    if (da == db) return a.name.compareTo(b.name);
    return da == null ? -1 : 1;
  }
  return db.compareTo(da);
}

/// Durée pendant laquelle un brassin en cours se rouvre au lancement (D-Q3).
const kRepriseMaximum = Duration(hours: 24);

/// Le brassin en cours de [uid] commencé depuis moins de [kRepriseMaximum], s'il
/// y en a un seul.
Brew? brassinAReprendre(List<Brew> brews, String? uid, DateTime now) {
  final eligibles = [
    for (final b in brews)
      if (b.ownerUid == uid &&
          b.status == BrewStatus.brewing &&
          b.brewedAt != null &&
          now.difference(b.brewedAt!) < kRepriseMaximum)
        b,
  ];
  return eligibles.length == 1 ? eligibles.single : null;
}
