import 'dart:async';
import 'dart:convert';

import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/fichiers/echange_fichiers.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/export_recipe_sheet.dart';
import 'package:kass_beer/features/recipes/presentation/libelles_echange.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_editor_screen.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

const grainfather = Equipment(
  id: 'e1',
  ownerUid: 'uid-brasseur',
  ownerName: 'Bruno Brasseur',
  content: equipementTest,
);

/// Recette complète ; [author] : auteur indiqué par un fichier importé.
RecipeContent complete({String? author}) => RecipeContent(
  name: 'Blonde d\'Été',
  type: 'all grain',
  author: author,
  style: 'Blonde',
  batchVolumeL: 20,
  boilTimeMin: 60,
  grainTempC: 18,
  equipmentId: 'e1',
  mashSteps: const [
    MashStep(name: 'Palier', tempC: 66, durationMin: 60, type: 'infusion'),
  ],
  fermentables: const [
    FermentableLine(
      name: 'Pils',
      type: 'grain',
      weightG: 4500,
      ebc: 3.5,
      yieldPct: 80,
    ),
  ],
  hops: const [
    HopLine(
      name: 'Magnum',
      amount: Quantite.grammes(20),
      use: HopUse.boil,
      form: 'pellet',
      alphaPct: 12,
      timeMin: 60,
    ),
  ],
  yeasts: const [
    YeastLine(
      name: 'US-05',
      type: 'ale',
      form: 'dry',
      attenuationPct: 78,
      amount: Quantite.grammes(11.5),
    ),
  ],
);

/// Recette à l'extrait : ni palier, ni température du grain, ni ébullition.
const extrait = RecipeContent(
  name: 'Blonde à l\'extrait',
  type: 'extract',
  batchVolumeL: 20,
  equipmentId: 'e1',
  fermentables: [
    FermentableLine(
      name: 'Extrait sec',
      type: 'dry extract',
      weightG: 3000,
      ebc: 8,
      yieldPct: 95,
    ),
  ],
  yeasts: [
    YeastLine(
      name: 'US-05',
      type: 'ale',
      form: 'dry',
      amount: Quantite.grammes(11.5),
    ),
  ],
);

const mien = 'uid-brasseur';

Future<TestApp> ouvrir(
  WidgetTester tester,
  RecipeContent content, {
  String owner = 'uid-autre',
  String? ownerName = 'Ophélie Autre',
  List<ModeEnvoi>? modes,
  ResultatEnvoi? envoi,
}) async {
  final app = TestApp();
  if (envoi != null) app.fichiers.envoi = envoi;
  await app.pump(tester, height: 2000);
  app.signIn(brewerUser, member: brewerMember);
  app.recipes.publish([
    Recipe(id: 'r1', ownerUid: owner, ownerName: ownerName, content: content),
  ]);
  app.equipment.publish([grainfather]);
  if (modes != null) app.fichiers.modes = modes;
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go('/recettes/r1');
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(OutlinedButton, 'Exporter'));
  await tester.pumpAndSettle();
  return app;
}

Finder dansFeuille(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

Map<Object?, Object?> recetteExportee(FichierEnvoye envoye) =>
    (((jsonDecode(utf8.decode(envoye.octets)) as Map)['beerjson']
                    as Map)['recipes']
                as List)
            .single
        as Map;

void main() {
  testWidgets(
    'E1 : un autre membre exporte une recette qui porte son auteur ; pertes',
    (tester) async {
      final app = await ouvrir(tester, complete(author: 'Brasseuse Fictive'));
      expect(find.text(TextesExport.titre('Blonde d\'Été')), findsOneWidget);
      expect(find.text(TextesExport.sansPrix), findsOneWidget);
      expect(find.text(TextesExport.pret), findsOneWidget);
      expect(
        find.text('Auteur dans le fichier : Brasseuse Fictive.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Non exporté : le style « Blonde » (BeerJSON demande sa catégorie).',
        ),
        findsOneWidget,
      );
      // Un seul bouton plein : « Partager le fichier ».
      expect(
        dansFeuille(find.widgetWithText(OutlinedButton, 'Enregistrer')),
        findsOneWidget,
      );
      expect(
        dansFeuille(find.widgetWithText(FilledButton, 'Partager le fichier')),
        findsOneWidget,
      );
      expect(dansFeuille(find.byType(FilledButton)), findsOneWidget);
      await tester.tap(dansFeuille(find.text('Partager le fichier')));
      await tester.pumpAndSettle();
      final envoye = app.fichiers.envoyes.single;
      expect(envoye.mode, ModeEnvoi.partager);
      expect(recetteExportee(envoye)['author'], 'Brasseuse Fictive');
    },
  );

  testWidgets(
    'Enregistrer, sa recette : auteur = owner_name, rendement de l\'équipement',
    (tester) async {
      final app = await ouvrir(
        tester,
        complete(),
        owner: mien,
        ownerName: 'Bruno Brasseur',
      );
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      final envoye = app.fichiers.envoyes.single;
      expect(envoye.mode, ModeEnvoi.enregistrer);
      expect(envoye.nom, 'blonde-d-ete.json');
      expect(envoye.typeMime, 'application/json');
      final recette = recetteExportee(envoye);
      expect(recette['author'], 'Bruno Brasseur');
      expect(recette['efficiency'], {
        'brewhouse': {'value': 72.0, 'unit': '%'},
      });
      expect(recette.containsKey('original_gravity'), isTrue);
      final texte = utf8.decode(envoye.octets);
      for (final interdit in [
        'owner_uid',
        'equipment_id',
        'Grainfather',
        'price',
      ]) {
        expect(texte, isNot(contains(interdit)), reason: interdit);
      }
      expect(find.text(TextesExport.enregistre), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets('web : « Télécharger », puis « Téléchargement lancé »', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      complete(),
      owner: mien,
      modes: const [ModeEnvoi.telecharger],
    );
    expect(dansFeuille(find.text('Enregistrer')), findsNothing);
    await tester.tap(dansFeuille(find.text('Télécharger')));
    await tester.pumpAndSettle();
    expect(app.fichiers.envoyes.single.mode, ModeEnvoi.telecharger);
    expect(
      find.text(TextesExport.telecharge('blonde-d-ete.json')),
      findsOneWidget,
    );
  });

  testWidgets('envoi impossible : dans la feuille, boutons actifs', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      complete(),
      owner: mien,
      envoi: const EnvoiImpossible(),
    );
    await tester.tap(dansFeuille(find.text('Partager le fichier')));
    await tester.pumpAndSettle();
    expect(dansFeuille(find.text(TextesExport.echec)), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final partager = tester.widget<FilledButton>(
      dansFeuille(find.widgetWithText(FilledButton, 'Partager le fichier')),
    );
    expect(partager.onPressed, isNotNull);
    // Réessai : le message part dès que l'envoi réussit.
    app.fichiers.envoi = const EnvoiFait();
    await tester.tap(dansFeuille(find.text('Partager le fichier')));
    await tester.pumpAndSettle();
    expect(app.fichiers.envoyes, hasLength(2));
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('10 : boutons radio inactifs pendant un envoi', (tester) async {
    final app = TestApp();
    final attente = Completer<ResultatEnvoi>();
    app.fichiers.attenteEnvoi = attente;
    await app.pump(tester, height: 2000);
    app.signIn(brewerUser, member: brewerMember);
    app.recipes.publish([
      Recipe(
        id: 'r1',
        ownerUid: mien,
        ownerName: 'Bruno Brasseur',
        content: complete(),
      ),
    ]);
    app.equipment.publish([grainfather]);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/recettes/r1');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Exporter'));
    await tester.pumpAndSettle();
    expect(
      find.text('Auteur dans le fichier : Bruno Brasseur.'),
      findsOneWidget,
    );
    await tester.tap(dansFeuille(find.text('Partager le fichier')));
    await tester.pump();
    for (final radio in tester.widgetList<RadioListTile<FormatExport>>(
      find.byType(RadioListTile<FormatExport>),
    )) {
      expect(radio.enabled, isFalse);
    }
    attente.complete(const EnvoiAnnule());
    await tester.pumpAndSettle();
    for (final radio in tester.widgetList<RadioListTile<FormatExport>>(
      find.byType(RadioListTile<FormatExport>),
    )) {
      expect(radio.enabled, isTrue);
    }
  });

  testWidgets('BeerXML : visible et bloqué avec sa raison', (tester) async {
    await ouvrir(tester, complete(), owner: mien);
    await tester.tap(find.text(TextesExport.beerXml));
    await tester.pumpAndSettle();
    expect(find.text(TextesExport.beerXmlBloque), findsOneWidget);
    expect(dansFeuille(find.text('Enregistrer')), findsNothing);
  });

  testWidgets(
    'B : recette à l\'extrait, sans empâtage ni ébullition, exportée',
    (tester) async {
      final app = await ouvrir(tester, extrait, owner: mien);
      expect(find.text(TextesExport.pret), findsOneWidget);
      expect(
        find.text('Non exporté : empâtage (aucun palier).'),
        findsOneWidget,
      );
      expect(
        find.text('Non exporté : ébullition (durée non renseignée).'),
        findsOneWidget,
      );
      await tester.tap(dansFeuille(find.text('Partager le fichier')));
      await tester.pumpAndSettle();
      final recette = recetteExportee(app.fichiers.envoyes.single);
      expect(recette.containsKey('mash'), isFalse);
      expect(recette.containsKey('boil'), isFalse);
    },
  );

  group('A : recette d\'un autre membre sans auteur', () {
    testWidgets(
      'bloquée : « Dupliquer » dans la feuille, sans « Auteur inconnu »',
      (tester) async {
        final app = await ouvrir(tester, complete());
        expect(find.text(TextesExport.dupliquerPourExporter), findsOneWidget);
        expect(find.textContaining('Auteur inconnu'), findsNothing);
        expect(dansFeuille(find.text(TextesExport.completer)), findsNothing);
        expect(find.textContaining('Export impossible'), findsNothing);
        await tester.tap(
          dansFeuille(
            find.widgetWithText(FilledButton, TextesExport.dupliquer),
          ),
        );
        await tester.pumpAndSettle();
        final write = app.recipes.writes.single;
        expect(write.kind, 'duplicate');
        expect(write.ownerUid, 'uid-brasseur');
      },
    );

    testWidgets('avec d\'autres manques : la liste, puis « Dupliquez »', (
      tester,
    ) async {
      await ouvrir(
        tester,
        const RecipeContent(
          name: 'Brouillon',
          fermentables: [
            FermentableLine(name: 'Pils', type: 'grain', weightG: 4000),
          ],
        ),
      );
      expect(find.textContaining('Export impossible :'), findsOneWidget);
      expect(
        dansFeuille(find.text('Type de recette non renseigné.')),
        findsOneWidget,
      );
      expect(find.text(TextesExport.dupliquerPourExporter), findsOneWidget);
      expect(find.textContaining('Auteur inconnu'), findsNothing);
    });
  });

  group('export bloqué', () {
    const incomplete = RecipeContent(
      name: 'Incomplète',
      fermentables: [
        FermentableLine(name: 'Pils', type: 'grain', weightG: 4000),
      ],
      yeasts: [YeastLine(name: 'S-04')],
    );

    testWidgets('auteur : la liste, puis « Compléter la recette »', (
      tester,
    ) async {
      await ouvrir(tester, incomplete, owner: mien, ownerName: 'Bruno');
      expect(find.textContaining('Export impossible :'), findsOneWidget);
      const libelles = [
        'Type de recette non renseigné.',
        'Volume en fermenteur non renseigné.',
        'Aucun équipement choisi : le rendement de brassage ne peut pas être '
            'calculé.',
        'Rendement d\'extrait non renseigné : Pils.',
        'Couleur non renseignée : Pils.',
        'Type de levure non renseigné : S-04.',
        'Forme de levure non renseignée : S-04.',
        'Quantité de levure non renseignée : S-04.',
      ];
      for (final libelle in libelles) {
        expect(
          dansFeuille(find.text(libelle)),
          findsOneWidget,
          reason: libelle,
        );
      }
      expect(find.text(TextesExport.bloque(libelles.length)), findsOneWidget);
      // Sans palier ni température du grain, l'empâtage est omis, pas bloqué.
      expect(find.textContaining('palier d\'empâtage'), findsNothing);
      await tester.tap(dansFeuille(find.text(TextesExport.completer)));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditorScreen), findsOneWidget);
    });

    testWidgets('autre membre, recette avec auteur : « Seul l\'auteur… »', (
      tester,
    ) async {
      await ouvrir(
        tester,
        const RecipeContent(
          name: 'Incomplète',
          author: 'Brasseuse Fictive',
          fermentables: [
            FermentableLine(name: 'Pils', type: 'grain', weightG: 4000),
          ],
        ),
      );
      expect(find.text(TextesExport.autreMembre), findsOneWidget);
      expect(dansFeuille(find.text(TextesExport.completer)), findsNothing);
      expect(dansFeuille(find.text(TextesExport.fermer)), findsOneWidget);
    });

    testWidgets('sa recette, ni auteur du fichier ni owner_name : bloqué', (
      tester,
    ) async {
      await ouvrir(tester, complete(), owner: mien, ownerName: null);
      expect(
        find.text(
          'Auteur inconnu : le compte qui a créé la recette n\'a pas de nom.',
        ),
        findsOneWidget,
      );
    });
  });
}
