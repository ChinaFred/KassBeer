import 'package:brewing/brewing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

/// Bornes d'un frais (`firestore.rules`, FR1).
const kFeeNameMaxLength = 60;
const kFeeMaxEur = 10000.0;

/// Nombre de frais au plus : limite du formulaire, les règles ne comptent pas
/// les documents (FR1).
const kMaxFees = 20;

/// Document `users/{uid}/fees/{id}` : un frais hors ingrédients (eau,
/// électricité, embouteillage), par brassin ou par bouteille. Privé (P5).
@immutable
class Fee {
  const Fee({
    required this.id,
    required this.name,
    required this.amountEur,
    required this.basis,
    this.updatedAt,
    this.hasPendingWrites = false,
  });

  /// Identifiant créé par l'appareil.
  final String id;
  final String name;

  /// Montant en euros, par brassin ou par bouteille selon [basis].
  final double amountEur;
  final FeeBasis basis;

  /// `null` tant qu'une écriture locale attend le serveur.
  final DateTime? updatedAt;
  final bool hasPendingWrites;

  /// Clé de la ligne du frais dans un coût figé (`brew_costs.lines[].key`).
  String get lineKey => 'frais-$id';

  /// Lit le document ; lève [DocumentIllisible] si un champ manque ou sort des
  /// bornes des règles. Aucune valeur reçue n'entre dans l'erreur.
  factory Fee.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    final read = LecteurChamps(data);
    final amount = read.nombre('amount_eur');
    if (amount < 0 || amount > kFeeMaxEur) {
      throw const DocumentIllisible('amount_eur', 'montant hors limites');
    }
    return Fee(
      id: id,
      name: read.texte('name'),
      amountEur: amount,
      basis: _basis(data['basis']),
      updatedAt: read.date('updated_at'),
      hasPendingWrites: hasPendingWrites,
    );
  }

  /// Champs à écrire ; `updated_at` est posée par le serveur.
  Map<String, Object?> toFirestore() => {
    'name': name.trim(),
    'amount_eur': amountEur,
    'basis': basis.storedValue,
    'updated_at': FieldValue.serverTimestamp(),
  };
}

FeeBasis _basis(Object? value) {
  for (final basis in FeeBasis.values) {
    if (basis.storedValue == value) return basis;
  }
  throw const DocumentIllisible('basis', 'base inconnue');
}
