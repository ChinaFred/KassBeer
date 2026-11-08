import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/app.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/providers.dart';
import 'package:kass_beer/core/services/error_report_service.dart';
import 'package:kass_beer/features/auth/data/auth_repository.dart';
import 'package:kass_beer/features/auth/domain/session_user.dart';
import 'package:kass_beer/features/brew_day/data/alerte_minuteur.dart';
import 'package:kass_beer/features/brews/data/brews_repository.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/equipment/data/equipment_repository.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/members/data/members_repository.dart';
import 'package:kass_beer/features/members/domain/member.dart';
import 'package:kass_beer/features/recipes/data/recipes_repository.dart';
import 'package:kass_beer/features/recipes/domain/chronologie.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/core/services/screen_wakelock.dart';

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
  Future<SignInOutcome> Function() onSignIn = () async =>
      SignInOutcome.cancelled;
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

  /// Nom porté par le jeton ; `null` pour un compte sans nom.
  String? tokenName = 'Bruno Brasseur';

  /// Retient la réponse tant qu'elle n'est pas terminée (jeton lent).
  Completer<void>? tokenGate;
  int tokenReads = 0;

  @override
  Future<String?> currentTokenName() async {
    tokenReads++;
    await tokenGate?.future;
    return tokenName;
  }
}

/// Écriture reçue par un double de dépôt de données.
class Write<T> {
  Write(this.kind, this.id, this.content, this.ownerUid, this.ownerName);

  /// `create`, `update`, `duplicate` ou `delete`.
  final String kind;
  final String id;
  final T? content;
  final String? ownerUid;
  final String? ownerName;
}

class FakeRecipesRepository implements RecipesRepository {
  final all = Replay<ListeLue<Recipe>>();
  final writes = <Write<RecipeContent>>[];
  int _next = 0;

  /// Réponse du serveur à une écriture ; jamais terminée par défaut (hors ligne).
  Future<void> Function() serverAnswer = () => Completer<void>().future;

  /// Publie [recipes] comme une lecture du serveur (ou du cache).
  void publish(List<Recipe> recipes, {bool fromCache = false}) => all.add(
    ListeLue(
      documents: [for (final r in recipes) DocumentValide(r.id, r)],
      fromCache: fromCache,
    ),
  );

  @override
  Stream<ListeLue<Recipe>> watchAll() => all.stream;

  @override
  CreationEnCours create({
    required RecipeContent content,
    required String ownerUid,
    required String? ownerName,
  }) {
    final id = 'recette-${++_next}';
    writes.add(Write('create', id, content, ownerUid, ownerName));
    return (id: id, written: serverAnswer());
  }

  @override
  Future<void> update({
    required String id,
    required RecipeContent content,
    required String? ownerName,
  }) {
    writes.add(Write('update', id, content, null, ownerName));
    return serverAnswer();
  }

  @override
  CreationEnCours duplicate({
    required Recipe source,
    required String ownerUid,
    required String? ownerName,
  }) {
    final id = 'copie-${++_next}';
    writes.add(
      Write('duplicate', id, source.content.duplicate(), ownerUid, ownerName),
    );
    return (id: id, written: serverAnswer());
  }

  @override
  Future<void> delete(String id) {
    writes.add(Write('delete', id, null, null, null));
    return serverAnswer();
  }

  /// Dernière chronologie reçue par [updateBrewSteps].
  List<BrewStepLine>? savedBrewSteps;
  int _nextKey = 0;

  @override
  String newStepKey() => 'cle-${++_nextKey}';

  @override
  Future<void> updateBrewSteps({
    required String id,
    required List<BrewStepLine> steps,
    required String? ownerName,
  }) {
    savedBrewSteps = steps;
    return serverAnswer();
  }
}

class FakeEquipmentRepository implements EquipmentRepository {
  final all = Replay<ListeLue<Equipment>>();
  final writes = <Write<EquipmentContent>>[];
  int _next = 0;

  /// Réponse du serveur à une écriture ; jamais terminée par défaut (hors ligne).
  Future<void> Function() serverAnswer = () => Completer<void>().future;

  void publish(List<Equipment> items, {bool fromCache = false}) => all.add(
    ListeLue(
      documents: [for (final e in items) DocumentValide(e.id, e)],
      fromCache: fromCache,
    ),
  );

  @override
  Stream<ListeLue<Equipment>> watchAll() => all.stream;

  @override
  CreationEnCours create({
    required EquipmentContent content,
    required String ownerUid,
    required String? ownerName,
  }) {
    final id = 'equipement-${++_next}';
    writes.add(Write('create', id, content, ownerUid, ownerName));
    return (id: id, written: serverAnswer());
  }

  @override
  Future<void> update({
    required String id,
    required EquipmentContent content,
    required String? ownerName,
  }) {
    writes.add(Write('update', id, content, null, ownerName));
    return serverAnswer();
  }

  @override
  Future<void> delete(String id) {
    writes.add(Write('delete', id, null, null, null));
    return serverAnswer();
  }
}

/// Écriture reçue par [FakeBrewsRepository].
class BrewWrite {
  BrewWrite(this.kind, this.brewId, [this.detail = const {}]);

  final String kind;
  final String brewId;
  final Map<String, Object?> detail;

  @override
  String toString() => 'BrewWrite($kind, $brewId, $detail)';
}

class FakeBrewsRepository implements BrewsRepository {
  final all = Replay<ListeLue<Brew>>();
  final _events = <String, Replay<ListeLue<BrewEvent>>>{};
  final writes = <BrewWrite>[];
  int _next = 0;

  /// Réponse du serveur à une écriture ; jamais terminée par défaut (hors ligne).
  Future<void> Function() serverAnswer = () => Completer<void>().future;

  /// Vrai si [attendreServeur] rend une réponse du serveur.
  bool serverReachable = true;
  int prepareCalls = 0;

  void publish(List<Brew> brews, {bool fromCache = false}) => all.add(
    ListeLue(
      documents: [for (final b in brews) DocumentValide(b.id, b)],
      fromCache: fromCache,
    ),
  );

  Replay<ListeLue<BrewEvent>> eventsOf(String brewId) =>
      _events.putIfAbsent(brewId, Replay.new);

  void publishEvents(
    String brewId,
    List<BrewEvent> events, {
    bool fromCache = false,
  }) => eventsOf(brewId).add(
    ListeLue(
      documents: [for (final e in events) DocumentValide(e.id, e)],
      fromCache: fromCache,
    ),
  );

  @override
  Stream<ListeLue<Brew>> watchAll() => all.stream;

  @override
  Stream<ListeLue<BrewEvent>> watchEvents(String brewId) =>
      eventsOf(brewId).stream;

  @override
  Future<bool> attendreServeur(
    String brewId, {
    Duration limite = kPrepareWait,
  }) async {
    prepareCalls++;
    return serverReachable;
  }

  @override
  CreationEnCours create({
    required Recipe recipe,
    required Equipment equipment,
    required String name,
    required DateTime? plannedFor,
    required String ownerUid,
    required String? ownerName,
    String? notes,
  }) {
    final id = 'brassin-${++_next}';
    writes.add(
      BrewWrite('create', id, {
        'name': name,
        'recipe_id': recipe.id,
        'equipment_id': equipment.id,
        'owner_name': ownerName,
        'notes': notes,
      }),
    );
    return (id: id, written: serverAnswer());
  }

  @override
  Future<void> update({
    required String id,
    required String name,
    required DateTime? plannedFor,
    required String? notes,
    required String? ownerName,
  }) {
    writes.add(
      BrewWrite('update', id, {'name': name, 'owner_name': ownerName}),
    );
    return serverAnswer();
  }

  @override
  Future<void> start({
    required String brewId,
    required String ownerUid,
    required DateTime at,
    required String? firstStepKey,
    required String? ownerName,
  }) {
    writes.add(
      BrewWrite('start', brewId, {
        'at': at,
        'first': firstStepKey,
        'owner_name': ownerName,
      }),
    );
    return serverAnswer();
  }

  @override
  Future<void> finish({required String brewId, required String? ownerName}) {
    writes.add(BrewWrite('finish', brewId, {'owner_name': ownerName}));
    return serverAnswer();
  }

  @override
  Future<void> writeSteps({
    required String brewId,
    required String ownerUid,
    required List<StepWrite> writes,
    required DateTime at,
  }) {
    this.writes.add(
      BrewWrite('steps', brewId, {
        'writes': [
          for (final w in writes) '${w.kind.storedValue}:${w.stepKey}',
        ],
        'at': at,
      }),
    );
    return serverAnswer();
  }

  @override
  CreationEnCours addEvent({
    required String brewId,
    required BrewEventInput input,
  }) {
    final id = 'event-${++_next}';
    writes.add(
      BrewWrite('event', brewId, {
        'id': id,
        'kind': input.kind.storedValue,
        'type': input.measureType?.storedValue,
        'value': input.value,
        'step': input.stepKey,
        'at': input.measuredAt,
      }),
    );
    return (id: id, written: serverAnswer());
  }

  @override
  Future<void> correct({
    required String brewId,
    required String eventId,
    required double? value,
    required String? note,
    required DateTime measuredAt,
  }) {
    writes.add(BrewWrite('correct', brewId, {'id': eventId, 'at': measuredAt}));
    return serverAnswer();
  }

  @override
  Future<void> deleteEvent({required String brewId, required String eventId}) {
    writes.add(BrewWrite('delete_event', brewId, {'id': eventId}));
    return serverAnswer();
  }

  @override
  Future<void> restoreEvent({
    required String brewId,
    required BrewEvent event,
  }) {
    writes.add(BrewWrite('restore_event', brewId, {'id': event.id}));
    return serverAnswer();
  }

  @override
  Future<void> delete(String id) {
    writes.add(BrewWrite('delete', id));
    return serverAnswer();
  }

  @override
  Future<void> deleteWithEvents(String id) {
    writes.add(BrewWrite('delete_with_events', id));
    return serverAnswer();
  }
}

class FakeAlerte implements AlerteMinuteur {
  int prepared = 0;
  int triggered = 0;

  @override
  void preparer() => prepared++;

  @override
  Future<void> declencher() async => triggered++;
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

  Replay<MemberLookup> lookup(String email) =>
      lookups.putIfAbsent(email, Replay.new);

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

const brewerMember = Member(
  email: 'brasseur@exemple.fr',
  role: MemberRole.brewer,
);
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
      recipes = FakeRecipesRepository(),
      equipment = FakeEquipmentRepository(),
      brews = FakeBrewsRepository(),
      alerte = FakeAlerte(),
      errors = RecordingErrorReportService() {
    wakelock = ScreenWakelock(
      errorReportService: errors,
      toggle: ({required bool enable}) async {
        wakelockCalls.add(enable);
      },
    );
    container = ProviderContainer(
      overrides: [
        errorReportServiceProvider.overrideWithValue(errors),
        authRepositoryProvider.overrideWithValue(auth),
        membersRepositoryProvider.overrideWithValue(members),
        recipesRepositoryProvider.overrideWithValue(recipes),
        equipmentRepositoryProvider.overrideWithValue(equipment),
        brewsRepositoryProvider.overrideWithValue(brews),
        horlogeProvider.overrideWithValue(() => now),
        alerteMinuteurProvider.overrideWithValue(alerte),
        screenWakelockProvider.overrideWithValue(wakelock),
        appVersionProvider.overrideWithValue('0.1.0'),
      ],
    );
    // Listes vides lues du serveur : l'accueil (Recettes) s'affiche sans attendre.
    recipes.publish(const []);
    equipment.publish(const []);
    brews.publish(const []);
  }

  final FakeAuthRepository auth;
  final FakeMembersRepository members;
  final FakeRecipesRepository recipes;
  final FakeEquipmentRepository equipment;
  final FakeBrewsRepository brews;
  final FakeAlerte alerte;
  final RecordingErrorReportService errors;
  late final ScreenWakelock wakelock;
  final wakelockCalls = <bool>[];

  /// Heure de l'appareil, modifiable par les tests.
  DateTime now = DateTime(2026, 11, 8, 12, 10);
  late final ProviderContainer container;

  /// Monte l'application dans une fenêtre de [width] × [height] pixels logiques.
  Future<void> pump(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const KassBeerApp(),
      ),
    );
  }

  /// Connecte [user] et répond à la lecture de son document par [member].
  void signIn(SessionUser user, {Member? member, bool fromCache = false}) {
    auth.session.add(user);
    members
        .lookup(user.memberKey!)
        .add(MemberLookup(member: member, fromCache: fromCache));
  }
}
