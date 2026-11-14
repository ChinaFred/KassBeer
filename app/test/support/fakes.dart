import 'dart:async';
import 'dart:typed_data';

import 'package:exchange/exchange.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/app.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/data/nouveautes.dart';
import 'package:kass_beer/core/fichiers/echange_fichiers.dart';
import 'package:kass_beer/core/preferences/preferences_appareil.dart';
import 'package:kass_beer/core/providers.dart';
import 'package:kass_beer/core/services/error_report_service.dart';
import 'package:kass_beer/features/admin/data/error_reports_repository.dart';
import 'package:kass_beer/features/admin/domain/error_report.dart';
import 'package:kass_beer/features/admin/data/logs_repository.dart';
import 'package:kass_beer/features/admin/domain/log_entry.dart';
import 'package:kass_beer/features/auth/data/auth_repository.dart';
import 'package:kass_beer/features/auth/domain/session_user.dart';
import 'package:kass_beer/features/brew_day/data/alerte_minuteur.dart';
import 'package:kass_beer/features/brews/data/brews_repository.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/deroule.dart';
import 'package:kass_beer/features/brews/domain/releves.dart';
import 'package:kass_beer/features/equipment/data/equipment_repository.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/import/data/import_fiches_repository.dart';
import 'package:kass_beer/features/library/data/library_repository.dart';
import 'package:kass_beer/features/library/domain/recette_publique.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/members/data/members_repository.dart';
import 'package:kass_beer/features/members/domain/member.dart';
import 'package:kass_beer/features/recipes/data/recipes_repository.dart';
import 'package:kass_beer/features/recipes/domain/chronologie.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_providers.dart';
import 'package:kass_beer/core/services/screen_wakelock.dart';
import 'package:kass_beer/features/tickets/data/tickets_repository.dart';
import 'package:kass_beer/features/tickets/domain/etat_jeton_github.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/domain/ticket_analysis.dart';
import 'package:kass_beer/features/tickets/domain/ticket_delivery.dart';
import 'package:kass_beer/features/tickets/domain/ticket_launch.dart';
import 'package:kass_beer/features/tickets/presentation/capture_ticket.dart';
import 'package:kass_beer/features/tickets/presentation/tickets_providers.dart';

import 'cost_fakes.dart';
import 'process_fakes.dart';

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

  /// Dernière valeur publiée ; `null` sans valeur ou après une erreur.
  T? get value => _hasEvent && _error == null ? _value : null;

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

  /// Réponse du serveur à l'écriture du déroulé ; [serverAnswer] si nulle.
  Future<void> Function()? processAnswer;

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
  Future<void> setProcess({
    required String brewId,
    required Deroule? deroule,
    required String? ownerName,
  }) {
    writes.add(
      BrewWrite('process', brewId, {
        'deroule': deroule,
        'owner_name': ownerName,
      }),
    );
    return (processAnswer ?? serverAnswer)();
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
        'phase': input.phase?.storedValue,
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
  EcritureReleve addReleve({
    required String brewId,
    required String ownerUid,
    required ReleveSaisi releve,
  }) {
    final ids = ['event-${++_next}'];
    writes.add(
      BrewWrite('releve', brewId, {
        'ids': ids,
        'gravity': releve.gravity,
        'temperature': releve.temperature,
        'note': releve.note,
        'at': releve.measuredAt,
      }),
    );
    return (ids: ids, written: serverAnswer());
  }

  @override
  Future<void> correctReleve({
    required String brewId,
    required String ownerUid,
    required Releve avant,
    required ReleveSaisi releve,
  }) {
    writes.add(
      BrewWrite('correct_releve', brewId, {
        'before': [for (final e in avant.events) e.id],
        'gravity': releve.gravity,
        'temperature': releve.temperature,
        'note': releve.note,
        'at': releve.measuredAt,
      }),
    );
    return serverAnswer();
  }

  @override
  Future<void> deleteEvents({
    required String brewId,
    required List<String> eventIds,
  }) {
    writes.add(BrewWrite('delete_events', brewId, {'ids': eventIds}));
    return serverAnswer();
  }

  @override
  Future<void> restoreEvents({
    required String brewId,
    required List<BrewEvent> events,
  }) {
    writes.add(
      BrewWrite('restore_events', brewId, {
        'ids': [for (final e in events) e.id],
      }),
    );
    return serverAnswer();
  }

  @override
  Future<void> setStatus({
    required String brewId,
    required BrewStatus status,
    required String? ownerName,
  }) {
    writes.add(
      BrewWrite('status', brewId, {'status': status, 'owner_name': ownerName}),
    );
    return serverAnswer();
  }

  @override
  Future<void> saveBottling({
    required String brewId,
    required String ownerUid,
    required Embouteillage embouteillage,
    required BrewStatus? nouveauStatut,
    double? finalGravity,
    required String? ownerName,
  }) {
    writes.add(
      BrewWrite('bottling', brewId, {
        'status': nouveauStatut,
        'bottled_at': embouteillage.bottledAt,
        'bottles_count': embouteillage.bottlesCount,
        'packaged_volume_l': embouteillage.packagedVolumeL,
        'priming_sugar_g': embouteillage.primingSugarG,
        'priming_sugar_name': embouteillage.primingSugarName,
        'final_gravity': finalGravity,
        'owner_name': ownerName,
      }),
    );
    return serverAnswer();
  }

  @override
  Future<void> setMesureRetenue({
    required String brewId,
    required MesureRetenueChamp champ,
    required String? eventId,
    required String? ownerName,
  }) {
    writes.add(
      BrewWrite('retained', brewId, {
        'field': champ.storedField,
        'id': eventId,
      }),
    );
    return serverAnswer();
  }

  @override
  Future<void> setSugarsInWort({
    required String brewId,
    required bool value,
    required String? ownerName,
  }) {
    writes.add(BrewWrite('sugars', brewId, {'value': value}));
    return serverAnswer();
  }

  @override
  Future<void> delete(String id, {required String ownerUid}) {
    writes.add(BrewWrite('delete', id, {'owner_uid': ownerUid}));
    return serverAnswer();
  }

  @override
  Future<void> deleteWithEvents(String id, {required String ownerUid}) {
    writes.add(BrewWrite('delete_with_events', id, {'owner_uid': ownerUid}));
    return serverAnswer();
  }
}

/// Double de [PreferencesAppareil] : valeur gardée en mémoire, échecs au choix.
class FakePreferencesAppareil implements PreferencesAppareil {
  String? valeur;
  Object? erreurLecture;
  Object? erreurEcriture;

  /// Erreurs des écritures suivantes, une par écriture (`null` : réussite),
  /// lues avant [erreurEcriture].
  final erreursEcritures = <Object?>[];
  Future<void>? attenteEcriture;
  final ecritures = <ThemeMode>[];

  @override
  Future<String?> lireValeurTheme() async {
    final erreur = erreurLecture;
    if (erreur != null) throw erreur;
    return valeur;
  }

  @override
  Future<void> ecrireTheme(ThemeMode mode) async {
    ecritures.add(mode);
    final erreurPrevue = erreursEcritures.isNotEmpty
        ? erreursEcritures.removeAt(0)
        : erreurEcriture;
    final attente = attenteEcriture;
    attenteEcriture = null;
    if (attente != null) await attente;
    final erreur = erreurPrevue;
    if (erreur != null) throw erreur;
    valeur = kValeursTheme[mode];
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

/// Fichier envoyé par le double de [EchangeFichiers].
class FichierEnvoye {
  FichierEnvoye(this.mode, this.nom, this.typeMime, this.octets);

  final ModeEnvoi mode;
  final String nom;
  final String typeMime;
  final Uint8List octets;
}

class FakeEchangeFichiers implements EchangeFichiers {
  /// Réponse au prochain choix ; annulé par défaut.
  ResultatChoix choix = const ChoixAnnule();
  int choixDemandes = 0;
  int? maxOctetsDemande;

  @override
  List<ModeEnvoi> modes = const [ModeEnvoi.enregistrer, ModeEnvoi.partager];

  /// Réponse aux envois ; fait par défaut.
  ResultatEnvoi envoi = const EnvoiFait();
  final envoyes = <FichierEnvoye>[];

  /// Choix en attente, terminé par le test (sélecteur ouvert) ; `null` : réponse
  /// immédiate par [choix].
  Completer<ResultatChoix>? attente;

  @override
  Future<ResultatChoix> choisir({required int maxOctets}) async {
    choixDemandes++;
    maxOctetsDemande = maxOctets;
    return attente?.future ?? choix;
  }

  @override
  Future<ResultatEnvoi> envoyer(
    ModeEnvoi mode, {
    required String nom,
    required String typeMime,
    required Uint8List octets,
  }) async {
    envoyes.add(FichierEnvoye(mode, nom, typeMime, octets));
    return attenteEnvoi?.future ?? envoi;
  }

  /// Envoi en attente, terminé par le test ; `null` : réponse immédiate.
  Completer<ResultatEnvoi>? attenteEnvoi;
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

/// Ticket reçu par [FakeTicketsRepository.create].
typedef TicketCree = ({
  String id,
  TicketBrouillon brouillon,
  String authorUid,
  String authorEmail,
  String? appVersion,
  String platform,
});

class FakeTicketsRepository implements TicketsRepository {
  final mine = Replay<ListeLue<Ticket>>();
  final githubStatus = Replay<RechercheDocument<EtatJetonGithub>>();
  final all = Replay<ListeLue<Ticket>>();
  final decisions = <String, Replay<ListeLue<TicketDecision>>>{};
  final decisionsCreated = <DecisionCreee>[];
  final sendRetries = <String>[];
  final decisionRetries = <String>[];
  int decisionIdsGiven = 0;
  final created = <TicketCree>[];
  final seen = <String>[];
  final watchedUids = <String>[];
  int idsGiven = 0;

  /// Réponse du serveur à une écriture ; jamais terminée par défaut (hors ligne).
  Future<void> Function() serverAnswer = () => Completer<void>().future;

  /// Publie [tickets] et, illisibles, les identifiants [invalid].
  void publish(
    List<Ticket> tickets, {
    bool fromCache = false,
    List<String> invalid = const [],
  }) => mine.add(
    ListeLue(
      documents: [
        for (final t in tickets) DocumentValide(t.id, t),
        for (final id in invalid)
          DocumentInvalide<Ticket>(
            id,
            const DocumentIllisible('type', 'type inconnu'),
          ),
      ],
      fromCache: fromCache,
    ),
  );

  @override
  String newTicketId() => 'ticket-${++idsGiven}';

  @override
  Future<void> create({
    required String id,
    required TicketBrouillon brouillon,
    required String authorUid,
    required String authorEmail,
    required String? appVersion,
    required String platform,
  }) {
    created.add((
      id: id,
      brouillon: brouillon,
      authorUid: authorUid,
      authorEmail: authorEmail,
      appVersion: appVersion,
      platform: platform,
    ));
    return serverAnswer();
  }

  @override
  Stream<ListeLue<Ticket>> watchMine(String uid) {
    watchedUids.add(uid);
    return mine.stream;
  }

  @override
  Future<void> markSeen(String id) async => seen.add(id);

  @override
  Stream<RechercheDocument<EtatJetonGithub>> watchGithubStatus() =>
      githubStatus.stream;

  /// Publie [tickets] pour l'administrateur et, illisibles, les identifiants
  /// [invalid].
  void publishAll(
    List<Ticket> tickets, {
    bool fromCache = false,
    List<String> invalid = const [],
  }) => all.add(
    ListeLue(
      documents: [
        for (final t in tickets) DocumentValide(t.id, t),
        for (final id in invalid)
          DocumentInvalide<Ticket>(
            id,
            const DocumentIllisible('type', 'type inconnu'),
          ),
      ],
      fromCache: fromCache,
    ),
  );

  Replay<ListeLue<TicketDecision>> decisionsOf(String ticketId) =>
      decisions.putIfAbsent(ticketId, Replay.new);

  /// Publie les décisions du ticket [ticketId].
  void publishDecisions(String ticketId, List<TicketDecision> list) =>
      decisionsOf(ticketId).add(
        ListeLue(
          documents: [for (final d in list) DocumentValide(d.id, d)],
          fromCache: false,
        ),
      );

  @override
  Stream<ListeLue<Ticket>> watchAll() => all.stream;

  @override
  Stream<ListeLue<TicketDecision>> watchDecisions(String ticketId) =>
      decisionsOf(ticketId).stream;

  @override
  String newDecisionId(String ticketId) => 'decision-${++decisionIdsGiven}';

  /// Réponse du serveur à une écriture d'administration (décision, relance) :
  /// vrai s'il l'accepte ; jamais terminée par défaut (hors ligne).
  Future<bool> Function() adminAnswer = () => Completer<bool>().future;

  @override
  Future<bool> createDecision({
    required String ticketId,
    required String id,
    required TicketDecisionAction action,
    required String? text,
    required String requestedByUid,
  }) {
    decisionsCreated.add((
      ticketId: ticketId,
      id: id,
      action: action,
      text: text,
      requestedByUid: requestedByUid,
    ));
    return adminAnswer();
  }

  /// Comme Firestore : l'écriture locale republie le ticket avec une écriture
  /// en attente ; `retry_requested_at` (heure du serveur) reste inchangé.
  @override
  Future<bool> retrySend(String ticketId) {
    sendRetries.add(ticketId);
    final list = all.value;
    if (list != null) {
      all.add(
        ListeLue(
          documents: [
            for (final d in list.documents)
              if (d case DocumentValide<Ticket>(
                :final value,
              ) when value.id == ticketId)
                DocumentValide(d.id, _enAttente(value))
              else
                d,
          ],
          fromCache: list.fromCache,
        ),
      );
    }
    return adminAnswer();
  }

  /// Comme Firestore : la décision reste `failed` dans le cache, avec une
  /// écriture en attente.
  @override
  Future<bool> retryDecision({
    required String ticketId,
    required String decisionId,
  }) {
    decisionRetries.add('$ticketId/$decisionId');
    final list = decisions[ticketId]?.value;
    if (list != null) {
      decisionsOf(ticketId).add(
        ListeLue(
          documents: [
            for (final d in list.documents)
              if (d case DocumentValide<TicketDecision>(
                :final value,
              ) when value.id == decisionId)
                DocumentValide(
                  d.id,
                  TicketDecision(
                    id: value.id,
                    action: value.action,
                    state: value.state,
                    text: value.text,
                    requestedAt: value.requestedAt,
                    errorReason: value.errorReason,
                    leaseUntil: value.leaseUntil,
                    hasPendingWrites: true,
                  ),
                )
              else
                d,
          ],
          fromCache: list.fromCache,
        ),
      );
    }
    return adminAnswer();
  }

  static Ticket _enAttente(Ticket t) => Ticket(
    id: t.id,
    type: t.type,
    title: t.title,
    description: t.description,
    screen: t.screen,
    status: t.status,
    appVersion: t.appVersion,
    platform: t.platform,
    createdAt: t.createdAt,
    statusChangedAt: t.statusChangedAt,
    seenByAuthorAt: t.seenByAuthorAt,
    replyText: t.replyText,
    deliveredPrUrl: t.deliveredPrUrl,
    deliveredVersion: t.deliveredVersion,
    authorEmail: t.authorEmail,
    issueNumber: t.issueNumber,
    issueUrl: t.issueUrl,
    deliveredPrNumber: t.deliveredPrNumber,
    sendAttempts: t.sendAttempts,
    lastSendError: t.lastSendError,
    issueMissingSince: t.issueMissingSince,
    allowedDecisions: t.allowedDecisions,
    canAnswer: t.canAnswer,
    canLaunchAnalysis: t.canLaunchAnalysis,
    canLaunchDevelopment: t.canLaunchDevelopment,
    canLaunchDelivery: t.canLaunchDelivery,
    canRelaunchDevelopment: t.canRelaunchDevelopment,
    decisionLeaseUntil: t.decisionLeaseUntil,
    retryRequestedAt: t.retryRequestedAt,
    hasPendingWrites: true,
  );

  final analyses = <String, Replay<RechercheDocument<TicketAnalysisDoc>>>{};

  Replay<RechercheDocument<TicketAnalysisDoc>> analysesOf(String ticketId) =>
      analyses.putIfAbsent(ticketId, Replay.new);

  @override
  Stream<RechercheDocument<TicketAnalysisDoc>> watchAnalysis(String ticketId) =>
      analysesOf(ticketId).stream;

  /// Réponses publiées par « Répondre » : ticket et texte.
  final answers = <({String ticketId, String answer})>[];

  /// Réponse du serveur à « Répondre » : `null` si publiée ; jamais terminée
  /// par défaut.
  Future<EchecReponse?> Function() answerResult = () =>
      Completer<EchecReponse?>().future;

  @override
  Future<EchecReponse?> answer({
    required String ticketId,
    required String answer,
  }) {
    answers.add((ticketId: ticketId, answer: answer));
    return answerResult();
  }

  /// Historique des lancements par ticket : absent par défaut (aucun
  /// lancement). Un test qui veut la lecture en cours place un [Replay] vide
  /// avant d'ouvrir la fiche.
  final launchHistories =
      <String, Replay<RechercheDocument<TicketLaunchesDoc>>>{};

  /// `ticket_status/launches` : absent par défaut.
  final launchStatus = Replay<RechercheDocument<EtatLancements>>()
    ..add(const DocumentAbsent());

  Replay<RechercheDocument<TicketLaunchesDoc>> launchesOf(String ticketId) =>
      launchHistories.putIfAbsent(
        ticketId,
        () => Replay()..add(const DocumentAbsent()),
      );

  @override
  Stream<RechercheDocument<TicketLaunchesDoc>> watchLaunches(String ticketId) =>
      launchesOf(ticketId).stream;

  @override
  Stream<RechercheDocument<EtatLancements>> watchLaunchStatus() =>
      launchStatus.stream;

  /// `admin/delivery` par ticket : absent par défaut.
  final deliveries = <String, Replay<RechercheDocument<TicketDelivery>>>{};

  Replay<RechercheDocument<TicketDelivery>> deliveryOf(String ticketId) =>
      deliveries.putIfAbsent(
        ticketId,
        () => Replay()..add(const DocumentAbsent()),
      );

  @override
  Stream<RechercheDocument<TicketDelivery>> watchDelivery(String ticketId) =>
      deliveryOf(ticketId).stream;

  /// Lancements demandés : ticket et action.
  final launches = <({String ticketId, ActionLancement action})>[];

  /// Réponse du serveur à un lancement ; jamais terminée par défaut.
  Future<ResultatLancement> Function() launchResult = () =>
      Completer<ResultatLancement>().future;

  @override
  Future<ResultatLancement> launch({
    required String ticketId,
    required ActionLancement action,
  }) {
    launches.add((ticketId: ticketId, action: action));
    return launchResult();
  }

  /// Captures jointes : ticket, auteur, octets.
  final screenshotsAttached =
      <({String ticketId, String authorUid, Uint8List png})>[];

  /// Réponse à [attachScreenshot] : vrai si la capture est jointe.
  Future<bool> Function() attachResult = () async => true;

  @override
  Future<bool> attachScreenshot({
    required String ticketId,
    required String authorUid,
    required Uint8List png,
  }) {
    screenshotsAttached.add((
      ticketId: ticketId,
      authorUid: authorUid,
      png: png,
    ));
    return attachResult();
  }

  /// Captures lues, par chemin ; absente : lecture en échec.
  final screenshots = <String, Uint8List>{};
  final screenshotReads = <String>[];

  @override
  Future<Uint8List> loadScreenshot(String path) async {
    screenshotReads.add(path);
    final bytes = screenshots[path];
    if (bytes == null) throw StateError('capture absente');
    return bytes;
  }
}

/// Demande de page reçue par [FakeLibraryRepository].
typedef DemandePage = ({String prefixe, CurseurPage? apres});

class FakeLibraryRepository implements LibraryRepository {
  /// Réponse à `lireIndex`, par nature ; absente : `DocumentAbsent`.
  final index = <NatureReferentiel, RechercheDocument<IndexReferentiel>>{};

  /// Panne de `lireIndex`, par nature.
  final indexErrors = <NatureReferentiel, Object>{};
  final indexReads = <NatureReferentiel>[];

  /// Lectures d'index faites dans le cache seul (`cacheSeul`).
  final indexCacheReads = <NatureReferentiel>[];

  /// Réponse retenue jusqu'à ce que le `Completer` de la nature soit complété.
  final indexAttente = <NatureReferentiel, Completer<void>>{};

  /// Réponse à `lireFiche`, par identifiant ; absente : `DocumentAbsent`.
  final fiches = <String, RechercheDocument<FicheReferentiel>>{};
  final ficheReads = <String>[];

  /// Recettes publiques, dans l'ordre de `recipe.name`.
  final recettes = <RecettePublique>[];

  /// Panne de la prochaine page demandée.
  Object? pageError;
  bool pagesFromCache = false;
  final pages = <DemandePage>[];

  @override
  Future<RechercheDocument<IndexReferentiel>> lireIndex(
    NatureReferentiel nature, {
    bool cacheSeul = false,
  }) async {
    indexReads.add(nature);
    if (cacheSeul) indexCacheReads.add(nature);
    final attente = indexAttente[nature];
    if (attente != null) await attente.future;
    final error = indexErrors[nature];
    if (error != null) throw error;
    return index[nature] ?? DocumentAbsent<IndexReferentiel>();
  }

  @override
  Future<RechercheDocument<FicheReferentiel>> lireFiche(
    NatureReferentiel nature,
    String id,
  ) async {
    ficheReads.add(id);
    return fiches[id] ?? DocumentAbsent<FicheReferentiel>();
  }

  @override
  Future<PageRecettesPubliques> pageRecettesPubliques({
    String prefixe = '',
    CurseurPage? apres,
  }) async {
    pages.add((prefixe: prefixe, apres: apres));
    final error = pageError;
    if (error != null) {
      pageError = null;
      throw error;
    }
    final matching = [
      for (final r in recettes)
        if (normaliserNomRecherche(
          r.name,
        ).startsWith(normaliserNomRecherche(prefixe)))
          r,
    ];
    final start = apres == null ? 0 : apres.valeur as int;
    final end = (start + kTaillePageRecettes).clamp(0, matching.length);
    return PageRecettesPubliques(
      documents: [
        for (final r in matching.sublist(start, end)) DocumentValide(r.id, r),
      ],
      suite: end - start < kTaillePageRecettes ? null : CurseurPage(end),
      fromCache: pagesFromCache,
    );
  }

  @override
  Future<RechercheDocument<RecettePublique>> lireRecettePublique(
    String id,
  ) async {
    for (final r in recettes) {
      if (r.id == id) return DocumentTrouve(r);
    }
    return DocumentAbsent<RecettePublique>();
  }

  /// Noms reçus par `signalerNonResolus`, un appel par liste.
  final signales = <List<NomNonResolu>>[];

  @override
  Future<void> signalerNonResolus(List<NomNonResolu> noms) async {
    signales.add(noms);
  }
}

/// Admin › Rapports d'erreur : [rapports] du plus récent au plus ancien,
/// servis par pages de [kTaillePageRapports] ; le curseur est l'indice suivant.
class FakeErrorReportsRepository implements ErrorReportsRepository {
  final rapports = <ErrorReport>[];

  /// Panne de la prochaine page demandée.
  Object? pageError;
  bool fromCache = false;

  /// Curseur de chaque page demandée (`null` : première page).
  final demandes = <CurseurRapports?>[];

  /// Réponse retenue jusqu'à ce que ce `Completer` soit complété.
  Completer<void>? attente;

  @override
  Future<PageRapports> page({CurseurRapports? apres}) async {
    demandes.add(apres);
    final retenue = attente;
    if (retenue != null) await retenue.future;
    final error = pageError;
    if (error != null) {
      pageError = null;
      throw error;
    }
    final start = apres == null ? 0 : apres.valeur as int;
    final end = (start + kTaillePageRapports).clamp(0, rapports.length);
    return PageRapports(
      rapports: rapports.sublist(start, end),
      suite: end - start < kTaillePageRapports ? null : CurseurRapports(end),
      fromCache: fromCache,
    );
  }
}

/// Admin › Journaux : chaque recherche est notée ; [reponses] sert les pages
/// dans l'ordre, une [EchecJournaux] ou autre erreur est levée.
class FakeLogsRepository implements LogsRepository {
  final reponses = <Object>[];
  final demandes = <({FiltresJournaux filtres, String? suite})>[];

  /// Réponse retenue jusqu'à ce que ce `Completer` soit complété.
  Completer<void>? attente;

  @override
  Future<PageJournaux> rechercher(
    FiltresJournaux filtres, {
    String? suite,
  }) async {
    demandes.add((filtres: filtres, suite: suite));
    final retenue = attente;
    if (retenue != null) await retenue.future;
    if (reponses.isEmpty) throw StateError('aucune réponse prévue');
    final r = reponses.removeAt(0);
    if (r is PageJournaux) return r;
    throw r;
  }
}

/// Décision reçue par [FakeTicketsRepository.createDecision].
typedef DecisionCreee = ({
  String ticketId,
  String id,
  TicketDecisionAction action,
  String? text,
  String requestedByUid,
});

class RecordingErrorReportService extends ErrorReportService {
  final reports = <({String feature, Object error, String? context})>[];

  @override
  void reportError({
    required String feature,
    required Object error,
    StackTrace? stackTrace,
    String? context,
  }) {
    reports.add((feature: feature, error: error, context: context));
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
/// Image PNG d'un pixel, valide pour `Image.memory`.
final kPngDeTest = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

class TestApp {
  /// [appVersion] : version installée lue au démarrage ; `null` si illisible.
  /// [themeMode] : thème lu sur l'appareil avant `runApp`.
  TestApp({
    String? appVersion = '0.1.0',
    ThemeMode themeMode = ThemeMode.system,
  }) : auth = FakeAuthRepository(),
       members = FakeMembersRepository(),
       recipes = FakeRecipesRepository(),
       equipment = FakeEquipmentRepository(),
       brews = FakeBrewsRepository(),
       costs = FakeCostsRepository(),
       alerte = FakeAlerte(),
       tickets = FakeTicketsRepository(),
       fichiers = FakeEchangeFichiers(),
       library = FakeLibraryRepository(),
       errorReports = FakeErrorReportsRepository(),
       logs = FakeLogsRepository(),
       processes = FakeProcessesRepository(),
       preferencesProcessus = FakePreferencesProcessusRepository(),
       importFirestore = FakeFirebaseFirestore(),
       preferences = FakePreferencesAppareil(),
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
        costsRepositoryProvider.overrideWithValue(costs),
        ticketsRepositoryProvider.overrideWithValue(tickets),
        libraryRepositoryProvider.overrideWithValue(library),
        errorReportsRepositoryProvider.overrideWithValue(errorReports),
        logsRepositoryProvider.overrideWithValue(logs),
        importFichesRepositoryProvider.overrideWithValue(
          FirestoreImportFichesRepository(firestore: importFirestore),
        ),
        processesRepositoryProvider.overrideWithValue(processes),
        preferencesProcessusRepositoryProvider.overrideWithValue(
          preferencesProcessus,
        ),
        ouvrirLienProvider.overrideWithValue((uri) async {
          openedLinks.add(uri);
          return openLinkResult;
        }),
        horlogeProvider.overrideWithValue(() => now),
        alerteMinuteurProvider.overrideWithValue(alerte),
        echangeFichiersProvider.overrideWithValue(fichiers),
        analyseurFichierProvider.overrideWithValue((o) => analyseur(o)),
        screenWakelockProvider.overrideWithValue(wakelock),
        appVersionProvider.overrideWithValue(appVersion),
        preferencesAppareilProvider.overrideWithValue(preferences),
        themeModeInitialProvider.overrideWithValue(themeMode),
        nouveautesSourceProvider.overrideWithValue(() => nouveautes()),
        // `toImage` ne se termine pas sous l'horloge simulée : la capture
        // rend [capture], et compte les appels.
        capturerEcranProvider.overrideWithValue((context) async {
          captureCalls++;
          return capture;
        }),
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
  final FakeCostsRepository costs;
  final FakeAlerte alerte;
  final FakeTicketsRepository tickets;
  final FakeEchangeFichiers fichiers;
  final FakeLibraryRepository library;
  final FakeErrorReportsRepository errorReports;
  final FakeLogsRepository logs;
  final FakeProcessesRepository processes;
  final FakePreferencesProcessusRepository preferencesProcessus;

  /// Firestore en mémoire d'Admin › Import (v0.6).
  final FakeFirebaseFirestore importFirestore;
  final FakePreferencesAppareil preferences;

  /// Analyse d'un fichier importé, remplaçable par les tests.
  AnalyseFichier Function(List<int>) analyseur = analyserFichier;
  final RecordingErrorReportService errors;

  /// Adresses ouvertes hors de l'application, et réponse du système.
  final openedLinks = <Uri>[];
  bool openLinkResult = true;
  late final ScreenWakelock wakelock;
  final wakelockCalls = <bool>[];

  /// Image rendue par la capture de « Signaler ou proposer » ; `null` : pas
  /// de capture.
  Uint8List? capture = kPngDeTest;
  int captureCalls = 0;

  /// Contenu de l'asset des nouveautés, modifiable par les tests.
  Future<String> Function() nouveautes = () async => '{"versions": []}';

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
