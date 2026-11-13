import 'dart:async';

import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/processes/data/preferences_processus_repository.dart';
import 'package:kass_beer/features/processes/data/processes_repository.dart';
import 'package:kass_beer/features/processes/domain/modele_processus.dart';
import 'package:kass_beer/features/processes/domain/preference_processus.dart';

import 'fakes.dart';

class FakeProcessesRepository implements ProcessesRepository {
  final all = Replay<ListeLue<ModeleProcessus>>();
  final writes = <Write<ContenuModele>>[];
  int _next = 0;
  int _nextKey = 0;

  /// Réponse du serveur à une écriture ; jamais terminée par défaut (hors ligne).
  Future<void> Function() serverAnswer = () => Completer<void>().future;

  /// Publie [items] comme une lecture du serveur (ou du cache) ; [illisibles] :
  /// identifiants de documents illisibles.
  void publish(
    List<ModeleProcessus> items, {
    bool fromCache = false,
    List<String> illisibles = const [],
  }) => all.add(
    ListeLue(
      documents: [
        for (final m in items) DocumentValide(m.id, m),
        for (final id in illisibles)
          DocumentInvalide<ModeleProcessus>(
            id,
            const DocumentIllisible('format_version', 'format inconnu'),
          ),
      ],
      fromCache: fromCache,
    ),
  );

  @override
  Stream<ListeLue<ModeleProcessus>> watchAll() => all.stream;

  @override
  String newKey() => 'k${++_nextKey}';

  @override
  CreationEnCours create({
    required ContenuModele content,
    required String ownerUid,
    required String? ownerName,
  }) {
    final id = 'processus-${++_next}';
    writes.add(Write('create', id, content, ownerUid, ownerName));
    return (id: id, written: serverAnswer());
  }

  @override
  Future<void> update({
    required String id,
    required ContenuModele content,
    required String? ownerName,
  }) {
    writes.add(Write('update', id, content, null, ownerName));
    return serverAnswer();
  }

  @override
  CreationEnCours copy({
    required ModeleProcessus source,
    required String ownerUid,
    required String? ownerName,
  }) {
    final id = 'copie-${++_next}';
    writes.add(
      Write(
        'copy',
        id,
        copieModele(source.content, newKey),
        ownerUid,
        ownerName,
      ),
    );
    return (id: id, written: serverAnswer());
  }

  @override
  CreationEnCours duplicate({
    required ModeleProcessus source,
    required String ownerUid,
    required String? ownerName,
  }) {
    final id = 'copie-${++_next}';
    writes.add(
      Write(
        'duplicate',
        id,
        copieModele(
          source.content,
          newKey,
          name: nomDuplication(source.content.name),
        ),
        ownerUid,
        ownerName,
      ),
    );
    return (id: id, written: serverAnswer());
  }

  @override
  Future<void> delete(String id) {
    writes.add(Write('delete', id, null, null, null));
    return serverAnswer();
  }
}

class FakePreferencesProcessusRepository
    implements PreferencesProcessusRepository {
  final _streams = <String, Replay<RechercheDocument<PreferenceProcessus>>>{};

  /// Choix écrits, dans l'ordre : (uid, modèle).
  final saved = <({String uid, String? templateId})>[];

  Future<void> Function() serverAnswer = () => Completer<void>().future;

  /// Lecture du choix de [uid] ; sans publication, absent du serveur.
  Replay<RechercheDocument<PreferenceProcessus>> of(String uid) =>
      _streams.putIfAbsent(
        uid,
        () =>
            Replay<RechercheDocument<PreferenceProcessus>>()
              ..add(DocumentAbsent<PreferenceProcessus>()),
      );

  /// Lecture de [uid] sans réponse (chargement).
  void enAttente(String uid) =>
      _streams[uid] = Replay<RechercheDocument<PreferenceProcessus>>();

  void publishDefault(String uid, String? templateId) => of(
    uid,
  ).add(DocumentTrouve(PreferenceProcessus(defaultTemplateId: templateId)));

  @override
  Stream<RechercheDocument<PreferenceProcessus>> watch(String uid) =>
      of(uid).stream;

  @override
  Future<void> saveDefault({required String uid, required String? templateId}) {
    saved.add((uid: uid, templateId: templateId));
    publishDefault(uid, templateId);
    return serverAnswer();
  }
}
