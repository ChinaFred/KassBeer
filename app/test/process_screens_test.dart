import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/etats.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/processes/domain/modele_exemple.dart';
import 'package:kass_beer/features/processes/domain/modele_processus.dart';
import 'package:kass_beer/features/processes/domain/preference_processus.dart';
import 'package:kass_beer/features/processes/presentation/process_detail_screen.dart';
import 'package:kass_beer/features/processes/presentation/process_editor_screen.dart';
import 'package:kass_beer/features/processes/presentation/libelles_processus.dart';
import 'package:kass_beer/features/processes/presentation/process_list_screen.dart';

import 'support/fakes.dart';

const moi = 'uid-brasseur';

/// Clés successives, propres à chaque modèle construit.
String Function() cles(String prefixe) {
  var n = 0;
  return () => '$prefixe-${n++}';
}

ModeleProcessus modele(
  String id, {
  String owner = moi,
  String? ownerName = 'Bruno Brasseur',
  ContenuModele? content,
  bool pending = false,
}) => ModeleProcessus(
  id: id,
  ownerUid: owner,
  ownerName: ownerName,
  content: content ?? modeleExemple(cles(id)),
  hasPendingWrites: pending,
);

/// Modèle d'une seule journée, de [etapes] étapes plus la chronologie.
ContenuModele uneJournee(String name, {int etapes = 1}) => ContenuModele(
  name: name,
  journees: [
    JourneeModele(
      key: '$name-j',
      name: 'Brassage',
      offsetDays: 0,
      elements: [
        const ElementModele.bloc(
          key: 'bloc',
          nature: NatureElement.chronologieRecette,
        ),
        for (var i = 0; i < etapes; i++)
          ElementModele.etape(
            key: '$name-$i',
            name: 'Étape $i',
            durationMin: 5,
          ),
      ],
    ),
  ],
);

Future<TestApp> open(
  WidgetTester tester,
  String path, {
  void Function(TestApp app)? before,
  double width = 400,
  double height = 900,
}) async {
  final app = TestApp();
  before?.call(app);
  await app.pump(tester, width: width, height: height);
  app.signIn(brewerUser, member: brewerMember);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return app;
}

Future<void> ajouterJournee(
  WidgetTester tester,
  String name,
  String ecart,
) async {
  // L'annonce précédente masquerait le bouton.
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .removeCurrentSnackBar();
  await defiler(tester, 'Ajouter une journée');
  await tester.tap(find.text('Ajouter une journée'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Nom de la journée'),
    name,
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Écart (jours après le brassage)'),
    ecart,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
  await tester.pumpAndSettle();
}

/// Texte de l'éditeur, même hors de l'écran.
Finder hors(String text) => find.text(text, skipOffstage: false);

/// Fait défiler l'éditeur jusqu'à [text], qui peut n'être pas encore construit.
Future<void> defiler(WidgetTester tester, String text) async {
  final scrollable = find
      .descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  // Depuis le haut : le texte peut être au-dessus de la position actuelle.
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  for (var i = 0; i < 50 && find.text(text).evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
}

/// Ordre vertical des en-têtes de journée.
List<String> ordreJournees(WidgetTester tester, List<String> titres) {
  final positions = {for (final t in titres) t: tester.getTopLeft(hors(t)).dy};
  return [...titres]..sort((a, b) => positions[a]!.compareTo(positions[b]!));
}

void main() {
  group('résumé d\'une journée', () {
    test('étapes du modèle seules, puis le bloc', () {
      final j = modeleExemple(cles('r')).journees.first;
      expect(
        resumeJournee(j),
        '9 étapes · 4\u00a0h\u00a015 + chronologie de la recette',
      );
    });

    test('sans étape : le bloc seul', () {
      const j = JourneeModele(
        key: 'j',
        name: 'Houblonnage',
        offsetDays: 4,
        elements: [
          ElementModele.bloc(key: 'b', nature: NatureElement.houblonsACru),
        ],
      );
      expect(resumeJournee(j), 'Houblons à cru');
    });
  });

  group('liste', () {
    testWidgets('menu du compte : « Mes processus » sous « Mes prix »', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      app.processes.publish(const []);
      await tester.tap(find.byTooltip('Mon compte'));
      await tester.pumpAndSettle();
      final prix = tester.getTopLeft(find.text('Mes prix')).dy;
      final processus = tester.getTopLeft(find.text('Mes processus')).dy;
      expect(processus, greaterThan(prix));
      await tester.tap(find.text('Mes processus'));
      await tester.pumpAndSettle();
      expect(find.text(ProcessListScreen.aucun), findsOneWidget);
      // Retour à l'écran précédent.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(ProcessListScreen.aucun), findsNothing);
    });

    testWidgets('chargement, puis panne et Réessayer', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/processus');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(EtatChargement, skipOffstage: false), findsOneWidget);
      app.processes.all.addError(Exception('permission-denied'));
      await tester.pumpAndSettle();
      expect(find.text(ProcessListScreen.lectureImpossible), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('vide : modèle d\'exemple prérempli, écrit à « Enregistrer » '
        'seulement, proposé par défaut', (tester) async {
      final app = await open(
        tester,
        '/processus',
        before: (app) => app.processes.publish(const []),
      );
      expect(find.text(ProcessListScreen.aucun), findsOneWidget);
      // Les deux boutons de création sont dans l'état vide.
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.text(ProcessListScreen.partirExemple));
      await tester.pumpAndSettle();
      expect(find.text(ProcessEditorScreen.titreNouveau), findsOneWidget);
      expect(find.text(kNomModeleExemple), findsOneWidget);
      expect(find.text(kNoteModeleExemple), findsOneWidget);
      expect(hors('2. Houblonnage à cru · J+4'), findsOneWidget);
      expect(hors('3. Embouteillage · J+14'), findsOneWidget);
      expect(app.processes.writes, isEmpty);
      final interrupteur = tester.widget<SwitchListTile>(
        find.widgetWithText(
          SwitchListTile,
          ProcessDetailScreen.proposerParDefaut,
        ),
      );
      expect(interrupteur.value, isTrue);

      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final write = app.processes.writes.single;
      expect(write.kind, 'create');
      expect(write.ownerUid, moi);
      expect(write.ownerName, 'Bruno Brasseur');
      expect(write.content!.journees, hasLength(3));
      expect(app.preferencesProcessus.saved.single.templateId, write.id);
      expect(find.text('Processus enregistré.'), findsOneWidget);
      // La fiche du processus enregistré s'ouvre.
      expect(find.text(ProcessDetailScreen.titre), findsOneWidget);
    });

    testWidgets('miens puis groupe, par nom ; résumé, auteur, « Par défaut »', (
      tester,
    ) async {
      await open(
        tester,
        '/processus',
        before: (app) {
          app.processes.publish([
            modele('z', owner: 'uid-zoe', ownerName: 'Zoé'),
            modele('b', content: uneJournee('Brassage seul')),
            modele(
              'a',
              content: uneJournee('Avec embouteillage'),
              pending: true,
            ),
          ]);
          app.preferencesProcessus.publishDefault(moi, 'b');
        },
      );
      expect(find.text('Processus du groupe'), findsOneWidget);
      expect(find.text('3 journées · J+0, J+4, J+14'), findsOneWidget);
      expect(find.text('Zoé'), findsOneWidget);
      expect(find.text('Par défaut'), findsOneWidget);
      expect(find.text('En attente du réseau'), findsOneWidget);
      final a = tester.getTopLeft(find.text('Avec embouteillage')).dy;
      final b = tester.getTopLeft(find.text('Brassage seul')).dy;
      final z = tester.getTopLeft(find.text(kNomModeleExemple)).dy;
      expect(a, lessThan(b));
      expect(b, lessThan(z));
      expect(
        find.bySemanticsLabel('Brassage seul, 1 journée, par défaut'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('$kNomModeleExemple, 3 journées, de Zoé'),
        findsOneWidget,
      );
      // Un processus à soi : le bouton flottant de création revient.
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets(
      'document illisible : sa ligne, rapporté par le dépôt ; la fiche '
      'le dit',
      (tester) async {
        final app = await open(
          tester,
          '/processus',
          before: (app) =>
              app.processes.publish([modele('a')], illisibles: ['casse']),
        );
        expect(find.text('Processus illisible'), findsOneWidget);
        expect(
          find.text('Le document contient une valeur inattendue.'),
          findsOneWidget,
        );
        expect(find.text(kNomModeleExemple), findsOneWidget);
        await tester.tap(find.text('Processus illisible'));
        await tester.pumpAndSettle();
        expect(find.text(textesProcessus.illisible), findsOneWidget);
        expect(app.processes.writes, isEmpty);
      },
    );

    testWidgets('ligne : le double appui du lecteur d\'écran ouvre la fiche', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(
        tester,
        '/processus',
        before: (app) =>
            app.processes.publish([modele('b', content: uneJournee('Simple'))]),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel('Simple, 1 journée'),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.semantics.tap(find.semantics.byLabel('Simple, 1 journée'));
      await tester.pumpAndSettle();
      expect(find.text(ProcessDetailScreen.titre), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('panne de lecture : « Nouveau processus » reste proposé', (
      tester,
    ) async {
      await open(
        tester,
        '/processus',
        before: (app) =>
            app.processes.all.addError(Exception('permission-denied')),
      );
      expect(find.text(ProcessListScreen.lectureImpossible), findsOneWidget);
      await tester.tap(find.text(ProcessListScreen.nouveau));
      await tester.pumpAndSettle();
      expect(find.text(ProcessEditorScreen.titreNouveau), findsOneWidget);
    });

    testWidgets('hors ligne, jamais lue : indisponible', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember, fromCache: true);
      app.processes.publish(const [], fromCache: true);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/processus');
      await tester.pumpAndSettle();
      expect(find.text(ProcessListScreen.horsLigne), findsOneWidget);
      expect(find.text(ProcessListScreen.nouveau), findsOneWidget);
    });
  });

  group('fiche', () {
    testWidgets('journées, mention, résumé, étapes et blocs', (tester) async {
      await open(
        tester,
        '/processus/a',
        before: (app) => app.processes.publish([modele('a')]),
      );
      expect(find.text('1. Brassage · J+0'), findsOneWidget);
      expect(
        find.text('9 étapes · 4 h 15 + chronologie de la recette'),
        findsOneWidget,
      );
      expect(find.text('Mise en place du matériel · 30 min'), findsOneWidget);
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text(ProcessDetailScreen.copier), findsNothing);
      final mention = find.text('Seulement si la recette a des houblons à cru');
      await tester.scrollUntilVisible(mention, 200);
      expect(mention, findsOneWidget);
      await tester.scrollUntilVisible(find.text('Houblons à cru'), 100);
      expect(
        find.bySemanticsLabel('Bloc de la recette : Houblons à cru'),
        findsOneWidget,
      );
    });

    testWidgets('autre membre : lecture seule, « Copier dans mes processus »', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/processus/z',
        before: (app) => app.processes.publish([
          modele('z', owner: 'uid-zoe', ownerName: 'Zoé'),
        ]),
      );
      expect(find.text('Processus de Zoé'), findsOneWidget);
      expect(find.text('Modifier'), findsNothing);
      expect(find.text('Supprimer'), findsNothing);
      expect(find.text(ProcessDetailScreen.proposerParDefaut), findsNothing);
      expect(find.byTooltip('Plus d\'actions'), findsNothing);

      await tester.tap(find.text(ProcessDetailScreen.copier));
      await tester.pumpAndSettle();
      final write = app.processes.writes.single;
      expect(write.kind, 'copy');
      expect(write.ownerUid, moi);
      expect(write.content!.name, kNomModeleExemple);
      final source = modele('z').content;
      final anciennes = {
        for (final j in source.journees) ...[
          j.key,
          for (final e in j.elements) e.key,
        ],
      };
      for (final j in write.content!.journees) {
        expect(anciennes.contains(j.key), isFalse);
        for (final e in j.elements) {
          expect(anciennes.contains(e.key), isFalse);
        }
      }
      expect(find.text(ProcessDetailScreen.copied), findsOneWidget);

      app.container.read(routerProvider).go('/processus/z/modifier');
      await tester.pumpAndSettle();
      expect(find.text(ProcessEditorScreen.readOnlyMessage), findsOneWidget);
      expect(find.text('Voir le processus'), findsOneWidget);
      expect(find.text('Enregistrer'), findsNothing);
    });

    testWidgets('choix par défaut : écrit sous le lecteur, annoncé', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/processus/a',
        before: (app) => app.processes.publish([modele('a')]),
      );
      await tester.tap(find.text(ProcessDetailScreen.proposerParDefaut));
      await tester.pumpAndSettle();
      expect(app.preferencesProcessus.saved.single, (
        uid: moi,
        templateId: 'a',
      ));
      expect(
        find.text(ProcessDetailScreen.defaultOn(kNomModeleExemple)),
        findsOneWidget,
      );
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      await tester.tap(find.text(ProcessDetailScreen.proposerParDefaut));
      await tester.pumpAndSettle();
      expect(app.preferencesProcessus.saved.last, (uid: moi, templateId: null));
      expect(find.text(ProcessDetailScreen.defaultOff), findsOneWidget);
      // Le modèle lu par le groupe n'est pas écrit.
      expect(app.processes.writes, isEmpty);
    });

    testWidgets('suppression du défaut : annoncée, choix remis à la '
        'chronologie seule', (tester) async {
      final app = await open(
        tester,
        '/processus/a',
        before: (app) {
          app.processes.publish([modele('a')]);
          app.preferencesProcessus.publishDefault(moi, 'a');
          app.processes.serverAnswer = () async {};
        },
      );
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(
        find.text(ProcessDetailScreen.deleteTitle(kNomModeleExemple)),
        findsOneWidget,
      );
      expect(find.text(ProcessDetailScreen.deleteGroup), findsOneWidget);
      expect(find.text(ProcessDetailScreen.deleteDefault), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(app.processes.writes.single.kind, 'delete');
      expect(app.processes.writes.single.id, 'a');
      expect(app.preferencesProcessus.saved.single, (
        uid: moi,
        templateId: null,
      ));
      expect(find.text(ProcessDetailScreen.deleted), findsOneWidget);
    });

    testWidgets('suppression d\'un processus qui n\'est pas le défaut', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/processus/a',
        before: (app) => app.processes.publish([modele('a')]),
      );
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text(ProcessDetailScreen.deleteDefault), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(app.preferencesProcessus.saved, isEmpty);
    });

    testWidgets('dupliquer : « {nom} (copie) »', (tester) async {
      final app = await open(
        tester,
        '/processus/a',
        before: (app) => app.processes.publish([modele('a')]),
      );
      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dupliquer'));
      await tester.pumpAndSettle();
      final write = app.processes.writes.single;
      expect(write.kind, 'duplicate');
      expect(write.content!.name, '$kNomModeleExemple (copie)');
      expect(find.text(ProcessDetailScreen.duplicated), findsOneWidget);
    });

    testWidgets('choix par défaut en lecture, puis illisible : Réessayer', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/processus/a',
        before: (app) {
          app.processes.publish([modele('a')]);
          app.preferencesProcessus.enAttente(moi);
        },
      );
      expect(find.text(ProcessDetailScreen.lectureDefaut), findsOneWidget);
      SwitchListTile interrupteur() => tester.widget<SwitchListTile>(
        find.widgetWithText(
          SwitchListTile,
          ProcessDetailScreen.proposerParDefaut,
        ),
      );
      expect(interrupteur().onChanged, isNull);
      app.preferencesProcessus.of(moi).addError(Exception('unavailable'));
      await tester.pumpAndSettle();
      expect(find.text(ProcessDetailScreen.defaultUnreadable), findsOneWidget);
      expect(interrupteur().onChanged, isNull);
      // « Réessayer » relance la lecture.
      app.preferencesProcessus.publishDefault(moi, 'a');
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text(ProcessDetailScreen.choixPersonnel), findsOneWidget);
      expect(interrupteur().value, isTrue);
    });

    testWidgets('suppression refusée : le choix par défaut reste', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/processus/a',
        before: (app) {
          app.processes.publish([modele('a')]);
          app.preferencesProcessus.publishDefault(moi, 'a');
          app.processes.serverAnswer = () async =>
              throw Exception('permission-denied');
        },
      );
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(app.processes.writes.single.kind, 'delete');
      expect(app.preferencesProcessus.saved, isEmpty);
      expect(
        find.text('La suppression de « $kNomModeleExemple » a échoué.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'dupliquer : bloqué pendant la lecture du nom, une seule copie',
      (tester) async {
        final app = await open(
          tester,
          '/processus/a',
          before: (app) => app.processes.publish([modele('a')]),
        );
        final gate = Completer<void>();
        app.auth.tokenGate = gate;
        await tester.tap(find.byTooltip('Plus d\'actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dupliquer'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Duplication'), findsOneWidget);
        expect(find.byTooltip('Plus d\'actions'), findsNothing);
        gate.complete();
        await tester.pumpAndSettle();
        expect(app.processes.writes.single.kind, 'duplicate');
      },
    );

    testWidgets('absent du serveur', (tester) async {
      await open(
        tester,
        '/processus/x',
        before: (app) => app.processes.publish(const []),
      );
      expect(find.text(textesProcessus.absent), findsOneWidget);
      expect(find.text('Revenir à mes processus'), findsOneWidget);
    });
  });

  group('éditeur', () {
    testWidgets('journée vide refusée, défilement jusqu\'à elle', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/processus/nouveau',
        before: (app) => app.processes.publish(const []),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom du processus'),
        'Simple',
      );
      await ajouterJournee(tester, 'Embouteillage', '14');
      expect(hors('2. Embouteillage · J+14'), findsOneWidget);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(
        find.text('La journée « Embouteillage » n\'a aucune étape.'),
        findsOneWidget,
      );
      expect(app.processes.writes, isEmpty);
    });

    testWidgets('nom manquant : message, rien n\'est écrit', (tester) async {
      final app = await open(
        tester,
        '/processus/nouveau',
        before: (app) => app.processes.publish(const []),
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Donnez un nom au processus.'), findsOneWidget);
      expect(app.processes.writes, isEmpty);
    });

    testWidgets('journée 1 fixe : chronologie non retirable, renommer seul', (
      tester,
    ) async {
      await open(
        tester,
        '/processus/nouveau',
        before: (app) => app.processes.publish(const []),
      );
      expect(find.text('1. Brassage'), findsOneWidget);
      expect(find.text('J+0, jour du brassage'), findsOneWidget);
      expect(
        find.text('Obligatoire dans la journée de brassage'),
        findsOneWidget,
      );
      // Bloc seul dans la journée : ni déplacement ni retrait, donc pas de ⋮.
      expect(
        find.byTooltip('Actions sur « Chronologie de la recette »'),
        findsNothing,
      );
      expect(find.text('Insérer un bloc de la recette'), findsNothing);
      await tester.tap(find.byTooltip('Actions sur la journée « Brassage »'));
      await tester.pumpAndSettle();
      expect(find.text('Renommer la journée'), findsOneWidget);
      expect(find.text('Retirer la journée'), findsNothing);
    });

    testWidgets('tri automatique par écart, annoncé', (tester) async {
      await open(
        tester,
        '/processus/nouveau?modele=exemple',
        before: (app) => app.processes.publish(const []),
      );
      await ajouterJournee(tester, 'Soutirage', '7');
      expect(
        find.text('« Embouteillage » passe en journée 4.'),
        findsOneWidget,
      );
      expect(hors('3. Soutirage · J+7'), findsOneWidget);
      expect(hors('4. Embouteillage · J+14'), findsOneWidget);
      expect(
        ordreJournees(tester, [
          '4. Embouteillage · J+14',
          '2. Houblonnage à cru · J+4',
          '3. Soutirage · J+7',
        ]),
        [
          '2. Houblonnage à cru · J+4',
          '3. Soutirage · J+7',
          '4. Embouteillage · J+14',
        ],
      );
    });

    testWidgets('5 journées au plus', (tester) async {
      await open(
        tester,
        '/processus/nouveau?modele=exemple',
        before: (app) => app.processes.publish(const []),
      );
      await ajouterJournee(tester, 'Soutirage', '7');
      await ajouterJournee(tester, 'Dégustation', '30');
      await defiler(tester, 'Ajouter une journée');
      expect(find.text('5 journées au plus.'), findsOneWidget);
      final bouton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Ajouter une journée'),
          matching: find.byWidgetPredicate((w) => w is OutlinedButton),
        ),
      );
      expect(bouton.onPressed, isNull);
    });

    testWidgets('60 étapes au plus dans une journée, blocs compris', (
      tester,
    ) async {
      await open(
        tester,
        '/processus/p/modifier',
        before: (app) => app.processes.publish([
          modele('p', content: uneJournee('Plein', etapes: 59)),
        ]),
      );
      await defiler(tester, 'Ajouter une étape');
      expect(find.text('60 étapes au plus dans une journée.'), findsOneWidget);
      final bouton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Ajouter une étape'),
          matching: find.byWidgetPredicate((w) => w is OutlinedButton),
        ),
      );
      expect(bouton.onPressed, isNull);
    });

    testWidgets('bloc déjà placé : inactif, « Déjà dans … »', (tester) async {
      await open(
        tester,
        '/processus/nouveau?modele=exemple',
        before: (app) => app.processes.publish(const []),
      );
      await ajouterJournee(tester, 'Soutirage', '7');
      final insert = hors('Insérer un bloc de la recette');
      // Journées 2, 3 et 4 : un bouton chacune.
      expect(insert, findsNWidgets(3));
      // Le bouton de « Soutirage », juste sous son en-tête.
      await defiler(tester, '3. Soutirage · J+7');
      final enTete = tester.getTopLeft(find.text('3. Soutirage · J+7')).dy;
      final boutons = find.text('Insérer un bloc de la recette');
      final suivant = [
        for (var i = 0; i < boutons.evaluate().length; i++) boutons.at(i),
      ].firstWhere((b) => tester.getTopLeft(b).dy > enTete);
      await tester.tap(suivant);
      await tester.pumpAndSettle();
      expect(find.text('Déjà dans « Houblonnage à cru »'), findsOneWidget);
      expect(find.text('Déjà dans « Embouteillage »'), findsOneWidget);
    });

    testWidgets('choix par défaut non lu : décoché, grisé, rien n\'est écrit', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/processus/nouveau',
        before: (app) {
          app.processes.publish(const []);
          app.preferencesProcessus
              .of(moi)
              .add(DocumentAbsentDuCache<PreferenceProcessus>());
        },
      );
      final interrupteur = tester.widget<SwitchListTile>(
        find.widgetWithText(
          SwitchListTile,
          ProcessDetailScreen.proposerParDefaut,
        ),
      );
      expect(interrupteur.value, isFalse);
      expect(interrupteur.onChanged, isNull);
      expect(
        find.text('Votre choix actuel n\'a pas pu être lu.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom du processus'),
        'Simple',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(app.processes.writes.single.kind, 'create');
      expect(app.preferencesProcessus.saved, isEmpty);
    });

    testWidgets('défaut existant : décoché ; défaut supprimé : coché', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/processus/nouveau',
        before: (app) {
          app.processes.publish([modele('a')]);
          app.preferencesProcessus.publishDefault(moi, 'a');
        },
      );
      SwitchListTile interrupteur() => tester.widget<SwitchListTile>(
        find.widgetWithText(
          SwitchListTile,
          ProcessDetailScreen.proposerParDefaut,
        ),
      );
      expect(interrupteur().value, isFalse);
      expect(interrupteur().onChanged, isNotNull);
      // Le processus par défaut a disparu d'une lecture du serveur.
      app.processes.publish(const []);
      await tester.pumpAndSettle();
      expect(interrupteur().value, isTrue);
    });

    testWidgets('journée retirée : annoncée, « Annuler » la remet', (
      tester,
    ) async {
      await open(
        tester,
        '/processus/nouveau?modele=exemple',
        before: (app) => app.processes.publish(const []),
      );
      await defiler(tester, '3. Embouteillage · J+14');
      await tester.tap(
        find.byTooltip('Actions sur la journée « Embouteillage »'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer la journée'));
      await tester.pumpAndSettle();
      expect(find.text('Journée « Embouteillage » retirée.'), findsOneWidget);
      expect(hors('3. Embouteillage · J+14'), findsNothing);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(hors('3. Embouteillage · J+14'), findsOneWidget);
    });

    testWidgets('modification : écrit le contenu, garde les clés', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/processus/a/modifier',
        before: (app) => app.processes.publish([modele('a')]),
      );
      expect(find.text(ProcessEditorScreen.titreModifier), findsOneWidget);
      // Le choix par défaut se fait sur la fiche, pas à la modification.
      expect(find.text(ProcessDetailScreen.proposerParDefaut), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom du processus'),
        'Mon déroulé',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final write = app.processes.writes.single;
      expect(write.kind, 'update');
      expect(write.id, 'a');
      expect(write.content!.name, 'Mon déroulé');
      expect(
        write.content!.journees.map((j) => j.key),
        modele('a').content.journees.map((j) => j.key),
      );
      expect(app.preferencesProcessus.saved, isEmpty);
    });
  });
}
