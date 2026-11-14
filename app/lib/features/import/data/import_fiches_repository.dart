import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:exchange/fiches.dart' show TypeEquipementFiche;

import '../../../core/data/lecture_document.dart';
import '../../brews/domain/brew.dart';
import '../../brews/domain/brew_event.dart';
import '../../costs/data/costs_repository.dart' show brewCostRef;
import '../../equipment/domain/equipment.dart';
import '../../recipes/domain/recipe.dart';
import '../domain/fiches_a_importer.dart';

/// Accès de Admin › Import (v0.6) à `recipes/`, `brews/`, `brews/{id}/events/`
/// et à l'existence des coûts figés de l'administrateur. Identifiants fixés
/// par le fichier (ID1) : les dépôts de recettes et de brassins créent les
/// leurs sur l'appareil, d'où ce dépôt. Le coût figé passe par
/// `CostsRepository.saveBrewCost`.
///
/// Aucun `catch` ici : l'écran et l'exécution de l'import rapportent chaque
/// erreur avec le rang de la fiche et l'étape d'écriture (EC10). Chaque
/// `Future` d'écriture se termine quand le serveur a accepté l'écriture.
abstract class ImportFichesRepository {
  /// Lit sur le serveur, jamais dans le cache, les recettes [recipeIds], les
  /// brassins [brewIds] avec leurs événements, et les coûts figés de [uid]
  /// pour ces brassins. Hors ligne, la lecture échoue (EC9).
  Future<EtatServeur> lireExistant({
    required String uid,
    required Set<String> recipeIds,
    required Set<String> brewIds,
  });

  /// Crée `recipes/{id}` sous [ownerUid].
  Future<void> creerRecette({
    required String id,
    required RecipeContent content,
    required String ownerUid,
    required String? ownerName,
  });

  /// Crée `brews/{id}`, statut `done`, avec sa copie de recette et une copie
  /// d'équipement neutre (EQ2).
  Future<void> creerBrassin(
    CreationBrassin creation, {
    required String ownerUid,
    required String? ownerName,
  });

  /// Modifie un groupe de champs de `brews/{id}` ; `owner_name` est réécrit ou
  /// retiré, `updated_at` posée par le serveur.
  Future<void> modifierBrassin(
    ModificationBrassin modification, {
    required String? ownerName,
  });

  /// Écrit un lot d'événements dans un `WriteBatch`.
  Future<void> ecrireEvenements(LotEvenements lot);
}

/// [ImportFichesRepository] sur Cloud Firestore.
class FirestoreImportFichesRepository implements ImportFichesRepository {
  FirestoreImportFichesRepository({FirebaseFirestore? firestore})
    : _injectedFirestore = firestore;

  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  static const _serveur = GetOptions(source: Source.server);

  @override
  Future<EtatServeur> lireExistant({
    required String uid,
    required Set<String> recipeIds,
    required Set<String> brewIds,
  }) async {
    final recettes = <String, String>{};
    final brassins = <String, BrassinExistant>{};
    final couts = <String>{};
    final etrangers = <String>{};
    await Future.wait([
      for (final id in recipeIds)
        _firestore.collection('recipes').doc(id).get(_serveur).then((s) {
          final owner = s.data()?['owner_uid'];
          if (s.exists) recettes[id] = owner is String ? owner : '';
        }),
      for (final id in brewIds)
        _lireBrassin(id, uid).then((lu) {
          final b = lu.brassin;
          if (b != null) brassins[id] = b;
          if (lu.etrangers) etrangers.add(id);
        }),
      for (final id in brewIds)
        brewCostRef(_firestore, uid: uid, brewId: id).get(_serveur).then((s) {
          if (s.exists) couts.add(id);
        }),
    ]);
    return EtatServeur(
      recettes: recettes,
      brassins: brassins,
      coutsFiges: couts,
      evenementsDAutrui: etrangers,
    );
  }

  /// Brassin [id] et ses événements. Les événements sont lus même sans
  /// brassin (S2) : un événement d'un autre compte à cet identifiant, laissé
  /// par un brassin supprimé, serait sinon pris pour un événement déjà écrit.
  Future<({BrassinExistant? brassin, bool etrangers})> _lireBrassin(
    String id,
    String uid,
  ) async {
    final ref = _firestore.collection('brews').doc(id);
    final (snapshot, events) = await (
      ref.get(_serveur),
      ref.collection('events').get(_serveur),
    ).wait;
    final etrangers = events.docs.any((d) => d.data()['owner_uid'] != uid);
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return (brassin: null, etrangers: etrangers);
    }
    T? lu<T>(String champ) {
      final v = data[champ];
      return v is T ? v : null;
    }

    final brassin = BrassinExistant(
      ownerUid: lu<String>('owner_uid') ?? '',
      importedFrom: lu<String>('imported_from'),
      brewedAt: lu<Timestamp>('brewed_at')?.toDate(),
      bottlesCount: lu<num>('bottles_count')?.toInt(),
      packagedVolumeL: lu<num>('packaged_volume_l')?.toDouble(),
      primingSugarName: lu<String>('priming_sugar_name'),
      notes: lu<String>('notes'),
      ogEventId: lu<String>('og_event_id'),
      fgEventId: lu<String>('fg_event_id'),
      fermenterVolumeEventId: lu<String>('fermenter_volume_event_id'),
      eventIds: {for (final d in events.docs) d.id},
    );
    return (brassin: brassin, etrangers: etrangers);
  }

  @override
  Future<void> creerRecette({
    required String id,
    required RecipeContent content,
    required String ownerUid,
    required String? ownerName,
  }) => _firestore.collection('recipes').doc(id).set({
    ...content.toFirestore(creation: true),
    'owner_uid': ownerUid,
    ...champFacultatif('owner_name', ownerName, creation: true),
    'created_at': FieldValue.serverTimestamp(),
    'updated_at': FieldValue.serverTimestamp(),
  });

  @override
  Future<void> creerBrassin(
    CreationBrassin creation, {
    required String ownerUid,
    required String? ownerName,
  }) {
    final recette = Recipe(
      id: creation.recipeId,
      ownerUid: ownerUid,
      ownerName: ownerName,
      content: creation.recette,
    );
    final equipement = Equipment(
      id: '',
      ownerUid: ownerUid,
      ownerName: ownerName,
      content: EquipmentContent(
        name: creation.equipementNom,
        kind: switch (creation.equipementType) {
          TypeEquipementFiche.cuves => EquipmentKind.multiVessel,
          TypeEquipementFiche.toutEnUn => EquipmentKind.allInOne,
        },
      ),
    );
    return _firestore.collection('brews').doc(creation.brewId).set({
      'owner_uid': ownerUid,
      'owner_name': ?ownerName,
      'recipe_id': creation.recipeId,
      'name': creation.name,
      'status': BrewStatus.done.storedValue,
      'planned_for': Timestamp.fromDate(creation.plannedFor),
      'recipe_snapshot': recipeSnapshot(recette),
      'equipment_snapshot': equipmentSnapshot(equipement),
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> modifierBrassin(
    ModificationBrassin modification, {
    required String? ownerName,
  }) => _firestore.collection('brews').doc(modification.brewId).update({
    for (final MapEntry(:key, :value) in modification.champs.entries)
      key: value is DateTime ? Timestamp.fromDate(value) : value,
    ...champFacultatif('owner_name', ownerName, creation: false),
    'updated_at': FieldValue.serverTimestamp(),
  });

  @override
  Future<void> ecrireEvenements(LotEvenements lot) {
    final events = _firestore
        .collection('brews')
        .doc(lot.brewId)
        .collection('events');
    final batch = _firestore.batch();
    for (final BrewEvent e in lot.evenements) {
      batch.set(events.doc(e.id), e.toFirestore());
    }
    return batch.commit();
  }
}
