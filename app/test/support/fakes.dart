import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/app.dart';
import 'package:kass_beer/core/providers.dart';
import 'package:kass_beer/core/services/error_report_service.dart';
import 'package:kass_beer/features/auth/data/auth_repository.dart';
import 'package:kass_beer/features/auth/domain/session_user.dart';
import 'package:kass_beer/features/members/data/members_repository.dart';
import 'package:kass_beer/features/members/domain/member.dart';

/// Flux qui rejoue sa dernière valeur ou erreur à chaque nouvel abonné.
class Replay<T> {
  final _listeners = <MultiStreamController<T>>[];
  bool _hasEvent = false;
  T? _value;
  Object? _error;

  int subscriptions = 0;

  Stream<T> get stream => Stream<T>.multi((controller) {
    subscriptions++;
    if (_hasEvent) {
      if (_error != null) {
        controller.addError(_error!);
      } else {
        controller.add(_value as T);
      }
    }
    _listeners.add(controller);
    controller.onCancel = () => _listeners.remove(controller);
  });

  void add(T value) {
    _hasEvent = true;
    _value = value;
    _error = null;
    for (final l in List.of(_listeners)) {
      l.add(value);
    }
  }

  void addError(Object error) {
    _hasEvent = true;
    _error = error;
    for (final l in List.of(_listeners)) {
      l.addError(error);
    }
  }
}

class FakeAuthRepository implements AuthRepository {
  final session = Replay<SessionUser?>();
  Future<SignInOutcome> Function() onSignIn = () async => SignInOutcome.cancelled;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Stream<SessionUser?> authStateChanges() => session.stream;

  @override
  Future<SignInOutcome> signInWithGoogle() {
    signInCalls++;
    return onSignIn();
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    session.add(null);
  }
}

class Invitation {
  Invitation(this.email, this.role, this.displayName, this.invitedBy);

  final String email;
  final MemberRole role;
  final String? displayName;
  final String invitedBy;
}

class FakeMembersRepository implements MembersRepository {
  final lookups = <String, Replay<MemberLookup>>{};
  final all = Replay<List<Member>>();
  final invitations = <Invitation>[];
  final removed = <String>[];

  /// Réponse du serveur à une écriture ; jamais terminée par défaut (hors ligne).
  Future<void> Function() serverAnswer = () => Completer<void>().future;

  Replay<MemberLookup> lookup(String email) => lookups.putIfAbsent(email, Replay.new);

  @override
  Stream<MemberLookup> watchMember(String emailKey) => lookup(emailKey).stream;

  @override
  Stream<List<Member>> watchAll() => all.stream;

  @override
  Future<void> invite({
    required String email,
    required MemberRole role,
    String? displayName,
    required String invitedByUid,
  }) {
    invitations.add(Invitation(email, role, displayName, invitedByUid));
    return serverAnswer();
  }

  @override
  Future<void> remove(String email) {
    removed.add(email);
    return serverAnswer();
  }
}

class RecordingErrorReportService extends ErrorReportService {
  final reports = <({String feature, Object error})>[];

  @override
  void reportError({
    required String feature,
    required Object error,
    StackTrace? stackTrace,
    String? context,
  }) {
    reports.add((feature: feature, error: error));
  }
}

const brewerUser = SessionUser(
  uid: 'uid-brasseur',
  email: 'Brasseur@Exemple.fr',
  displayName: 'Bruno Brasseur',
);
const adminUser = SessionUser(
  uid: 'uid-admin',
  email: 'admin@exemple.fr',
  displayName: 'Alice Admin',
);

const brewerMember = Member(email: 'brasseur@exemple.fr', role: MemberRole.brewer);
const adminMember = Member(
  email: 'admin@exemple.fr',
  role: MemberRole.admin,
  displayName: 'Alice Admin',
);

/// Environnement de test : doubles, conteneur Riverpod, application montée.
class TestApp {
  TestApp()
    : auth = FakeAuthRepository(),
      members = FakeMembersRepository(),
      errors = RecordingErrorReportService() {
    container = ProviderContainer(
      overrides: [
        errorReportServiceProvider.overrideWithValue(errors),
        authRepositoryProvider.overrideWithValue(auth),
        membersRepositoryProvider.overrideWithValue(members),
        appVersionProvider.overrideWithValue('0.1.0'),
      ],
    );
  }

  final FakeAuthRepository auth;
  final FakeMembersRepository members;
  final RecordingErrorReportService errors;
  late final ProviderContainer container;

  /// Monte l'application dans une fenêtre de [width] × [height] pixels logiques.
  Future<void> pump(WidgetTester tester, {double width = 400, double height = 900}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KassBeerApp()),
    );
  }

  /// Connecte [user] et répond à la lecture de son document par [member].
  void signIn(SessionUser user, {Member? member, bool fromCache = false}) {
    auth.session.add(user);
    members.lookup(user.memberKey!).add(MemberLookup(member: member, fromCache: fromCache));
  }
}
