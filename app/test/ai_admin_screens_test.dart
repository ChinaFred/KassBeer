import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/menu_compte.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/admin/domain/postes_ia.dart';
import 'package:kass_beer/features/admin/presentation/couts_ia_screen.dart';
import 'package:kass_beer/features/admin/presentation/moteur_ia_screen.dart';
import 'package:kass_beer/features/ai/data/ai_repository.dart';
import 'package:kass_beer/features/ai/domain/comptes_ia.dart';
import 'package:kass_beer/features/members/domain/member.dart';

import 'support/ai_fakes.dart';
import 'support/fakes.dart';

/// Admin › Moteur d'IA, Admin › Coûts de l'IA et ligne « IA ce mois »
/// (ADR-016, sections 6 et 9 ; P58, P60).
void main() {
  Future<TestApp> ouvrir(
    WidgetTester tester,
    String chemin, {
    bool admin = true,
    double width = 400,
    double height = 1600,
    void Function(TestApp app)? avant,
  }) async {
    final app = TestApp();
    avant?.call(app);
    await app.pump(tester, width: width, height: height);
    if (admin) {
      app.signIn(adminUser, member: adminMember);
    } else {
      app.signIn(brewerUser, member: brewerMember);
    }
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go(chemin);
    await tester.pumpAndSettle();
    return app;
  }

  group('Moteur d\'IA', () {
    testWidgets('brasseur renvoyé sur Recettes', (tester) async {
      await ouvrir(tester, AppRoutes.adminAiEngine, admin: false);
      expect(find.text(TextesMoteurIa.postes), findsNothing);
    });

    testWidgets('politique absente : Non enregistré, proposition initiale', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        avant: (app) => app.ai.grille = LectureIa(
          DocumentTrouve(uneGrille(verifieeLe: DateTime(2026, 11, 1))),
          fromCache: false,
        ),
      );
      expect(find.text(TextesMoteurIa.nonEnregistre), findsOneWidget);
      expect(find.text(TextesMoteurIa.aucunReglage), findsOneWidget);
      expect(find.text('Sonnet 5.5 · claude-sonnet-5-5'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, TextesMoteurIa.enregistrer),
      );
      await tester.tap(
        find.widgetWithText(FilledButton, TextesMoteurIa.enregistrer),
      );
      await tester.pumpAndSettle();
      expect(app.ai.enregistrements.single.kind, 'policy');
      expect(app.ai.enregistrements.single.value, {
        'version': 1,
        'features': {
          kPosteAssistantRecette: {
            'model': 'claude-sonnet-5-5',
            'effort': 'medium',
            'members_enabled': false,
            'turns_per_day': 20,
            'founder_turns_per_day': 60,
            'turns_per_conversation': 20,
          },
        },
      });
      expect(
        find.text(TextesMoteurIa.enregistres('Assistant de recette')),
        findsOneWidget,
      );
    });

    testWidgets('refus du serveur : message sous le champ nommé', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        avant: (app) {
          app.ai.grille = LectureIa(
            DocumentTrouve(uneGrille()),
            fromCache: false,
          );
          app.ai.refus = const EchecReglagesIa(
            CauseEchecReglagesIa.champ,
            champ: 'features.recipe_assistant_turn.turns_per_day',
            message: 'Entre 1 et 100.',
          );
        },
      );
      await tester.enterText(
        find.widgetWithText(TextField, TextesMoteurIa.toursParJour),
        '101',
      );
      await tester.pump();
      final bouton = find.widgetWithText(
        FilledButton,
        TextesMoteurIa.enregistrer,
      );
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();
      expect(app.ai.enregistrements, hasLength(1));
      expect(find.text('Entre 1 et 100.'), findsOneWidget);
    });

    testWidgets('grille absente : Tarifs en panne, menu des modèles vide', (
      tester,
    ) async {
      await ouvrir(tester, AppRoutes.adminAiEngine);
      expect(find.text(TextesMoteurIa.grilleAbsente), findsOneWidget);
      expect(find.text(TextesMoteurIa.ajouterModeleDabord), findsOneWidget);
    });

    testWidgets('grille de plus de 90 jours : à revérifier', (tester) async {
      await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        avant: (app) {
          app.now = DateTime(2026, 11, 15, 12);
          app.ai.grille = LectureIa(
            DocumentTrouve(uneGrille(verifieeLe: DateTime(2026, 8, 1))),
            fromCache: false,
          );
        },
      );
      expect(find.text(TextesMoteurIa.aReverifier), findsOneWidget);
    });

    testWidgets('modèle cité par la politique : Retirer inactif', (
      tester,
    ) async {
      await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        avant: (app) {
          app.ai.grille = LectureIa(
            DocumentTrouve(uneGrille()),
            fromCache: false,
          );
          app.ai.politique = politiqueLue(reglageAssistant);
        },
      );
      expect(
        find.text(TextesMoteurIa.sertAuPoste('Assistant de recette')),
        findsOneWidget,
      );
    });

    testWidgets('grille : ajouter un modèle, puis enregistrer', (tester) async {
      final app = await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        height: 2600,
        avant: (app) => app.ai.grille = LectureIa(
          DocumentTrouve(uneGrille()),
          fromCache: false,
        ),
      );
      final ajouter = find.text(TextesMoteurIa.ajouterModele);
      await tester.ensureVisible(ajouter);
      await tester.tap(ajouter);
      await tester.pumpAndSettle();
      Future<void> champ(String label, String texte) =>
          tester.enterText(find.widgetWithText(TextFormField, label), texte);
      await champ(TextesMoteurIa.identifiant, 'claude-opus-5-5');
      await champ(TextesMoteurIa.nomAffiche, 'Opus 5.5');
      await champ(TextesMoteurIa.entree, '4');
      await champ(TextesMoteurIa.sortie, '20');
      await champ(TextesMoteurIa.ecritureCache, '5');
      await champ(TextesMoteurIa.lectureCache, '0,4');
      await champ(TextesMoteurIa.effortsAcceptes, 'low, medium , high');
      await tester.tap(
        find.widgetWithText(FilledButton, TextesMoteurIa.ajouter),
      );
      await tester.pumpAndSettle();
      expect(find.text('Opus 5.5'), findsOneWidget);
      final enregistrer = find.widgetWithText(
        FilledButton,
        TextesMoteurIa.enregistrerGrille,
      );
      await tester.ensureVisible(enregistrer);
      await tester.tap(enregistrer);
      await tester.pumpAndSettle();
      final value = app.ai.enregistrements.single.value as Map;
      expect(app.ai.enregistrements.single.kind, 'pricing');
      expect(value['version'], 1);
      expect(value['checked_on'], '2026-11-01');
      expect((value['models'] as Map)['claude-opus-5-5'], {
        'label': 'Opus 5.5',
        'input_usd_per_mtok': 4.0,
        'output_usd_per_mtok': 20.0,
        'cache_write_usd_per_mtok': 5.0,
        'cache_read_usd_per_mtok': 0.4,
        'efforts': ['low', 'medium', 'high'],
      });
    });

    testWidgets('changements : retour de la coquille confirmé', (tester) async {
      final app = await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        avant: (app) {
          app.ai.grille = LectureIa(
            DocumentTrouve(uneGrille()),
            fromCache: false,
          );
          app.ai.politique = politiqueLue(reglageAssistant);
        },
      );
      await tester.enterText(
        find.widgetWithText(TextField, TextesMoteurIa.toursParJour),
        '15',
      );
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await tester.tap(find.text('Continuer la saisie'));
      await tester.pumpAndSettle();
      expect(find.text(TextesMoteurIa.postes), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.text(TextesMoteurIa.postes), findsNothing);
      expect(
        app.container.read(routerProvider).state.uri.path,
        AppRoutes.admin,
      );
    });

    testWidgets('changements : navigation par le rail confirmée', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        width: 1000,
        avant: (app) {
          app.ai.grille = LectureIa(
            DocumentTrouve(uneGrille()),
            fromCache: false,
          );
          app.ai.politique = politiqueLue(reglageAssistant);
        },
      );
      await tester.enterText(
        find.widgetWithText(TextField, TextesMoteurIa.toursParJour),
        '15',
      );
      await tester.pump();
      final rail = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Recettes'),
      );
      await tester.tap(rail);
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await tester.tap(find.text('Continuer la saisie'));
      await tester.pumpAndSettle();
      expect(
        app.container.read(routerProvider).state.uri.path,
        AppRoutes.adminAiEngine,
      );
      await tester.tap(rail);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(
        app.container.read(routerProvider).state.uri.path,
        AppRoutes.recipes,
      );
    });

    testWidgets('sans changement : retour sans question', (tester) async {
      await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        avant: (app) => app.ai.politique = politiqueLue(reglageAssistant),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsNothing);
      expect(find.text(TextesMoteurIa.postes), findsNothing);
    });

    testWidgets('360 × 640, texte à 200 % : aucun débordement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        width: 360,
        height: 640,
        avant: (app) => app.ai.grille = LectureIa(
          DocumentTrouve(uneGrille()),
          fromCache: false,
        ),
      );
      expect(tester.takeException(), isNull);
      // Toute la page défile sans débordement.
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('poste non enregistré modifié : départ confirmé', (
      tester,
    ) async {
      await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        avant: (app) => app.ai.grille = LectureIa(
          DocumentTrouve(uneGrille()),
          fromCache: false,
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, TextesMoteurIa.toursParJour),
        '12',
      );
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
    });

    testWidgets('Actualiser avec des changements : confirmation d\'abord', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        avant: (app) => app.ai.politique = politiqueLue(reglageAssistant),
      );
      final lectures = app.ai.lecturesPolitique;
      await tester.enterText(
        find.widgetWithText(TextField, TextesMoteurIa.toursParJour),
        '12',
      );
      await tester.pump();
      await tester.tap(find.text(TextesMoteurIa.actualiser));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await tester.tap(find.text('Continuer la saisie'));
      await tester.pumpAndSettle();
      String jour() => tester
          .widget<TextField>(
            find.widgetWithText(TextField, TextesMoteurIa.toursParJour),
          )
          .controller!
          .text;
      expect(app.ai.lecturesPolitique, lectures);
      expect(jour(), '12');
      await tester.tap(find.text(TextesMoteurIa.actualiser));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(app.ai.lecturesPolitique, greaterThan(lectures));
      expect(jour(), '20');
    });

    testWidgets('refus du serveur : focus sur le champ nommé', (tester) async {
      final app = await ouvrir(
        tester,
        AppRoutes.adminAiEngine,
        avant: (app) {
          app.ai.grille = LectureIa(
            DocumentTrouve(uneGrille()),
            fromCache: false,
          );
          app.ai.refus = const EchecReglagesIa(
            CauseEchecReglagesIa.champ,
            champ: 'features.recipe_assistant_turn.turns_per_conversation',
            message: 'Entre 1 et 100.',
          );
        },
      );
      final bouton = find.widgetWithText(
        FilledButton,
        TextesMoteurIa.enregistrer,
      );
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();
      expect(app.ai.enregistrements, hasLength(1));
      final champ = tester.widget<TextField>(
        find.widgetWithText(TextField, TextesMoteurIa.toursParConversation),
      );
      expect(champ.focusNode!.hasFocus, isTrue);
    });

    testWidgets('hors ligne : Enregistrer inactif', (tester) async {
      final app = TestApp();
      app.ai.grille = LectureIa(DocumentTrouve(uneGrille()), fromCache: true);
      app.ai.politique = politiqueLue(reglageAssistant, fromCache: true);
      await app.pump(tester, height: 1600);
      app.signIn(adminUser, member: adminMember, fromCache: true);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.adminAiEngine);
      await tester.pumpAndSettle();
      expect(find.text(TextesMoteurIa.horsLigne), findsOneWidget);
      expect(
        find.text(TextesMoteurIa.enregistrementHorsLigne),
        findsNWidgets(2),
      );
    });
  });

  group('Coûts de l\'IA', () {
    CompteMoisIa compte(
      String uid,
      String? email,
      ComptesPoste c, {
      String mois = '2026-11',
    }) => CompteMoisIa(
      id: '${mois}_$uid',
      mois: mois,
      uid: uid,
      email: email,
      postes: {kPosteAssistantRecette: c},
    );

    testWidgets('noms lus dans members/, membre retiré, sans montant', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        AppRoutes.adminAiCosts,
        avant: (app) {
          app.ai.grille = LectureIa(
            DocumentTrouve(uneGrille()),
            fromCache: false,
          );
          app.ai.comptes['2026-11'] = ComptesDuMois(
            comptes: [
              DocumentValide(
                '2026-11_u1',
                compte(
                  'u1',
                  'admin@exemple.fr',
                  desComptes(appels: 12, montant: 0.42),
                ),
              ),
              DocumentValide(
                '2026-11_u2',
                compte(
                  'u2',
                  'parti@exemple.fr',
                  desComptes(appels: 4, sansMontant: 4),
                ),
              ),
            ],
            fromCache: false,
            tronque: false,
          );
        },
      );
      app.members.all.add(const [adminMember]);
      await tester.pumpAndSettle();
      expect(find.text('Alice Admin'), findsOneWidget);
      expect(find.text(CoutsIaScreen.membreRetire), findsOneWidget);
      expect(find.textContaining('parti@exemple.fr'), findsOneWidget);
      expect(find.text(CoutsIaScreen.sansMontant(4)), findsOneWidget);
      expect(find.textContaining('Total : ≈ 0,42 \$'), findsOneWidget);
      expect(find.textContaining('montant inconnu'), findsOneWidget);
    });

    testWidgets('840 px et plus : tours et montant sur la ligne du nom', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        AppRoutes.adminAiCosts,
        width: 1000,
        avant: (app) => app.ai.comptes['2026-11'] = ComptesDuMois(
          comptes: [
            DocumentValide(
              '2026-11_u1',
              compte(
                'u1',
                'admin@exemple.fr',
                desComptes(appels: 12, montant: 0.42),
              ),
            ),
          ],
          fromCache: false,
          tronque: false,
        ),
      );
      app.members.all.add(const [adminMember]);
      await tester.pumpAndSettle();
      final nom = find.text('Alice Admin');
      final resume = find.text('12 tours · ≈\u00a00,42\u00a0\$');
      expect(resume, findsOneWidget);
      expect(tester.getCenter(resume).dy, tester.getCenter(nom).dy);
      expect(
        tester.getCenter(resume).dx,
        greaterThan(tester.getCenter(nom).dx),
      );
      await tester.tap(nom);
      await tester.pumpAndSettle();
      expect(find.text('Jetons d\'entrée'), findsOneWidget);
      expect(find.text('Jetons de sortie'), findsOneWidget);
    });

    testWidgets('mois vide et choix d\'un autre mois', (tester) async {
      final app = await ouvrir(tester, AppRoutes.adminAiCosts);
      app.members.all.add(const <Member>[]);
      await tester.pumpAndSettle();
      expect(find.text(CoutsIaScreen.vide('novembre 2026')), findsOneWidget);
      await tester.tap(find.text('Novembre 2026 (en cours)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Octobre 2026').last);
      await tester.pumpAndSettle();
      expect(find.text(CoutsIaScreen.vide('octobre 2026')), findsOneWidget);
    });

    testWidgets('grille absente : Tarifs en panne', (tester) async {
      await ouvrir(tester, AppRoutes.adminAiCosts);
      expect(find.text(CoutsIaScreen.tarifsEnPanne), findsOneWidget);
    });
  });

  group('accueil Admin', () {
    testWidgets('entrées Moteur d\'IA et Coûts de l\'IA, pastille d\'alerte', (
      tester,
    ) async {
      await ouvrir(tester, AppRoutes.admin);
      expect(find.text(TextesMoteurIa.titre), findsOneWidget);
      expect(find.text(CoutsIaScreen.titre), findsOneWidget);
      // Grille et politique absentes : deux alertes.
      expect(
        find.bySemanticsLabel(RegExp('Moteur d\'IA, 2 alertes')),
        findsOneWidget,
      );
    });
  });

  group('menu du compte : « IA ce mois »', () {
    Future<void> ouvrirMenu(WidgetTester tester) async {
      await tester.tap(find.byType(MenuCompte));
      await tester.pumpAndSettle();
    }

    testWidgets('admin : ligne affichée, lue à l\'ouverture du menu', (
      tester,
    ) async {
      final app = await ouvrir(tester, AppRoutes.recipes);
      expect(app.ai.lecturesCompteMois, 0);
      await ouvrirMenu(tester);
      expect(app.ai.lecturesCompteMois, 1);
      expect(app.ai.moisLus.single, '2026-11');
      expect(find.text('IA ce mois : aucun tour'), findsOneWidget);
    });

    testWidgets('brasseur, poste fermé, aucun tour : ligne absente', (
      tester,
    ) async {
      await ouvrir(tester, AppRoutes.recipes, admin: false);
      await ouvrirMenu(tester);
      expect(find.textContaining('IA ce mois'), findsNothing);
    });

    testWidgets('brasseur avec des tours ce mois : ligne affichée', (
      tester,
    ) async {
      await ouvrir(
        tester,
        AppRoutes.recipes,
        admin: false,
        avant: (app) => app.ai.compteMois = LectureIa(
          DocumentTrouve(
            CompteMoisIa(
              id: '2026-11_${brewerUser.uid}',
              mois: '2026-11',
              uid: brewerUser.uid,
              email: brewerMember.email,
              postes: {
                kPosteAssistantRecette: desComptes(
                  appels: 3,
                  sansMontant: 1,
                  montant: 0.1,
                ),
              },
            ),
          ),
          fromCache: false,
        ),
      );
      await ouvrirMenu(tester);
      expect(
        find.text('IA ce mois : 3 tours, ≈ 0,10 \$ (1 sans montant)'),
        findsOneWidget,
      );
    });
  });
}
