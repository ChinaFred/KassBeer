import 'dart:async';

import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/segments.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/ai/domain/reglages_ia.dart';
import 'package:kass_beer/features/library/domain/aromes_houblon.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/recipes/domain/assistant_recette.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/panneau_assistant.dart';

import 'support/ai_fakes.dart';
import 'support/fakes.dart';
import 'support/library_fixtures.dart';

/// Panneau Assistant de l'éditeur de recette (ADR-015, lot A1 ; P59, P60).
void main() {
  const reponse = ReponseAssistant(
    texte: '## Avis\n\nLa recette est **équilibrée**.',
    tour: 1,
    quota: (limite: 20, restants: 17, repriseLe: null),
  );

  Future<TestApp> ouvrir(
    WidgetTester tester, {
    bool admin = true,
    bool offline = false,
    double width = 400,
    void Function(TestApp app)? avant,
    String chemin = '/recettes/nouvelle',
  }) async {
    final app = TestApp();
    avant?.call(app);
    await app.pump(tester, width: width);
    if (admin) {
      app.signIn(adminUser, member: adminMember, fromCache: offline);
    } else {
      app.signIn(brewerUser, member: brewerMember, fromCache: offline);
    }
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go(chemin);
    await tester.pumpAndSettle();
    return app;
  }

  final icone = find.byTooltip(TextesAssistant.ouvrir);
  Finder envoyer() =>
      find.widgetWithText(FilledButton, TextesAssistant.envoyer);

  Future<void> ouvrirPanneau(WidgetTester tester) async {
    await tester.tap(icone);
    await tester.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester tester, String texte) async {
    await tester.enterText(
      find.widgetWithText(TextField, TextesAssistant.champ),
      texte,
    );
    await tester.pump();
  }

  group('accès (ADR-015, section 2)', () {
    testWidgets('admin : icône visible, aucun envoi à l\'ouverture', (
      tester,
    ) async {
      final app = await ouvrir(tester);
      expect(icone, findsOneWidget);
      await ouvrirPanneau(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(TextesAssistant.avertissement), findsOneWidget);
      expect(find.text(TextesAssistant.mentionAnthropic), findsOneWidget);
      expect(find.text(TextesAssistant.vide), findsOneWidget);
      // Politique absente : aucune constante de plafond (P60).
      expect(find.text(TextesAssistant.toursInconnus), findsOneWidget);
      expect(app.assistant.envois, isEmpty);
      // Politique relue à l'ouverture du panneau.
      expect(app.ai.lecturesPolitique, greaterThanOrEqualTo(2));
      expect(app.ai.lecturesQuotas, 1);
    });

    testWidgets('brasseur : icône absente tant que le poste est fermé', (
      tester,
    ) async {
      await ouvrir(tester, admin: false);
      expect(icone, findsNothing);
    });

    testWidgets('brasseur : icône visible quand le poste est ouvert', (
      tester,
    ) async {
      await ouvrir(
        tester,
        admin: false,
        avant: (app) =>
            app.ai.politique = politiqueLue(const ReglagePosteIaTest().ouvert),
      );
      expect(icone, findsOneWidget);
    });
  });

  group('un tour', () {
    testWidgets('raccourci : remplit le champ sans rien envoyer', (
      tester,
    ) async {
      final app = await ouvrir(tester);
      await ouvrirPanneau(tester);
      await tester.tap(find.text(TextesAssistant.analyser));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, TextesAssistant.champ),
            )
            .controller!
            .text,
        kRaccourciAnalyser,
      );
      expect(app.assistant.envois, isEmpty);
    });

    testWidgets('Envoyer : un appel, réponse en Markdown, tours restants', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        avant: (app) {
          app.ai.politique = politiqueLue(reglageAssistant);
          app.assistant.reponses.add(reponse);
        },
      );
      await ouvrirPanneau(tester);
      expect(
        find.text('Tours restants aujourd\'hui : 20 sur 20'),
        findsOneWidget,
      );
      await saisir(tester, 'Que penses-tu de ma recette ?');
      // Aucune frappe n'envoie (P60).
      expect(app.assistant.envois, isEmpty);
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      expect(app.assistant.envois, hasLength(1));
      final envoi = app.assistant.envois.single;
      expect(envoi['message'], 'Que penses-tu de ma recette ?');
      expect(envoi['history'], isEmpty);
      expect(envoi.containsKey('mode'), isFalse);
      expect(
        envoi.keys.toSet().difference({
          'conversationId',
          'history',
          'message',
          'summary',
          'recipe',
          'calculs',
          'equipment',
          'style',
          'aromas',
          'mode',
        }),
        isEmpty,
      );
      expect(find.textContaining('équilibrée'), findsOneWidget);
      expect(
        find.text('Tours restants aujourd\'hui : 17 sur 20'),
        findsOneWidget,
      );
      expect(find.byTooltip(TextesAssistant.copierReponse), findsOneWidget);
    });

    testWidgets('bouton inactif pendant l\'appel : un seul envoi', (
      tester,
    ) async {
      final app = await ouvrir(tester);
      final attente = Completer<void>();
      app.assistant
        ..attente = attente
        ..reponses.add(reponse);
      await ouvrirPanneau(tester);
      await saisir(tester, 'Question');
      await tester.tap(envoyer());
      await tester.pump();
      expect(find.text(TextesAssistant.redige), findsOneWidget);
      final bouton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(TextesAssistant.envoi),
          matching: find.byType(FilledButton),
        ),
      );
      expect(bouton.onPressed, isNull);
      attente.complete();
      await tester.pumpAndSettle();
      expect(app.assistant.envois, hasLength(1));
    });

    testWidgets('second tour : historique rejoué, même conversation', (
      tester,
    ) async {
      final app = await ouvrir(tester);
      app.assistant.reponses.addAll([reponse, reponse]);
      await ouvrirPanneau(tester);
      await saisir(tester, 'Un');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      await saisir(tester, 'Deux');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      final [premier, second] = app.assistant.envois;
      expect(second['conversationId'], premier['conversationId']);
      expect(second['history'], [
        {'role': 'user', 'text': 'Un'},
        {'role': 'assistant', 'text': reponse.texte},
      ]);
    });

    testWidgets('style et arômes de la Bibliothèque joints', (tester) async {
      final app = await ouvrir(
        tester,
        chemin: '/recettes/r1/modifier',
        avant: (app) {
          app.recipes.publish([
            Recipe(
              id: 'r1',
              ownerUid: adminUser.uid,
              content: const RecipeContent(
                name: 'Blonde',
                style: 'Blonde Ale',
                hops: [
                  HopLine(
                    name: 'Cascade',
                    amount: Quantite.grammes(20),
                    use: HopUse.boil,
                    form: 'pellet',
                    timeMin: 60,
                  ),
                ],
              ),
            ),
          ]);
          app.library.index[NatureReferentiel.styles] = const DocumentTrouve(
            IndexReferentiel(
              nature: NatureReferentiel.styles,
              entrees: [
                EntreeStyle(id: 'style-18a', name: 'Blonde Ale', code: '18A'),
              ],
            ),
          );
          app.library.fiches['style-18a'] = const DocumentTrouve(
            FicheStyle(
              id: 'style-18a',
              name: 'Blonde Ale',
              styleId: '18A',
              ibu: Plage(minimum: 15, maximum: 28),
            ),
          );
          app.library.index[NatureReferentiel.hops] = const DocumentTrouve(
            IndexReferentiel(
              nature: NatureReferentiel.hops,
              entrees: [EntreeHoublon(id: 'hop-cascade', name: 'Cascade')],
            ),
          );
          app.library.aromes['hop-cascade'] = DocumentTrouve(
            AromesHoublon.fromFirestore(hopAromaDoc()),
          );
          app.assistant.reponses.add(reponse);
        },
      );
      await ouvrirPanneau(tester);
      await saisir(tester, 'Avis ?');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      final envoi = app.assistant.envois.single;
      expect((envoi['style']! as Map)['code'], '18A');
      final aromes = envoi['aromas']! as List;
      expect((aromes.single as Map)['hop'], 'Cascade');
      expect((envoi['recipe']! as Map)['name'], 'Blonde');
    });
  });

  group('échecs', () {
    testWidgets('poste fermé : message, texte remis, Envoyer inactif', (
      tester,
    ) async {
      final app = await ouvrir(tester);
      app.assistant.reponses.add(
        const EchecAssistant(CauseEchecAssistant.posteFerme),
      );
      await ouvrirPanneau(tester);
      await saisir(tester, 'Question');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      expect(
        find.text(
          TextesAssistant.echec(
            const EchecAssistant(CauseEchecAssistant.posteFerme),
            admin: true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Question'), findsOneWidget);
      expect(tester.widget<FilledButton>(envoyer()).onPressed, isNull);
    });

    testWidgets('réglages absents : message d\'ADR-016', (tester) async {
      final app = await ouvrir(tester);
      app.assistant.reponses.add(
        const EchecAssistant(CauseEchecAssistant.reglagesAbsents),
      );
      await ouvrirPanneau(tester);
      await saisir(tester, 'Question');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Assistant indisponible : les réglages de l\'IA'),
        findsOneWidget,
      );
    });

    testWidgets('hors ligne : Envoyer inactif, message gardé', (tester) async {
      final app = await ouvrir(tester, offline: true);
      await ouvrirPanneau(tester);
      await saisir(tester, 'Question');
      expect(find.text(TextesAssistant.horsLigne), findsOneWidget);
      expect(tester.widget<FilledButton>(envoyer()).onPressed, isNull);
      expect(app.assistant.envois, isEmpty);
    });

    testWidgets('plus de 1 500 caractères : erreur, Envoyer inactif', (
      tester,
    ) async {
      await ouvrir(tester);
      await ouvrirPanneau(tester);
      await saisir(tester, 'x' * (kAssistantMessageMax + 1));
      expect(find.text(TextesAssistant.tropLongChamp), findsOneWidget);
      expect(tester.widget<FilledButton>(envoyer()).onPressed, isNull);
    });
  });

  group('Résumer et continuer', () {
    testWidgets('au dernier tour permis : résumé, nouvelle conversation', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        avant: (app) {
          app.ai.politique = politiqueLue(const ReglagePosteIaTest().unTour);
          app.assistant.reponses.addAll([
            reponse,
            const ReponseAssistant(texte: 'Résumé : recette blonde.'),
          ]);
        },
      );
      await ouvrirPanneau(tester);
      await saisir(tester, 'Question');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      expect(find.text(TextesAssistant.atteint(1)), findsOneWidget);
      expect(app.assistant.envois, hasLength(1));
      await tester.tap(find.text(TextesAssistant.resumer));
      await tester.pumpAndSettle();
      final [tour, resume] = app.assistant.envois;
      expect(resume['mode'], 'summary');
      expect(resume.containsKey('message'), isFalse);
      expect(resume['history'], hasLength(2));
      expect(find.text(TextesAssistant.titreResume), findsOneWidget);
      // La conversation suivante part avec un nouvel identifiant et le
      // résumé dans `summary`, jamais dans `history`.
      app.assistant.reponses.add(reponse);
      await saisir(tester, 'Et maintenant ?');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      final suite = app.assistant.envois.last;
      expect(suite['conversationId'], isNot(tour['conversationId']));
      expect(suite['summary'], 'Résumé : recette blonde.');
      expect(suite['history'], isEmpty);
    });

    testWidgets('refus conversation_full : bouton proposé', (tester) async {
      final app = await ouvrir(tester);
      app.assistant.reponses.addAll([
        reponse,
        const EchecAssistant(CauseEchecAssistant.conversationPleine),
      ]);
      await ouvrirPanneau(tester);
      await saisir(tester, 'Un');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      await saisir(tester, 'Deux');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      expect(find.text(TextesAssistant.tropLongue), findsOneWidget);
      expect(find.text(TextesAssistant.resumer), findsOneWidget);
      expect(app.assistant.envois, hasLength(2));
    });
  });

  group('départ et disposition', () {
    testWidgets('quitter l\'éditeur avec une conversation : confirmation', (
      tester,
    ) async {
      final app = await ouvrir(tester);
      app.assistant.reponses.add(reponse);
      await ouvrirPanneau(tester);
      await saisir(tester, 'Question');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(TextesAssistant.fermer));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Quitter l\'éditeur ?'), findsOneWidget);
      await tester.tap(find.text('Rester'));
      await tester.pumpAndSettle();
      expect(find.text('Nouvelle recette'), findsOneWidget);
    });

    testWidgets('Enregistrer sans nom : nom demandé avant la boîte', (
      tester,
    ) async {
      final app = await ouvrir(tester);
      app.assistant.reponses.add(reponse);
      await ouvrirPanneau(tester);
      await saisir(tester, 'Question');
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(TextesAssistant.fermer));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Enregistrer et fermer l\'assistant ?'), findsNothing);
      expect(find.text('Donnez un nom à la recette.'), findsOneWidget);
      // Nom donné : la boîte de la conversation paraît.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom'),
        'Blonde',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Enregistrer et fermer l\'assistant ?'), findsOneWidget);
    });

    testWidgets('de 840 à 1 279 px : commutateur Calculs / Assistant', (
      tester,
    ) async {
      await ouvrir(tester, width: 1000);
      expect(
        find.byWidgetPredicate((w) => w is BoutonsSegmentes),
        findsOneWidget,
      );
      await ouvrirPanneau(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text(TextesAssistant.avertissement), findsOneWidget);
      expect(find.byTooltip(TextesAssistant.fermer), findsWidgets);
    });

    testWidgets('360 × 640, texte à 200 % : feuille sans débordement', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp();
      app.ai.politique = politiqueLue(const ReglagePosteIaTest().unTour);
      app.assistant.reponses.add(reponse);
      await app.pump(tester, width: 360, height: 640);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/recettes/nouvelle');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await ouvrirPanneau(tester);
      expect(tester.takeException(), isNull);
      // Petite hauteur et grand texte : tout défile d'un bloc.
      final defilement = find
          .descendant(
            of: find.byType(PanneauAssistant),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> voir(Finder f) async {
        await tester.scrollUntilVisible(f, 200, scrollable: defilement);
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
      }

      await voir(find.widgetWithText(TextField, TextesAssistant.champ));
      await saisir(tester, 'Question');
      await voir(envoyer());
      await tester.tap(envoyer());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Réponse, puis encadré « Résumer et continuer » à la limite d'un tour.
      await voir(find.text(TextesAssistant.resumer));
      expect(find.text(TextesAssistant.resumer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('840 à 1 279 px : ni titre ni ✕ sous le commutateur', (
      tester,
    ) async {
      await ouvrir(tester, width: 1000);
      await ouvrirPanneau(tester);
      final panneau = find.byType(PanneauAssistant);
      expect(
        find.descendant(of: panneau, matching: find.byIcon(Icons.close)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: panneau,
          matching: find.byTooltip('Plus d\'actions'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('1 280 px et plus : trois colonnes', (tester) async {
      await ouvrir(tester, width: 1400);
      await ouvrirPanneau(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text(TextesAssistant.avertissement), findsOneWidget);
      // Le bloc des calculs reste affiché à côté.
      expect(find.text('Densité initiale'), findsWidgets);
    });
  });
}

/// Réglages de test dérivés de [reglageAssistant].
class ReglagePosteIaTest {
  const ReglagePosteIaTest();

  ReglagePosteIa get ouvert => ReglagePosteIa(
    modele: reglageAssistant.modele,
    effort: reglageAssistant.effort,
    ouvertAuxMembres: true,
    toursParJour: reglageAssistant.toursParJour,
    toursFondateurParJour: reglageAssistant.toursFondateurParJour,
    toursParConversation: reglageAssistant.toursParConversation,
  );

  ReglagePosteIa get unTour => ReglagePosteIa(
    modele: reglageAssistant.modele,
    effort: reglageAssistant.effort,
    ouvertAuxMembres: false,
    toursParJour: reglageAssistant.toursParJour,
    toursFondateurParJour: reglageAssistant.toursFondateurParJour,
    toursParConversation: 1,
  );
}
