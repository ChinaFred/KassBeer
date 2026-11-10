import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/brew_cost.dart';
import '../domain/fee.dart';
import '../domain/price.dart';

/// Document `users/{uid}/brew_costs/{brewId}` : lu ici et par la suppression d'un
/// brassin (CB19).
DocumentReference<Map<String, dynamic>> brewCostRef(
  FirebaseFirestore firestore, {
  required String uid,
  required String brewId,
}) =>
    firestore.collection('users').doc(uid).collection('brew_costs').doc(brewId);

/// Accès à `users/{uid}/prices`, `fees` et `brew_costs`, privés à leur
/// propriétaire (P5). Les écrans passent par cette interface ; les tests la
/// remplacent par un double sans Firebase.
///
/// Lectures ordinaires avec le cache hors ligne : aucune `runTransaction`, aucun
/// `Source.server` (HL1). Chaque écriture est faite dans le cache dès l'appel ;
/// la `Future` se termine quand le serveur l'a acceptée. Aucun rapport ne porte
/// de prix, de quantité, de total ni de nom de poste (SE4, P13).
abstract class CostsRepository {
  /// Prix de [uid], à chaque changement ; un document illisible est rapporté et
  /// rendu comme tel (LI9).
  Stream<ListeLue<Price>> watchPrices(String uid);

  /// Frais de [uid], à chaque changement.
  Stream<ListeLue<Fee>> watchFees(String uid);

  /// Coût figé du brassin [brewId] de [uid] : trouvé, illisible (CB20), absent,
  /// ou absent du cache seul.
  Stream<RechercheDocument<BrewCost>> watchBrewCost({
    required String uid,
    required String brewId,
  });

  /// Écrit [price] sous sa clé : un seul document par clé (PR8). Sert aussi à
  /// « Annuler » une suppression (PR10).
  Future<void> savePrice({required String uid, required Price price});

  /// Supprime le prix [key]. Les coûts figés ne changent pas (CB12).
  Future<void> deletePrice({required String uid, required String key});

  /// Identifiant d'un frais nouveau, créé par l'appareil (FR2).
  String newFeeId(String uid);

  /// Écrit [fee] sous son identifiant. Sert aussi à « Annuler » une suppression.
  Future<void> saveFee({required String uid, required Fee fee});

  /// Supprime le frais [id].
  Future<void> deleteFee({required String uid, required String id});

  /// Écrit le coût figé [cost], document entier (CB16). Premier figeage
  /// ([FreezeKind.initial]) : un refus du serveur n'est annoncé (erreur relancée,
  /// `costs.freeze_rejected`) que si le document n'y est pas ; s'il y est sans
  /// écriture en attente, le refus vient d'un rejeu ou d'un autre appareil
  /// arrivé avant : il est journalisé (`costs.freeze_replayed`) et la `Future`
  /// se termine sans erreur (HL5).
  Future<void> saveBrewCost({required String uid, required BrewCost cost});
}

/// [CostsRepository] sur Cloud Firestore.
class FirestoreCostsRepository implements CostsRepository {
  FirestoreCostsRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _prices(String uid) =>
      _firestore.collection('users').doc(uid).collection('prices');

  CollectionReference<Map<String, dynamic>> _fees(String uid) =>
      _firestore.collection('users').doc(uid).collection('fees');

  @override
  Stream<ListeLue<Price>> watchPrices(String uid) => _watch(
    _prices(uid),
    'costs.watch_prices',
    (id, data, pending) =>
        Price.fromFirestore(id, data, hasPendingWrites: pending),
    'prices',
  );

  @override
  Stream<ListeLue<Fee>> watchFees(String uid) => _watch(
    _fees(uid),
    'costs.watch_fees',
    (id, data, pending) =>
        Fee.fromFirestore(id, data, hasPendingWrites: pending),
    'fees',
  );

  Stream<ListeLue<T>> _watch<T>(
    CollectionReference<Map<String, dynamic>> collection,
    String feature,
    T Function(String id, Map<String, dynamic> data, bool pending) read,
    String label,
  ) => collection
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => ListeLue<T>(
          documents: [
            for (final doc in snapshot.docs)
              _read(
                doc.id,
                () => read(doc.id, doc.data(), doc.metadata.hasPendingWrites),
                // L'identifiant d'un prix dérive de son nom : il ne part pas
                // dans le rapport (P13).
                label == 'prices' ? label : '$label/${doc.id}',
              ),
          ],
          fromCache: snapshot.metadata.isFromCache,
        ),
      )
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: feature,
          error: error,
          stackTrace: stackTrace,
        );
        // Relancée : l'écran affiche la panne.
        Error.throwWithStackTrace(error, stackTrace);
      });

  DocumentLu<T> _read<T>(String id, T Function() read, String path) {
    try {
      return DocumentValide(id, read());
    } on DocumentIllisible catch (error, stackTrace) {
      _errors.reportError(
        feature: 'costs.read',
        error: error,
        stackTrace: stackTrace,
        context: '$path illisible',
      );
      return DocumentInvalide(id, error);
    }
  }

  @override
  Stream<RechercheDocument<BrewCost>> watchBrewCost({
    required String uid,
    required String brewId,
  }) => brewCostRef(_firestore, uid: uid, brewId: brewId)
      .snapshots(includeMetadataChanges: true)
      .map<RechercheDocument<BrewCost>>((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          return snapshot.metadata.isFromCache
              ? DocumentAbsentDuCache<BrewCost>()
              : DocumentAbsent<BrewCost>();
        }
        return switch (_read(
          brewId,
          () => BrewCost.fromFirestore(
            brewId,
            data,
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
          ),
          'brew_costs/$brewId',
        )) {
          DocumentValide<BrewCost>(:final value) => DocumentTrouve(value),
          DocumentInvalide<BrewCost>(:final error) => DocumentIllisibleTrouve(
            error,
          ),
        };
      })
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: 'costs.watch_brew_cost',
          error: error,
          stackTrace: stackTrace,
        );
        Error.throwWithStackTrace(error, stackTrace);
      });

  @override
  Future<void> savePrice({required String uid, required Price price}) => _guard(
    'costs.price_write',
    () => _prices(uid).doc(price.key).set(price.toFirestore()),
  );

  @override
  Future<void> deletePrice({required String uid, required String key}) =>
      _guard('costs.price_write', () => _prices(uid).doc(key).delete());

  @override
  String newFeeId(String uid) => _fees(uid).doc().id;

  @override
  Future<void> saveFee({required String uid, required Fee fee}) => _guard(
    'costs.fee_write',
    () => _fees(uid).doc(fee.id).set(fee.toFirestore()),
  );

  @override
  Future<void> deleteFee({required String uid, required String id}) =>
      _guard('costs.fee_write', () => _fees(uid).doc(id).delete());

  @override
  Future<void> saveBrewCost({required String uid, required BrewCost cost}) {
    final ref = brewCostRef(_firestore, uid: uid, brewId: cost.brewId);
    return ecritureCoutSuivie(
      ref: ref,
      kind: cost.freezeKind,
      write: () => ref.set(cost.toFirestore()),
    );
  }

  /// Lance [write]. Un refus d'un premier figeage n'est annoncé que si le coût
  /// n'est pas sur le serveur (HL5), comme `creationSuivie` des brassins.
  @visibleForTesting
  Future<void> ecritureCoutSuivie({
    required DocumentReference<Map<String, dynamic>> ref,
    required FreezeKind kind,
    required Future<void> Function() write,
  }) async {
    try {
      await write();
    } catch (error, stackTrace) {
      final context =
          'kind=${kind.storedValue} '
          'code=${error is FirebaseException ? error.code : error.runtimeType}';
      if (kind == FreezeKind.initial && await _presentSurServeur(ref)) {
        // Rejeu après un accusé perdu, ou coût figé par un autre appareil :
        // journalisé, jamais annoncé (HL5).
        _errors.reportError(
          feature: 'costs.freeze_replayed',
          error: error,
          stackTrace: stackTrace,
          context: context,
        );
        return;
      }
      _errors.reportError(
        feature: 'costs.freeze_rejected',
        error: error,
        stackTrace: stackTrace,
        context: context,
      );
      rethrow;
    }
  }

  /// Vrai si le document existe sans écriture locale en attente. Lecture
  /// ordinaire (cache puis serveur), jamais `Source.server`.
  Future<bool> _presentSurServeur(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final snapshot = await ref.get();
      return snapshot.exists && !snapshot.metadata.hasPendingWrites;
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'costs.freeze_check',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Lance [write] tout de suite (l'écriture locale est faite avant le retour) ;
  /// une erreur est rapportée puis relancée pour l'écran.
  Future<void> _guard(String feature, Future<void> Function() write) async {
    try {
      await write();
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: feature,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
