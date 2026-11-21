import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/admin/domain/error_report.dart';
import 'package:kass_beer/features/admin/domain/log_entry.dart';
import 'package:kass_beer/features/admin/domain/ticket_depuis_panne.dart';
import 'package:kass_beer/features/admin/presentation/analyser_panne.dart';
import 'package:kass_beer/features/admin/presentation/logs_screen.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/domain/ticket_launch.dart';
import 'package:kass_beer/features/tickets/presentation/admin_ticket_screen.dart';
import 'package:kass_beer/features/tickets/presentation/boite_lancement.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_form_screen.dart';

import 'support/fakes.dart';
import 'support/ticket_fixtures.dart';

const _pileMelee =
    '#0      Object.noSuchMethod (dart:core-patch/object_patch.dart:38:5)\n'
    '#1      RecipeEditor.save (package:kass_beer/features/recipes/presentation/recipe_editor.dart:120:7)\n'
    '#2      State.setState (package:flutter/src/widgets/framework.dart:1199:30)\n'
    '#3      _RootZone.run (dart:async/zone.dart:1654:54)\n'
    '#4      RecipesRepository.write (package:kass_beer/features/recipes/data/recipes_repository.dart:88:3)';

ErrorReport _rapport({
  String id = 'er-1',
  String error = 'StateError: panne de lecture',
  String? feature = 'recipes.watch',
  String? stackTrace = _pileMelee,
}) => ErrorReport(
  id: id,
  error: error,
  createdAt: DateTime(2026, 11, 14, 10, 30),
  uid: 'AbCdEfGhIjKlMnOpQrStUvWxYz12',
  feature: feature,
  context: 'users/AbCdEfGhIjKlMnOpQrStUvWxYz12/prices/malt',
  stackTrace: stackTrace,
  appVersion: '0.1.51+52',
  platform: PlateformeRapport.android,
);

EntreeJournal _entree({String insertId = 'ins-1'}) => EntreeJournal(
  horodatage: DateTime(2026, 11, 14, 10, 30, 5),
  severity: 'ERROR',
  fonction: 'synctickets',
  message: 'Échec pour brasseur@exemple.fr',
  insertId: insertId,
  payload: '{"uid": "AbCdEfGhIjKlMnOpQrStUvWxYz12"}',
  payloadCoupe: false,
  caracteresGardes: 8000,
);

Ticket _ticketDe(
  String id, {
  required String cle,
  int? issueNumber,
  DateTime? createdAt,
  TicketStatus status = TicketStatus.received,
  bool canLaunchAnalysis = false,
}) => unTicket(
  id: id,
  title: 'Erreur recipes.watch : StateError',
  description: '$cle (ne pas modifier : sert à marquer le rapport)\nsuite',
  screen: 'inconnu',
  issueNumber: issueNumber,
  createdAt: createdAt ?? DateTime(2026, 11, 14, 11),
  status: status,
  canLaunchAnalysis: canLaunchAnalysis,
);

Future<TestApp> _ouvrirRapports(
  WidgetTester tester, {
  List<ErrorReport>? rapports,
  List<Ticket> tickets = const [],
  bool offline = false,
}) async {
  final app = TestApp();
  app.errorReports.rapports.addAll(rapports ?? [_rapport()]);
  app.tickets.publishAll(tickets);
  await app.pump(tester);
  app.signIn(adminUser, member: adminMember, fromCache: offline);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(AppRoutes.adminErrorReports);
  await tester.pumpAndSettle();
  return app;
}

Future<void> _deplier(WidgetTester tester) async {
  await tester.tap(find.text('StateError: panne de lecture'));
  await tester.pumpAndSettle();
}

/// Déplie le premier rapport et ouvre le formulaire prérempli.
Future<void> _analyser(WidgetTester tester) async {
  await _deplier(tester);
  await _appuyerAnalyser(tester);
}

Future<void> _appuyerAnalyser(WidgetTester tester) async {
  final bouton = find.text(TextesAnalyser.analyser);
  await tester.ensureVisible(bouton);
  await tester.pumpAndSettle();
  await tester.tap(bouton);
  await tester.pumpAndSettle();
}

/// La fiche d'un ticket attend ses lectures : aucun `pumpAndSettle`.
Future<void> _pumpFiche(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _envoyer(WidgetTester tester) async {
  await tester.tap(find.text('Envoyer'));
  await tester.pumpAndSettle();
}

void main() {
  group('brouillon depuis un rapport', () {
    test('en-tête, origine, résumé, type, pile du code de l\'application', () {
      final b = brouillonDepuisRapport(_rapport());
      expect(b.type, TicketType.bug);
      expect(b.screen, 'inconnu');
      expect(b.title, 'Erreur recipes.watch : StateError');
      final lignes = b.description.split('\n');
      expect(
        lignes.first,
        'Rapport : er-1 (ne pas modifier : sert à marquer le rapport)',
      );
      expect(lignes[1], 'Créé depuis Admin › Rapports d\'erreur.');
      expect(
        lignes[2],
        'recipes.watch · v0.1.51+52 · Android · 14 novembre 2026',
      );
      expect(lignes[3], 'Type : StateError');
      expect(lignes[4], 'Pile (code de l\'application) :');
      expect(lignes.sublist(5, 7), [
        contains('package:kass_beer/features/recipes/presentation/'),
        contains('package:kass_beer/features/recipes/data/'),
      ]);
      expect(b.description, isNot(contains('package:flutter/')));
      expect(b.description, isNot(contains('dart:core')));
      expect(b.description, isNot(contains('dart:async')));
      expect(b.description, endsWith('\n\n'));
      expect(clePanneDeDescription(b.description), (
        nature: NaturePanne.rapport,
        id: 'er-1',
      ));
    });

    test('e-mail, uid et chemin users/ de l\'erreur absents du résultat', () {
      const uid = 'AbCdEfGhIjKlMnOpQrStUvWxYz12';
      final b = brouillonDepuisRapport(
        _rapport(
          error:
              'FirebaseException: brasseur@exemple.fr users/$uid/prices refusé '
              'pour $uid',
          stackTrace:
              '#0 a (package:kass_beer/a.dart:1:1)\n'
              '#1 brasseur@exemple.fr (package:kass_beer/b.dart:1:1)\n'
              '#2 users/x (package:kass_beer/c.dart:1:1)\n'
              '#3 $uid (package:kass_beer/d.dart:1:1)',
        ),
      );
      for (final texte in [b.title, b.description]) {
        expect(texte, isNot(contains('@')));
        expect(texte, isNot(contains('users/')));
        expect(texte, isNot(contains(uid)));
        expect(texte, isNot(contains('refusé')));
        expect(texte, isNot(contains('prices')));
      }
      expect(b.title, 'Erreur recipes.watch : FirebaseException');
      expect(b.description, contains('package:kass_beer/a.dart'));
      expect(b.description, isNot(contains('package:kass_beer/b.dart')));
    });

    test('type : nom de classe en Exception ou Error seulement', () {
      expect(typeException('StateError: x'), 'StateError');
      expect(typeException('FirebaseException: x'), 'FirebaseException');
      expect(typeException('FormatException: x'), 'FormatException');
      expect(typeException('Error: x'), 'Error');
      expect(typeException('PrixDeJean: 12,50'), isNull);
      expect(typeException('Dupont: x'), isNull);
      expect(typeException('TimeoutException after 0:00:30: x'), isNull);
    });

    test('pile : trame Dart exacte seulement, aucun texte libre', () {
      final lignes = lignesPileApplication(
        '#0      main (package:kass_beer/main.dart:10:3)\n'
        '#1      f (package:kass_beer/a.dart:1:1) Jean Dupont 12,50 €\n'
        'package:kass_beer/b.dart 12:3  Jean Dupont 12,50 €\n'
        '#2      Jean Dupont 12,50 € (package:kass_beer/c.dart:1:1)\n'
        '#4      Jean Dupont habite Lyon (package:kass_beer/d.dart:1:1)\n'
        '#3      _State.build.<anonymous closure> '
        '(package:kass_beer/features/x/y.dart:4:9)',
      );
      expect(lignes, [
        '#0      main (package:kass_beer/main.dart:10:3)',
        '#3      _State.build.<anonymous closure> '
            '(package:kass_beer/features/x/y.dart:4:9)',
      ]);
      expect(lignes.join(), isNot(contains('€')));
    });

    test('pile : 15 lignes au plus, celles du code de l\'application', () {
      final pile = [
        for (var i = 0; i < 20; i++) ...[
          '#$i f$i (package:kass_beer/f$i.dart:1:1)',
          '#$i g (package:flutter/src/g.dart:1:1)',
        ],
      ].join('\n');
      final lignes = lignesPileApplication(pile);
      expect(lignes, hasLength(kLignesPileMax));
      expect(lignes.first, contains('f0.dart'));
      expect(lignes.last, contains('f14.dart'));
      expect(lignes.every((l) => l.contains('package:kass_beer/')), isTrue);
    });

    test('bornes : titre d\'une ligne de 5 à 100, description de 10 à 2 000, '
        'pile retirée par la fin', () {
      final nom = 'a' * 100;
      final chemin = 'b' * 120;
      final b = brouillonDepuisRapport(
        _rapport(
          feature: 'a${'b' * 59}',
          error: 'TresLongue${'E' * 40}Exception: x',
          stackTrace: [
            for (var i = 0; i < 15; i++)
              '#$i $nom (package:kass_beer/f$i/$chemin.dart:1:1)',
          ].join('\n'),
        ),
      );
      expect(b.title.length, inInclusiveRange(5, kTicketTitleMaxLength));
      expect(b.title, isNot(contains('\n')));
      expect(
        b.description.trim().length,
        inInclusiveRange(10, kTicketDescriptionMaxLength),
      );
      expect(b.description.length, lessThanOrEqualTo(2000));
      expect(b.description, contains('package:kass_beer/f0/'));
      expect(b.description, isNot(contains('package:kass_beer/f14/')));
    });

    test(
      'sans type ni fonctionnalité ni pile : titre et phrase par défaut',
      () {
        final b = brouillonDepuisRapport(
          _rapport(error: 'Bad state: x', feature: null, stackTrace: null),
        );
        expect(b.title, kTitreRapportParDefaut);
        expect(b.description, contains(kPileNonPubliee));
        expect(b.description, isNot(contains('Type :')));
        expect(typeException('Exception: boom'), 'Exception');
        expect(typeException('[cloud_firestore/unavailable] x'), isNull);
      },
    );
  });

  group('brouillon depuis une entrée de journal', () {
    test('insertId, fonction, gravité, heure ; ni message ni données', () {
      final b = brouillonDepuisJournal(_entree());
      expect(b.title, 'Erreur dans synctickets');
      expect(b.type, TicketType.bug);
      expect(b.screen, 'inconnu');
      final lignes = b.description.split('\n');
      expect(
        lignes.first,
        'Entrée de journal : ins-1 (ne pas modifier : sert à marquer '
        'l\'entrée)',
      );
      expect(b.description, contains('Créé depuis Admin › Journaux.'));
      expect(b.description, contains('Fonction : synctickets'));
      expect(b.description, contains('Gravité : ERROR'));
      expect(b.description, contains('Heure : 14 nov. 10:30:05'));
      expect(b.description, isNot(contains('Échec')));
      expect(b.description, isNot(contains('@')));
      expect(b.description, isNot(contains('uid')));
      expect(clePanneDeDescription(b.description), (
        nature: NaturePanne.journal,
        id: 'ins-1',
      ));
    });
  });

  group('marque dérivée', () {
    test('identifiant lu sur la première ligne seule', () {
      expect(clePanneDeDescription('Rapport : R1 (ne pas modifier…)\nx'), (
        nature: NaturePanne.rapport,
        id: 'R1',
      ));
      expect(clePanneDeDescription('Le rapport : R1'), isNull);
      expect(clePanneDeDescription('x\nRapport : R1'), isNull);
      expect(clePanneDeDescription('Rapport : '), isNull);
    });

    test('index : le plus récent, le nombre, les libellés', () {
      final index = indexTicketsParPanne([
        _ticketDe('a', cle: 'Rapport : R1', issueNumber: 3),
        _ticketDe(
          'b',
          cle: 'Rapport : R1',
          issueNumber: 7,
          createdAt: DateTime(2026, 11, 15, 9),
        ),
        _ticketDe('c', cle: 'Rapport : R2'),
        unTicket(id: 'd'),
      ]);
      expect(index, hasLength(2));
      final r1 = index[(nature: NaturePanne.rapport, id: 'R1')]!;
      expect(r1.recent.id, 'b');
      expect(r1.nombre, 2);
      expect(r1.libelle, 'Ticket #7 créé le 15 novembre 2026 (2 tickets)');
      expect(
        index[(nature: NaturePanne.rapport, id: 'R2')]!.libelle,
        'Ticket créé, non publié',
      );
    });
  });

  group('Admin › Rapports d\'erreur : Analyser', () {
    testWidgets('bouton de 48 px, formulaire prérempli, case cochée', (
      tester,
    ) async {
      await _ouvrirRapports(tester);
      await _deplier(tester);
      final bouton = find.ancestor(
        of: find.text(TextesAnalyser.analyser),
        matching: find.byType(OutlinedButton),
      );
      final copier = find.ancestor(
        of: find.text('Copier le rapport'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.getSize(bouton).height, tester.getSize(copier).height);
      expect(tester.getSize(bouton).height, greaterThanOrEqualTo(48));
      await _appuyerAnalyser(tester);
      expect(find.byType(TicketFormScreen), findsOneWidget);
      expect(find.text('Erreur recipes.watch : StateError'), findsOneWidget);
      expect(
        find.textContaining('Rapport : er-1 (ne pas modifier'),
        findsOneWidget,
      );
      final caseLancement = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, TicketFormScreen.lancerAnalyse),
      );
      expect(caseLancement.value, isTrue);
      expect(caseLancement.onChanged, isNotNull);
      final radio = tester.widget<RadioGroup<TicketType>>(
        find.byType(RadioGroup<TicketType>),
      );
      expect(radio.groupValue, TicketType.bug);
    });

    testWidgets('marque sur R1 seul, appui vers la fiche du ticket', (
      tester,
    ) async {
      await _ouvrirRapports(
        tester,
        rapports: [
          _rapport(id: 'R1'),
          _rapport(id: 'R2', error: 'StateError: autre panne'),
        ],
        tickets: [_ticketDe('t1', cle: 'Rapport : R1', issueNumber: 12)],
      );
      expect(find.text('Ticket #12 créé le 14 novembre 2026'), findsOneWidget);
      await tester.tap(find.text('Ticket #12 créé le 14 novembre 2026'));
      await _pumpFiche(tester);
      expect(find.byType(AdminTicketScreen), findsOneWidget);
    });

    testWidgets('ticket existant : boîte avant un second ticket', (
      tester,
    ) async {
      await _ouvrirRapports(
        tester,
        tickets: [_ticketDe('t1', cle: 'Rapport : er-1', issueNumber: 12)],
      );
      await _analyser(tester);
      expect(
        find.text(
          'Un ticket existe déjà pour ce rapport (#12). Créer un second '
          'ticket ?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.byType(TicketFormScreen), findsNothing);
      await _appuyerAnalyser(tester);
      await tester.tap(find.text(TextesAnalyser.creerSecond));
      await tester.pumpAndSettle();
      expect(find.byType(TicketFormScreen), findsOneWidget);
    });

    testWidgets('case cochée : boîte, rien d\'écrit avant « Envoyer et '
        'lancer », un seul lancement', (tester) async {
      final app = await _ouvrirRapports(tester);
      await _analyser(tester);
      await _envoyer(tester);
      expect(find.byType(BoiteEnvoiAnalyse), findsOneWidget);
      expect(find.text(BoiteEnvoiAnalyse.effet), findsOneWidget);
      expect(find.text('Lancements restants : inconnu.'), findsOneWidget);
      expect(app.tickets.created, isEmpty);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(app.tickets.created, isEmpty);
      expect(find.byType(TicketFormScreen), findsOneWidget);

      await _envoyer(tester);
      await tester.tap(find.text(BoiteEnvoiAnalyse.envoyer));
      await tester.pump();
      expect(app.tickets.created, hasLength(1));
      final cree = app.tickets.created.single;
      expect(cree.brouillon.description, startsWith('Rapport : er-1'));
      expect(find.text(BoiteEnvoiAnalyse.publication), findsWidgets);
      expect(app.tickets.launches, isEmpty);

      final server = Completer<ResultatLancement>();
      app.tickets.launchResult = () => server.future;
      app.tickets.publishAll([
        unTicket(id: cree.id, status: TicketStatus.pending),
      ]);
      await tester.pump();
      expect(app.tickets.launches, isEmpty);
      final publie = unTicket(
        id: cree.id,
        issueNumber: 40,
        canLaunchAnalysis: true,
      );
      app.tickets.publishAll([publie]);
      await tester.pump();
      app.tickets.publishAll([publie]);
      await tester.pump();
      expect(app.tickets.launches, [
        (ticketId: cree.id, action: ActionLancement.analyse),
      ]);
      expect(find.text(BoiteEnvoiAnalyse.lancement), findsWidgets);
      server.complete(const ResultatLancement(IssueLancement.lance));
      await tester.pumpAndSettle();
      expect(
        find.text(const ResultatLancement(IssueLancement.lance).message),
        findsOneWidget,
      );
      await tester.tap(find.text(BoiteEnvoiAnalyse.voir));
      await _pumpFiche(tester);
      expect(find.byType(AdminTicketScreen), findsOneWidget);
      expect(app.tickets.launches, hasLength(1));
    });

    testWidgets('quota d\'envoi dépassé : aucun lancement, la boîte le dit', (
      tester,
    ) async {
      final app = await _ouvrirRapports(tester);
      await _analyser(tester);
      await _envoyer(tester);
      await tester.tap(find.text(BoiteEnvoiAnalyse.envoyer));
      await tester.pump();
      final id = app.tickets.created.single.id;
      app.tickets.publishAll([
        unTicket(id: id, status: TicketStatus.overQuota),
      ]);
      await tester.pumpAndSettle();
      expect(app.tickets.launches, isEmpty);
      expect(find.text(BoiteEnvoiAnalyse.nonLance), findsOneWidget);
      expect(find.text(BoiteEnvoiAnalyse.voir), findsOneWidget);
    });

    testWidgets('sans publication en 2 minutes : aucun lancement', (
      tester,
    ) async {
      final app = await _ouvrirRapports(tester);
      await _analyser(tester);
      await _envoyer(tester);
      await tester.tap(find.text(BoiteEnvoiAnalyse.envoyer));
      await tester.pump();
      await tester.pump(BoiteEnvoiAnalyse.delaiPublication);
      await tester.pump();
      expect(find.text(BoiteEnvoiAnalyse.nonLance), findsOneWidget);
      final id = app.tickets.created.single.id;
      app.tickets.publishAll([
        unTicket(id: id, issueNumber: 40, canLaunchAnalysis: true),
      ]);
      await tester.pumpAndSettle();
      expect(app.tickets.launches, isEmpty);
    });

    testWidgets('boîte fermée avant la publication : message, aucun '
        'lancement', (tester) async {
      final app = await _ouvrirRapports(tester);
      await _analyser(tester);
      await _envoyer(tester);
      await tester.tap(find.text(BoiteEnvoiAnalyse.envoyer));
      await tester.pump();
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.byType(BoiteEnvoiAnalyse), findsNothing);
      expect(find.byType(TicketFormScreen), findsNothing);
      expect(find.text(BoiteEnvoiAnalyse.nonLance), findsOneWidget);
      final id = app.tickets.created.single.id;
      app.tickets.publishAll([
        unTicket(id: id, issueNumber: 40, canLaunchAnalysis: true),
      ]);
      await tester.pumpAndSettle();
      expect(app.tickets.launches, isEmpty);
    });

    testWidgets('plafond atteint : « Envoyer sans lancer », aucun lancement', (
      tester,
    ) async {
      final app = TestApp();
      app.errorReports.rapports.add(_rapport());
      app.tickets.publishAll(const []);
      app.tickets.launchStatus.add(
        const DocumentTrouve(
          EtatLancements(day: '20261121', countDay: 10, perDay: 10),
        ),
      );
      await app.pump(tester);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.adminErrorReports);
      await tester.pumpAndSettle();
      await _analyser(tester);
      await _envoyer(tester);
      expect(find.text(BoiteEnvoiAnalyse.plafond), findsOneWidget);
      expect(find.text(BoiteEnvoiAnalyse.envoyer), findsNothing);
      await tester.tap(find.text(BoiteEnvoiAnalyse.envoyerSansLancer));
      await tester.pumpAndSettle();
      expect(app.tickets.created, hasLength(1));
      expect(find.byType(BoiteEnvoiAnalyse), findsNothing);
      expect(find.text(BoiteEnvoiAnalyse.nonLance), findsOneWidget);
      final id = app.tickets.created.single.id;
      app.tickets.publishAll([
        unTicket(id: id, issueNumber: 40, canLaunchAnalysis: true),
      ]);
      await tester.pumpAndSettle();
      expect(app.tickets.launches, isEmpty);
    });

    testWidgets('lancement refusé : « Ticket envoyé. » et le motif', (
      tester,
    ) async {
      final app = await _ouvrirRapports(tester);
      app.tickets.launchResult = () async => const ResultatLancement(
        IssueLancement.refuse,
        motif: 'Plafond atteint.',
      );
      await _analyser(tester);
      await _envoyer(tester);
      await tester.tap(find.text(BoiteEnvoiAnalyse.envoyer));
      await tester.pump();
      expect(find.text(BoiteEnvoiAnalyse.titreEnvoi), findsOneWidget);
      expect(
        find.text(BoiteEnvoiAnalyse.fermerAvantPublication),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final id = app.tickets.created.single.id;
      app.tickets.publishAll([
        unTicket(id: id, issueNumber: 40, canLaunchAnalysis: true),
      ]);
      await tester.pumpAndSettle();
      expect(find.text(BoiteEnvoiAnalyse.titreEnvoye), findsOneWidget);
      expect(find.text('Ticket envoyé. Plafond atteint.'), findsOneWidget);
      expect(app.tickets.launches, hasLength(1));
    });

    testWidgets('écriture refusée : la boîte le dit, le formulaire reste', (
      tester,
    ) async {
      final app = await _ouvrirRapports(tester);
      app.tickets.serverAnswer = () async => throw StateError('refus');
      await _analyser(tester);
      await _envoyer(tester);
      await tester.tap(find.text(BoiteEnvoiAnalyse.envoyer));
      await tester.pumpAndSettle();
      expect(find.text(BoiteEnvoiAnalyse.refuse), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.byType(TicketFormScreen), findsOneWidget);
      expect(app.tickets.launches, isEmpty);
    });

    testWidgets('marque : lecture unique, relue par Actualiser ; panne sans '
        'marque', (tester) async {
      final app = await _ouvrirRapports(
        tester,
        tickets: [_ticketDe('t1', cle: 'Rapport : er-1', issueNumber: 12)],
      );
      expect(app.tickets.readAllCount, 1);
      expect(find.textContaining('Ticket #12'), findsOneWidget);
      app.tickets.readAllError = StateError('lecture impossible');
      await tester.tap(find.byTooltip('Actualiser'));
      await tester.pumpAndSettle();
      expect(app.tickets.readAllCount, 2);
      expect(find.textContaining('Ticket #12'), findsNothing);
      expect(find.text('StateError: panne de lecture'), findsOneWidget);
    });

    testWidgets('case décochée : envoi ordinaire, sans boîte ni lancement', (
      tester,
    ) async {
      final app = await _ouvrirRapports(tester);
      await _analyser(tester);
      final caseLancement = find.text(TicketFormScreen.lancerAnalyse);
      await tester.ensureVisible(caseLancement);
      await tester.pumpAndSettle();
      await tester.tap(caseLancement);
      await tester.pumpAndSettle();
      await _envoyer(tester);
      expect(find.byType(BoiteEnvoiAnalyse), findsNothing);
      expect(app.tickets.created, hasLength(1));
      expect(find.text(TicketFormScreen.sentOnline), findsOneWidget);
      expect(app.tickets.launches, isEmpty);
    });

    testWidgets('hors ligne : case inactive, envoi ordinaire', (tester) async {
      final app = await _ouvrirRapports(tester, offline: true);
      await _analyser(tester);
      final caseLancement = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, TicketFormScreen.lancerAnalyse),
      );
      expect(caseLancement.onChanged, isNull);
      expect(find.text(TicketFormScreen.lancementHorsLigne), findsOneWidget);
      await _envoyer(tester);
      expect(find.byType(BoiteEnvoiAnalyse), findsNothing);
      expect(app.tickets.created, hasLength(1));
      expect(app.tickets.launches, isEmpty);
    });

    testWidgets('formulaire ordinaire : aucune case de lancement', (
      tester,
    ) async {
      final app = await _ouvrirRapports(tester);
      unawaited(app.container.read(routerProvider).push(AppRoutes.newTicket));
      await tester.pumpAndSettle();
      expect(find.byType(TicketFormScreen), findsOneWidget);
      expect(find.text(TicketFormScreen.lancerAnalyse), findsNothing);
    });
  });

  group('Admin › Journaux : Analyser', () {
    Future<TestApp> ouvrir(WidgetTester tester, List<Ticket> tickets) async {
      final app = TestApp();
      app.logs.reponses.add(
        PageJournaux(
          entrees: [
            _entree(),
            _entree(insertId: 'ins-2'),
          ],
          suite: null,
          fonctions: const ['synctickets'],
        ),
      );
      app.tickets.publishAll(tickets);
      await app.pump(tester);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.adminLogs);
      await tester.pumpAndSettle();
      await tester.tap(find.text(LogsScreen.rechercher));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('marque sur l\'entrée du ticket, formulaire prérempli', (
      tester,
    ) async {
      await ouvrir(tester, [
        unTicket(
          id: 't9',
          description:
              'Entrée de journal : ins-1 (ne pas modifier : sert à marquer '
              'l\'entrée)\nx',
          issueNumber: 9,
          createdAt: DateTime(2026, 11, 14, 11),
        ),
      ]);
      final marque = find.text('Ticket #9 créé le 14 novembre 2026');
      await tester.scrollUntilVisible(marque, 300);
      expect(marque, findsOneWidget);
      final titre = find.text('Échec pour brasseur@exemple.fr').first;
      await tester.ensureVisible(titre);
      await tester.tap(titre);
      await tester.pumpAndSettle();
      final bouton = find.text(TextesAnalyser.analyser);
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Un ticket existe déjà pour cette entrée (#9). Créer un second '
          'ticket ?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(TextesAnalyser.creerSecond));
      await tester.pumpAndSettle();
      expect(find.byType(TicketFormScreen), findsOneWidget);
      expect(find.text('Erreur dans synctickets'), findsOneWidget);
      expect(find.textContaining('Entrée de journal : ins-'), findsOneWidget);
      expect(find.textContaining('brasseur@exemple.fr'), findsNothing);
    });
  });
}
