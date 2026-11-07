import 'package:cloud_firestore/cloud_firestore.dart';

/// Document Firestore qu'on ne peut pas lire sans inventer une valeur : champ
/// obligatoire absent, type inattendu. Le dépôt de données la rapporte par
/// `ErrorReportService.reportError` ; l'écran affiche le document comme illisible.
class DocumentIllisible implements Exception {
  const DocumentIllisible(this.field, this.reason);

  /// Champ fautif (`name`, `fermentables[2].weight_g`…).
  final String field;

  /// Raison, en français.
  final String reason;

  @override
  String toString() => 'DocumentIllisible($field) : $reason';
}

/// Lecture stricte des champs d'un document ou d'un élément de liste. Aucune valeur
/// par défaut : un champ obligatoire absent ou mal typé lève [DocumentIllisible].
class LecteurChamps {
  const LecteurChamps(this.data, [this.prefix = '']);

  final Map<String, dynamic> data;

  /// Préfixe du nom des champs dans les erreurs (`hops[1].`).
  final String prefix;

  String _path(String key) => '$prefix$key';

  /// Chaîne obligatoire, non vide après retrait des espaces.
  String texte(String key) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw DocumentIllisible(_path(key), 'texte obligatoire absent');
  }

  /// Chaîne facultative ; vide ou absente rend `null`.
  String? texteFacultatif(String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! String) {
      throw DocumentIllisible(_path(key), 'texte attendu');
    }
    return value.trim().isEmpty ? null : value;
  }

  /// Nombre obligatoire.
  double nombre(String key) {
    final value = data[key];
    if (value is num && value.isFinite) return value.toDouble();
    throw DocumentIllisible(_path(key), 'nombre obligatoire absent');
  }

  /// Nombre facultatif.
  double? nombreFacultatif(String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is num && value.isFinite) return value.toDouble();
    throw DocumentIllisible(_path(key), 'nombre attendu');
  }

  /// Liste de maps facultative ; absente rend une liste vide.
  List<LecteurChamps> liste(String key) {
    final value = data[key];
    if (value == null) return const [];
    if (value is! List) throw DocumentIllisible(_path(key), 'liste attendue');
    return [
      for (var i = 0; i < value.length; i++)
        if (value[i] is Map<String, dynamic>)
          LecteurChamps(value[i] as Map<String, dynamic>, '${_path(key)}[$i].')
        else
          throw DocumentIllisible('${_path(key)}[$i]', 'élément illisible'),
    ];
  }

  /// Date facultative (`updated_at` est nulle tant qu'une écriture locale attend
  /// le serveur).
  DateTime? date(String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    throw DocumentIllisible(_path(key), 'date attendue');
  }
}

/// Champ facultatif à écrire : absent à la création, retiré
/// (`FieldValue.delete()`) à la modification quand il n'a pas de valeur.
Map<String, Object?> champFacultatif(
  String key,
  Object? value, {
  required bool creation,
}) {
  if (value != null) return {key: value};
  return creation ? const {} : {key: FieldValue.delete()};
}

/// Auteur d'un contenu partagé, tel que le groupe le voit (arbitrage A1) :
/// « Vous » pour soi, sinon le nom déclaré par l'auteur, sinon « Autre brasseur ».
/// Libellé seul : aucun droit ne s'appuie sur `owner_name`, seulement sur
/// `owner_uid`.
String libelleAuteur({
  required String ownerUid,
  required String? ownerName,
  required String? readerUid,
}) {
  if (ownerUid == readerUid) return 'Vous';
  return ownerName ?? 'Autre brasseur';
}

/// Création en cours : identifiant créé par l'appareil, connu avant la réponse du
/// serveur ; `written` se termine quand le serveur a accepté l'écriture.
typedef CreationEnCours = ({String id, Future<void> written});

/// Vue d'un document lu dans une liste : contenu, ou raison de l'échec de lecture.
sealed class DocumentLu<T> {
  const DocumentLu(this.id);

  final String id;
}

/// Document lu.
class DocumentValide<T> extends DocumentLu<T> {
  const DocumentValide(super.id, this.value);

  final T value;
}

/// Document illisible, déjà rapporté par le dépôt de données.
class DocumentInvalide<T> extends DocumentLu<T> {
  const DocumentInvalide(super.id, this.error);

  final Object error;
}

/// Liste d'une collection : documents lus, et provenance de la lecture.
class ListeLue<T> {
  const ListeLue({required this.documents, required this.fromCache});

  final List<DocumentLu<T>> documents;

  /// Vrai quand la lecture vient du cache local : un document absent peut
  /// exister sur le serveur.
  final bool fromCache;

  /// Documents lus, sans les illisibles.
  List<T> get valides => [
    for (final d in documents)
      if (d is DocumentValide<T>) d.value,
  ];

  /// Le document [id] ; voir [RechercheDocument].
  RechercheDocument<T> chercher(String id) {
    for (final d in documents) {
      if (d.id != id) continue;
      return switch (d) {
        DocumentValide<T>(:final value) => DocumentTrouve(value),
        DocumentInvalide<T>(:final error) => DocumentIllisibleTrouve(error),
      };
    }
    return fromCache ? DocumentAbsentDuCache<T>() : DocumentAbsent<T>();
  }
}

/// Résultat de la recherche d'un document dans une [ListeLue].
sealed class RechercheDocument<T> {
  const RechercheDocument();
}

class DocumentTrouve<T> extends RechercheDocument<T> {
  const DocumentTrouve(this.value);

  final T value;
}

class DocumentIllisibleTrouve<T> extends RechercheDocument<T> {
  const DocumentIllisibleTrouve(this.error);

  final Object error;
}

/// Absent d'une lecture du serveur : le document n'existe pas ou a été supprimé.
class DocumentAbsent<T> extends RechercheDocument<T> {
  const DocumentAbsent();
}

/// Absent du cache seul : rien ne prouve qu'il n'existe pas (comme `watchMember`).
class DocumentAbsentDuCache<T> extends RechercheDocument<T> {
  const DocumentAbsentDuCache();
}
