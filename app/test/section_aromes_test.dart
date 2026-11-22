import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/etiquette.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/library/domain/aromes_houblon.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/library/presentation/data_sources_screen.dart';
import 'package:kass_beer/features/library/presentation/section_aromes.dart';
import 'package:kass_beer/features/library/presentation/texte_redige.dart';

import 'support/fakes.dart';
import 'support/library_fixtures.dart';

const _id = 'hop-cascade';
const _chemin = '/bibliotheque/houblons/$_id';

/// Ouvre la fiche du houblon Cascade ; [aromes] : document de
/// `beer_hop_aromas/hop-cascade` lu, absent par défaut.
Future<TestApp> ouvrir(
  WidgetTester tester, {
  Map<String, dynamic>? aromes,
  bool offline = false,
  void Function(TestApp app)? before,
}) async {
  final app = TestApp();
  app.library.fiches[_id] = DocumentTrouve(
    FicheReferentiel.fromFirestore(NatureReferentiel.hops, _id, hopDoc()),
  );
  if (aromes != null) {
    app.library.aromes[_id] = DocumentTrouve(
      AromesHoublon.fromFirestore(aromes),
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

void main() {
  testWidgets('décrit : descripteurs, usages, mention IA', (tester) async {
    final app = await ouvrir(tester, aromes: hopAromaDoc());
    expect(find.text(TextesAromes.titre), findsOneWidget);
    expect(find.text('Pamplemousse'), findsOneWidget);
    expect(find.text('Floral'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Descripteurs : Pamplemousse, Floral'),
      findsOneWidget,
    );
    expect(find.text('Ébullition longue (amertume)'), findsOneWidget);
    expect(find.text(kTexteAmertume), findsOneWidget);
    expect(find.text('Houblonnage à cru'), findsOneWidget);
    expect(find.text(kTexteCru), findsOneWidget);
    expect(find.text('Premier moût'), findsNothing);
    expect(find.text('Whirlpool'), findsNothing);
    expect(find.text(TextesRediges.confianceFaible), findsNothing);
    expect(find.text(TextesRediges.mention), findsOneWidget);
    expect(find.textContaining('relu'), findsNothing);
    // Mention sous le titre « Arômes », avant les descripteurs.
    final mention = tester.getTopLeft(find.text(TextesRediges.mention)).dy;
    expect(
      tester.getTopLeft(find.text(TextesAromes.titre)).dy < mention,
      isTrue,
    );
    expect(mention < tester.getTopLeft(find.text('Pamplemousse')).dy, isTrue);
    // Entre « Valeurs » et « Provenance ».
    final valeurs = tester.getTopLeft(find.text('Valeurs')).dy;
    final aromes = tester.getTopLeft(find.text(TextesAromes.titre)).dy;
    final provenance = tester.getTopLeft(find.text('Provenance')).dy;
    expect(valeurs < aromes && aromes < provenance, isTrue);
    expect(app.library.aromesReads, [_id]);
  });

  testWidgets('ordre fixe des usages, quel que soit l\'ordre du document', (
    tester,
  ) async {
    await ouvrir(
      tester,
      aromes: hopAromaDoc(
        uses: {
          'dry_hop': {'text': kTexteCru},
          'whirlpool': {'text': kTexteWhirlpool},
          'late_boil': {'text': kTexteWhirlpool},
          'bittering': {'text': kTexteAmertume},
          'first_wort': {'text': kTexteAmertume},
        },
      ),
    );
    final titres = [
      'Premier moût',
      'Ébullition longue (amertume)',
      'Fin d\'ébullition (10 min ou moins)',
      'Whirlpool',
      'Houblonnage à cru',
    ];
    final positions = [
      for (final t in titres) tester.getTopLeft(find.text(t)).dy,
    ];
    expect(positions, [...positions]..sort());
  });

  testWidgets(
    'confiance faible, document non relu : aucune mention de relecture',
    (tester) async {
      await ouvrir(
        tester,
        aromes: hopAromaDoc(extra: {'confidence': 'low', 'reviewed': false}),
      );
      expect(find.text(TextesRediges.confianceFaible), findsOneWidget);
      expect(find.text(TextesRediges.mention), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(Etiquette, TextesRediges.confianceFaible),
          matching: find.byIcon(Icons.info_outline),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.help_outline), findsNothing);
      expect(find.textContaining('relu'), findsNothing);
    },
  );

  testWidgets(
    'rendu inchangé par le widget commun : mention, confiance, style',
    (tester) async {
      await ouvrir(tester, aromes: hopAromaDoc(extra: {'confidence': 'low'}));
      const mention = TextesRediges.mention;
      // Titre, mention, « Confiance faible », descripteurs : dans cet ordre.
      final ordre = [
        TextesAromes.titre,
        mention,
        TextesRediges.confianceFaible,
        'Pamplemousse',
        'Ébullition longue (amertume)',
        'Provenance',
      ];
      final positions = [
        for (final t in ordre) tester.getTopLeft(find.text(t)).dy,
      ];
      expect(positions, [...positions]..sort());
      final theme = Theme.of(tester.element(find.text(mention)));
      final texte = tester.widget<Text>(find.text(mention));
      expect(texte.style?.color, theme.colorScheme.onSurfaceVariant);
      expect(texte.style?.fontSize, theme.textTheme.bodyMedium?.fontSize);
      expect(find.byType(MentionTexteRedige), findsOneWidget);
      expect(find.byType(EtiquetteConfianceFaible), findsOneWidget);
      // Aucune section des divers sur la fiche d'un houblon.
      expect(find.text('Utilisation'), findsNothing);
      expect(find.text('Goût'), findsNothing);
    },
  );

  testWidgets('usage absent et clé inconnue : rien pour eux', (tester) async {
    await ouvrir(
      tester,
      aromes: hopAromaDoc(
        uses: {
          'whirlpool': {'text': kTexteWhirlpool},
          'hop_stand': {'text': kTexteCru},
        },
      ),
    );
    expect(find.text('Whirlpool'), findsOneWidget);
    expect(find.text(kTexteWhirlpool), findsOneWidget);
    expect(find.text(kTexteCru), findsNothing);
    expect(find.text('Houblonnage à cru'), findsNothing);
    expect(find.text(TextesRediges.miseAJour), findsNothing);
  });

  testWidgets('aucune clé d\'usage connue : mettre l\'application à jour', (
    tester,
  ) async {
    await ouvrir(
      tester,
      aromes: hopAromaDoc(
        uses: {
          'hop_stand': {'text': kTexteCru},
        },
      ),
    );
    expect(find.text('Pamplemousse'), findsOneWidget);
    expect(find.text(TextesRediges.miseAJour), findsOneWidget);
    expect(find.text(TextesRediges.mention), findsOneWidget);
  });

  testWidgets('unknown : aucune description, mention IA', (tester) async {
    await ouvrir(tester, aromes: hopAromaUnknownDoc());
    expect(find.text(TextesAromes.titre), findsOneWidget);
    expect(find.text(TextesAromes.inconnu), findsOneWidget);
    expect(find.text(TextesRediges.mention), findsOneWidget);
    expect(find.textContaining('relu'), findsNothing);
    expect(find.text(TextesRediges.confianceFaible), findsNothing);
  });

  testWidgets('document absent : ni titre ni rapport', (tester) async {
    final app = await ouvrir(tester);
    expect(find.text('Acides alpha'), findsOneWidget);
    expect(find.text(TextesAromes.titre), findsNothing);
    expect(app.errors.reports, isEmpty);
    expect(app.library.aromesReads, [_id]);
  });

  testWidgets('illisible : panne affichée, reste de la fiche, pas de bouton', (
    tester,
  ) async {
    await ouvrir(
      tester,
      before: (app) => app.library.aromes[_id] = const DocumentIllisibleTrouve(
        DocumentIllisible('status', 'x'),
      ),
    );
    expect(find.text(TextesAromes.illisible), findsOneWidget);
    expect(find.text('Acides alpha'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('chargement : le reste de la fiche n\'attend pas', (
    tester,
  ) async {
    final attente = Completer<void>();
    final app = TestApp();
    app.library.fiches[_id] = DocumentTrouve(
      FicheReferentiel.fromFirestore(NatureReferentiel.hops, _id, hopDoc()),
    );
    app.library.aromesAttente[_id] = attente;
    app.library.aromes[_id] = DocumentTrouve(
      AromesHoublon.fromFirestore(hopAromaDoc()),
    );
    await app.pump(tester, height: 2400);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go(_chemin);
    await tester.pump();
    await tester.pump();
    expect(find.text('Acides alpha'), findsOneWidget);
    expect(find.text(TextesAromes.chargement), findsOneWidget);
    attente.complete();
    await tester.pumpAndSettle();
    expect(find.text(TextesAromes.chargement), findsNothing);
    expect(find.text('Pamplemousse'), findsOneWidget);
  });

  testWidgets('panne : message, Réessayer désactivé pendant la relecture', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      before: (app) => app.library.aromesErrors[_id] = Exception('refus'),
    );
    expect(find.text(TextesAromes.panne), findsOneWidget);
    expect(find.text('Acides alpha'), findsOneWidget);
    app.library.aromesErrors.clear();
    app.library.aromes[_id] = DocumentTrouve(
      AromesHoublon.fromFirestore(hopAromaDoc()),
    );
    final attente = Completer<void>();
    app.library.aromesAttente[_id] = attente;
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
    expect(find.text(TextesAromes.panne), findsNothing);
    expect(find.text('Pamplemousse'), findsOneWidget);
    expect(app.library.aromesReads, [_id, _id]);
  });

  testWidgets('hors ligne, absent du cache : indisponible, sans bouton', (
    tester,
  ) async {
    await ouvrir(
      tester,
      offline: true,
      before: (app) => app.library.aromes[_id] = const DocumentAbsentDuCache(),
    );
    expect(find.text(TextesAromes.horsLigne), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('hors ligne, lecture en échec : indisponible, sans bouton', (
    tester,
  ) async {
    await ouvrir(
      tester,
      offline: true,
      before: (app) => app.library.aromesErrors[_id] = Exception('hors ligne'),
    );
    expect(find.text(TextesAromes.horsLigne), findsOneWidget);
    expect(find.text(TextesAromes.panne), findsNothing);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('hors ligne, en cache : affiché normalement', (tester) async {
    await ouvrir(tester, offline: true, aromes: hopAromaDoc());
    expect(find.text('Pamplemousse'), findsOneWidget);
    expect(find.text(TextesAromes.horsLigne), findsNothing);
  });

  testWidgets('autre nature : aucune lecture des arômes', (tester) async {
    final app = TestApp();
    app.library.fiches['bjcp2021-21a'] = DocumentTrouve(
      FicheReferentiel.fromFirestore(
        NatureReferentiel.styles,
        'bjcp2021-21a',
        styleDoc(),
      ),
    );
    await app.pump(tester, height: 2400);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/bibliotheque/styles/bjcp2021-21a');
    await tester.pumpAndSettle();
    expect(find.text('21 · IPA'), findsOneWidget);
    app.container.read(routerProvider).go('/bibliotheque/levures/inconnue');
    await tester.pumpAndSettle();
    expect(app.library.aromesReads, isEmpty);
    expect(find.text(TextesAromes.titre), findsNothing);
  });

  testWidgets('Sources des données : descriptions aromatiques', (tester) async {
    final app = TestApp();
    await app.pump(tester, height: 2400);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/sources-des-donnees');
    await tester.pumpAndSettle();
    expect(find.byType(DataSourcesScreen), findsOneWidget);
    // La section suit le texte de licence de srm2hex : hors de l'écran au départ.
    await tester.scrollUntilVisible(
      find.text(DataSourcesScreen.aromesHoublons),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Descriptions aromatiques'), findsOneWidget);
    expect(find.text(DataSourcesScreen.aromesHoublons), findsOneWidget);
  });
}
