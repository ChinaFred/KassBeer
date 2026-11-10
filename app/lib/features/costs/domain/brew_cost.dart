import 'package:brewing/brewing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

/// Nombre de lignes d'un coût figé au plus (`firestore.rules`, SE6).
const kMaxBrewCostLines = 200;

/// Écriture d'un coût figé : premier figeage (création seule) ou « Recalculer
/// avec mes prix actuels » (modification seule). Les règles refusent l'un à la
/// place de l'autre (SE2).
enum FreezeKind {
  initial('initial'),
  recalculation('recalculation');

  const FreezeKind(this.storedValue);

  final String storedValue;
}

/// Ligne d'un coût figé : quantité et coût du jour du figeage.
@immutable
class BrewCostLine {
  const BrewCostLine({
    required this.key,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.costEur,
  });

  /// Clé d'ingrédient, ou `frais-{id}` pour un frais.
  final String key;
  final String name;

  /// Grammes, sachets, 1 (par brassin) ou bouteilles.
  final double quantity;
  final CostUnit unit;
  final double costEur;

  factory BrewCostLine.fromFirestore(LecteurChamps read) {
    final quantity = read.nombre('quantity');
    final cost = read.nombre('cost_eur');
    if (quantity < 0 || cost < 0) {
      throw DocumentIllisible('${read.prefix}cost_eur', 'valeur négative');
    }
    return BrewCostLine(
      key: read.texte('key'),
      name: read.texte('name'),
      quantity: quantity,
      unit: _unit(read.data['unit'], '${read.prefix}unit'),
      costEur: cost,
    );
  }

  Map<String, Object?> toFirestore() => {
    'key': key,
    'name': name,
    'quantity': quantity,
    'unit': unit.storedValue,
    'cost_eur': costEur,
  };
}

CostUnit _unit(Object? value, String field) {
  for (final unit in CostUnit.values) {
    // `l` depuis la v0.1.17 : ligne mesurée en volume, chiffrée au prix au litre.
    if (unit.storedValue == value) return unit;
  }
  throw DocumentIllisible(field, 'unité inconnue');
}

/// Document `users/{uid}/brew_costs/{brewId}` : coût réel d'un brassin, figé avec
/// les prix du jour (CB12). Il garde les valeurs d'embouteillage utilisées, pour
/// signaler un écart (CB15).
@immutable
class BrewCost {
  const BrewCost({
    required this.brewId,
    required this.totalEur,
    required this.lines,
    required this.computedAt,
    required this.freezeKind,
    this.bottlesCount,
    this.packagedVolumeL,
    this.primingSugarG,
    this.primingSugarName,
    this.hasPendingWrites = false,
  });

  final String brewId;

  /// Somme exacte des lignes, sans arrondi.
  final double totalEur;
  final List<BrewCostLine> lines;

  /// Heure de l'appareil au figeage (HL3).
  final DateTime computedAt;
  final FreezeKind freezeKind;
  final int? bottlesCount;
  final double? packagedVolumeL;
  final double? primingSugarG;
  final String? primingSugarName;
  final bool hasPendingWrites;

  /// Coût d'une bouteille réelle (CB13), ou `null` sans nombre de bouteilles.
  double? get perBottleEur => bottlesCount == null
      ? null
      : costPerBottle(total: totalEur, bottles: bottlesCount!);

  /// Coût par litre conditionné (CB14), ou `null` sans volume conditionné : la
  /// valeur prévue ne remplace jamais une mesure.
  double? get perLitreEur => packagedVolumeL == null
      ? null
      : costPerLitre(total: totalEur, volumeLitres: packagedVolumeL!);

  /// Lit le document ; lève [DocumentIllisible] si un champ manque ou sort des
  /// bornes des règles (CB20). Aucune valeur reçue n'entre dans l'erreur.
  factory BrewCost.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    final read = LecteurChamps(data);
    final total = read.nombre('total_eur');
    if (total < 0) {
      throw const DocumentIllisible('total_eur', 'total négatif');
    }
    final computedAt = read.date('computed_at');
    if (computedAt == null) {
      throw const DocumentIllisible('computed_at', 'date absente');
    }
    final bottles = read.nombreFacultatif('bottles_count');
    if (bottles != null &&
        (bottles < 1 || bottles != bottles.roundToDouble())) {
      throw const DocumentIllisible('bottles_count', 'nombre de bouteilles');
    }
    final volume = read.nombreFacultatif('packaged_volume_l');
    if (volume != null && volume <= 0) {
      throw const DocumentIllisible('packaged_volume_l', 'volume nul');
    }
    final kind = data['freeze_kind'];
    return BrewCost(
      brewId: id,
      totalEur: total,
      lines: List.unmodifiable(
        read.liste('lines').map(BrewCostLine.fromFirestore),
      ),
      computedAt: computedAt,
      freezeKind: FreezeKind.values.firstWhere(
        (k) => k.storedValue == kind,
        orElse: () =>
            throw const DocumentIllisible('freeze_kind', 'valeur inconnue'),
      ),
      bottlesCount: bottles?.toInt(),
      packagedVolumeL: volume,
      primingSugarG: read.nombreFacultatif('priming_sugar_g'),
      primingSugarName: read.texteFacultatif('priming_sugar_name'),
      hasPendingWrites: hasPendingWrites,
    );
  }

  /// Document complet : il remplace le précédent en entier (CB16).
  Map<String, Object?> toFirestore() => {
    'brew_id': brewId,
    'total_eur': totalEur,
    'lines': [for (final l in lines) l.toFirestore()],
    'computed_at': Timestamp.fromDate(computedAt),
    'freeze_kind': freezeKind.storedValue,
    'bottles_count': ?bottlesCount,
    'packaged_volume_l': ?packagedVolumeL,
    'priming_sugar_g': ?primingSugarG,
    'priming_sugar_name': ?primingSugarName,
  };
}
