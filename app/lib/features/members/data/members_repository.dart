import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/services/error_report_service.dart';
import '../domain/member.dart';

/// Lecture de `members/{email}` impossible : ni le serveur ni le cache ne permettent
/// de dire si le compte est invité. L'écran montre une panne, jamais « non invité ».
class MemberLookupUnavailable implements Exception {
  const MemberLookupUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'MemberLookupUnavailable($reason)';
}

/// Version d'un document `members/{email}` : `data` vaut `null` s'il est absent.
typedef MemberDocView = ({
  String id,
  Map<String, dynamic>? data,
  bool fromCache,
  bool hasPendingWrites,
});

/// Accès à `members/`. Les écrans passent par cette interface ; les tests la
/// remplacent par un double sans Firebase.
abstract class MembersRepository {
  /// Le document du compte [emailKey] (e-mail en minuscules), à chaque changement.
  ///
  /// Un document absent du serveur rend `MemberLookup(member: null)`. Un document
  /// absent du cache seul ne prouve rien : faute de réponse du serveur, le flux lève
  /// [MemberLookupUnavailable].
  Stream<MemberLookup> watchMember(String emailKey);

  /// Tous les membres, triés (administrateurs d'abord, puis e-mail). Admin seul.
  Stream<List<Member>> watchAll();

  /// Crée `members/{email}`. La Future rendue se termine quand le serveur a accepté
  /// l'écriture ; l'écriture locale est faite dès l'appel (hors ligne, elle part au
  /// retour du réseau).
  Future<void> invite({
    required String email,
    required MemberRole role,
    String? displayName,
    required String invitedByUid,
  });

  /// Supprime `members/{email}`. Même déroulé que [invite].
  Future<void> remove(String email);
}

/// [MembersRepository] sur Cloud Firestore.
class FirestoreMembersRepository implements MembersRepository {
  FirestoreMembersRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
    this.serverWait = kMemberServerWait,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore;

  /// Attente d'une réponse du serveur quand le cache ne connaît pas le document du
  /// compte. Au-delà, l'écran affiche la panne.
  static const kMemberServerWait = Duration(seconds: 10);

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;
  final Duration serverWait;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _members =>
      _firestore.collection('members');

  @override
  Stream<MemberLookup> watchMember(String emailKey) => lookupsFrom(
    _members
        .doc(emailKey)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => (
            id: snapshot.id,
            data: snapshot.data(),
            fromCache: snapshot.metadata.isFromCache,
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
          ),
        ),
  );

  /// Lectures du membre à partir des versions successives de son document.
  ///
  /// Un document absent du cache ne prouve rien : faute de version du serveur dans
  /// [serverWait], le flux lève [MemberLookupUnavailable]. Pure hors du minuteur,
  /// testée.
  Stream<MemberLookup> lookupsFrom(Stream<MemberDocView> docs) {
    late final StreamController<MemberLookup> controller;
    StreamSubscription<MemberDocView>? subscription;
    Timer? serverTimer;

    void failUnavailable() {
      if (controller.isClosed) return;
      const error = MemberLookupUnavailable('aucune réponse du serveur');
      final stackTrace = StackTrace.current;
      _errors.reportError(
        feature: 'members.watch_member',
        error: error,
        stackTrace: stackTrace,
        context:
            'document absent du cache, serveur muet après ${serverWait.inSeconds} s',
      );
      controller.addError(error, stackTrace);
    }

    controller = StreamController<MemberLookup>(
      onListen: () {
        subscription = docs.listen(
          (doc) {
            final data = doc.data;
            if (data == null && doc.fromCache) {
              // Absent du cache : le serveur seul peut dire « non invité ».
              serverTimer ??= Timer(serverWait, failUnavailable);
              return;
            }
            serverTimer?.cancel();
            serverTimer = null;
            controller.add(
              MemberLookup(
                member: data == null
                    ? null
                    : Member.fromFirestore(
                        doc.id,
                        data,
                        hasPendingWrites: doc.hasPendingWrites,
                      ),
                fromCache: doc.fromCache,
              ),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            serverTimer?.cancel();
            serverTimer = null;
            _errors.reportError(
              feature: 'members.watch_member',
              error: error,
              stackTrace: stackTrace,
            );
            controller.addError(error, stackTrace);
          },
        );
      },
      onCancel: () async {
        serverTimer?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<Member>> watchAll() {
    return _members
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final members = [
            for (final doc in snapshot.docs)
              Member.fromFirestore(
                doc.id,
                doc.data(),
                hasPendingWrites: doc.metadata.hasPendingWrites,
              ),
          ]..sort(compareMembers);
          return members;
        })
        .handleError((Object error, StackTrace stackTrace) {
          _errors.reportError(
            feature: 'members.watch_all',
            error: error,
            stackTrace: stackTrace,
          );
          // Relancée : l'écran affiche la panne.
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  @override
  Future<void> invite({
    required String email,
    required MemberRole role,
    String? displayName,
    required String invitedByUid,
  }) {
    final name = displayName?.trim();
    return _guard(
      'members.invite',
      () => _members.doc(email).set({
        'email': email,
        'role': role.value,
        if (name != null && name.isNotEmpty) 'display_name': name,
        'invited_at': FieldValue.serverTimestamp(),
        'invited_by': invitedByUid,
      }),
    );
  }

  @override
  Future<void> remove(String email) =>
      _guard('members.remove', () => _members.doc(email).delete());

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
