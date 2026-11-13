import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:exchange/exchange.dart' show IndexImport;
import 'package:exchange/fiches.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/fichiers/echange_fichiers.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/mesures_retenues.dart';
import 'package:kass_beer/features/costs/data/costs_repository.dart';
import 'package:kass_beer/features/costs/presentation/formats_cout.dart';
import 'package:kass_beer/features/import/data/execution_import.dart';
import 'package:kass_beer/features/import/data/import_fiches_repository.dart';
import 'package:kass_beer/features/import/domain/fiches_a_importer.dart';
import 'package:kass_beer/features/import/presentation/import_fiches_screen.dart';
import 'package:kass_beer/features/import/presentation/libelles_import_fiches.dart';
import 'package:kass_beer/features/members/domain/member.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/fakes.dart';

/// Admin › Import (v0.6, TE2) sur la fixture inventée d'`exchange/` : noms et
/// prix fictifs.
const _fixture = '../exchange/test/fixtures/fiches/fiches-valide.json';
const _uid = 'uid-admin';
final _maintenant = DateTime.utc(2026, 11, 13, 12);

Map<String, Object?> _json() =>
    jsonDecode(File(_fixture).readAsStringSync()) as Map<String, Object?>;

FichierFiches _lu([Map<String, Object?>? json]) =>
    lireFichierFiches(
          utf8.encode(jsonEncode(json ?? _json())),
          maintenant: _maintenant,
        )
        as FichierFiches;

List<FicheAImporter> _preparer(
  RecordingErrorReportService errors, [
  Map<String, Object?>? json,
]) => preparerFiches(
  _lu(json),
  uid: _uid,
  index: const IndexImport(),
  errors: errors,
  reported: <String>{},
);

/// Dépôt qui refuse ou retient certaines écritures.
class _DepotPiege implements ImportFichesRepository {
  _DepotPiege(this.vrai);

  final ImportFichesRepository vrai;

  /// Brassin dont la création est refusée (`permission-denied`).
  String? brassinRefuse;

  /// Lots d'événements jamais acceptés (hors ligne).
  bool evenementsSansReponse = false;
  int ecritures = 0;

  @override
  Future<EtatServeur> lireExistant({
    required String uid,
    required Set<String> recipeIds,
    required Set<String> brewIds,
  }) => vrai.lireExistant(uid: uid, recipeIds: recipeIds, brewIds: brewIds);

  @override
  Future<void> creerRecette({
    required String id,
    required RecipeContent content,
    required String ownerUid,
    required String? ownerName,
  }) {
    ecritures++;
    return vrai.creerRecette(
      id: id,
      content: content,
      ownerUid: ownerUid,
      ownerName: ownerName,
    );
  }

  @override
  Future<void> creerBrassin(
    CreationBrassin creation, {
    required String ownerUid,
    required String? ownerName,
  }) {
    ecritures++;
    if (creation.brewId == brassinRefuse) {
      return Future.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
    }
    return vrai.creerBrassin(
      creation,
      ownerUid: ownerUid,
      ownerName: ownerName,
    );
  }

  @override
  Future<void> modifierBrassin(
    ModificationBrassin modification, {
    required String? ownerName,
  }) {
    ecritures++;
    return vrai.modifierBrassin(modification, ownerName: ownerName);
  }

  @override
  Future<void> ecrireEvenements(LotEvenements lot) {
    ecritures++;
    if (evenementsSansReponse) return Completer<void>().future;
    return vrai.ecrireEvenements(lot);
  }
}

void main() {
  group('préparation et plan d\'écriture', () {
    test('coût figé avec les prix et frais de la fiche, sinon la raison', () {
      final fiches = _preparer(RecordingErrorReportService());
      final blonde = fiches[0].cout as CoutCalcule;
      // Pils 4 kg à 2 €/kg, houblon 30 g à 0,10 €/g, 1 sachet à 4 €, eau 1,50 €,
      // 50 capsules à 0,02 €.
      expect(blonde.cout.totalEur, closeTo(17.5, 1e-9));
      expect(blonde.cout.brewId, 'fiche-2024-07-14-blonde-essai');
      expect(
        blonde.cout.computedAt,
        DateTime.parse('2024-07-14T09:15:00+02:00'),
      );
      expect(blonde.cout.bottlesCount, 50);
      expect(fiches[1].cout, isA<SansPrix>());
      expect(fiches[2].cout, isA<CoutImpossible>());
      expect(lignesCout(fiches[2].cout).single, contains('prix manquant'));
      expect(lignesCout(blonde), ['Coût figé : ${formatEuros(17.5)}']);
    });

    test('plan d\'une fiche nouvelle : documents, ordre, groupes', () {
      final blonde = _preparer(RecordingErrorReportService()).first;
      final plan = planDeFiche(
        blonde,
        existant: null,
        recetteAbsente: true,
        coutFige: false,
      );
      expect(plan.map((e) => e.etape), [
        EtapeEcriture.recette,
        EtapeEcriture.brassin,
        EtapeEcriture.dateDeBrassage,
        EtapeEcriture.embouteillage,
        EtapeEcriture.notes,
        EtapeEcriture.evenements,
        EtapeEcriture.mesuresRetenues,
        EtapeEcriture.cout,
        EtapeEcriture.marque,
      ]);
      final date = plan[2] as ModificationBrassin;
      expect(
        date.champs['brewed_at'],
        DateTime.parse('2024-07-14T09:15:00+02:00'),
      );
      final marque = plan.last as ModificationBrassin;
      expect(
        marque.champs['imported_from'],
        'Fiche Excel · 2024-07-14-blonde-essai · ${blonde.source.empreinte}',
      );
      expect((marque.champs['imported_from']! as String).length, lessThan(200));
    });

    test('événements par lots de 10', () {
      final json = _json();
      final fiche =
          ((json['kassbeer_fiches']! as Map)['fiches']! as List).first as Map;
      final events = fiche['events']! as List;
      for (var i = 0; i < 16; i++) {
        events.add({
          'id': 'x$i',
          'kind': 'measurement',
          'step_key': 'empatage',
          'measure_type': 'temperature',
          'value': 66,
          'measured_at': '2024-07-14T09:30:00+02:00',
          'time_source': 'fiche',
        });
      }
      final f = _preparer(RecordingErrorReportService(), json).first;
      final lots = planDeFiche(
        f,
        existant: null,
        recetteAbsente: false,
        coutFige: false,
      ).whereType<LotEvenements>().toList();
      expect(lots.map((l) => l.evenements.length), [10, 10, 3]);
      expect(lots.map((l) => l.numero), [1, 2, 3]);
    });

    test('relevé de densité finale estimé : heure du fichier, sans calcul', () {
      final blonde = _preparer(RecordingErrorReportService()).first;
      final releve = blonde.evenements.last;
      expect(releve.measuredAt, DateTime.parse('2024-08-11T12:00:00+02:00'));
      expect(releve.phase, PhaseEvenement.fermentation);
      expect(
        heuresReprises(blonde),
        contains('Relevé sans date : daté de 28 jours après le brassage.'),
      );
    });
  });

  group('écriture sur Firestore en mémoire', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreImportFichesRepository depot;
    late FirestoreCostsRepository couts;
    late RecordingErrorReportService errors;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      errors = RecordingErrorReportService();
      depot = FirestoreImportFichesRepository(firestore: firestore);
      couts = FirestoreCostsRepository(
        errorReportService: errors,
        firestore: firestore,
      );
    });

    Future<EtatServeur> etat(List<FicheAImporter> fiches) => depot.lireExistant(
      uid: _uid,
      recipeIds: {for (final f in fiches) f.fiche!.recipeDocId},
      brewIds: {for (final f in fiches) f.brewId},
    );

    Future<List<IssueFiche>> importer(
      List<FicheAImporter> fiches, {
      ImportFichesRepository? avec,
      Future<void>? perte,
      Duration delai = kDelaiEcriture,
    }) async => executerImport(
      fiches: fiches,
      etat: await etat(fiches),
      uid: _uid,
      ownerName: 'Alice Admin',
      depot: avec ?? depot,
      couts: couts,
      errors: errors,
      perteConnexion: perte ?? Completer<void>().future,
      delai: delai,
    );

    Future<int> nombreDocuments() async {
      var n = (await firestore.collection('recipes').get()).size;
      final brews = await firestore.collection('brews').get();
      n += brews.size;
      for (final b in brews.docs) {
        n += (await b.reference.collection('events').get()).size;
      }
      n += (await firestore.collection('users/$_uid/brew_costs').get()).size;
      return n;
    }

    test('import complet : recettes partagées, brassins Terminé, coût figé, '
        'aucun prix ni frais dans Mes prix', () async {
      final fiches = _preparer(errors);
      final issues = await importer(fiches);
      expect(issues, everyElement(isA<FicheEcrite>()));
      expect((await firestore.collection('recipes').get()).size, 2);
      final brews = await firestore.collection('brews').get();
      expect(brews.size, 3);
      final blonde = await firestore
          .doc('brews/fiche-2024-07-14-blonde-essai')
          .get();
      final data = blonde.data()!;
      expect(data['status'], 'done');
      expect(data['owner_uid'], _uid);
      expect(data['bottles_count'], 50);
      expect(data['og_event_id'], 'e05');
      expect(data.containsKey('bottled_at'), isFalse);
      // ADR-010 : aucun déroulé écrit ; le brassin se lit comme une journée
      // tirée de la chronologie de sa copie figée (P37).
      expect(data.containsKey('process'), isFalse);
      final lu = Brew.fromFirestore(blonde.id, data);
      expect(lu.process, isNull);
      expect(lu.deroule.journees, hasLength(1));
      expect(lu.deroule.lignes.map((l) => l.key), [
        'empatage',
        'ebullition',
        'densite-initiale',
      ]);
      expect(data['imported_from'], fiches.first.marque);
      expect(
        (data['equipment_snapshot'] as Map)['name'],
        'Installation à cuves (fiches Excel)',
      );
      expect((await firestore.collection('users/$_uid/prices').get()).size, 0);
      expect((await firestore.collection('users/$_uid/fees').get()).size, 0);
      final cout = await firestore
          .doc('users/$_uid/brew_costs/fiche-2024-07-14-blonde-essai')
          .get();
      expect(cout.data()!['freeze_kind'], 'initial');
      expect(cout.data()!['total_eur'], closeTo(17.5, 1e-9));
      expect(
        (await firestore.collection('users/$_uid/brew_costs').get()).size,
        1,
      );
      expect(errors.reports, isEmpty);
    });

    test('relevé J+28 retenu comme densité finale d\'un brassin Terminé sans '
        'date d\'embouteillage', () async {
      await importer(_preparer(errors));
      final doc = await firestore
          .doc('brews/fiche-2024-07-14-blonde-essai')
          .get();
      final brew = Brew.fromFirestore(doc.id, doc.data()!);
      final events = await firestore
          .collection('brews/fiche-2024-07-14-blonde-essai/events')
          .get();
      final lus = [
        for (final e in events.docs) BrewEvent.fromFirestore(e.id, e.data()),
      ];
      expect(brew.status, BrewStatus.done);
      expect(brew.bottledAt, isNull);
      final retenues = MesuresRetenues.de(brew, lus);
      expect(retenues.densiteFinale?.event.id, 'e07');
      expect(retenues.densiteFinale?.value, 1.023);
      expect(retenues.densiteInitiale?.value, 1.052);
    });

    test('second import : tout « Déjà importée », aucune écriture', () async {
      final fiches = _preparer(errors);
      await importer(fiches);
      final avant = await nombreDocuments();
      final serveur = await etat(fiches);
      final etats = [
        for (final f in fiches) etatDe(f, serveur, uid: _uid).etat,
      ];
      expect(etats, everyElement(EtatFiche.dejaImportee));
      expect(etats.where(cochable), isEmpty);
      expect(await nombreDocuments(), avant);
    });

    test(
      'fiche changée après l\'import : contenu différent, non cochable',
      () async {
        await importer(_preparer(errors));
        final json = _json();
        final fiche =
            ((json['kassbeer_fiches']! as Map)['fiches']! as List).first as Map;
        (fiche['brew']! as Map)['bottles_count'] = 49;
        final changees = _preparer(errors, json);
        final serveur = await etat(changees);
        final e = etatDe(changees.first, serveur, uid: _uid).etat;
        expect(e, EtatFiche.contenuDifferent);
        expect(cochable(e), isFalse);
      },
    );

    test(
      'reprise : seul ce qui manque est écrit, aucun événement en double',
      () async {
        final fiches = _preparer(errors);
        final blonde = fiches.first;
        // Import interrompu : recette, brassin, date et 2 événements écrits.
        await depot.creerRecette(
          id: blonde.fiche!.recipeDocId,
          content: blonde.recette!,
          ownerUid: _uid,
          ownerName: 'Alice Admin',
        );
        final plan = planDeFiche(
          blonde,
          existant: null,
          recetteAbsente: false,
          coutFige: false,
        );
        await depot.creerBrassin(
          plan.whereType<CreationBrassin>().single,
          ownerUid: _uid,
          ownerName: 'Alice Admin',
        );
        await depot.modifierBrassin(
          plan.whereType<ModificationBrassin>().first,
          ownerName: 'Alice Admin',
        );
        await depot.ecrireEvenements(
          LotEvenements(blonde.brewId, 1, blonde.evenements.take(2).toList()),
        );
        final serveur = await etat([blonde]);
        expect(etatDe(blonde, serveur, uid: _uid).etat, EtatFiche.aCompleter);
        final reprise = planDeFiche(
          blonde,
          existant: serveur.brassins[blonde.brewId],
          recetteAbsente: false,
          coutFige: false,
        );
        expect(reprise.map((e) => e.etape), [
          EtapeEcriture.embouteillage,
          EtapeEcriture.notes,
          EtapeEcriture.evenements,
          EtapeEcriture.mesuresRetenues,
          EtapeEcriture.cout,
          EtapeEcriture.marque,
        ]);
        expect(
          reprise.whereType<LotEvenements>().single.evenements,
          hasLength(5),
        );

        final issues = await importer([blonde]);
        expect(issues.single, isA<FicheEcrite>());
        final events = await firestore
            .collection('brews/${blonde.brewId}/events')
            .get();
        expect(events.size, 7);
        expect((await firestore.collection('recipes').get()).size, 1);
        final apres = await etat([blonde]);
        expect(etatDe(blonde, apres, uid: _uid).etat, EtatFiche.dejaImportee);
      },
    );

    test('erreur partielle : la fiche refusée est passée, les autres écrites, '
        'rapport sans prix ni texte', () async {
      final fiches = _preparer(errors);
      final piege = _DepotPiege(depot)
        ..brassinRefuse = 'fiche-2024-07-14-blonde-essai';
      final issues = await importer(fiches, avec: piege);
      expect(issues[0], isA<FicheEnErreur>());
      final erreur = issues[0] as FicheEnErreur;
      expect(erreur.etape, EtapeEcriture.brassin);
      expect(erreur.code, 'permission-denied');
      expect(issues[1], isA<FicheEcrite>());
      expect(issues[2], isA<FicheEcrite>());
      // La recette créée par la fiche en erreur sert à la troisième.
      expect((await firestore.collection('recipes').get()).size, 2);
      final rapport = errors.reports.single;
      expect(rapport.feature, 'import.fiches');
      expect(
        rapport.context,
        'fiche n° 1, étape brassin, code permission-denied',
      );
      final texte = errors.reports
          .map((r) => '${r.error} ${r.context}')
          .join(' ');
      for (final interdit in ['€', '17,5', '17.5', 'Pils', 'Blonde']) {
        expect(texte, isNot(contains(interdit)));
      }
    });

    test('connexion perdue pendant l\'écriture : import arrêté, suite non '
        'traitée', () async {
      final fiches = _preparer(errors);
      final piege = _DepotPiege(depot)..evenementsSansReponse = true;
      final perte = Completer<void>();
      final issues = importer(fiches, avec: piege, perte: perte.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      perte.complete();
      final resultat = await issues;
      expect(resultat[0], isA<FicheInterrompue>());
      expect(resultat[1], isA<FicheNonTraitee>());
      expect(resultat[2], isA<FicheNonTraitee>());
    });

    test('accusé absent : arrêt après le délai', () async {
      final fiches = _preparer(errors);
      final piege = _DepotPiege(depot)..evenementsSansReponse = true;
      final resultat = await importer(
        fiches,
        avec: piege,
        delai: const Duration(milliseconds: 20),
      );
      expect(resultat.first, isA<FicheInterrompue>());
      expect(resultat.skip(1), everyElement(isA<FicheNonTraitee>()));
    });

    test('hors ligne au départ : aucune écriture', () async {
      final fiches = _preparer(errors);
      final piege = _DepotPiege(depot);
      final resultat = await importer(
        fiches,
        avec: piege,
        perte: Future<void>.value(),
      );
      expect(resultat, everyElement(isA<FicheNonTraitee>()));
      expect(piege.ecritures, 0);
      expect(await nombreDocuments(), 0);
    });

    /// État de la première fiche, sans aucune écriture de l'import.
    Future<(EtatFiche, RefusImport?)> etatPremiere() async {
      final blonde = _preparer(errors).first;
      final piege = _DepotPiege(depot);
      final serveur = await piege.lireExistant(
        uid: _uid,
        recipeIds: {blonde.fiche!.recipeDocId},
        brewIds: {blonde.brewId},
      );
      expect(piege.ecritures, 0);
      final (:etat, :refus) = etatDe(blonde, serveur, uid: _uid);
      return (etat, refus);
    }

    test('S3 : recette d\'un autre membre à l\'identifiant de la fiche : '
        'refusée, non cochable', () async {
      await firestore.doc('recipes/fiche-blonde-essai').set({
        'owner_uid': 'autre',
      });
      final (etat, refus) = await etatPremiere();
      expect(etat, EtatFiche.refusee);
      expect(refus, isA<DocumentDUnAutreMembre>());
      expect(cochable(etat), isFalse);
    });

    test('S3 : brassin d\'un autre membre à l\'identifiant de la fiche : '
        'refusée', () async {
      await firestore.doc('brews/fiche-2024-07-14-blonde-essai').set({
        'owner_uid': 'autre',
      });
      final (etat, refus) = await etatPremiere();
      expect(etat, EtatFiche.refusee);
      expect(refus, isA<DocumentDUnAutreMembre>());
    });

    test('S2 : événement d\'un autre compte sous le brassin, absent puis '
        'présent : refusée, aucune écriture', () async {
      await firestore.doc('brews/fiche-2024-07-14-blonde-essai/events/e01').set(
        {'owner_uid': 'autre', 'kind': 'note'},
      );
      final (sans, refusSans) = await etatPremiere();
      expect(sans, EtatFiche.refusee);
      expect(refusSans, isA<DocumentDUnAutreMembre>());
      await firestore.doc('brews/fiche-2024-07-14-blonde-essai').set({
        'owner_uid': _uid,
      });
      final (avec, refusAvec) = await etatPremiere();
      expect(avec, EtatFiche.refusee);
      expect(refusAvec, isA<DocumentDUnAutreMembre>());
    });
  });

  group('écran Admin › Import', () {
    final annonces = <String>[];

    setUp(() {
      annonces.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            final data = (message as Map?)?['data'];
            if (data is Map && data['message'] is String) {
              annonces.add(data['message'] as String);
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          );
    });

    Future<TestApp> ouvrir(WidgetTester tester, {bool admin = true}) async {
      final app = TestApp()..now = DateTime(2026, 11, 13, 12);
      app.costs.serverAnswer = () async {};
      await app.pump(tester);
      app.signIn(
        admin ? adminUser : brewerUser,
        member: admin ? adminMember : brewerMember,
      );
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.adminImport);
      await tester.pumpAndSettle();
      return app;
    }

    void choisir(TestApp app) => app.fichiers.choix = FichierChoisi(
      'fiches.json',
      Uint8List.fromList(File(_fixture).readAsBytesSync()),
    );

    testWidgets('un brasseur ne peut pas ouvrir l\'écran', (tester) async {
      await ouvrir(tester, admin: false);
      expect(find.byType(ImportFichesScreen), findsNothing);
    });

    testWidgets('analyse, import, second import sans écriture', (tester) async {
      final app = await ouvrir(tester);
      expect(find.text(TextesImportFiches.aide), findsOneWidget);
      choisir(app);
      await tester.tap(find.text(TextesImportFiches.choisir));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(
        find.text(
          '3 fiches · 2 recettes · 3 brassins · 12 heures et mesures · '
          '1 coût figé',
        ),
        findsOneWidget,
      );
      expect(find.text('3 nouvelles'), findsOneWidget);
      await tester.tap(find.text('Importer 3 fiches'));
      await tester.pumpAndSettle();
      expect(find.text('Importer 3 fiches ?'), findsOneWidget);
      expect(
        find.text(
          '3 brassins et 2 recettes seront écrits sous votre compte. Ils '
          'seront visibles du groupe. Les coûts restent privés.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Importer'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(
        find.text('Import terminé · 3 créées · 0 ignorée · 0 en erreur'),
        findsOneWidget,
      );
      expect(find.text(TextesImportFiches.aRevoir), findsOneWidget);
      expect((await app.importFirestore.collection('brews').get()).size, 3);
      expect(
        app.costs.writes.where((w) => w.kind == 'brew_cost'),
        hasLength(1),
      );
      expect(
        app.costs.writes.where((w) => w.kind == 'price' || w.kind == 'fee'),
        isEmpty,
      );

      // Second import du même fichier : rien à écrire (ID2, FIN3).
      app.container.read(routerProvider).go(AppRoutes.admin);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.adminImport);
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextesImportFiches.choisir));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('3 déjà importées'), findsOneWidget);
      expect(find.text(TextesImportFiches.rienAEcrire), findsOneWidget);
      expect(find.textContaining('Importer 3'), findsNothing);

      // Aucun montant dans une annonce ni dans un rapport (CO5, P13).
      expect(annonces, isNotEmpty);
      for (final texte in [
        ...annonces,
        for (final r in app.errors.reports) '${r.error} ${r.context}',
      ]) {
        expect(texte, isNot(contains('€')));
        expect(texte, isNot(contains('17,50')));
      }
    });

    Future<void> analyser(WidgetTester tester, TestApp app) async {
      choisir(app);
      await tester.tap(find.text(TextesImportFiches.choisir));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('U3 : libellé accessible d\'une ligne, explication comprise', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await ouvrir(tester);
      // Import commencé et non terminé pour la deuxième fiche.
      await app.importFirestore.doc('brews/fiche-2023-04-02-ambree-essai').set({
        'owner_uid': adminUser.uid,
      });
      await analyser(tester, app);
      expect(
        find.bySemanticsLabel(
          RegExp(
            r"^Blonde d'essai, 1[34] juillet 2024, nouvelle, \d+ points à "
            r'revoir$',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            r"^Ambrée d'essai, [12] avril 2023, à compléter, .*"
            'Import commencé et non terminé : seul ce qui manque sera écrit.',
          ),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets(
      'U1 : connexion perdue pendant l\'écriture, « Import arrêté »',
      (tester) async {
        final app = await ouvrir(tester);
        // Le coût figé de la première fiche n'a jamais d'accusé.
        app.costs.serverAnswer = () => Completer<void>().future;
        await analyser(tester, app);
        await tester.tap(find.text('Importer 3 fiches'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Importer'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();
        expect(find.textContaining('Fiche 1 sur 3'), findsOneWidget);
        app.members
            .lookup(adminUser.memberKey!)
            .add(const MemberLookup(member: adminMember, fromCache: true));
        await tester.pumpAndSettle();
        expect(
          find.text('Import arrêté · 0 créée · 2 ignorées · 1 en erreur'),
          findsOneWidget,
        );
        expect(
          find.text(TextesImportFiches.connexionPerdue(1, 3)),
          findsOneWidget,
        );
        expect(find.textContaining('Import terminé'), findsNothing);
        expect(annonces.last, startsWith('Import arrêté.'));
      },
    );

    testWidgets('U2 : hors ligne pendant la relecture, barre et en-tête', (
      tester,
    ) async {
      final app = await ouvrir(tester);
      await analyser(tester, app);
      expect(find.text(TextesImportFiches.choisirAutre), findsOneWidget);
      expect(find.text('Importer 3 fiches'), findsOneWidget);
      app.members
          .lookup(adminUser.memberKey!)
          .add(const MemberLookup(member: adminMember, fromCache: true));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Import impossible hors ligne. Reconnectez-vous pour importer les '
          'fiches cochées.',
        ),
        findsOneWidget,
      );
      expect(find.text(TextesImportFiches.choisirAutre), findsNothing);
      expect(find.text(TextesImportFiches.horsLigne), findsNothing);
      expect(find.text('Importer 3 fiches'), findsNothing);
    });

    testWidgets('fichier qui n\'est pas un fichier de fiches', (tester) async {
      final app = await ouvrir(tester);
      app.fichiers.choix = FichierChoisi(
        'recette.json',
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'beerjson': {
                'version': 2.06,
                'recipes': [
                  {'name': 'A', 'ingredients': <String, Object?>{}},
                ],
              },
            }),
          ),
        ),
      );
      await tester.tap(find.text(TextesImportFiches.choisir));
      await tester.pumpAndSettle();
      expect(find.text(TextesImportFiches.pasUnFichier), findsOneWidget);
    });

    testWidgets('hors ligne : message à la place du bouton', (tester) async {
      final app = TestApp()..now = DateTime(2026, 11, 13, 12);
      await app.pump(tester);
      app.signIn(adminUser, member: adminMember, fromCache: true);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.adminImport);
      await tester.pumpAndSettle();
      expect(find.text(TextesImportFiches.horsLigne), findsOneWidget);
      expect(find.text(TextesImportFiches.choisir), findsNothing);
    });
  });
}
