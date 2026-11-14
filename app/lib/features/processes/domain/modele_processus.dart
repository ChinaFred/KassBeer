import 'package:brewing/brewing.dart'
    show
        ProcessTemplateIssueKind,
        ProcessTemplateItem,
        ProcessTemplateSession,
        maxProcessOffsetDays,
        maxProcessSessions,
        processTemplateIssue;
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../recipes/domain/chronologie.dart';
import '../../recipes/domain/recipe.dart' show truncateName;

/// Modèle de processus (`process_templates/{id}`, ADR-010) : de 1 à 5 journées
/// nommées, chacune avec son écart en jours et ses étapes, dont les blocs tirés de
/// la recette. Lu par le groupe, écrit par son auteur. La résolution avec une
/// recette se fait dans `brewing/` (P3).

/// Version du format d'un modèle.
const kModeleFormatVersion = 1;

/// Longueurs maximales (`firestore.rules`).
const kNomModeleMaxLength = 120;
const kNotesModeleMaxLength = 10000;
const kNomJourneeModeleMaxLength = 120;

/// Éléments d'une journée de modèle, blocs compris.
const kMaxElementsJourneeModele = 60;

/// Longueur d'une clé de journée ou d'élément.
const kCleModeleMaxLength = 100;

/// Nature d'un élément de journée (`kind`).
enum NatureElement {
  etape('step', ProcessTemplateItem.step),
  chronologieRecette('recipe_steps', ProcessTemplateItem.recipeSteps),
  houblonsACru('dry_hops', ProcessTemplateItem.dryHops),
  ajoutsEmbouteillage(
    'packaging_additions',
    ProcessTemplateItem.packagingAdditions,
  );

  const NatureElement(this.storedValue, this.item);

  final String storedValue;

  /// Nature vue par la résolution de `brewing/`.
  final ProcessTemplateItem item;

  static NatureElement fromStored(Object? value, String field) {
    for (final n in values) {
      if (n.storedValue == value) return n;
    }
    throw DocumentIllisible(field, 'nature inconnue');
  }
}

/// Élément d'une journée : une étape (nom, durée, température facultative), ou
/// un bloc tiré de la recette, sans nom ni durée.
@immutable
class ElementModele {
  const ElementModele.etape({
    required this.key,
    required String this.name,
    required double this.durationMin,
    this.tempC,
  }) : nature = NatureElement.etape;

  const ElementModele.bloc({required this.key, required this.nature})
    : name = null,
      durationMin = null,
      tempC = null;

  final String key;
  final NatureElement nature;

  /// Nom, durée en minutes et température : étape seulement.
  final String? name;
  final double? durationMin;
  final double? tempC;

  bool get estBloc => nature != NatureElement.etape;

  factory ElementModele.fromFirestore(LecteurChamps read) {
    final key = read.texte('key');
    final nature = NatureElement.fromStored(
      read.data['kind'],
      '${read.prefix}kind',
    );
    if (nature != NatureElement.etape) {
      return ElementModele.bloc(key: key, nature: nature);
    }
    return ElementModele.etape(
      key: key,
      name: read.texte('name'),
      durationMin: read.nombre('duration_min'),
      tempC: read.nombreFacultatif('temp_c'),
    );
  }

  /// Liste blanche des champs : aucun prix, stock ni coût (P5).
  Map<String, Object?> toFirestore() => {
    'key': key,
    'kind': nature.storedValue,
    if (!estBloc) ...{
      'name': name!.trim(),
      'duration_min': durationMin,
      'temp_c': ?tempC,
    },
  };
}

/// Journée d'un modèle.
@immutable
class JourneeModele {
  const JourneeModele({
    required this.key,
    required this.name,
    required this.offsetDays,
    required this.elements,
    this.requiresRecipeBlock = false,
  });

  final String key;
  final String name;

  /// Écart en jours depuis le début du brassage.
  final int offsetDays;

  /// La journée n'entre dans un brassin que si son bloc tiré de la recette n'est
  /// pas vide.
  final bool requiresRecipeBlock;
  final List<ElementModele> elements;

  factory JourneeModele.fromFirestore(LecteurChamps read) {
    final offset = read.data['offset_days'];
    if (offset is! int) {
      throw DocumentIllisible('${read.prefix}offset_days', 'entier attendu');
    }
    return JourneeModele(
      key: read.texte('key'),
      name: read.texte('name'),
      offsetDays: offset,
      requiresRecipeBlock:
          read.boolFacultatif('requires_recipe_block') ?? false,
      elements: List.unmodifiable([
        for (final e in read.liste('steps')) ElementModele.fromFirestore(e),
      ]),
    );
  }

  Map<String, Object?> toFirestore() => {
    'key': key,
    'name': name.trim(),
    'offset_days': offsetDays,
    if (requiresRecipeBlock) 'requires_recipe_block': true,
    'steps': [for (final e in elements) e.toFirestore()],
  };

  /// Journée vue par la résolution de `brewing/`. Lève `BrewingInputException`
  /// pour un écart hors de 0 à 365 jours.
  ProcessTemplateSession toInput() => ProcessTemplateSession(
    offsetDays: offsetDays,
    requiresRecipeBlock: requiresRecipeBlock,
    items: [for (final e in elements) e.nature.item],
  );
}

/// Contenu d'un modèle : ce que l'auteur saisit.
@immutable
class ContenuModele {
  const ContenuModele({required this.name, required this.journees, this.notes});

  final String name;
  final String? notes;
  final List<JourneeModele> journees;

  /// Lève [DocumentIllisible] si un champ obligatoire manque, si le format est
  /// inconnu ou si une journée est illisible. Un champ inconnu est ignoré.
  factory ContenuModele.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    if (data['format_version'] != kModeleFormatVersion) {
      throw const DocumentIllisible('format_version', 'format inconnu');
    }
    return ContenuModele(
      name: read.texte('name'),
      notes: read.texteFacultatif('notes'),
      journees: List.unmodifiable([
        for (final j in read.liste('sessions')) JourneeModele.fromFirestore(j),
      ]),
    );
  }

  /// Champs du contenu ; le dépôt ajoute propriétaire et dates. Ne s'écrit
  /// qu'après [erreurModele].
  Map<String, Object?> toFirestore() => {
    'format_version': kModeleFormatVersion,
    'name': name.trim(),
    'notes': notes?.trim(),
    'sessions': [for (final j in journees) j.toFirestore()],
  };
}

/// Document `process_templates/{id}`.
@immutable
class ModeleProcessus {
  const ModeleProcessus({
    required this.id,
    required this.ownerUid,
    required this.content,
    this.ownerName,
    this.createdAt,
    this.updatedAt,
    this.hasPendingWrites = false,
  });

  final String id;

  /// Uid de l'auteur : seule base des droits.
  final String ownerUid;

  /// Nom de l'auteur, pour l'affichage seul.
  final String? ownerName;
  final ContenuModele content;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Une écriture locale attend le serveur (« En attente du réseau »).
  final bool hasPendingWrites;

  /// Lit `process_templates/{id}` ; lève [DocumentIllisible] comme
  /// [ContenuModele.fromFirestore].
  factory ModeleProcessus.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    final read = LecteurChamps(data);
    return ModeleProcessus(
      id: id,
      ownerUid: read.texte('owner_uid'),
      ownerName: read.texteFacultatif('owner_name'),
      content: ContenuModele.fromFirestore(data),
      createdAt: read.date('created_at'),
      updatedAt: read.date('updated_at'),
      hasPendingWrites: hasPendingWrites,
    );
  }
}

/// Copie de [modele] avec des clés neuves pour chaque journée et chaque élément
/// ([nouvelleCle] : `doc().id`) : copie d'un modèle du groupe, duplication. Le nom
/// devient [name] s'il est donné, coupé à [kNomModeleMaxLength] caractères.
ContenuModele copieModele(
  ContenuModele modele,
  String Function() nouvelleCle, {
  String? name,
}) => ContenuModele(
  name: name == null ? modele.name : truncateName(name, kNomModeleMaxLength),
  notes: modele.notes,
  journees: [
    for (final j in modele.journees)
      JourneeModele(
        key: nouvelleCle(),
        name: j.name,
        offsetDays: j.offsetDays,
        requiresRecipeBlock: j.requiresRecipeBlock,
        elements: [
          for (final e in j.elements)
            e.estBloc
                ? ElementModele.bloc(key: nouvelleCle(), nature: e.nature)
                : ElementModele.etape(
                    key: nouvelleCle(),
                    name: e.name!,
                    durationMin: e.durationMin!,
                    tempC: e.tempC,
                  ),
        ],
      ),
  ],
);

/// Première erreur d'un modèle à enregistrer, ou `null`. Les règles ne lisent
/// pas les journées : le dépôt n'écrit le modèle qu'à cette condition.
String? erreurModele(ContenuModele modele) {
  final name = modele.name.trim();
  if (name.isEmpty || name.length > kNomModeleMaxLength) {
    return 'Nom : de 1 à $kNomModeleMaxLength caractères.';
  }
  final notes = modele.notes?.trim();
  if (notes != null && notes.length > kNotesModeleMaxLength) {
    return 'Notes : $kNotesModeleMaxLength caractères au plus.';
  }
  final journees = modele.journees;
  if (journees.isEmpty || journees.length > maxProcessSessions) {
    return 'De 1 à $maxProcessSessions journées.';
  }
  final journeeKeys = <String>{};
  final elementKeys = <String>{};
  for (final (i, j) in journees.indexed) {
    final rang = 'Journée ${i + 1}';
    if (!_cleValide(j.key) || !journeeKeys.add(j.key)) {
      return '$rang : clé invalide.';
    }
    final jName = j.name.trim();
    if (jName.isEmpty || jName.length > kNomJourneeModeleMaxLength) {
      return '$rang : nom de 1 à $kNomJourneeModeleMaxLength caractères.';
    }
    if (j.offsetDays < 0 || j.offsetDays > maxProcessOffsetDays) {
      return '$rang : écart de 0 à $maxProcessOffsetDays jours.';
    }
    if (j.elements.length > kMaxElementsJourneeModele) {
      return '$rang : $kMaxElementsJourneeModele étapes au plus.';
    }
    for (final (k, e) in j.elements.indexed) {
      final where = '$rang, étape ${k + 1}';
      if (!_cleValide(e.key) || !elementKeys.add(e.key)) {
        return '$where : clé invalide.';
      }
      if (e.estBloc) continue;
      final eName = e.name!.trim();
      if (eName.isEmpty || eName.length > kBrewStepNameMaxLength) {
        return '$where : nom de 1 à $kBrewStepNameMaxLength caractères.';
      }
      final duration = e.durationMin!;
      if (duration.isNaN || duration < 0 || duration > kBrewStepMaxMinutes) {
        return '$where : durée hors de 0 à 600 minutes.';
      }
      final temp = e.tempC;
      if (temp != null && (temp.isNaN || temp < 0 || temp > kBrewStepMaxTemp)) {
        return '$where : température hors de 0 à 100 °C.';
      }
    }
  }
  final issue = processTemplateIssue([for (final j in journees) j.toInput()]);
  if (issue == null) return null;
  final index = issue.sessionIndex;
  final message = _messageDefaut(issue.kind);
  return index == null ? message : 'Journée ${index + 1} : $message';
}

bool _cleValide(String key) =>
    key.isNotEmpty && key.length <= kCleModeleMaxLength;

String _messageDefaut(ProcessTemplateIssueKind kind) => switch (kind) {
  ProcessTemplateIssueKind.noSession => 'Au moins une journée.',
  ProcessTemplateIssueKind.tooManySessions =>
    '$maxProcessSessions journées au plus.',
  ProcessTemplateIssueKind.firstOffsetNotZero =>
    'la première journée est le jour du brassage, à J+0.',
  ProcessTemplateIssueKind.recipeStepsMissing =>
    'la première journée porte la chronologie de la recette.',
  ProcessTemplateIssueKind.recipeStepsTwice =>
    'la chronologie de la recette n\'apparaît qu\'une fois, le jour du '
        'brassage.',
  ProcessTemplateIssueKind.blockInFirstSession =>
    'houblons à cru et ajouts à l\'embouteillage n\'entrent pas dans le jour '
        'du brassage.',
  ProcessTemplateIssueKind.dryHopsTwice => 'un seul bloc de houblons à cru.',
  ProcessTemplateIssueKind.packagingTwice =>
    'un seul bloc d\'ajouts à l\'embouteillage.',
  ProcessTemplateIssueKind.dryHopsWithPackaging =>
    'houblons à cru et ajouts à l\'embouteillage vont dans deux journées '
        'différentes.',
  ProcessTemplateIssueKind.requiresRecipeBlockWithoutBlock =>
    'une journée conditionnée à la recette porte des houblons à cru ou des '
        'ajouts à l\'embouteillage.',
  ProcessTemplateIssueKind.offsetDecreasing =>
    'écart plus petit que celui de la journée précédente.',
};
