import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kass_beer/core/presentation/bandeau_hors_ligne.dart';
import 'package:kass_beer/core/presentation/breakpoints.dart';
import 'package:kass_beer/core/presentation/encadre.dart';
import 'package:kass_beer/core/presentation/etats.dart';
import 'package:kass_beer/core/presentation/etiquette.dart';
import 'package:kass_beer/core/presentation/fiche.dart';
import 'package:kass_beer/core/presentation/ligne_liste.dart';
import 'package:kass_beer/core/presentation/page_secondaire.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/core/theme/app_theme.dart';

import 'support/fakes.dart';

/// Composant seul dans une page du thème de l'application.
Future<void> poser(
  WidgetTester tester,
  Widget child, {
  double width = 400,
  double height = 800,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: Scaffold(body: ListView(children: [child])),
    ),
  );
}

ColorScheme schema(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold))).colorScheme;

void main() {
  group('LigneListe', () {
    testWidgets('titre, détails, étiquettes ; lue d\'un bloc ; appui', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var appuis = 0;
      await poser(
        tester,
        LigneListe(
          icone: Icons.science_outlined,
          titre: 'Blonde',
          details: const [Text('Grainfather · Vous')],
          etiquettes: const [Etiquette(label: 'En attente du réseau')],
          onTap: () => appuis++,
        ),
      );
      expect(
        tester.getSize(find.byType(LigneListe)).height,
        greaterThanOrEqualTo(kLigneListeMinHeight),
      );
      // Étiquette sous les détails.
      expect(
        tester.getTopLeft(find.text('En attente du réseau')).dy,
        greaterThan(tester.getTopLeft(find.text('Grainfather · Vous')).dy),
      );
      // Détail en onSurfaceVariant.
      final detail = tester.widget<RichText>(
        find.descendant(
          of: find.text('Grainfather · Vous'),
          matching: find.byType(RichText),
        ),
      );
      expect(detail.text.style?.color, schema(tester).onSurfaceVariant);
      // Repère : disque secondaryContainer de 40 px.
      final disque = find.ancestor(
        of: find.byIcon(Icons.science_outlined),
        matching: find.byType(DecoratedBox),
      );
      expect(tester.getSize(disque.first), const Size(40, 40));
      expect(
        (tester.widget<DecoratedBox>(disque.first).decoration as BoxDecoration)
            .color,
        schema(tester).secondaryContainer,
      );
      expect(
        tester.getSemantics(find.text('Blonde')),
        isSemantics(
          label: 'Blonde\nGrainfather · Vous\nEn attente du réseau',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.text('Blonde'));
      expect(appuis, 1);
      semantics.dispose();
    });

    testWidgets('choisie : fond secondaryContainer, lue « sélectionnée »', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await poser(
        tester,
        LigneListe(
          icone: Icons.bug_report_outlined,
          iconeLabel: 'Bug',
          titre: 'Densité fausse',
          selected: true,
          onTap: () {},
        ),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(LigneListe),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, schema(tester).secondaryContainer);
      expect(
        tester.getSemantics(find.text('Densité fausse')),
        isSemantics(label: 'Bug\nDensité fausse', isSelected: true),
      );
      semantics.dispose();
    });

    testWidgets('action à droite : lue à part, hors de la zone d\'appui', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var supprime = 0;
      await poser(
        tester,
        LigneListe(
          icone: Icons.error_outline,
          erreur: true,
          titre: 'Prix illisible',
          action: TextButton(
            onPressed: () => supprime++,
            child: const Text(
              'Supprimer',
              semanticsLabel: 'Supprimer le prix illisible',
            ),
          ),
        ),
      );
      expect(
        (tester
                    .widget<DecoratedBox>(
                      find
                          .ancestor(
                            of: find.byIcon(Icons.error_outline),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .color,
        schema(tester).errorContainer,
      );
      expect(
        find.bySemanticsLabel('Supprimer le prix illisible'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Prix illisible'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Supprimer le prix illisible'));
      expect(supprime, 1);
      semantics.dispose();
    });

    testWidgets('lecture imposée : un seul nœud qui porte l\'appui', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var appuis = 0;
      await poser(
        tester,
        LigneListe(
          titre: 'Simple',
          details: const [Text('1 journée')],
          semanticsLabel: 'Simple, 1 journée',
          onTap: () => appuis++,
        ),
      );
      expect(find.bySemanticsLabel('Simple'), findsNothing);
      tester.semantics.tap(find.semantics.byLabel('Simple, 1 journée'));
      expect(appuis, 1);
      semantics.dispose();
    });

    testWidgets('texte × 2 sur 320 px : aucun débordement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await poser(
        tester,
        LigneListe(
          icone: Icons.menu_book_outlined,
          titre: 'Une recette au nom vraiment très long pour la ligne',
          details: const [Text('American Pale Ale · 23 l · Zoé')],
          etiquettes: const [
            Etiquette(label: 'En fermentation', ton: TonEtiquette.tertiaire),
            Etiquette(label: 'En attente du réseau'),
          ],
          trailing: const Icon(Icons.circle, size: 12),
          chevron: true,
          onTap: () {},
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    for (final brightness in Brightness.values) {
      testWidgets('contraste du texte, thème ${brightness.name}', (
        tester,
      ) async {
        await poser(
          tester,
          Column(
            children: [
              LigneListe(
                icone: Icons.science_outlined,
                titre: 'Blonde',
                details: const [Text('Grainfather · Vous')],
                etiquettes: const [
                  Etiquette(label: 'Prévu', ton: TonEtiquette.neutre),
                ],
                onTap: () {},
              ),
              LigneListe(
                titre: 'Densité fausse',
                details: const [Text('#12 · 07/11/26')],
                selected: true,
                onTap: () {},
              ),
            ],
          ),
          brightness: brightness,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      });
    }
  });

  group('Encadre', () {
    testWidgets('fond et texte du ton, icône non lue', (tester) async {
      final semantics = tester.ensureSemantics();
      await poser(
        tester,
        const Column(
          children: [
            Encadre(
              ton: TonEncadre.information,
              icone: Icons.payments_outlined,
              child: Text('information'),
            ),
            Encadre(
              ton: TonEncadre.avertissement,
              child: Text('avertissement'),
            ),
            Encadre(ton: TonEncadre.succes, child: Text('succès')),
            Encadre(
              ton: TonEncadre.erreur,
              liveRegion: true,
              child: Text('erreur'),
            ),
          ],
        ),
      );
      final s = schema(tester);
      final etat = CouleursEtat.of(tester.element(find.byType(Scaffold)));
      final attendus = {
        'information': (s.secondaryContainer, s.onSecondaryContainer),
        'avertissement': (s.tertiaryContainer, s.onTertiaryContainer),
        'succès': (etat.conteneurSucces, etat.surConteneurSucces),
        'erreur': (s.errorContainer, s.onErrorContainer),
      };
      for (final MapEntry(key: texte, value: (fond, encre))
          in attendus.entries) {
        final material = tester.widget<Material>(
          find
              .ancestor(of: find.text(texte), matching: find.byType(Material))
              .first,
        );
        expect(material.color, fond, reason: texte);
        expect(
          material.borderRadius,
          BorderRadius.circular(AppTheme.rayon),
          reason: texte,
        );
        final rich = tester.widget<RichText>(
          find.descendant(
            of: find.text(texte),
            matching: find.byType(RichText),
          ),
        );
        expect(rich.text.style?.color, encre, reason: texte);
      }
      expect(
        tester.widget<Icon>(find.byIcon(Icons.payments_outlined)).color,
        s.onSecondaryContainer,
      );
      semantics.dispose();
    });

    testWidgets('texte lu seul, sans l\'icône ; annoncé si liveRegion', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await poser(
        tester,
        const Encadre(
          ton: TonEncadre.erreur,
          icone: Icons.error_outline,
          liveRegion: true,
          child: Text('Calcul du coût impossible.'),
        ),
      );
      expect(
        tester.getSemantics(find.text('Calcul du coût impossible.')),
        isSemantics(label: 'Calcul du coût impossible.', isLiveRegion: true),
      );
      semantics.dispose();
    });

    for (final brightness in Brightness.values) {
      testWidgets('contraste du texte, thème ${brightness.name}', (
        tester,
      ) async {
        await poser(
          tester,
          Column(
            children: [
              for (final ton in TonEncadre.values)
                Encadre(
                  ton: ton,
                  icone: Icons.info_outline,
                  child: const Text('Tout est prêt.'),
                ),
            ],
          ),
          brightness: brightness,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }
  });

  group('EtatVide', () {
    testWidgets('titre en en-tête, icône dans un disque de 80 px', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await poser(
        tester,
        const EtatVide(
          icon: Icons.menu_book_outlined,
          titre: 'Aucune recette',
          message: 'Appuyez sur Nouvelle recette pour commencer.',
        ),
      );
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(
        tester.widget<Text>(find.text('Aucune recette')).style,
        theme.textTheme.titleLarge,
      );
      expect(
        tester.getSemantics(find.text('Aucune recette')),
        isSemantics(label: 'Aucune recette', isHeader: true),
      );
      expect(
        tester.getTopLeft(find.text('Aucune recette')).dy,
        lessThan(
          tester
              .getTopLeft(
                find.text('Appuyez sur Nouvelle recette pour commencer.'),
              )
              .dy,
        ),
      );
      final disque = find.ancestor(
        of: find.byIcon(Icons.menu_book_outlined),
        matching: find.byType(DecoratedBox),
      );
      expect(tester.getSize(disque.first), const Size(80, 80));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.menu_book_outlined)).size,
        40,
      );
      semantics.dispose();
    });

    testWidgets('sans titre : le message seul', (tester) async {
      await poser(
        tester,
        const EtatVide(icon: Icons.search_off, message: 'Aucun résultat.'),
      );
      expect(find.byType(Text), findsOneWidget);
    });
  });

  group('LigneFiche', () {
    const libelle = 'Date prévue';
    const valeur = 'sam. 14 nov. 2026';

    testWidgets('moins de 600 px : libellé à gauche, valeur au bord droit', (
      tester,
    ) async {
      // Police de test : 14 px par caractère ; textes courts pour tenir sur
      // une ligne.
      await poser(tester, const LigneFiche(label: 'Total', value: '12 €'));
      expect(tester.getTopLeft(find.text('Total')).dx, 0);
      expect(tester.getTopRight(find.text('12 €')).dx, 400);
      expect(
        tester.widget<Text>(find.text('Total')).style?.color,
        schema(tester).onSurfaceVariant,
      );
    });

    testWidgets('600 px et plus : colonne du libellé, valeur à sa suite', (
      tester,
    ) async {
      await poser(
        tester,
        const Column(
          children: [
            LigneFiche(label: libelle, value: valeur),
            LigneFiche(label: 'Équipement', value: null),
          ],
        ),
        width: 800,
      );
      const colonne = 800 * kLibelleFicheFraction + 16;
      expect(tester.getTopLeft(find.text(valeur)).dx, colonne);
      expect(tester.getTopLeft(find.text('Non renseigné')).dx, colonne);
      // Même ligne : la valeur commence avant le bas du libellé.
      expect(
        tester.getTopLeft(find.text(valeur)).dy,
        lessThan(tester.getBottomLeft(find.text(libelle)).dy),
      );
    });

    testWidgets('lue d\'un bloc', (tester) async {
      final semantics = tester.ensureSemantics();
      await poser(
        tester,
        const LigneFiche(label: libelle, value: null),
        width: 800,
      );
      expect(
        tester.getSemantics(find.text(libelle)),
        isSemantics(label: 'Date prévue\nNon renseigné'),
      );
      semantics.dispose();
    });
  });

  group('EnTeteFiche', () {
    testWidgets('nom en en-tête, sous-titre atténué, étiquettes, action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await poser(
        tester,
        EnTeteFiche(
          titre: 'Blonde',
          sousTitre: 'American Pale Ale · Recette de Zoé',
          etiquettes: const [Etiquette(label: 'En attente du réseau')],
          action: IconButton(
            tooltip: 'Plus d\'actions',
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          ),
        ),
      );
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(
        tester.widget<Text>(find.text('Blonde')).style,
        theme.textTheme.headlineSmall,
      );
      expect(
        tester.getSemantics(find.text('Blonde')),
        isSemantics(label: 'Blonde', isHeader: true),
      );
      final sousTitre = find.text('American Pale Ale · Recette de Zoé');
      expect(
        tester.widget<Text>(sousTitre).style?.color,
        theme.colorScheme.onSurfaceVariant,
      );
      // Nom, puis sous-titre, puis étiquettes ; action à droite du nom.
      expect(
        tester.getTopLeft(sousTitre).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Blonde')).dy),
      );
      expect(
        tester.getTopLeft(find.text('En attente du réseau')).dy,
        greaterThan(tester.getBottomLeft(sousTitre).dy),
      );
      expect(
        tester.getTopLeft(find.byTooltip('Plus d\'actions')).dx,
        greaterThan(tester.getTopRight(find.text('Blonde')).dx),
      );
      semantics.dispose();
    });

    testWidgets('sans sous-titre ni étiquette : le nom seul', (tester) async {
      await poser(tester, const EnTeteFiche(titre: 'Blonde', sousTitre: ''));
      expect(find.byType(Text), findsOneWidget);
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('texte × 2 sur 320 px : aucun débordement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await poser(
        tester,
        EnTeteFiche(
          titre: 'Une recette au nom vraiment très long',
          sousTitre: 'American Pale Ale · Recette de Zoé',
          etiquettes: const [
            Etiquette(label: 'En fermentation', ton: TonEtiquette.tertiaire),
            Etiquette(label: 'En attente du réseau'),
          ],
          action: IconButton(
            tooltip: 'Plus d\'actions',
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          ),
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('CarteSection', () {
    Widget carte() => const CarteSection(
      titre: 'Rendement',
      children: [LigneFiche(label: 'Évaporation', value: '3 l/h')],
    );

    testWidgets('carte du thème, titre en en-tête, marge de 16', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await poser(tester, carte(), width: 800);
      final s = schema(tester);
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(Card), matching: find.byType(Material)),
      );
      expect(material.color, s.surfaceContainerLow);
      expect(
        tester.getSemantics(find.text('Rendement')),
        isSemantics(label: 'Rendement', isHeader: true),
      );
      final bord = tester.getTopLeft(find.byType(Card));
      // Espace de 16 au-dessus de la carte, contenu à 16 de son bord.
      expect(bord, const Offset(0, 16));
      expect(tester.getTopLeft(find.text('Rendement')).dx, 16);
      expect(tester.getTopLeft(find.text('Évaporation')).dx, 16);
      expect(
        tester.getBottomLeft(find.byType(Card)).dy -
            tester.getBottomLeft(find.byType(LigneFiche)).dy,
        16,
      );
      semantics.dispose();
    });

    testWidgets('téléphone : déborde de 8 px, contenu aligné sur la colonne', (
      tester,
    ) async {
      await poser(
        tester,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: carte(),
        ),
      );
      expect(tester.getTopLeft(find.byType(Card)).dx, 16 - kDebordCarteCompact);
      expect(tester.getSize(find.byType(Card)).width, 400 - 32 + 16);
      expect(tester.getTopLeft(find.text('Rendement')).dx, 16);
      expect(tester.getTopLeft(find.text('Évaporation')).dx, 16);
    });

    testWidgets('repliable : sans marge basse', (tester) async {
      await poser(
        tester,
        const CarteSection(
          repliable: true,
          children: [
            SectionRepliable(
              titre: 'Déroulé',
              storageKey: 'deroule',
              children: [Text('Brassage')],
            ),
          ],
        ),
        width: 800,
      );
      expect(
        tester.getBottomLeft(find.byType(Card)).dy,
        tester.getBottomLeft(find.byType(SectionRepliable)).dy,
      );
    });

    Widget carteAction() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Builder(
        builder: (context) => CarteSection(
          action: true,
          children: [
            FilledButton(onPressed: () {}, child: const Text('Brasser')),
            Text(
              'Préparé sur cet appareil',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );

    testWidgets('action : primaryContainer, bord à 8 px sur téléphone', (
      tester,
    ) async {
      await poser(tester, carteAction());
      final material = tester.widget<Material>(
        find
            .descendant(of: find.byType(Card), matching: find.byType(Material))
            .first,
      );
      expect(material.color, schema(tester).primaryContainer);
      // Même débord qu'une carte de section, marge de 16 en haut, enfants
      // espacés de 8.
      expect(tester.getTopLeft(find.byType(Card)).dx, 16 - kDebordCarteCompact);
      expect(tester.getTopLeft(find.byType(FilledButton)).dx, 16);
      expect(
        tester.getTopLeft(find.byType(FilledButton)).dy -
            tester.getTopLeft(find.byType(Card)).dy,
        16,
      );
      expect(
        tester.getTopLeft(find.text('Préparé sur cet appareil')).dy -
            tester.getBottomLeft(find.byType(FilledButton)).dy,
        8,
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('action : contraste, thème ${brightness.name}', (
        tester,
      ) async {
        await poser(tester, carteAction(), brightness: brightness);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('contraste et cibles, thème ${brightness.name}', (
        tester,
      ) async {
        await poser(
          tester,
          Padding(
            padding: const EdgeInsets.all(16),
            child: CarteSection(
              titre: 'Notes',
              children: [
                const Text('Belle mousse.'),
                const TexteAbsent('Aucune note.'),
                TextButton(onPressed: () {}, child: const Text('Modifier')),
              ],
            ),
          ),
          brightness: brightness,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      });
    }
  });

  group('Etiquette sur une ligne choisie', () {
    BoxBorder? contour(WidgetTester tester, String label) =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .ancestor(
                            of: find.text(label),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .border;

    testWidgets('ton normal : contour outlineVariant sur la ligne choisie', (
      tester,
    ) async {
      await poser(
        tester,
        Column(
          children: [
            LigneListe(
              titre: 'Densité fausse',
              selected: true,
              etiquettes: const [
                Etiquette(label: 'Vous'),
                Etiquette(label: 'Refusé', ton: TonEtiquette.neutre),
              ],
              onTap: () {},
            ),
            LigneListe(
              titre: 'Mousse absente',
              etiquettes: const [Etiquette(label: 'Moi')],
              onTap: () {},
            ),
          ],
        ),
      );
      expect(
        contour(tester, 'Vous'),
        Border.all(color: schema(tester).outlineVariant),
      );
      // Un autre ton se distingue déjà du fond ; une ligne ordinaire non plus.
      expect(contour(tester, 'Refusé'), isNull);
      expect(contour(tester, 'Moi'), isNull);
    });
  });

  group('PageSecondaire', () {
    Future<GoRouter> ouvrir(
      WidgetTester tester,
      Widget page, {
      double width = 400,
    }) async {
      final app = TestApp();
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(app.container.dispose);
      final router = GoRouter(
        initialLocation: '/page',
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) => const Scaffold(body: Text('Accueil')),
          ),
          GoRoute(path: '/page', builder: (_, _) => page),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: app.container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('titre, retour vers le repli, liste centrée sur 840 px', (
      tester,
    ) async {
      final router = await ouvrir(
        tester,
        PageSecondaire(
          titre: 'Mes prix',
          body: Builder(
            builder: (context) => ListView(
              padding: PageSecondaire.marges(
                context,
                const EdgeInsets.symmetric(horizontal: 16),
              ),
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 48, key: ValueKey('ligne-$i')),
              ],
            ),
          ),
        ),
        width: 1400,
      );
      expect(find.widgetWithText(AppBar, 'Mes prix'), findsOneWidget);
      expect(find.byType(BandeauHorsLigne), findsNothing);
      // Liste sur toute la largeur, lignes centrées sur 840 px moins les
      // marges de la page.
      expect(tester.getSize(find.byType(ListView)).width, 1400);
      final ligne = find.byKey(const ValueKey('ligne-0'));
      expect(tester.getSize(ligne).width, kContentMaxWidth - 32);
      expect(tester.getTopLeft(ligne).dx, (1400 - kContentMaxWidth) / 2 + 16);
      // La molette fait défiler la page au-dessus de la marge latérale.
      final repere = find.byKey(const ValueKey('ligne-5'));
      final avant = tester.getTopLeft(repere).dy;
      final souris = TestPointer(1, PointerDeviceKind.mouse);
      souris.hover(const Offset(40, 400));
      await tester.sendEventToBinding(souris.scroll(const Offset(0, 100)));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(repere).dy, avant - 100);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/recettes');
      expect(find.text('Accueil'), findsOneWidget);
    });

    testWidgets('hors ligne : bandeau ; sans borne : toute la largeur', (
      tester,
    ) async {
      await ouvrir(
        tester,
        PageSecondaire(
          titre: 'Mes tickets',
          horsLigne: true,
          largeurMax: null,
          floatingActionButton: FloatingActionButton(
            onPressed: () {},
            child: const Icon(Icons.add),
          ),
          body: const SizedBox.expand(key: ValueKey('contenu')),
        ),
        width: 1400,
      );
      expect(find.byType(BandeauHorsLigne), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('contenu'))).width, 1400);
    });
  });
}
