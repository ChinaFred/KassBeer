import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/etiquette.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/library/domain/description_divers.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/library/presentation/data_sources_screen.dart';
import 'package:kass_beer/features/library/presentation/section_description_divers.dart';
import 'package:kass_beer/features/library/presentation/texte_redige.dart';

import 'support/fakes.dart';
import 'support/library_fixtures.dart';

const _id = 'misc-mousse-irlandaise';
const _chemin = '/bibliotheque/divers/$_id';
typedef _T = TextesDescriptionDivers;

/// Ouvre la fiche du divers ; [description] : document de
/// `beer_misc_descriptions/{id}` lu, absent par défaut.
Future<TestApp> ouvrir(
  WidgetTester tester, {
  Map<String, dynamic>? description,
  bool offline = false,
  void Function(TestApp app)? before,
}) async {
  final app = TestApp();
  app.library.fiches[_id] = DocumentTrouve(
    FicheReferentiel.fromFirestore(NatureReferentiel.miscs, _id, miscDoc()),
  );
  if (description != null) {
    app.library.descriptions[_id] = DocumentTrouve(
      DescriptionDivers.fromFirestore(description),
    );
  }
  before?.call(app);
  await app.pump(tester, height: 2400);
  app.signIn(brewerUser, member: brewerMember, fromCache: offline);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(_chemin);
  await tester.pumpAndSettle();
  return app;
}

double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

const _mention = TextesRediges.mention;

void main() {
  testWidgets('décrit : résumé, rôles, moments, goût, mention, dans l\'ordre', (
    tester,
  ) async {
    final app = await ouvrir(tester, description: miscDescriptionDoc());
    expect(find.text(kTexteResume), findsOneWidget);
    expect(find.text('Clarifier'), findsOneWidget);
    expect(find.text('Autre usage'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Rôles : Clarifier, Autre usage'),
      findsOneWidget,
    );
    expect(find.text('Ébullition'), findsOneWidget);
    expect(find.text(kTexteEbullition), findsOneWidget);
    expect(find.text('Fermentation'), findsOneWidget);
    expect(find.text(kTexteFermentation), findsOneWidget);
    expect(find.text('Empâtage'), findsNothing);
    expect(find.text('Après ébullition'), findsNothing);
    expect(find.text('Embouteillage'), findsNothing);
    expect(find.text(TextesRediges.confianceFaible), findsNothing);
    expect(find.text(TextesDescriptionDivers.miseAJourMoments), findsNothing);
    // « Goût » s'affiche quand `changes_taste` est faux.
    expect(find.text(_T.titreGout), findsOneWidget);
    expect(find.text(_T.sansGout), findsOneWidget);
    final ordre = [
      'Valeurs',
      _T.titre,
      kTexteResume,
      'Clarifier',
      'Ébullition',
      'Fermentation',
      _T.titreGout,
      _T.sansGout,
      _mention,
      'Provenance',
    ];
    final positions = [for (final t in ordre) _y(tester, t)];
    expect(positions, [...positions]..sort());
    expect(app.library.descriptionsReads, [_id]);
    expect(app.library.aromesReads, isEmpty);
    expect(app.errors.reports, isEmpty);
  });

  testWidgets('ordre fixe des moments, libellés de l\'éditeur', (tester) async {
    await ouvrir(
      tester,
      description: miscDescriptionDoc(
        moments: {
          'bottling': {'text': kTexteFermentation},
          'fermentation': {'text': kTexteFermentation},
          'after_boil': {'text': kTexteEbullition},
          'boil': {'text': kTexteEbullition},
          'mash': {'text': kTexteEbullition},
        },
      ),
    );
    final titres = [
      'Empâtage',
      'Ébullition',
      'Après ébullition',
      'Fermentation',
      'Embouteillage',
    ];
    final positions = [for (final t in titres) _y(tester, t)];
    expect(positions, [...positions]..sort());
  });

  testWidgets('goût, confiance faible en tête, sans mention de relecture', (
    tester,
  ) async {
    await ouvrir(
      tester,
      description: miscDescriptionDoc(
        extra: {
          'confidence': 'low',
          'reviewed': false,
          'changes_taste': true,
          'taste': {'text': kTexteGout},
        },
      ),
    );
    expect(find.text(kTexteGout), findsOneWidget);
    expect(find.text(_T.sansGout), findsNothing);
    expect(find.text(TextesRediges.mention), findsOneWidget);
    expect(find.textContaining('relu'), findsNothing);
    expect(
      find.descendant(
        of: find.widgetWithText(Etiquette, TextesRediges.confianceFaible),
        matching: find.byIcon(Icons.info_outline),
      ),
      findsOneWidget,
    );
    final confiance = _y(tester, TextesRediges.confianceFaible);
    expect(_y(tester, _T.titre) < confiance, isTrue);
    expect(confiance < _y(tester, kTexteResume), isTrue);
    expect(_y(tester, kTexteGout) < _y(tester, TextesRediges.mention), isTrue);
  });

  testWidgets('mention en bodyMedium, onSurfaceVariant', (tester) async {
    await ouvrir(tester, description: miscDescriptionDoc());
    final context = tester.element(find.text(_mention));
    final theme = Theme.of(context);
    final texte = tester.widget<Text>(find.text(_mention));
    expect(texte.style?.color, theme.colorScheme.onSurfaceVariant);
    expect(texte.style?.fontSize, theme.textTheme.bodyMedium?.fontSize);
  });

  testWidgets('aucune clé de moment connue : mettre l\'application à jour', (
    tester,
  ) async {
    await ouvrir(
      tester,
      description: miscDescriptionDoc(
        moments: {
          'whirlpool': {'text': kTexteEbullition},
        },
      ),
    );
    expect(find.text(kTexteResume), findsOneWidget);
    expect(find.text('Clarifier'), findsOneWidget);
    expect(find.text(kTexteEbullition), findsNothing);
    expect(find.text(TextesDescriptionDivers.miseAJourMoments), findsOneWidget);
    expect(
      _y(tester, 'Clarifier') <
          _y(tester, TextesDescriptionDivers.miseAJourMoments),
      isTrue,
    );
  });

  testWidgets('unknown : aucune description, mention IA, sans Goût', (
    tester,
  ) async {
    await ouvrir(tester, description: miscDescriptionUnknownDoc());
    expect(find.text(_T.titre), findsOneWidget);
    expect(find.text(_T.inconnu), findsOneWidget);
    expect(find.text(TextesRediges.mention), findsOneWidget);
    expect(_y(tester, _T.inconnu) < _y(tester, TextesRediges.mention), isTrue);
    expect(find.text(_T.titreGout), findsNothing);
    expect(find.text(TextesRediges.confianceFaible), findsNothing);
  });

  testWidgets('document absent : ni Utilisation ni Goût, aucun rapport', (
    tester,
  ) async {
    final app = await ouvrir(tester);
    expect(find.text('Nom français'), findsOneWidget);
    expect(find.text(_T.titre), findsNothing);
    expect(find.text(_T.titreGout), findsNothing);
    expect(find.textContaining('Texte rédigé par une IA'), findsNothing);
    expect(app.errors.reports, isEmpty);
    expect(app.library.descriptionsReads, [_id]);
  });

  testWidgets('illisible : panne affichée, reste de la fiche, pas de bouton', (
    tester,
  ) async {
    await ouvrir(
      tester,
      before: (app) => app.library.descriptions[_id] =
          const DocumentIllisibleTrouve(DocumentIllisible('taste', 'x')),
    );
    expect(find.text(_T.illisible), findsOneWidget);
    expect(find.text('Nom français'), findsOneWidget);
    expect(find.text(_T.titreGout), findsNothing);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('chargement : le reste de la fiche n\'attend pas, Goût attend', (
    tester,
  ) async {
    final attente = Completer<void>();
    final app = TestApp();
    app.library.fiches[_id] = DocumentTrouve(
      FicheReferentiel.fromFirestore(NatureReferentiel.miscs, _id, miscDoc()),
    );
    app.library.descriptionsAttente[_id] = attente;
    app.library.descriptions[_id] = DocumentTrouve(
      DescriptionDivers.fromFirestore(miscDescriptionDoc()),
    );
    await app.pump(tester, height: 2400);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go(_chemin);
    await tester.pump();
    await tester.pump();
    expect(find.text('Nom français'), findsOneWidget);
    expect(find.text(_T.chargement), findsOneWidget);
    expect(find.text(_T.titreGout), findsNothing);
    attente.complete();
    await tester.pumpAndSettle();
    expect(find.text(_T.chargement), findsNothing);
    expect(find.text(kTexteResume), findsOneWidget);
    expect(find.text(_T.titreGout), findsOneWidget);
  });

  testWidgets('panne : message, Réessayer désactivé pendant la relecture', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      before: (app) => app.library.descriptionsErrors[_id] = Exception('refus'),
    );
    expect(find.text(_T.panne), findsOneWidget);
    expect(find.text('Nom français'), findsOneWidget);
    app.library.descriptionsErrors.clear();
    app.library.descriptions[_id] = DocumentTrouve(
      DescriptionDivers.fromFirestore(miscDescriptionDoc()),
    );
    final attente = Completer<void>();
    app.library.descriptionsAttente[_id] = attente;
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Lecture en cours'), findsOneWidget);
    final bouton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Lecture en cours'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(bouton.onPressed, isNull);
    attente.complete();
    await tester.pumpAndSettle();
    expect(find.text(_T.panne), findsNothing);
    expect(find.text(kTexteResume), findsOneWidget);
    expect(app.library.descriptionsReads, [_id, _id]);
  });

  testWidgets('hors ligne, absent du cache : indisponible, sans bouton', (
    tester,
  ) async {
    await ouvrir(
      tester,
      offline: true,
      before: (app) =>
          app.library.descriptions[_id] = const DocumentAbsentDuCache(),
    );
    expect(find.text(_T.horsLigne), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('hors ligne, lecture en échec : indisponible, relue au retour', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      offline: true,
      before: (app) =>
          app.library.descriptionsErrors[_id] = Exception('hors ligne'),
    );
    expect(find.text(_T.horsLigne), findsOneWidget);
    expect(find.text(_T.panne), findsNothing);
    expect(find.text('Réessayer'), findsNothing);
    app.library.descriptionsErrors.clear();
    app.library.descriptions[_id] = DocumentTrouve(
      DescriptionDivers.fromFirestore(miscDescriptionDoc()),
    );
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    expect(find.text(_T.horsLigne), findsNothing);
    expect(find.text(kTexteResume), findsOneWidget);
  });

  testWidgets('hors ligne, en cache : affiché normalement', (tester) async {
    await ouvrir(tester, offline: true, description: miscDescriptionDoc());
    expect(find.text(kTexteResume), findsOneWidget);
    expect(find.text(_T.horsLigne), findsNothing);
  });

  testWidgets('houblon : aucune lecture des descriptions de divers', (
    tester,
  ) async {
    final app = TestApp();
    app.library.fiches['hop-cascade'] = DocumentTrouve(
      FicheReferentiel.fromFirestore(
        NatureReferentiel.hops,
        'hop-cascade',
        hopDoc(),
      ),
    );
    await app.pump(tester, height: 2400);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/bibliotheque/houblons/hop-cascade');
    await tester.pumpAndSettle();
    expect(find.text('Acides alpha'), findsOneWidget);
    expect(app.library.descriptionsReads, isEmpty);
    expect(find.text(_T.titre), findsNothing);
  });

  testWidgets('texte agrandi à 200 % : aucun débordement', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await ouvrir(
      tester,
      description: miscDescriptionDoc(
        extra: {
          'confidence': 'low',
          'changes_taste': true,
          'taste': {'text': kTexteGout},
        },
      ),
    );
    await tester.scrollUntilVisible(
      find.text(kTexteGout),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.text(kTexteGout), findsOneWidget);
  });

  testWidgets('Sources des données : descriptions des divers', (tester) async {
    final app = TestApp();
    await app.pump(tester, height: 2400);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/sources-des-donnees');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(DataSourcesScreen.descriptionsDivers),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Descriptions des divers'), findsOneWidget);
    expect(find.text(DataSourcesScreen.descriptionsDivers), findsOneWidget);
  });
}
