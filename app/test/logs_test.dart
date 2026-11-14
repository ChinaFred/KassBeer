import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/bandeau_liste_perimee.dart';
import 'package:kass_beer/core/presentation/etats.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/admin/data/logs_repository.dart';
import 'package:kass_beer/features/admin/domain/log_entry.dart';
import 'package:kass_beer/features/admin/presentation/error_reports_screen.dart';
import 'package:kass_beer/features/admin/presentation/logs_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';
import 'package:kass_beer/features/tickets/data/tickets_repository.dart'
    show AppelCallable;

import 'support/fakes.dart';

const _fonctions = ['publishTicket', 'syncTickets', 'queryLogs'];

EntreeJournal _entree(
  int n, {
  String severity = 'ERROR',
  String payload = '{\n  "feature": "tickets"\n}',
  bool coupe = false,
}) => EntreeJournal(
  horodatage: DateTime(2026, 11, 14, 10, 30, n % 60),
  severity: severity,
  fonction: 'synctickets',
  message: 'Tickets : tâche horaire en échec $n\nsuite',
  insertId: 'id-$n',
  payload: payload,
  payloadCoupe: coupe,
  caracteresGardes: 8000,
);

PageJournaux _page(List<EntreeJournal> entrees, {String? suite}) =>
    PageJournaux(entrees: entrees, suite: suite, fonctions: _fonctions);

/// Page lue comme la réponse du serveur, avec [maxChars] et des entrées
/// coupées.
PageJournaux _pageServeur({required int maxChars}) => PageJournaux.depuis({
  'entries': [
    {
      'timestamp': '2026-11-14T10:30:05.123Z',
      'severity': 'ERROR',
      'functionName': 'synctickets',
      'message': 'Message coupé',
      'insertId': 'i1',
      'payload': '{"a": 1}',
      'payloadTruncated': true,
      'messageTruncated': true,
    },
  ],
  'nextPageToken': null,
  'functions': _fonctions,
  'maxChars': maxChars,
});

Future<TestApp> _ouvrir(
  WidgetTester tester, {
  List<Object> reponses = const [],
  double width = 400,
}) async {
  final app = TestApp();
  app.logs.reponses.addAll(reponses);
  await app.pump(tester, width: width);
  app.signIn(adminUser, member: adminMember);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(AppRoutes.adminLogs);
  await tester.pumpAndSettle();
  return app;
}

/// Fait défiler la liste de l'écran (filtres compris) jusqu'à [cible].
Future<void> _voir(
  WidgetTester tester,
  Finder cible, {
  double pas = 200,
  bool attendre = true,
}) async {
  final liste = find
      .descendant(
        of: find.byType(LogsScreen),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(cible, pas, scrollable: liste);
  // Pendant un appel, l'indicateur tourne sans fin : une image suffit.
  attendre ? await tester.pumpAndSettle() : await tester.pump();
}

Future<void> _rechercher(WidgetTester tester) async {
  final bouton = find.text(LogsScreen.rechercher);
  await _voir(tester, bouton);
  await tester.tap(bouton);
  await tester.pumpAndSettle();
}

void main() {
  group('Domaine des journaux', () {
    test('filtres : arguments, résumé, égalité au ticket près des espaces', () {
      const defaut = FiltresJournaux();
      expect(defaut.versArguments(), {'severity': 'INFO', 'periodMinutes': 60});
      expect(defaut.resume, 'Info et plus · 1 h · Toutes les fonctions');
      final f = defaut.copyWith(
        gravite: FiltreGravite.debogageSeul,
        periode: FiltrePeriode.septJours,
        fonction: () => 'syncTickets',
        ticket: ' T1 ',
        texte: 'échec',
      );
      expect(f.versArguments(), {
        'severity': 'DEBUG',
        'periodMinutes': 10080,
        'functionName': 'syncTickets',
        'ticketId': 'T1',
        'freeText': 'échec',
      });
      expect(f, f.copyWith(ticket: 'T1'));
      expect(f.copyWith(fonction: () => null).fonction, isNull);
      expect(f == defaut, isFalse);
    });

    test('page : lecture, suite vide = fin, forme fausse refusée', () {
      final page = PageJournaux.depuis({
        'entries': [
          {
            'timestamp': '2026-11-14T10:30:05.123Z',
            'severity': 'WARNING',
            'functionName': 'synctickets',
            'message': 'm',
            'insertId': 'i',
            'payload': '',
            'payloadTruncated': false,
            'messageTruncated': true,
          },
        ],
        'nextPageToken': '',
        'functions': _fonctions,
        'maxChars': 8000,
      });
      expect(page.suite, isNull);
      expect(page.fonctions, _fonctions);
      final e = page.entrees.single;
      expect(e.gravite, GraviteJournal.avertissement);
      expect(
        e.horodatage,
        DateTime.utc(2026, 11, 14, 10, 30, 5, 123).toLocal(),
      );
      expect(e.caracteresGardes, 8000);
      expect(e.messageCoupe, isTrue);
      expect(e.payloadCoupe, isFalse);
      expect(() => PageJournaux.depuis({'entries': []}), throwsFormatException);
      expect(
        () => PageJournaux.depuis({'entries': [], 'functions': []}),
        throwsFormatException,
        reason: 'maxChars absent',
      );
      expect(
        () => PageJournaux.depuis({
          'entries': [
            {'message': 'm'},
          ],
          'functions': [],
          'maxChars': 8000,
        }),
        throwsFormatException,
      );
    });

    test('titre : première ligne ; message entier en chasse fixe s\'il en a '
        'plusieurs', () {
      final e = _entree(1);
      expect(e.titre, 'Tickets : tâche horaire en échec 1');
      expect(e.messageComplet, 'Tickets : tâche horaire en échec 1\nsuite');
      expect(e.messageMultiligne, isTrue);
      expect(LogsScreen.texteCoupe(8000), contains('8'));
      expect(LogsScreen.texteCoupe(8000), endsWith('000 caractères.'));
    });

    test('gravités : familles de Cloud Logging', () {
      expect(GraviteJournal.depuis('CRITICAL'), GraviteJournal.erreur);
      expect(GraviteJournal.depuis('NOTICE'), GraviteJournal.information);
      expect(GraviteJournal.depuis('DEFAULT'), GraviteJournal.autre);
    });

    test('échecs : code et motif du serveur', () {
      CauseEchecJournaux cause(String code, [Object? details]) =>
          EchecJournaux.depuis(code: code, details: details).cause;
      expect(cause('resource-exhausted'), CauseEchecJournaux.quota);
      expect(
        cause('failed-precondition', {'reason': 'iam'}),
        CauseEchecJournaux.iam,
      );
      expect(
        cause('failed-precondition', {'reason': 'emulator'}),
        CauseEchecJournaux.emulateur,
      );
      expect(cause('permission-denied'), CauseEchecJournaux.acces);
      expect(cause('unauthenticated'), CauseEchecJournaux.acces);
      expect(
        cause('unavailable', {'reason': 'logging_unavailable'}),
        CauseEchecJournaux.indisponible,
      );
      expect(cause('unavailable'), CauseEchecJournaux.horsLigne);
      expect(cause('deadline-exceeded'), CauseEchecJournaux.indisponible);
      expect(cause('internal'), CauseEchecJournaux.indisponible);
      expect(
        cause('invalid-argument', {'field': 'pageToken'}),
        CauseEchecJournaux.refuse,
      );
      // Seul `pageToken` relance la première page ; un autre champ refusé
      // n'a pas de « Réessayer ».
      expect(cause('invalid-argument'), CauseEchecJournaux.rejete);
      expect(
        cause('invalid-argument', {'field': 'severity'}),
        CauseEchecJournaux.rejete,
      );
      expect(CauseEchecJournaux.rejete.reessayable, isFalse);
      expect(
        CauseEchecJournaux.rejete.message,
        'Recherche refusée par le serveur.',
      );
      final champ = EchecJournaux.depuis(
        code: 'invalid-argument',
        details: {'field': 'freeText', 'reason': 'x'},
        message: 'Message du serveur.',
      );
      expect(champ.cause, CauseEchecJournaux.champ);
      expect(champ.champ, 'freeText');
      expect(champ.motif, 'Message du serveur.');
      expect(CauseEchecJournaux.iam.reessayable, isFalse);
      expect(CauseEchecJournaux.emulateur.reessayable, isFalse);
      expect(CauseEchecJournaux.quota.reessayable, isTrue);
    });
  });

  group('FunctionsLogsRepository', () {
    late RecordingErrorReportService errors;
    setUp(() => errors = RecordingErrorReportService());

    test('appel : arguments, page suivante, réponse lue', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repo = FunctionsLogsRepository(
        errorReportService: errors,
        callable: (name, data) async {
          calls.add((name, data));
          return {
            'entries': [],
            'nextPageToken': 'tok',
            'functions': _fonctions,
            'maxChars': 8000,
          };
        },
      );
      final page = await repo.rechercher(
        const FiltresJournaux(texte: 'x'),
        suite: 'prec',
      );
      expect(page.suite, 'tok');
      expect(calls.single.$1, 'queryLogs');
      expect(calls.single.$2, {
        'severity': 'INFO',
        'periodMinutes': 60,
        'freeText': 'x',
        'pageToken': 'prec',
      });
      expect(errors.reports, isEmpty);
    });

    test(
      'refus du serveur : échec levé, rapporté sans le texte cherché',
      () async {
        final repo = FunctionsLogsRepository(
          errorReportService: errors,
          callable: (name, data) async => throw FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'Texte de 1 à 100 caractères, sans saut de ligne.',
            details: {'field': 'freeText', 'reason': 'x'},
          ),
        );
        await expectLater(
          repo.rechercher(const FiltresJournaux(texte: 'secret-cherché')),
          throwsA(
            isA<EchecJournaux>()
                .having((e) => e.cause, 'cause', CauseEchecJournaux.champ)
                .having((e) => e.champ, 'champ', 'freeText')
                .having(
                  (e) => e.motif,
                  'motif',
                  'Texte de 1 à 100 caractères, sans saut de ligne.',
                ),
          ),
        );
        final report = errors.reports.single;
        expect(report.feature, 'admin.logs');
        expect(report.context, contains('code=invalid-argument'));
        expect(report.context, contains('field=freeText'));
        expect(report.context, isNot(contains('secret')));
      },
    );

    test(
      'réponse illisible ou erreur inconnue : indisponible, rapportée',
      () async {
        for (final callable in <AppelCallable>[
          (name, data) async => {'entries': 'non'},
          (name, data) async => throw StateError('panne'),
        ]) {
          final repo = FunctionsLogsRepository(
            errorReportService: errors,
            callable: callable,
          );
          await expectLater(
            repo.rechercher(const FiltresJournaux()),
            throwsA(
              isA<EchecJournaux>().having(
                (e) => e.cause,
                'cause',
                CauseEchecJournaux.indisponible,
              ),
            ),
          );
        }
        expect(errors.reports, hasLength(2));
      },
    );
  });

  group('Admin › Journaux', () {
    testWidgets('tuile après « Rapports d\'erreur », ouverture sans appel', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.admin);
      await tester.pumpAndSettle();
      final rapports = tester.getTopLeft(find.text(ErrorReportsScreen.titre));
      final journaux = tester.getTopLeft(find.text(LogsScreen.titre));
      expect(journaux.dy, greaterThan(rapports.dy));
      expect(find.text(LogsScreen.sousTitre), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
      await tester.tap(find.text(LogsScreen.titre));
      await tester.pumpAndSettle();
      await _voir(tester, find.text(LogsScreen.invite));
      expect(find.text(LogsScreen.invite), findsOneWidget);
      expect(find.text(LogsScreen.aideFonctions), findsOneWidget);
      expect(find.text(LogsScreen.noteEmails), findsOneWidget);
      expect(app.logs.demandes, isEmpty);
    });

    testWidgets('un brasseur n\'ouvre pas l\'écran', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.adminLogs);
      await tester.pumpAndSettle();
      expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
      expect(app.logs.demandes, isEmpty);
    });

    testWidgets('une frappe ne lance rien ; Rechercher : liste, compte, fin', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        reponses: [
          _page([_entree(1), _entree(2, severity: 'INFO')]),
        ],
      );
      await tester.enterText(
        find.widgetWithText(TextField, LogsScreen.texte),
        'échec',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(app.logs.demandes, isEmpty);

      await _rechercher(tester);
      expect(app.logs.demandes.single.filtres.texte, 'échec');
      expect(app.logs.demandes.single.suite, isNull);
      expect(find.text(LogsScreen.compte(2)), findsOneWidget);
      expect(find.text(LogsScreen.fin), findsOneWidget);
      // Téléphone : filtres repliés en une ligne.
      expect(
        find.text('Info et plus · 1 h · Toutes les fonctions · « échec »'),
        findsOneWidget,
      );
      expect(find.text(LogsScreen.modifierFiltres), findsOneWidget);
      expect(find.text(LogsScreen.rechercher), findsNothing);
      expect(find.text('14 nov. 10:30:01 · synctickets'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Erreur')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Information')), findsOneWidget);
      expect(find.text('Charger la suite'), findsNothing);
    });

    testWidgets('menu des fonctions tiré de la réponse du serveur', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        reponses: [
          _page([_entree(1)]),
          _page([_entree(2)]),
        ],
      );
      await _rechercher(tester);
      await tester.tap(find.text(LogsScreen.modifierFiltres));
      await tester.pumpAndSettle();
      expect(find.text(LogsScreen.aideFonctions), findsNothing);
      await tester.tap(find.byType(DropdownMenu<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('syncTickets').last);
      await tester.pumpAndSettle();
      await _voir(tester, find.text(LogsScreen.filtresModifies));
      expect(find.text(LogsScreen.filtresModifies), findsOneWidget);
      await _rechercher(tester);
      expect(app.logs.demandes.last.filtres.fonction, 'syncTickets');
      expect(find.text(LogsScreen.filtresModifies), findsNothing);
    });

    testWidgets('filtre changé : liste gardée, ligne affichée, suite masquée', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        reponses: [
          _page([_entree(1)], suite: 'tok'),
          _page([_entree(2)]),
        ],
      );
      await _rechercher(tester);
      expect(find.text(LogsScreen.chargerSuite), findsOneWidget);
      await tester.tap(find.text(LogsScreen.modifierFiltres));
      await tester.pumpAndSettle();
      await tester.tap(find.text('24 h'));
      await tester.pumpAndSettle();
      await _voir(tester, find.text(LogsScreen.filtresModifies));
      expect(find.text(LogsScreen.filtresModifies), findsOneWidget);
      expect(find.text(LogsScreen.compte(1)), findsOneWidget);
      expect(find.text(LogsScreen.chargerSuite), findsNothing);
      // Revenir aux filtres de la liste efface la ligne.
      await _voir(tester, find.text('1 h'), pas: -200);
      await tester.tap(find.text('1 h'));
      await tester.pumpAndSettle();
      expect(find.text(LogsScreen.filtresModifies), findsNothing);
      await _voir(tester, find.text(LogsScreen.chargerSuite));
      await tester.tap(find.text(LogsScreen.chargerSuite));
      await tester.pumpAndSettle();
      expect(app.logs.demandes.last.suite, 'tok');
      expect(app.logs.demandes.last.filtres, const FiltresJournaux());
      expect(find.text(LogsScreen.compte(2)), findsOneWidget);
      await _voir(tester, find.text(LogsScreen.fin));
      expect(find.text(LogsScreen.fin), findsOneWidget);
    });

    testWidgets('aucune entrée : état vide', (tester) async {
      await _ouvrir(tester, reponses: [_page(const [])]);
      await _rechercher(tester);
      expect(find.text(LogsScreen.vide), findsOneWidget);
      expect(find.text(LogsScreen.compte(0)), findsOneWidget);
    });

    testWidgets('rôle IAM manquant : panne sans Réessayer', (tester) async {
      await _ouvrir(
        tester,
        reponses: [const EchecJournaux(CauseEchecJournaux.iam)],
      );
      await _rechercher(tester);
      expect(
        find.text('Lecture des journaux non autorisée : rôle IAM manquant.'),
        findsOneWidget,
      );
      expect(find.byType(EtatErreur), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('émulateur : panne sans Réessayer', (tester) async {
      await _ouvrir(
        tester,
        reponses: [const EchecJournaux(CauseEchecJournaux.emulateur)],
      );
      await _rechercher(tester);
      expect(
        find.text('Journaux non disponibles dans l\'émulateur.'),
        findsOneWidget,
      );
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('quota : Réessayer rejoue l\'appel, panne gardée jusqu\'à la '
        'réponse', (tester) async {
      final app = await _ouvrir(
        tester,
        reponses: [
          const EchecJournaux(CauseEchecJournaux.quota),
          _page([_entree(1)]),
        ],
      );
      await _rechercher(tester);
      const quota =
          'Quota de lecture des journaux atteint, réessayez dans une minute.';
      expect(find.text(quota), findsOneWidget);
      final attente = Completer<void>();
      app.logs.attente = attente;
      await _voir(tester, find.text('Réessayer'));
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      expect(find.text(quota), findsOneWidget);
      // Un seul indicateur, sur « Réessayer ».
      expect(
        find.descendant(
          of: find.byType(EtatErreur),
          matching: find.byType(IndicateurBouton),
        ),
        findsOneWidget,
      );
      expect(
        find.byType(IndicateurBouton, skipOffstage: false),
        findsOneWidget,
      );
      attente.complete();
      await tester.pumpAndSettle();
      expect(find.text(quota), findsNothing);
      expect(app.logs.demandes, hasLength(2));
      expect(app.logs.demandes.last.filtres, app.logs.demandes.first.filtres);
      expect(find.text(LogsScreen.compte(1)), findsOneWidget);
    });

    testWidgets('panne après une liste : bandeau au-dessus de la liste', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        reponses: [
          _page([_entree(1)], suite: 'tok'),
          const EchecJournaux(CauseEchecJournaux.horsLigne),
        ],
      );
      await _rechercher(tester);
      await _voir(tester, find.text(LogsScreen.chargerSuite));
      await tester.tap(find.text(LogsScreen.chargerSuite));
      await tester.pumpAndSettle();
      await _voir(tester, find.byType(BandeauListePerimee), pas: -200);
      expect(
        find.text('Hors ligne. La recherche des journaux demande le réseau.'),
        findsOneWidget,
      );
      expect(find.text(LogsScreen.compte(1)), findsOneWidget);
    });

    testWidgets('argument refusé : message sous le champ, focus', (
      tester,
    ) async {
      const motif = 'Identifiant refusé par le serveur.';
      const quota =
          'Quota de lecture des journaux atteint, réessayez dans une minute.';
      final app = await _ouvrir(
        tester,
        reponses: [
          const EchecJournaux(CauseEchecJournaux.quota),
          const EchecJournaux(
            CauseEchecJournaux.champ,
            champ: EchecJournaux.champTicket,
            motif: motif,
          ),
        ],
      );
      await _rechercher(tester);
      expect(find.text(quota), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, LogsScreen.ticket),
        'a b',
      );
      await _rechercher(tester);
      expect(find.text(motif), findsOneWidget);
      // L'ancienne panne ne reste pas à côté du refus de champ.
      expect(find.text(quota, skipOffstage: false), findsNothing);
      final champ = tester.widget<TextField>(
        find.widgetWithText(TextField, LogsScreen.ticket),
      );
      expect(champ.focusNode!.hasFocus, isTrue);
      expect(app.logs.demandes.last.filtres.ticket, 'a b');
    });

    testWidgets('entrée dépliée : message, données, texte coupé, copie', (
      tester,
    ) async {
      String? copie;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copie = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _ouvrir(
        tester,
        reponses: [
          _page([_entree(1, coupe: true)]),
        ],
      );
      await _rechercher(tester);
      expect(find.text(LogsScreen.texteCoupe(8000)), findsNothing);
      // Titre : première ligne seule.
      expect(find.text('Tickets : tâche horaire en échec 1'), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text(LogsScreen.donnees), findsOneWidget);
      expect(find.text(LogsScreen.texteCoupe(8000)), findsOneWidget);
      final message = tester.widget<SelectableText>(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              w.data == 'Tickets : tâche horaire en échec 1\nsuite',
        ),
      );
      expect(message.style?.fontFamily, 'monospace');
      await tester.ensureVisible(find.text(LogsScreen.copier));
      await tester.tap(find.text(LogsScreen.copier));
      await tester.pumpAndSettle();
      expect(find.text(LogsScreen.copie), findsOneWidget);
      expect(copie, contains('"feature": "tickets"'));
      expect(copie, contains('Tickets : tâche horaire en échec 1'));
    });

    testWidgets('Rechercher avec une liste : seul le bouton appuyé attend', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        reponses: [
          _page([_entree(1)], suite: 'tok'),
          _page([_entree(2)]),
        ],
      );
      await _rechercher(tester);
      await tester.tap(find.text(LogsScreen.modifierFiltres));
      await tester.pumpAndSettle();
      final attente = Completer<void>();
      app.logs.attente = attente;
      final bouton = find.text(LogsScreen.rechercher);
      await _voir(tester, bouton);
      await tester.tap(bouton);
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(IndicateurBouton),
        ),
        findsOneWidget,
      );
      await _voir(tester, find.text(LogsScreen.chargerSuite), attendre: false);
      final suite = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(LogsScreen.chargerSuite),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(suite.onPressed, isNull, reason: 'désactivé, sans indicateur');
      expect(
        find.byType(IndicateurBouton, skipOffstage: false),
        findsOneWidget,
      );
      attente.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('page suivante refusée : Réessayer relit la première page', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        reponses: [
          _page([_entree(1)], suite: 'tok'),
          const EchecJournaux(CauseEchecJournaux.refuse),
          _page([_entree(3)]),
        ],
      );
      await _rechercher(tester);
      await _voir(tester, find.text(LogsScreen.chargerSuite));
      await tester.tap(find.text(LogsScreen.chargerSuite));
      await tester.pumpAndSettle();
      expect(app.logs.demandes.last.suite, 'tok');
      await _voir(tester, find.byType(BandeauListePerimee), pas: -200);
      await tester.tap(
        find.descendant(
          of: find.byType(BandeauListePerimee),
          matching: find.text('Réessayer'),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.logs.demandes, hasLength(3));
      expect(app.logs.demandes.last.suite, isNull);
      expect(app.logs.demandes.last.filtres, const FiltresJournaux());
      expect(find.text(LogsScreen.compte(1)), findsOneWidget);
    });

    testWidgets('bandeau : « Recherche en cours » sur son bouton pendant la '
        'relance', (tester) async {
      final app = await _ouvrir(
        tester,
        reponses: [
          _page([_entree(1)], suite: 'tok'),
          const EchecJournaux(CauseEchecJournaux.indisponible),
          _page([_entree(2)]),
        ],
      );
      await _rechercher(tester);
      await _voir(tester, find.text(LogsScreen.chargerSuite));
      await tester.tap(find.text(LogsScreen.chargerSuite));
      await tester.pumpAndSettle();
      await _voir(tester, find.byType(BandeauListePerimee), pas: -200);
      final attente = Completer<void>();
      app.logs.attente = attente;
      await tester.tap(
        find.descendant(
          of: find.byType(BandeauListePerimee),
          matching: find.text('Réessayer'),
        ),
      );
      await tester.pump();
      final indicateur = tester.widget<IndicateurBouton>(
        find.descendant(
          of: find.byType(BandeauListePerimee),
          matching: find.byType(IndicateurBouton),
        ),
      );
      expect(indicateur.label, LogsScreen.rechercheEnCours);
      attente.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('autre argument refusé : panne sans « Réessayer »', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        reponses: [const EchecJournaux(CauseEchecJournaux.rejete)],
      );
      await _rechercher(tester);
      await _voir(tester, find.text('Recherche refusée par le serveur.'));
      expect(find.text('Recherche refusée par le serveur.'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('longueur gardée lue dans la réponse : 5 000, message et '
        'données', (tester) async {
      await _ouvrir(tester, reponses: [_pageServeur(maxChars: 5000)]);
      await _rechercher(tester);
      await tester.tap(find.text('Message coupé'));
      await tester.pumpAndSettle();
      expect(find.text(LogsScreen.texteCoupe(5000)), findsNWidgets(2));
      expect(LogsScreen.texteCoupe(5000), contains('5'));
      expect(LogsScreen.texteCoupe(5000), endsWith('000 caractères.'));
    });

    testWidgets('nouvelle recherche : une entrée au même rang est repliée', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        reponses: [
          _page([_entree(1)]),
          _page([_entree(1)]),
        ],
      );
      await _rechercher(tester);
      final titre = find.text('Tickets : tâche horaire en échec 1');
      await tester.tap(titre);
      await tester.pumpAndSettle();
      expect(find.text(LogsScreen.donnees), findsOneWidget);
      await tester.tap(find.text(LogsScreen.modifierFiltres));
      await tester.pumpAndSettle();
      await _rechercher(tester);
      expect(find.text(LogsScreen.compte(1)), findsOneWidget);
      expect(find.text(LogsScreen.donnees, skipOffstage: false), findsNothing);
    });

    testWidgets('entrée dépliée : reste dépliée après un défilement', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        reponses: [
          _page([for (var i = 1; i <= 30; i++) _entree(i)]),
        ],
      );
      await _rechercher(tester);
      final premiere = find.text('Tickets : tâche horaire en échec 1');
      await _voir(tester, premiere, pas: -200);
      await tester.tap(premiere);
      await tester.pumpAndSettle();
      expect(find.text(LogsScreen.donnees), findsOneWidget);
      await _voir(tester, find.text(LogsScreen.fin), pas: 400);
      expect(find.text(LogsScreen.donnees), findsNothing);
      await _voir(tester, find.text(LogsScreen.donnees), pas: -400);
      expect(find.text(LogsScreen.donnees), findsOneWidget);
    });

    testWidgets('large : filtres toujours dépliés, Rechercher à droite', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        width: 1300,
        reponses: [
          _page([_entree(1)]),
        ],
      );
      await _rechercher(tester);
      expect(find.text(LogsScreen.modifierFiltres), findsNothing);
      final bouton = tester.getRect(find.text(LogsScreen.rechercher));
      final texte = tester.getRect(
        find.widgetWithText(TextField, LogsScreen.texte),
      );
      expect(bouton.right, greaterThan(texte.right));
      final gravite = tester.getTopLeft(find.text(LogsScreen.gravite));
      final periode = tester.getTopLeft(find.text(LogsScreen.periode));
      expect(periode.dy, gravite.dy);
    });

    for (final width in [400.0, 1300.0]) {
      testWidgets('texte à 200 % sans débordement (${width.toInt()} px)', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _ouvrir(
          tester,
          width: width,
          reponses: [
            _page([_entree(1)]),
          ],
        );
        expect(tester.takeException(), isNull);
        await _rechercher(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(LogsScreen.compte(1)), findsOneWidget);
      });
    }
  });
}
