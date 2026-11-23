import 'dart:async';

import 'package:brewing/brewing.dart' show HopUse;
import 'package:exchange/exchange.dart'
    show
        OperationProposee,
        PropositionLue,
        RaisonRefusOperation,
        RefusOperation,
        lireProposition;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/recipes/domain/assistant_recette.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/carte_proposition.dart';
import 'package:kass_beer/features/recipes/presentation/contenu_recette.dart';
import 'package:kass_beer/features/recipes/presentation/panneau_assistant.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_calculations_view.dart';

import 'support/fakes.dart';

/// Propositions de l'assistant dans l'éditeur (ADR-015, section 6, lot A2 ;
/// amendement du 2026-11-21 ; P61) : carte, aperçu, application, annulation,
/// marque « (proposée par l'IA) ».
void main() {
  ReponseAssistant reponseAvec(Map<String, Object?> operation) =>
      ReponseAssistant(
        texte: 'Ajoutons un houblon de fin d\'ébullition.',
        tour: 1,
        proposition:
            (lireProposition({
                      'resume': 'Mosaic en fin d\'ébullition.',
                      'operations': [operation],
                    })
                    as PropositionLue)
                .proposition,
      );

  const mosaic = {
    'op': 'add_hop',
    'name': 'Mosaic',
    'form': 'pellet',
    'amount_g': 30,
    'use': 'boil',
    'time_min': 10,
    'alpha_acid_pct': 12.5,
  };

  void bibliotheque(TestApp app) {
    app.library.index[NatureReferentiel.fermentables] = const DocumentTrouve(
      IndexReferentiel(nature: NatureReferentiel.fermentables, entrees: []),
    );
    app.library.index[NatureReferentiel.hops] = const DocumentTrouve(
      IndexReferentiel(
        nature: NatureReferentiel.hops,
        entrees: [EntreeHoublon(id: 'hop-cascade', name: 'Cascade')],
      ),
    );
    app.library.index[NatureReferentiel.miscs] = const DocumentTrouve(
      IndexReferentiel(nature: NatureReferentiel.miscs, entrees: []),
    );
    app.library.index[NatureReferentiel.cultures] = const DocumentTrouve(
      IndexReferentiel(nature: NatureReferentiel.cultures, entrees: []),
    );
  }

  Future<TestApp> ouvrir(
    WidgetTester tester, {
    double width = 1300,
    bool lireBibliotheque = true,
    Map<String, Object?> operation = mosaic,
    bool avecMaltEtEquipement = false,
  }) async {
    final app = TestApp();
    if (lireBibliotheque) bibliotheque(app);
    if (avecMaltEtEquipement) {
      // Malt et rendement connus : densités, IBU et couleur se calculent.
      app.equipment.publish([
        Equipment(
          id: 'e1',
          ownerUid: adminUser.uid,
          content: const EquipmentContent(
            name: 'Cuve',
            kind: EquipmentKind.multiVessel,
            mashEfficiencyPct: 72,
          ),
        ),
      ]);
    }
    app.recipes.publish([
      Recipe(
        id: 'r1',
        ownerUid: adminUser.uid,
        content: RecipeContent(
          name: 'Blonde',
          batchVolumeL: 20,
          boilTimeMin: 60,
          equipmentId: avecMaltEtEquipement ? 'e1' : null,
          fermentables: [
            if (avecMaltEtEquipement)
              const FermentableLine(
                name: 'Pale Ale',
                type: 'grain',
                weightG: 4500,
                ebc: 6,
                yieldPct: 80,
              ),
          ],
          hops: const [
            HopLine(
              name: 'Cascade',
              amount: Quantite.grammes(20),
              use: HopUse.boil,
              form: 'pellet',
              alphaPct: 6,
              timeMin: 60,
            ),
          ],
        ),
      ),
    ]);
    app.assistant.reponses.add(reponseAvec(operation));
    await app.pump(tester, width: width);
    app.signIn(adminUser, member: adminMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/recettes/r1/modifier');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(TextesAssistant.ouvrir));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, TextesAssistant.champ),
      'Propose un houblon de fin.',
    );
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, TextesAssistant.envoyer),
    );
    await tester.pumpAndSettle();
    return app;
  }

  final appliquer = find.widgetWithText(
    FilledButton,
    TextesProposition.appliquer,
  );

  Future<void> appliquerProposition(WidgetTester tester) async {
    await tester.ensureVisible(appliquer);
    await tester.pumpAndSettle();
    await tester.tap(appliquer);
    await tester.pumpAndSettle();
  }

  /// Ferme la fenêtre (ou la feuille) par ✕.
  Future<void> fermer(WidgetTester tester) async {
    await tester.tap(find.byTooltip(TextesAssistant.fermer));
    await tester.pumpAndSettle();
  }

  /// Rouvre l'assistant par l'icône de la barre du haut.
  Future<void> rouvrir(WidgetTester tester) async {
    await tester.tap(find.byTooltip(TextesAssistant.ouvrir));
    await tester.pumpAndSettle();
  }

  Future<void> annulerProposition(WidgetTester tester) async {
    final annuler = find.widgetWithText(
      OutlinedButton,
      TextesProposition.annuler,
    );
    await tester.ensureVisible(annuler);
    await tester.pumpAndSettle();
    await tester.tap(annuler);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'carte : résumé, compte, chiffres qui changent, aucune écriture',
    (tester) async {
      final app = await ouvrir(tester);
      expect(find.text(TextesProposition.titre), findsOneWidget);
      expect(find.text('Mosaic en fin d\'ébullition.'), findsOneWidget);
      expect(
        find.text('1 changement · 1 valeur proposée par l\'IA'),
        findsOneWidget,
      );
      expect(appliquer, findsOneWidget);
      expect(app.recipes.writes, isEmpty);
      await tester.tap(find.text(TextesProposition.voirDetail));
      await tester.pumpAndSettle();
      expect(find.text(TextesProposition.changements), findsOneWidget);
      expect(
        find.textContaining('Ajout · Mosaic · Ébullition'),
        findsOneWidget,
      );
      expect(find.textContaining(kProposeeParIa), findsWidgets);
      expect(find.text(TextesProposition.calculs), findsOneWidget);
      expect(find.textContaining('IBU : '), findsOneWidget);
    },
  );

  testWidgets('Appliquer puis Annuler : brouillon remplacé puis rendu', (
    tester,
  ) async {
    final app = await ouvrir(tester, avecMaltEtEquipement: true);
    String resumeCalculs() => tester
        .widget<PanneauAssistant>(find.byType(PanneauAssistant))
        .resumeCalculs;
    final resumeAvant = resumeCalculs();
    expect(resumeAvant, contains('IBU'));
    expect(resumeAvant, isNot(contains('DI —')));
    await appliquerProposition(tester);
    expect(find.text(TextesProposition.annonceAppliquee), findsOneWidget);
    // Fenêtre fermée : la ligne du brouillon porte la marque de la valeur du
    // modèle.
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Mosaic'), findsWidgets);
    expect(
      find.textContaining('12,5\u00a0% alpha $kProposeeParIa'),
      findsWidgets,
    );
    expect(app.recipes.writes, isEmpty);
    await rouvrir(tester);
    expect(find.text(TextesProposition.appliquee), findsOneWidget);
    // Le houblon ajouté change l'amertume : la ligne des calculs diffère.
    expect(resumeCalculs(), isNot(resumeAvant));
    await annulerProposition(tester);
    expect(find.text(TextesProposition.annulee), findsOneWidget);
    // Ligne des calculs de la fenêtre : celle du brouillon rendu.
    expect(resumeCalculs(), resumeAvant);
    // Fermée puis rouverte, la fenêtre montre toujours la ligne d'avant.
    await fermer(tester);
    await rouvrir(tester);
    expect(resumeCalculs(), resumeAvant);
    expect(find.textContaining('12,5\u00a0% alpha'), findsNothing);
    expect(appliquer, findsOneWidget);
  });

  testWidgets('Annuler après une modification à la main : confirmation', (
    tester,
  ) async {
    await ouvrir(tester);
    await appliquerProposition(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom'),
      'Blonde révisée',
    );
    await tester.pump();
    await rouvrir(tester);
    await annulerProposition(tester);
    expect(find.text(TextesProposition.confirmerAnnulation), findsOneWidget);
    expect(
      find.text(TextesProposition.confirmerAnnulationTexte),
      findsOneWidget,
    );
  });

  testWidgets('Enregistrer : marques écrites dans ai_proposed', (tester) async {
    final app = await ouvrir(tester);
    await appliquerProposition(tester);
    await tester.tap(find.text('Enregistrer').first);
    await tester.pumpAndSettle();
    // « Enregistrer et effacer la conversation ? » : la conversation sera perdue.
    await tester.tap(find.text('Enregistrer').last);
    await tester.pumpAndSettle();
    final ecrit = app.recipes.writes.single.content!;
    expect(
      [for (final m in ecrit.aiProposed) m.texte],
      ['hop:houblon-mosaic:alpha_acid'],
    );
  });

  testWidgets('proposition périmée : avertissement et détail déplié', (
    tester,
  ) async {
    await ouvrir(tester);
    // La fenêtre est modale : le brouillon se modifie fenêtre fermée.
    await fermer(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom'),
      'Autre nom',
    );
    await tester.pumpAndSettle();
    await rouvrir(tester);
    expect(find.text(TextesProposition.perimee), findsOneWidget);
    expect(find.text(TextesProposition.changements), findsOneWidget);
    expect(appliquer, findsOneWidget);
  });

  testWidgets('Bibliothèque illisible : panne, aucun bouton Appliquer', (
    tester,
  ) async {
    await ouvrir(tester, lireBibliotheque: false);
    expect(find.text(TextesProposition.bibliothequeIllisible), findsOneWidget);
    expect(find.text(TextesProposition.reessayer), findsOneWidget);
    expect(appliquer, findsNothing);
  });

  testWidgets('élément changé : aucun changement ne peut s\'appliquer', (
    tester,
  ) async {
    await ouvrir(
      tester,
      operation: const {'op': 'remove_hop', 'index': 0, 'name': 'Citra'},
    );
    expect(find.text(TextesProposition.aucunChangement), findsOneWidget);
    expect(
      find.text(
        'Retrait du houblon n° 1 : ce houblon a changé depuis la '
        'proposition.',
      ),
      findsOneWidget,
    );
    expect(appliquer, findsNothing);
  });

  testWidgets('téléphone : la feuille se ferme après Appliquer', (
    tester,
  ) async {
    await ouvrir(tester, width: 400);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.ensureVisible(appliquer);
    await tester.ensureVisible(appliquer);
    await tester.pumpAndSettle();
    await tester.tap(appliquer);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text(TextesProposition.annonceAppliquee), findsOneWidget);
  });

  for (final largeur in [1000.0, 1300.0]) {
    testWidgets('$largeur px : Appliquer ferme la fenêtre, « Annuler » 10 s, '
        'carte appliquée à la réouverture', (tester) async {
      await ouvrir(tester, width: largeur);
      expect(find.byType(Dialog), findsOneWidget);
      await appliquerProposition(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text(TextesProposition.annonceAppliquee), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Annuler'), findsOneWidget);
      // Focus rendu à l'icône Assistant.
      final icone = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.auto_awesome_outlined),
      );
      expect(icone.focusNode?.hasFocus, isTrue);
      await rouvrir(tester);
      expect(find.text(TextesProposition.appliquee), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, TextesProposition.annuler),
        findsOneWidget,
      );
    });
  }

  testWidgets('réponse arrivée pendant « Annuler » : annoncée ensuite, sans '
      'couper l\'annonce', (tester) async {
    final app = await ouvrir(tester, width: 1000);
    final attente = Completer<void>();
    app.assistant
      ..attente = attente
      ..reponses.add(const ReponseAssistant(texte: 'Autre avis.'));
    await tester.enterText(
      find.widgetWithText(TextField, TextesAssistant.champ),
      'Et la levure ?',
    );
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, TextesAssistant.envoyer),
    );
    await tester.pump();
    // Appel en cours : l'indicateur tourne, pas de pumpAndSettle.
    await tester.ensureVisible(appliquer);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(appliquer);
    await tester.pump(const Duration(milliseconds: 500));
    attente.complete();
    await tester.pumpAndSettle();
    expect(find.text(TextesProposition.annonceAppliquee), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Annuler'), findsOneWidget);
    expect(find.text(TextesAssistant.reponseRecue), findsNothing);
    // Fin des 10 s de « Annuler » : l'annonce de la réponse suit.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text(TextesProposition.annonceAppliquee), findsNothing);
    expect(find.text(TextesAssistant.reponseRecue), findsOneWidget);
  });

  testWidgets('réponse pendant « Annuler », assistant rouvert avant 10 s : '
      'aucune annonce ensuite', (tester) async {
    final app = await ouvrir(tester, width: 1000);
    final attente = Completer<void>();
    app.assistant
      ..attente = attente
      ..reponses.add(const ReponseAssistant(texte: 'Autre avis.'));
    await tester.enterText(
      find.widgetWithText(TextField, TextesAssistant.champ),
      'Et la levure ?',
    );
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, TextesAssistant.envoyer),
    );
    await tester.pump();
    await tester.ensureVisible(appliquer);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(appliquer);
    await tester.pump(const Duration(milliseconds: 500));
    attente.complete();
    await tester.pumpAndSettle();
    // Rouverte par l'icône : la réponse est lue dans la fenêtre.
    await rouvrir(tester);
    expect(find.text('Autre avis.'), findsOneWidget);
    // Refermée avant la fin des 10 s : la réponse lue ne s'annonce pas.
    await fermer(tester);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text(TextesAssistant.reponseRecue), findsNothing);
  });

  testWidgets('nouvelle conversation : la proposition appliquée ne s\'annule '
      'plus', (tester) async {
    await ouvrir(tester);
    await appliquerProposition(tester);
    await rouvrir(tester);
    await tester.tap(find.byTooltip('Plus d\'actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(TextesAssistant.nouvelleConversation).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(TextesAssistant.effacer));
    await tester.pumpAndSettle();
    expect(find.text(TextesProposition.appliquee), findsNothing);
    expect(find.text(TextesProposition.annonceAppliquee), findsNothing);
    // Le brouillon garde la proposition appliquée.
    expect(find.text('Mosaic'), findsWidgets);
  });

  group('textes de l\'aperçu', () {
    test('nom absent, valeur manquante, palier', () {
      expect(
        texteRefus(
          const OperationProposee('add_hop', {}),
          const RefusOperation(
            0,
            'add_hop',
            RaisonRefusOperation.valeurManquante,
            'time_min',
          ),
        ),
        'Ajout d\'un houblon : valeur manquante (durée).',
      );
      expect(
        texteRefus(
          const OperationProposee('set_culture', {}),
          const RefusOperation(
            0,
            'set_culture',
            RaisonRefusOperation.horsBornes,
            'attenuation_pct',
          ),
        ),
        'Levure : valeur hors des limites acceptées (atténuation).',
      );
      expect(
        texteRefus(
          const OperationProposee('add_misc', {}),
          const RefusOperation(
            0,
            'add_misc',
            RaisonRefusOperation.listePleine,
            'index',
          ),
        ),
        'Ajout d\'un ingrédient : la liste est pleine.',
      );
    });

    test('changement refusé', () {
      expect(
        texteRefus(
          const OperationProposee('update_hop', {'index': 3, 'name': 'X'}),
          const RefusOperation(
            0,
            'update_hop',
            RaisonRefusOperation.indexAbsent,
            'index',
          ),
        ),
        'Modification du houblon n° 4 : ce houblon n\'est plus dans la '
        'recette.',
      );
      expect(
        texteRefus(
          const OperationProposee('add_hop', {'name': 'Citra'}),
          const RefusOperation(
            0,
            'add_hop',
            RaisonRefusOperation.horsBornes,
            'amount_g',
          ),
        ),
        'Ajout de Citra : valeur hors des limites acceptées (quantité).',
      );
    });

    test('calculs : flèche exclue de la lecture', () {
      const vide = CalculsImpossibles('x');
      final lignes = lignesCalculs(vide, vide);
      expect(lignes.map((l) => l.ligne.texte), [
        'Densité initiale : — → —',
        'Densité finale : — → —',
        'Degré : — → —\u00a0%\u00a0vol',
        'IBU : — → —\u00a0IBU',
        'Couleur : — → — EBC',
      ]);
      expect(
        lignes[3].ligne.lecture,
        'IBU, avant indisponible, après '
        'indisponible',
      );
    });
  });
}
