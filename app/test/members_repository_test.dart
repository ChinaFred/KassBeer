import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/features/members/data/members_repository.dart';
import 'package:kass_beer/features/members/domain/member.dart';

import 'support/fakes.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingErrorReportService errors;
  late FirestoreMembersRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    errors = RecordingErrorReportService();
    repository = FirestoreMembersRepository(
      errorReportService: errors,
      firestore: firestore,
    );
  });

  test(
    'invitation : champs de firestore.rules, identifiant = e-mail',
    () async {
      await repository.invite(
        email: 'nina@exemple.fr',
        role: MemberRole.brewer,
        displayName: '  Nina ',
        invitedByUid: 'uid-admin',
      );
      final doc = await firestore
          .collection('members')
          .doc('nina@exemple.fr')
          .get();
      final data = doc.data()!;
      expect(data.keys.toSet(), {
        'email',
        'role',
        'display_name',
        'invited_at',
        'invited_by',
      });
      expect(data['email'], 'nina@exemple.fr');
      expect(data['role'], 'brewer');
      expect(data['display_name'], 'Nina');
      expect(data['invited_by'], 'uid-admin');
      expect(data['invited_at'], isA<Timestamp>());
    },
  );

  test('invitation sans nom : champ omis', () async {
    await repository.invite(
      email: 'zoe@exemple.fr',
      role: MemberRole.admin,
      displayName: '',
      invitedByUid: 'uid-admin',
    );
    final data =
        (await firestore.collection('members').doc('zoe@exemple.fr').get())
            .data()!;
    expect(data.containsKey('display_name'), isFalse);
    expect(data['role'], 'admin');
  });

  test('liste triée : administrateurs d\'abord, puis e-mail', () async {
    for (final (email, role) in [
      ('zoe@exemple.fr', 'brewer'),
      ('bob@exemple.fr', 'admin'),
      ('alice@exemple.fr', 'brewer'),
      ('yann@exemple.fr', 'admin'),
    ]) {
      await firestore.collection('members').doc(email).set({
        'email': email,
        'role': role,
      });
    }
    final members = await repository.watchAll().first;
    expect(members.map((m) => m.email), [
      'bob@exemple.fr',
      'yann@exemple.fr',
      'alice@exemple.fr',
      'zoe@exemple.fr',
    ]);
  });

  test('membre présent puis retiré', () async {
    await firestore.collection('members').doc('nina@exemple.fr').set({
      'email': 'nina@exemple.fr',
      'role': 'brewer',
    });
    final lookups = repository.watchMember('nina@exemple.fr');
    final events = <MemberLookup>[];
    final sub = lookups.listen(events.add);
    await Future<void>.delayed(Duration.zero);
    await repository.remove('nina@exemple.fr');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events.first.member?.role, MemberRole.brewer);
    expect(events.last.member, isNull);
    expect(events.last.fromCache, isFalse);
  });

  group('document absent du cache', () {
    MemberDocView view({Map<String, dynamic>? data, required bool fromCache}) =>
        (
          id: 'nina@exemple.fr',
          data: data,
          fromCache: fromCache,
          hasPendingWrites: false,
        );

    test('serveur muet : panne, jamais « non invité »', () {
      fakeAsync((async) {
        final docs = StreamController<MemberDocView>();
        final events = <Object>[];
        repository
            .lookupsFrom(docs.stream)
            .listen(events.add, onError: events.add);
        docs.add(view(fromCache: true));
        async.elapse(const Duration(seconds: 9));
        expect(events, isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(events.single, isA<MemberLookupUnavailable>());
        expect(errors.reports.single.feature, 'members.watch_member');
      });
    });

    test('le serveur répond à temps : « non invité »', () {
      fakeAsync((async) {
        final docs = StreamController<MemberDocView>();
        final events = <Object>[];
        repository
            .lookupsFrom(docs.stream)
            .listen(events.add, onError: events.add);
        docs.add(view(fromCache: true));
        async.elapse(const Duration(seconds: 3));
        docs.add(view(fromCache: false));
        async.elapse(const Duration(seconds: 20));
        expect(events, [const MemberLookup(member: null, fromCache: false)]);
        expect(errors.reports, isEmpty);
      });
    });

    test('document en cache : membre hors ligne, sans attente', () {
      fakeAsync((async) {
        final docs = StreamController<MemberDocView>();
        final events = <Object>[];
        repository
            .lookupsFrom(docs.stream)
            .listen(events.add, onError: events.add);
        docs.add(view(data: {'role': 'admin'}, fromCache: true));
        async.flushMicrotasks();
        final lookup = events.single as MemberLookup;
        expect(lookup.fromCache, isTrue);
        expect(lookup.member?.isAdmin, isTrue);
      });
    });

    test('erreur de lecture : rapportée et transmise', () {
      fakeAsync((async) {
        final docs = StreamController<MemberDocView>();
        final events = <Object>[];
        repository
            .lookupsFrom(docs.stream)
            .listen(events.add, onError: events.add);
        docs.addError(StateError('permission-denied'));
        async.flushMicrotasks();
        expect(events.single, isA<StateError>());
        expect(errors.reports.single.feature, 'members.watch_member');
      });
    });
  });

  test('rôle inconnu : aucun droit d\'administration', () {
    final member = Member.fromFirestore('x@exemple.fr', {'role': 'root'});
    expect(member.role, isNull);
    expect(member.isAdmin, isFalse);
  });

  test('adresse : minuscules et forme', () {
    expect(normalizeMemberEmail('  Nina@Exemple.FR '), 'nina@exemple.fr');
    expect(isValidMemberEmail('nina@exemple.fr'), isTrue);
    expect(isValidMemberEmail('nina@exemple'), isFalse);
    expect(isValidMemberEmail('nina exemple.fr'), isFalse);
    expect(isValidMemberEmail('a@b@exemple.fr'), isFalse);
    expect(isValidMemberEmail('${'a' * 250}@exemple.fr'), isFalse);
  });
}
