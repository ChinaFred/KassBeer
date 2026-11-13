import 'package:brewing/brewing.dart'
    show
        ActualDayDuration,
        ActualDayKind,
        ActualStepDuration,
        ActualStepKind,
        DurationUpdateIssue,
        HopUse,
        StepStatus;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/brew_day/domain/plan_du_jour.dart';
import 'package:kass_beer/features/brews/domain/assemblage_deroule.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/deroule.dart';
import 'package:kass_beer/features/brews/domain/mise_a_jour_processus.dart';
import 'package:kass_beer/features/brews/presentation/choix_processus.dart';
import 'package:kass_beer/features/brews/presentation/libelles_deroule.dart';
import 'package:kass_beer/features/brews/presentation/maj_processus.dart';
import 'package:kass_beer/features/brews/presentation/section_deroule.dart';
import 'package:kass_beer/features/processes/domain/modele_exemple.dart';
import 'package:kass_beer/features/processes/domain/modele_processus.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/tickets/domain/ticket_screens.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

/// Prévu et réel sur la fiche d'un brassin, et « Mettre à jour mon processus
/// avec ce brassin » (ADR-010).

String Function() cles(String prefixe) {
  var n = 0;
  return () => '$prefixe-${n++}';
}

/// Texte sans espaces insécables, pour comparer à une chaîne lisible.
String lisible(String texte) => texte.replaceAll(nbsp, ' ');

/// Widget `Text` dont le texte, sans espaces insécables, vaut [texte].
Finder texte(String texte) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && lisible(w.data!) == texte,
);

const cascade = HopLine(
  name: 'Cascade',
  amount: Quantite.grammes(20),
  use: HopUse.dryHop,
  form: 'pellet',
);

const recetteAvecCru = RecipeContent(
  name: 'Blonde',
  brewSteps: [palier, ebullition],
  hops: [cascade],
);

/// Deux houblons à cru à J+3 et J+5 : deux journées « Houblonnage à cru ».
const recetteDeuxCrus = RecipeContent(
  name: 'Double',
  brewSteps: [palier, ebullition],
  hops: [
    HopLine(
      name: 'Citra',
      amount: Quantite.grammes(30),
      use: HopUse.dryHop,
      form: 'pellet',
      dayMin: 3 * 1440,
    ),
    HopLine(
      name: 'Mosaic',
      amount: Quantite.grammes(30),
      use: HopUse.dryHop,
      form: 'pellet',
      dayMin: 5 * 1440,
    ),
  ],
);

/// Modèle d'exemple de l'auteur : clés `p1-0` (journée Brassage), `p1-1`
/// (Mise en place du matériel, 30 min), `p1-2` (Désinfection du fermenteur,
/// 20), `p1-3` (Chauffe, 40), `p1-4` (Mouture, 20), `p1-10` (Rangement, 30),
/// `p1-12` (Désinfection du matériel, 10)…
ModeleProcessus exemple({
  String owner = 'uid-brasseur',
  ContenuModele? content,
}) => ModeleProcessus(
  id: 'p1',
  ownerUid: owner,
  ownerName: 'Bruno Brasseur',
  content: content ?? modeleExemple(cles('p1')),
);

Deroule derouleDe(RecipeContent recipe) => assemblerDeroule(
  templateId: 'p1',
  modele: exemple().content,
  recipe: recipe,
  nouvelleCle: cles('d'),
).deroule;

final deroule = derouleDe(recetteAvecCru);
final brassage = deroule.brassage!;
final cru = deroule.journees[1];

/// Étape [rang] de la journée de brassage.
String etape(int rang) => brassage.lignes[rang].key;

final brasse = DateTime(2026, 11, 4, 8);
DateTime h(int heure, int minute, [int seconde = 0]) =>
    DateTime(2026, 11, 4, heure, minute, seconde);

/// Mise en place 08:00–08:42 (42 min, prévu 30) ; désinfection 08:50–09:05
/// (15, prévu 20) ; chauffe 09:10–09:50 (40, déjà à cette durée) ; mouture
/// 10:00:00–10:00:20 (0 min, hors de 1 à 600).
final eventsBrassage = <BrewEvent>[
  debut('e1', etape(0), h(8, 0)),
  fin('f1', etape(0), h(8, 42)),
  debut('e2', etape(1), h(8, 50)),
  fin('f2', etape(1), h(9, 5)),
  debut('e3', etape(2), h(9, 10)),
  fin('f3', etape(2), h(9, 50)),
  debut('e4', etape(3), h(10, 0)),
  fin('f4', etape(3), h(10, 0, 20)),
];

Brew brassin({
  BrewStatus status = BrewStatus.fermenting,
  String owner = 'uid-brasseur',
  Deroule? process,
  RecipeContent recipe = recetteAvecCru,
}) => unBrassin(
  status: status,
  owner: owner,
  brewedAt: brasse,
  recipe: recipe,
  process: process ?? deroule,
);

Future<TestApp> ouvrir(
  WidgetTester tester, {
  Brew? brew,
  List<BrewEvent>? events,
  List<ModeleProcessus>? modeles,
  bool owner = true,
  bool offline = false,
  bool cache = false,
  bool publier = true,
  double width = 400,
  double height = 900,
}) async {
  final app = TestApp();
  await app.pump(tester, width: width, height: height);
  app.signIn(
    owner ? brewerUser : adminUser,
    member: owner ? brewerMember : adminMember,
    fromCache: offline,
  );
  app.brews.publish([brew ?? brassin()]);
  app.brews.publishEvents('b1', events ?? eventsBrassage);
  if (publier) {
    app.processes.publish(modeles ?? [exemple()], fromCache: cache);
  }
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go('/brassins/b1');
  await tester.pumpAndSettle();
  return app;
}

/// Ouvre le pli « Déroulé » de la fiche d'un brassin après le brassage.
Future<void> ouvrirDeroule(WidgetTester tester) async {
  final pli = find.text(TextesDeroule.titre);
  await tester.scrollUntilVisible(
    pli,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(pli.first);
  await tester.pumpAndSettle();
  await tester.tap(pli.first);
  await tester.pumpAndSettle();
}

/// Ouvre la feuille « Mettre à jour mon processus ».
Future<void> ouvrirFeuille(WidgetTester tester) async {
  await ouvrirDeroule(tester);
  final bouton = find.text(TextesMajProcessus.action);
  await Scrollable.ensureVisible(tester.element(bouton), alignment: 0.3);
  await tester.pumpAndSettle();
  await tester.tap(bouton);
  await tester.pumpAndSettle();
}

/// Amène [finder] à l'écran dans la feuille, puis le touche.
Future<void> appuyer(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Prévu et réel des journées de [brew] avec [events], comme sur la fiche.
Map<String, ActualDayDuration> dureesDe(Brew brew, List<BrewEvent> events) {
  final now = DateTime(2026, 11, 8, 12);
  return {
    for (final j in brew.deroule.journees)
      j.key: () {
        final plan = PlanDuJour.calculer(
          brew: brew,
          events: events,
          now: now,
          journee: j,
        );
        return plan.durees(
          close: journeeClose(brew: brew, journee: j, plan: plan),
        );
      }(),
  };
}

void main() {
  group('libellés de la fiche', () {
    TexteDuree? etapeDe(
      ActualStepKind kind,
      int prevu, [
      int? reel,
      StepStatus status = StepStatus.done,
    ]) => dureeEtapeReelle(
      ActualStepDuration(
        kind: kind,
        plannedMinutes: prevu,
        actualMinutes: reel,
      ),
      status,
    );

    test('étape faite : écart positif, négatif, nul, au-delà d\'une heure', () {
      final plus = etapeDe(ActualStepKind.measured, 45, 57)!;
      expect(lisible(plus.affiche), 'prévu 45 min · réel 57 min · +12 min');
      expect(lisible(plus.lu), 'prévu 45 min, réel 57 min, 12 minutes de plus');
      final moins = etapeDe(ActualStepKind.measured, 45, 40)!;
      expect(lisible(moins.affiche), 'prévu 45 min · réel 40 min · −5 min');
      expect(moins.lu, endsWith('5 minutes de moins'));
      final nul = etapeDe(ActualStepKind.measured, 45, 45)!;
      expect(lisible(nul.affiche), 'prévu 45 min · réel 45 min · 0 min');
      expect(nul.lu, endsWith('sans écart'));
      final long = etapeDe(ActualStepKind.measured, 90, 102)!;
      expect(lisible(long.affiche), 'prévu 1 h 30 · réel 1 h 42 · +12 min');
      expect(formatEcartMinutes(75).replaceAll(nbsp, ' '), '+1 h 15');
      expect(
        etapeDe(ActualStepKind.measured, 10, 11)!.lu,
        endsWith('1 minute de plus'),
      );
    });

    test('étape sans réel : sautée, non faite, à venir, en cours, sans fin ; '
        'action inchangée', () {
      final sautee = etapeDe(
        ActualStepKind.none,
        45,
        null,
        StepStatus.skipped,
      )!;
      expect(lisible(sautee.affiche), 'prévu 45 min · réel —');
      expect(lisible(sautee.lu), 'prévu 45 min, pas de durée réelle');
      expect(
        lisible(
          etapeDe(ActualStepKind.none, 45, null, StepStatus.notDone)!.affiche,
        ),
        'prévu 45 min · réel —',
      );
      final aVenir = etapeDe(
        ActualStepKind.none,
        45,
        null,
        StepStatus.pending,
      )!;
      expect(lisible(aVenir.affiche), 'prévu 45 min');
      expect(lisible(aVenir.lu), 'prévu 45 min');
      expect(
        lisible(etapeDe(ActualStepKind.running, 45)!.affiche),
        'prévu 45 min · réel en cours',
      );
      expect(
        lisible(etapeDe(ActualStepKind.missingEnd, 45)!.affiche),
        'prévu 45 min · réel sans heure de fin',
      );
      expect(etapeDe(ActualStepKind.action, 0), isNull);
      // Seuls nombre et unité sont soudés : la ligne se coupe entre les mots.
      final affiche = etapeDe(ActualStepKind.missingEnd, 45)!.affiche;
      expect(affiche, 'prévu 45${nbsp}min · réel sans heure de fin');
    });

    test('journée : réel, attentes, en cours, sans fin, jamais commencée', () {
      ActualDayDuration jour(
        ActualDayKind kind, {
        int? reel,
        int? entre,
        int sansFin = 0,
      }) => ActualDayDuration(
        kind: kind,
        plannedMinutes: 370,
        actualMinutes: reel,
        betweenStepsMinutes: entre,
        stepsWithoutEnd: sansFin,
        steps: const [],
      );
      final reel = dureeJourneeReelle(
        jour(ActualDayKind.measured, reel: 412, entre: 32),
      )!;
      expect(
        lisible(reel.affiche),
        'Durée totale : prévu 6 h 10 · réel 6 h 52, dont 32 min entre les '
        'étapes · +42 min',
      );
      expect(
        lisible(reel.lu),
        'Durée totale : prévue 6 h 10, réelle 6 h 52 dont 32 minutes entre '
        'les étapes, 42 minutes de plus que prévu.',
      );
      expect(
        lisible(
          dureeJourneeReelle(
            jour(ActualDayKind.measured, reel: 412, entre: 0),
          )!.affiche,
        ),
        'Durée totale : prévu 6 h 10 · réel 6 h 52 · +42 min',
      );
      expect(
        dureeJourneeReelle(
          jour(ActualDayKind.measured, reel: 370, entre: 0),
        )!.lu,
        endsWith('sans écart.'),
      );
      expect(
        lisible(dureeJourneeReelle(jour(ActualDayKind.running))!.affiche),
        'Durée totale : prévu 6 h 10 · réel en cours',
      );
      expect(
        lisible(
          dureeJourneeReelle(
            jour(ActualDayKind.missingEnd, sansFin: 1),
          )!.affiche,
        ),
        'Durée totale : prévu 6 h 10 · réel inconnu : 1 étape sans heure de '
        'fin',
      );
      expect(
        dureeJourneeReelle(jour(ActualDayKind.missingEnd, sansFin: 2))!.affiche,
        contains('2 étapes'),
      );
      expect(dureeJourneeReelle(jour(ActualDayKind.none)), isNull);
    });
  });

  group('durées proposées au processus', () {
    test('proposables, non proposées et raisons', () {
      final brew = brassin();
      final sansRangement = exemple().content;
      final modele = ContenuModele(
        name: sansRangement.name,
        notes: sansRangement.notes,
        journees: [
          for (final j in sansRangement.journees)
            JourneeModele(
              key: j.key,
              name: j.name,
              offsetDays: j.offsetDays,
              requiresRecipeBlock: j.requiresRecipeBlock,
              elements: [
                for (final e in j.elements)
                  if (e.key != 'p1-10') e,
              ],
            ),
        ],
      );
      final p = proposerMiseAJour(
        deroule: brew.deroule,
        durees: dureesDe(brew, eventsBrassage),
        modele: modele,
      );
      expect(p.groupes.map((g) => g.journee), ['Brassage']);
      final etapes = p.groupes.single.etapes;
      expect(etapes.map((e) => e.cle), ['p1-1', 'p1-2']);
      expect(etapes.map((e) => e.nom), [
        'Mise en place du matériel',
        'Désinfection du fermenteur',
      ]);
      expect(etapes.first.valeurs.single.minutes, 42);
      expect(etapes.first.dureeActuelle, 30);
      expect(etapes.first.repetee, isFalse);
      expect(p.dejaALaDuree, 1);
      expect(p.horsBornes, 1);
      expect(p.retirees, 1);
      // 18 étapes du modèle dans le brassin : 2 proposées, 3 ci-dessus.
      expect(p.sansDureeReelle, 13);
      expect(p.etapesDeLaRecette, isTrue);
      expect(
        TextesMajProcessus.nonProposees(p),
        'Non proposées : 13 sans durée réelle, 1 déjà à cette durée, 1 '
        'retirée du processus, 1 hors de 1 à 600 min. '
        '${TextesMajProcessus.recette}',
      );
    });

    test('étape renommée dans le processus : nom actuel', () {
      final brew = brassin();
      final base = exemple().content;
      final modele = avecDurees(base, const {});
      final renomme = ContenuModele(
        name: modele.name,
        journees: [
          for (final j in modele.journees)
            JourneeModele(
              key: j.key,
              name: j.name,
              offsetDays: j.offsetDays,
              requiresRecipeBlock: j.requiresRecipeBlock,
              elements: [
                for (final e in j.elements)
                  e.key == 'p1-1'
                      ? const ElementModele.etape(
                          key: 'p1-1',
                          name: 'Installation',
                          durationMin: 30,
                        )
                      : e,
              ],
            ),
        ],
      );
      final p = proposerMiseAJour(
        deroule: brew.deroule,
        durees: dureesDe(brew, eventsBrassage),
        modele: renomme,
      );
      expect(p.etape('p1-1')?.nom, 'Installation');
    });

    test('journées répétées : une valeur par journée, une étape du modèle', () {
      final process = derouleDe(recetteDeuxCrus);
      final brew = brassin(process: process, recipe: recetteDeuxCrus);
      final cru1 = process.journees[1];
      final cru2 = process.journees[2];
      expect(
        [cru1.name, cru2.name],
        ['Houblonnage à cru 1', 'Houblonnage à cru 2'],
      );
      expect(cru1.cleJourneeModele, cru2.cleJourneeModele);
      final desinfection1 = cru1.lignes.first.key;
      final desinfection2 = cru2.lignes.first.key;
      final mesure2 = cru2.lignes[1].key;
      final events = [
        debut('a1', desinfection1, DateTime(2026, 11, 7, 9)),
        fin('b1', desinfection1, DateTime(2026, 11, 7, 9, 12)),
        debut('a2', desinfection2, DateTime(2026, 11, 9, 9)),
        fin('b2', desinfection2, DateTime(2026, 11, 9, 9, 9)),
        // Mesure de densité à 5 min : déjà à cette durée, journée 2 seule.
        debut('a3', mesure2, DateTime(2026, 11, 9, 9, 10)),
        fin('b3', mesure2, DateTime(2026, 11, 9, 9, 15)),
      ];
      final p = proposerMiseAJour(
        deroule: process,
        durees: dureesDe(brew, events),
        modele: exemple().content,
      );
      final groupe = p.groupes.single;
      expect(groupe.journee, 'Houblonnage à cru');
      final e = groupe.etapes.single;
      expect(e.cle, 'p1-12');
      expect(e.repetee, isTrue);
      expect(e.valeurs.map((v) => (v.journee, v.minutes)), [
        ('Houblonnage à cru 1', 12),
        ('Houblonnage à cru 2', 9),
      ]);
      expect(p.dejaALaDuree, 1);
      expect(
        TextesMajProcessus.journeeNonProposee(
          const DureeDeJournee(
            journee: 'Houblonnage à cru 1',
            minutes: 10,
            raison: DurationUpdateIssue.unchanged,
          ),
        ).replaceAll(nbsp, ' '),
        'Houblonnage à cru 1 : réel 10 min, déjà à cette durée',
      );
      expect(
        TextesMajProcessus.journeeNonProposee(
          const DureeDeJournee(
            journee: 'Houblonnage à cru 2',
            minutes: 0,
            raison: DurationUpdateIssue.outOfBounds,
          ),
        ).replaceAll(nbsp, ' '),
        'Houblonnage à cru 2 : réel 0 min, hors de 1 à 600 min',
      );
      expect(
        TextesMajProcessus.journeeNonProposee(
          const DureeDeJournee(
            journee: 'Houblonnage à cru 2',
            minutes: null,
            raison: DurationUpdateIssue.noActual,
          ),
        ),
        'Houblonnage à cru 2 : pas de durée réelle',
      );
    });

    test('étape du modèle sans clé : ni proposée ni comptée ; clé retirée '
        'comptée une fois', () {
      final brew = brassin();
      final base = brew.deroule;
      final brassageSansCle = base.journees.first;
      // Mise en place : sans clé ; désinfection : clé absente du modèle,
      // portée par deux étapes.
      final etapes = [
        for (final (i, e) in brassageSansCle.etapes.indexed)
          i == 0
              ? EtapeDeroulee(ligne: e.ligne, origine: e.origine)
              : i == 1 || i == 2
              ? EtapeDeroulee(
                  ligne: e.ligne,
                  origine: e.origine,
                  cleEtapeModele: 'cle-retiree',
                )
              : e,
      ];
      final deroule = Deroule(
        templateId: base.templateId,
        templateName: base.templateName,
        journees: [
          JourneeDeroulee(
            key: brassageSansCle.key,
            name: brassageSansCle.name,
            offsetDays: 0,
            sourceEcart: brassageSansCle.sourceEcart,
            role: brassageSansCle.role,
            cleJourneeModele: brassageSansCle.cleJourneeModele,
            etapes: etapes,
          ),
          ...base.journees.skip(1),
        ],
      );
      final p = proposerMiseAJour(
        deroule: deroule,
        durees: dureesDe(brew, eventsBrassage),
        modele: exemple().content,
      );
      expect(p.etape('p1-1'), isNull);
      expect(p.etape('p1-2'), isNull);
      expect(p.retirees, 1);
      // Restent 15 clés du modèle : mouture hors bornes, 14 sans durée
      // réelle ; la chauffe porte la clé retirée.
      expect(p.horsBornes, 1);
      expect(p.dejaALaDuree, 0);
      expect(p.sansDureeReelle, 14);
      expect(p.vide, isTrue);
    });

    test('avecDurees : seule duration_min des étapes choisies change', () {
      final base = exemple().content;
      final change = avecDurees(base, const {'p1-1': 42});
      final avant = base.toFirestore();
      final apres = change.toFirestore();
      final etapesAvant =
          ((avant['sessions']! as List).first as Map)['steps'] as List;
      final etapesApres =
          ((apres['sessions']! as List).first as Map)['steps'] as List;
      expect((etapesApres.first as Map)['duration_min'], 42);
      expect(
        {...etapesApres.first as Map}..remove('duration_min'),
        {...etapesAvant.first as Map}..remove('duration_min'),
      );
      expect(etapesApres.skip(1).toList(), etapesAvant.skip(1).toList());
      expect(
        (apres['sessions']! as List).skip(1).toList(),
        (avant['sessions']! as List).skip(1).toList(),
      );
      expect(apres['name'], avant['name']);
      expect(dureesActuelles(change, ['p1-1', 'p1-5']), {'p1-1': 42});
    });
  });

  group('fiche : prévu et réel', () {
    testWidgets('lignes d\'étape et ligne de journée', (tester) async {
      await ouvrir(tester);
      await ouvrirDeroule(tester);
      expect(
        texte('Terminée · prévu 30 min · réel 42 min · +12 min'),
        findsOneWidget,
      );
      expect(
        texte('Terminée · prévu 20 min · réel 15 min · −5 min'),
        findsOneWidget,
      );
      expect(
        texte('Terminée · prévu 40 min · réel 40 min · 0 min'),
        findsOneWidget,
      );
      // Étapes jamais commencées d'un brassage terminé : pas de réel.
      expect(texte('À venir · prévu 45 min'), findsOneWidget);
      // 6 h prévues ; 08:00 à 10:00:20, dont 3 min entre les étapes.
      expect(
        texte(
          'Durée totale : prévu 6 h 00 · réel 2 h 00, dont 23 min entre les '
          'étapes · −4 h 00',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            'Mise en place du matériel, Terminée, .*prévu.30.min, '
            'réel.42.min, 12 minutes de plus',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('étape sans fin après le brassage : journée sans réel', (
      tester,
    ) async {
      await ouvrir(
        tester,
        events: [
          debut('e1', etape(0), h(8, 0)),
          fin('f1', etape(0), h(8, 30)),
          debut('e2', etape(1), h(8, 35)),
        ],
      );
      await ouvrirDeroule(tester);
      expect(
        texte('En cours · prévu 20 min · réel sans heure de fin'),
        findsOneWidget,
      );
      expect(
        texte(
          'Durée totale : prévu 6 h 00 · réel inconnu : 1 étape sans heure '
          'de fin',
        ),
        findsOneWidget,
      );
    });

    testWidgets('texte à 200 % sur 360 px : coupures entre les mots', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await ouvrir(
        tester,
        width: 360,
        height: 1600,
        events: [
          debut('e1', etape(0), h(8, 0)),
          fin('f1', etape(0), h(8, 30)),
          debut('e2', etape(1), h(8, 35)),
        ],
      );
      await ouvrirDeroule(tester);
      expect(tester.takeException(), isNull);
      bool lettre(String c) =>
          RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c);
      for (final attendu in [
        'En cours · prévu 20 min · réel sans heure de fin',
        'Durée totale : prévu 6 h 00 · réel inconnu : 1 étape sans heure de '
            'fin',
      ]) {
        final finder = texte(attendu);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final p = tester.renderObject<RenderParagraph>(
          find.descendant(of: finder, matching: find.byType(RichText)),
        );
        final plain = p.text.toPlainText();
        // Haut de chaque caractère : un caractère plus bas que le précédent
        // ouvre une ligne.
        double haut(int i) => p
            .getBoxesForSelection(
              TextSelection(baseOffset: i, extentOffset: i + 1),
            )
            .first
            .top;
        var lignes = 1;
        for (var i = 1; i < plain.length; i++) {
          if (haut(i) <= haut(i - 1)) continue;
          lignes++;
          // Aucune coupure au milieu d'un mot.
          expect(
            lettre(plain[i - 1]) && lettre(plain[i]),
            isFalse,
            reason: '$attendu, coupé à $i',
          );
        }
        expect(lignes, greaterThan(1), reason: attendu);
      }
    });

    testWidgets('journée jamais commencée : rien de neuf', (tester) async {
      await ouvrir(tester, events: const []);
      await ouvrirDeroule(tester);
      expect(find.textContaining('Durée totale'), findsNothing);
      expect(find.textContaining('prévu$nbsp'), findsNothing);
    });

    testWidgets('brassin sans processus : durées, aucune action', (
      tester,
    ) async {
      await ouvrir(
        tester,
        brew: unBrassin(
          status: BrewStatus.fermenting,
          brewedAt: brasse,
          recipe: recetteAvecCru,
        ),
        events: [
          debut('e1', palier.key, h(9, 0)),
          fin('f1', palier.key, h(9, 50)),
        ],
      );
      await ouvrirDeroule(tester);
      expect(
        texte('Terminée · prévu 45 min · réel 50 min · +5 min'),
        findsOneWidget,
      );
      expect(find.text(TextesMajProcessus.action), findsNothing);
    });

    testWidgets('autre membre : prévu et réel, aucun bouton', (tester) async {
      await ouvrir(tester, owner: false);
      await ouvrirDeroule(tester);
      expect(
        texte('Terminée · prévu 30 min · réel 42 min · +12 min'),
        findsOneWidget,
      );
      expect(find.text(TextesMajProcessus.action), findsNothing);
    });

    testWidgets('écran du jour inchangé', (tester) async {
      final app = TestApp()..now = h(8, 50);
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      app.brews.publish([brassin(status: BrewStatus.brewing)]);
      app.brews.publishEvents('b1', [
        debut('e1', etape(0), h(8, 0)),
        fin('f1', etape(0), h(8, 42)),
      ]);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins/b1/jour');
      await tester.pumpAndSettle();
      expect(find.textContaining('prévu$nbsp'), findsNothing);
      expect(find.textContaining('Durée totale'), findsNothing);
    });
  });

  group('Mettre à jour mon processus', () {
    testWidgets('brassin en cours : pas d\x27action', (tester) async {
      await ouvrir(tester, brew: brassin(status: BrewStatus.brewing));
      expect(find.text(TextesMajProcessus.action), findsNothing);
    });

    testWidgets('processus d\'un autre membre : pas d\'action', (tester) async {
      await ouvrir(tester, modeles: [exemple(owner: 'uid-autre')]);
      await ouvrirDeroule(tester);
      expect(find.text(TextesMajProcessus.action), findsNothing);
    });

    testWidgets('processus supprimé : message existant, pas d\'action', (
      tester,
    ) async {
      await ouvrir(tester, modeles: const []);
      await ouvrirDeroule(tester);
      expect(find.text(TextesDeroule.modeleSupprime), findsOneWidget);
      expect(find.text(TextesMajProcessus.action), findsNothing);
    });

    testWidgets('hors ligne sans cache : indisponible', (tester) async {
      await ouvrir(tester, modeles: const [], offline: true, cache: true);
      await ouvrirDeroule(tester);
      expect(find.text(TextesMajProcessus.horsLigne), findsOneWidget);
      expect(find.text(TextesMajProcessus.action), findsNothing);
    });

    testWidgets('panne de lecture : message et Réessayer', (tester) async {
      final app = await ouvrir(tester, publier: false);
      app.processes.all.addError(StateError('lecture refusée'));
      await tester.pumpAndSettle();
      await ouvrirDeroule(tester);
      expect(find.text(TextesMajProcessus.panne), findsOneWidget);
      expect(find.text(TextesMajProcessus.action), findsNothing);
    });

    testWidgets('rien à proposer : pas d\'action', (tester) async {
      await ouvrir(
        tester,
        events: [
          debut('e3', etape(2), h(9, 10)),
          fin('f3', etape(2), h(9, 50)),
        ],
      );
      await ouvrirDeroule(tester);
      expect(find.text(TextesMajProcessus.action), findsNothing);
    });

    testWidgets('feuille : lignes décochées, bouton chiffré, écriture de la '
        'seule durée, Annuler', (tester) async {
      final app = await ouvrir(tester);
      await ouvrirFeuille(tester);
      expect(find.text(TextesMajProcessus.titre), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FeuilleMajProcessus),
          matching: find.text(TextesMajProcessus.processus(kNomModeleExemple)),
        ),
        findsOneWidget,
      );
      expect(find.text(TextesMajProcessus.aide), findsOneWidget);
      expect(texte('processus 30 min → réel 42 min'), findsOneWidget);
      expect(texte('processus 20 min → réel 15 min'), findsOneWidget);
      final cases = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(cases.map((c) => c.value), [false, false]);
      expect(find.text(TextesMajProcessus.auMoinsUne), findsOneWidget);
      final bouton = find.widgetWithText(FilledButton, 'Mettre à jour');
      expect(tester.widget<FilledButton>(bouton).onPressed, isNull);
      expect(
        find.textContaining('Non proposées : 14 sans durée réelle'),
        findsOneWidget,
      );

      await appuyer(tester, find.text('Mise en place du matériel').last);
      await tester.pumpAndSettle();
      expect(find.text(TextesMajProcessus.auMoinsUne), findsNothing);
      await appuyer(tester, find.text('Mettre à jour 1 durée'));
      await tester.pumpAndSettle();

      final write = app.processes.writes.single;
      expect(write.kind, 'update');
      expect(write.id, 'p1');
      expect(write.ownerName, 'Bruno Brasseur');
      expect(
        write.content!.toFirestore(),
        avecDurees(exemple().content, const {'p1-1': 42}).toFirestore(),
      );
      expect(app.brews.writes, isEmpty);
      expect(
        find.text(TextesMajProcessus.misAJour(kNomModeleExemple, 1)),
        findsOneWidget,
      );

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(app.processes.writes.length, 2);
      expect(
        app.processes.writes.last.content!.toFirestore(),
        exemple().content.toFirestore(),
      );
      expect(
        find.text('Processus « $kNomModeleExemple » : 1 durée rétablie.'),
        findsOneWidget,
      );
    });

    test('annonces de « Annuler » : singulier, pluriel, hors ligne', () {
      expect(
        TextesMajProcessus.retabli('P', 3),
        'Processus « P » : 3 durées '
        'rétablies.',
      );
      expect(
        TextesMajProcessus.retabliHorsLigne('P', 3),
        'Processus « P » : 3 durées rétablies sur l\'appareil. Elles '
        'partiront au retour du réseau.',
      );
      expect(
        TextesMajProcessus.retabliHorsLigne('P', 1),
        'Processus « P » : 1 durée rétablie sur l\'appareil. Elle partira au '
        'retour du réseau.',
      );
    });

    testWidgets('plus rien à proposer pendant la feuille : « Fermer »', (
      tester,
    ) async {
      final app = await ouvrir(tester);
      await ouvrirFeuille(tester);
      app.processes.publish([
        exemple(
          content: avecDurees(exemple().content, const {
            'p1-1': 42,
            'p1-2': 15,
          }),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text(TextesMajProcessus.rien), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text(TextesMajProcessus.titre), findsNothing);
      expect(app.processes.writes, isEmpty);
    });

    testWidgets('deux durées : « Mettre à jour 2 durées »', (tester) async {
      final app = await ouvrir(tester);
      await ouvrirFeuille(tester);
      await appuyer(tester, find.text('Mise en place du matériel').last);
      await appuyer(tester, find.text('Désinfection du fermenteur').last);
      await tester.pumpAndSettle();
      await appuyer(tester, find.text('Mettre à jour 2 durées'));
      await tester.pumpAndSettle();
      expect(
        app.processes.writes.single.content!.toFirestore(),
        avecDurees(exemple().content, const {
          'p1-1': 42,
          'p1-2': 15,
        }).toFirestore(),
      );
      expect(
        find.text(TextesMajProcessus.misAJour(kNomModeleExemple, 2)),
        findsOneWidget,
      );
    });

    testWidgets('hors ligne, processus dans le cache : annonce sur '
        'l\'appareil', (tester) async {
      final app = await ouvrir(tester, offline: true, cache: true);
      await ouvrirFeuille(tester);
      await appuyer(tester, find.text('Mise en place du matériel').last);
      await tester.pumpAndSettle();
      await appuyer(tester, find.text('Mettre à jour 1 durée'));
      await tester.pumpAndSettle();
      expect(app.processes.writes.single.kind, 'update');
      expect(
        find.text(TextesMajProcessus.misAJourHorsLigne(kNomModeleExemple, 1)),
        findsOneWidget,
      );
    });

    testWidgets('refus du serveur : annoncé', (tester) async {
      final app = await ouvrir(tester);
      app.processes.serverAnswer = () =>
          Future<void>.error(StateError('refusé'));
      await ouvrirFeuille(tester);
      await appuyer(tester, find.text('Mise en place du matériel').last);
      await tester.pumpAndSettle();
      await appuyer(tester, find.text('Mettre à jour 1 durée'));
      await tester.pumpAndSettle();
      expect(
        find.text(TextesMajProcessus.refus(kNomModeleExemple)),
        findsOneWidget,
      );
    });

    testWidgets('modèle invalide : refusé dans la feuille, rien d\'écrit', (
      tester,
    ) async {
      final base = exemple().content;
      final long = ContenuModele(
        name: 'P' * (kNomModeleMaxLength + 1),
        journees: base.journees,
      );
      final app = await ouvrir(tester, modeles: [exemple(content: long)]);
      await ouvrirFeuille(tester);
      await appuyer(tester, find.text('Mise en place du matériel').last);
      await tester.pumpAndSettle();
      await appuyer(tester, find.text('Mettre à jour 1 durée'));
      await tester.pumpAndSettle();
      expect(find.text(TextesChoixProcessus.modeleInvalide), findsOneWidget);
      expect(app.processes.writes, isEmpty);
    });

    testWidgets('journées répétées : boutons radio, « Garder » au départ', (
      tester,
    ) async {
      final process = derouleDe(recetteDeuxCrus);
      final cru1 = process.journees[1];
      final cru2 = process.journees[2];
      final app = await ouvrir(
        tester,
        brew: brassin(process: process, recipe: recetteDeuxCrus),
        events: [
          debut('a1', cru1.lignes.first.key, DateTime(2026, 11, 7, 9)),
          fin('b1', cru1.lignes.first.key, DateTime(2026, 11, 7, 9, 12)),
          debut('a2', cru2.lignes.first.key, DateTime(2026, 11, 8, 9)),
          fin('b2', cru2.lignes.first.key, DateTime(2026, 11, 8, 9, 9)),
        ],
      );
      await ouvrirFeuille(tester);
      expect(
        texte('Désinfection du matériel · processus 10 min'),
        findsOneWidget,
      );
      expect(texte('Garder 10 min'), findsOneWidget);
      expect(texte('réel 12 min · Houblonnage à cru 1'), findsOneWidget);
      expect(texte('réel 9 min · Houblonnage à cru 2'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Mettre à jour'),
            )
            .onPressed,
        isNull,
      );
      await appuyer(tester, texte('réel 9 min · Houblonnage à cru 2'));
      await tester.pumpAndSettle();
      await appuyer(tester, find.text('Mettre à jour 1 durée'));
      await tester.pumpAndSettle();
      expect(
        app.processes.writes.single.content!.toFirestore(),
        avecDurees(exemple().content, const {'p1-12': 9}).toFirestore(),
      );
    });

    testWidgets('journées répétées, une seule valeur : case avec la journée', (
      tester,
    ) async {
      final process = derouleDe(recetteDeuxCrus);
      final cru1 = process.journees[1];
      await ouvrir(
        tester,
        brew: brassin(process: process, recipe: recetteDeuxCrus),
        events: [
          debut('a1', cru1.lignes.first.key, DateTime(2026, 11, 7, 9)),
          fin('b1', cru1.lignes.first.key, DateTime(2026, 11, 7, 9, 12)),
        ],
      );
      await ouvrirFeuille(tester);
      expect(
        texte('processus 10 min → réel 12 min · Houblonnage à cru 1'),
        findsOneWidget,
      );
      expect(
        texte('Houblonnage à cru 2 : pas de durée réelle'),
        findsOneWidget,
      );
      expect(find.byType(RadioListTile<int>), findsNothing);
    });

    testWidgets('deuxième usage : la valeur déjà reprise n\'est plus '
        'proposée', (tester) async {
      final repris = avecDurees(exemple().content, const {
        'p1-1': 42,
        'p1-2': 15,
      });
      await ouvrir(tester, modeles: [exemple(content: repris)]);
      await ouvrirDeroule(tester);
      expect(find.text(TextesMajProcessus.action), findsNothing);
    });
  });

  test('ticket : la feuille a son élément', () {
    expect(
      kTicketElements['/brassins/:id/fenetre/maj-processus'],
      'Mettre à jour mon processus',
    );
  });
}
