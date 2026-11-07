import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

/// Longueur maximale du nom (`firestore.rules`).
const kEquipmentNameMaxLength = 120;

/// Longueur maximale des notes (`firestore.rules`).
const kEquipmentNotesMaxLength = 10000;

/// Type d'installation, champ `kind` de `equipment/`.
enum EquipmentKind {
  /// Cuves séparées : cuve d'empâtage et cuve d'ébullition.
  multiVessel('multi_vessel', 'Cuves séparées'),

  /// Tout-en-un (Grainfather) : une seule cuve.
  allInOne('all_in_one', 'Tout-en-un');

  const EquipmentKind(this.storedValue, this.label);

  /// Valeur stockée.
  final String storedValue;

  /// Libellé affiché.
  final String label;

  /// Type de la valeur stockée [value] ; lève [DocumentIllisible] pour une valeur
  /// inconnue.
  static EquipmentKind fromStored(Object? value) {
    for (final kind in values) {
      if (kind.storedValue == value) return kind;
    }
    // La valeur, écrite par un autre membre, n'entre pas dans l'erreur rapportée.
    throw DocumentIllisible('kind', 'type inconnu (${_length(value)})');
  }
}

/// Champs saisis d'un équipement, sans propriétaire ni dates. Unités du système
/// international : litres, pourcentages de 0 à 100.
@immutable
class EquipmentContent {
  const EquipmentContent({
    required this.name,
    required this.kind,
    this.mashEfficiencyPct,
    this.mashTunVolumeL,
    this.kettleVolumeL,
    this.mashTunDeadSpaceL,
    this.kettleDeadSpaceL,
    this.boilOffLPerH,
    this.trubLossL,
    this.fermenterLossL,
    this.grainAbsorptionLPerKg,
    this.notes,
  });

  final String name;
  final EquipmentKind kind;

  /// Rendement d'empâtage, de 0 à 100 %.
  final double? mashEfficiencyPct;

  /// Volume de la cuve d'empâtage, ou de la cuve unique d'un tout-en-un.
  final double? mashTunVolumeL;

  /// Volume de la cuve d'ébullition ; toujours nul pour un tout-en-un.
  final double? kettleVolumeL;
  final double? mashTunDeadSpaceL;
  final double? kettleDeadSpaceL;
  final double? boilOffLPerH;
  final double? trubLossL;
  final double? fermenterLossL;
  final double? grainAbsorptionLPerKg;
  final String? notes;

  /// Lit les champs saisis de [data] ; lève [DocumentIllisible] si le nom ou le
  /// type manque, ou si un champ a un type inattendu.
  factory EquipmentContent.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    return EquipmentContent(
      name: read.texte('name'),
      kind: EquipmentKind.fromStored(data['kind']),
      mashEfficiencyPct: read.nombreFacultatif('mash_efficiency_pct'),
      mashTunVolumeL: read.nombreFacultatif('mash_tun_volume_l'),
      kettleVolumeL: read.nombreFacultatif('kettle_volume_l'),
      mashTunDeadSpaceL: read.nombreFacultatif('mash_tun_dead_space_l'),
      kettleDeadSpaceL: read.nombreFacultatif('kettle_dead_space_l'),
      boilOffLPerH: read.nombreFacultatif('boil_off_l_per_h'),
      trubLossL: read.nombreFacultatif('trub_loss_l'),
      fermenterLossL: read.nombreFacultatif('fermenter_loss_l'),
      grainAbsorptionLPerKg: read.nombreFacultatif('grain_absorption_l_per_kg'),
      notes: read.texteFacultatif('notes'),
    );
  }

  /// Champs à écrire. Un champ vide est absent à la création et retiré à la
  /// modification ([creation] faux). Un tout-en-un n'écrit pas les champs de la
  /// cuve d'ébullition.
  Map<String, Object?> toFirestore({required bool creation}) {
    final allInOne = kind == EquipmentKind.allInOne;
    Map<String, Object?> opt(String key, Object? value) =>
        champFacultatif(key, value, creation: creation);
    return {
      'name': name.trim(),
      'kind': kind.storedValue,
      ...opt('mash_efficiency_pct', mashEfficiencyPct),
      ...opt('mash_tun_volume_l', mashTunVolumeL),
      ...opt('kettle_volume_l', allInOne ? null : kettleVolumeL),
      ...opt('mash_tun_dead_space_l', mashTunDeadSpaceL),
      ...opt('kettle_dead_space_l', allInOne ? null : kettleDeadSpaceL),
      ...opt('boil_off_l_per_h', boilOffLPerH),
      ...opt('trub_loss_l', trubLossL),
      ...opt('fermenter_loss_l', fermenterLossL),
      ...opt('grain_absorption_l_per_kg', grainAbsorptionLPerKg),
      ...opt('notes', notes?.trim().isEmpty ?? true ? null : notes!.trim()),
    };
  }
}

/// Document `equipment/{id}`.
@immutable
class Equipment {
  const Equipment({
    required this.id,
    required this.ownerUid,
    this.ownerName,
    required this.content,
    this.updatedAt,
    this.hasPendingWrites = false,
  });

  final String id;

  /// Uid de l'auteur : seule base des droits et du tri « les miens d'abord ».
  final String ownerUid;

  /// Nom déclaré par l'auteur, pour l'affichage seul.
  final String? ownerName;
  final EquipmentContent content;

  /// `null` tant qu'une écriture locale attend le serveur.
  final DateTime? updatedAt;

  /// Écriture locale pas encore reçue par le serveur (« En attente du réseau »).
  final bool hasPendingWrites;

  String get name => content.name;

  /// Lit `equipment/{id}` ; lève [DocumentIllisible] si un champ obligatoire
  /// manque.
  factory Equipment.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    final read = LecteurChamps(data);
    return Equipment(
      id: id,
      ownerUid: read.texte('owner_uid'),
      ownerName: read.texteFacultatif('owner_name'),
      content: EquipmentContent.fromFirestore(data),
      updatedAt: read.date('updated_at'),
      hasPendingWrites: hasPendingWrites,
    );
  }
}

/// Tri de la liste : les équipements de [readerUid] d'abord, puis par nom.
int Function(Equipment, Equipment) compareEquipment(String? readerUid) =>
    (a, b) {
      final mineA = a.ownerUid == readerUid;
      final mineB = b.ownerUid == readerUid;
      if (mineA != mineB) return mineA ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    };

/// Description d'une valeur stockée inattendue, sans son contenu.
String _length(Object? value) => value is String
    ? '${value.length} caractères'
    : 'type ${value.runtimeType}';
