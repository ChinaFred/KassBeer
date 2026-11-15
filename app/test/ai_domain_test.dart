import 'dart:convert';
import 'dart:io';

import 'package:brewing/brewing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/admin/domain/postes_ia.dart';
import 'package:kass_beer/features/ai/data/ai_repository.dart';
import 'package:kass_beer/features/ai/domain/comptes_ia.dart';
import 'package:kass_beer/features/ai/domain/reglages_ia.dart';
import 'package:kass_beer/features/ai/presentation/ligne_ia_ce_mois.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/recipes/domain/assistant_recette.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/ai_fakes.dart';

/// Postes, réglages, comptes de l'IA (ADR-016) et données de l'assistant
/// (ADR-015) : lecture stricte, aucune borne ni tarif en Dart (P60).
void main() {
  group('postes de coût (ADR-016, section 3)', () {
    test('postes_ia.dart rejoue test-fixtures/ai_cost_centers.json', () {
      final fixture =
          jsonDecode(
                File(
                  '../test-fixtures/ai_cost_centers.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final postes = (fixture['cost_centers'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        [for (final p in kPostesIa) (p.cle, p.libelle, p.adr)],
        [for (final p in postes) (p['key'], p['label'], p['adr'])],
      );
      expect(posteIa(kPosteAssistantRecette)?.libelle, 'Assistant de recette');
      expect(libellePosteIa('poste_inconnu'), 'poste_inconnu');
    });
  });

  group('politique (ai_config/policy)', () {
    Map<String, dynamic> doc(Map<String, Object?> poste) => {
      'version': 1,
      'features': {kPosteAssistantRecette: poste},
      'updated_by_uid': 'uid-admin',
    };
    const lisible = {
      'model': 'claude-sonnet-5-5',
      'effort': 'medium',
      'members_enabled': false,
      'turns_per_day': 20,
      'founder_turns_per_day': 60,
      'turns_per_conversation': 20,
    };

    test('réglage lu, limite selon le profil', () {
      final p = PolitiqueIa.fromFirestore(doc(lisible));
      final r = p.reglage(kPosteAssistantRecette)!;
      expect(r, reglageAssistant);
      expect(r.limiteDuJour(fondateur: false), 20);
      expect(r.limiteDuJour(fondateur: true), 60);
    });

    test('poste illisible, autre poste absent', () {
      final p = PolitiqueIa.fromFirestore(
        doc({...lisible, 'members_enabled': 'oui'}),
      );
      expect(p.poste(kPosteAssistantRecette), isA<ReglagePosteIllisible>());
      expect(p.poste('autre'), isA<ReglagePosteAbsent>());
      expect(p.reglage(kPosteAssistantRecette), isNull);
      expect(
        PolitiqueIa.fromFirestore(
          doc({...lisible, 'turns_per_day': 2.5}),
        ).poste(kPosteAssistantRecette),
        isA<ReglagePosteIllisible>(),
      );
    });

    test('aucune borne haute en Dart : 101 se lit, le serveur refuse', () {
      final p = PolitiqueIa.fromFirestore(
        doc({...lisible, 'turns_per_day': 101}),
      );
      expect(p.reglage(kPosteAssistantRecette)!.toursParJour, 101);
    });

    test('version inconnue : document illisible', () {
      expect(
        () => PolitiqueIa.fromFirestore({'version': 2, 'features': {}}),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('argument de saveAiSettings : version et postes connus seuls', () {
      final actuelle = PolitiqueIa.fromFirestore(doc(lisible));
      final arg = PolitiqueIa.argument(
        actuelle: actuelle,
        connus: [kPosteAssistantRecette],
        cle: kPosteAssistantRecette,
        reglage: const ReglagePosteIa(
          modele: 'claude-haiku-5-5',
          effort: null,
          ouvertAuxMembres: true,
          toursParJour: 10,
          toursFondateurParJour: 30,
          toursParConversation: 8,
        ),
      );
      expect(arg, {
        'version': 1,
        'features': {
          kPosteAssistantRecette: {
            'model': 'claude-haiku-5-5',
            'effort': null,
            'members_enabled': true,
            'turns_per_day': 10,
            'founder_turns_per_day': 30,
            'turns_per_conversation': 8,
          },
        },
      });
    });
  });

  group('grille (ai_config/pricing)', () {
    final data = {
      'version': 1,
      'checked_on': '2026-08-01',
      'source': '',
      'models': {
        'claude-sonnet-5-5': {
          'label': 'Sonnet 5.5',
          'input_usd_per_mtok': 2,
          'output_usd_per_mtok': 10,
          'cache_write_usd_per_mtok': 2.5,
          'cache_read_usd_per_mtok': 0.2,
          'efforts': ['low', 'medium'],
        },
      },
    };

    test('lue, à revérifier après 90 jours', () {
      final g = GrilleTarifaire.fromFirestore(data);
      expect(g.modele('claude-sonnet-5-5')!.efforts, ['low', 'medium']);
      expect(g.aReverifier(DateTime(2026, 10, 30)), isFalse);
      expect(g.aReverifier(DateTime(2026, 10, 31)), isTrue);
    });

    test('argument : même forme que le document, source toujours écrite', () {
      final g = GrilleTarifaire.fromFirestore(data);
      expect(g.versArgument(), data);
    });

    test('date hors calendrier : illisible', () {
      expect(
        () => GrilleTarifaire.fromFirestore({
          ...data,
          'checked_on': '2026-02-30',
        }),
        throwsA(isA<DocumentIllisible>()),
      );
    });
  });

  group('comptes et tours restants', () {
    final now = DateTime(2026, 11, 15, 21);
    final minuit = DateTime(2026, 11, 16);
    LectureIa<PolitiqueIa> politique = politiqueLue(reglageAssistant);
    RechercheDocument<QuotasIa> quotas(int count, DateTime resets) =>
        DocumentTrouve(
          QuotasIa.fromFirestore({
            'features': {
              kPosteAssistantRecette: {
                'day': '20261115',
                'count': count,
                'resets_at': Timestamp.fromDate(resets),
              },
            },
          }),
        );
    PolitiqueIa p() =>
        (politique.document as DocumentTrouve<PolitiqueIa>).value;

    test('limite du profil moins le compte du jour', () {
      final t =
          toursRestants(
                politique: p(),
                quotas: quotas(3, minuit),
                poste: kPosteAssistantRecette,
                fondateur: false,
                now: now,
              )
              as ToursConnus;
      expect((t.restants, t.limite, t.repriseLe), (17, 20, minuit));
      final f =
          toursRestants(
                politique: p(),
                quotas: quotas(3, minuit),
                poste: kPosteAssistantRecette,
                fondateur: true,
                now: now,
              )
              as ToursConnus;
      expect((f.restants, f.limite), (57, 60));
    });

    test('resets_at passé : compte à 0 ; aucun document : compte à 0', () {
      final passe =
          toursRestants(
                politique: p(),
                quotas: quotas(20, now.subtract(const Duration(hours: 1))),
                poste: kPosteAssistantRecette,
                fondateur: false,
                now: now,
              )
              as ToursConnus;
      expect(passe.restants, 20);
      final absent =
          toursRestants(
                politique: p(),
                quotas: const DocumentAbsent(),
                poste: kPosteAssistantRecette,
                fondateur: false,
                now: now,
              )
              as ToursConnus;
      expect(absent.restants, 20);
    });

    test('politique ou compteur illisible : inconnu', () {
      expect(
        toursRestants(
          politique: null,
          quotas: const DocumentAbsent(),
          poste: kPosteAssistantRecette,
          fondateur: false,
          now: now,
        ),
        isA<ToursInconnus>(),
      );
      for (final q in <RechercheDocument<QuotasIa>?>[
        null,
        const DocumentIllisibleTrouve('x'),
        const DocumentAbsentDuCache(),
      ]) {
        expect(
          toursRestants(
            politique: p(),
            quotas: q,
            poste: kPosteAssistantRecette,
            fondateur: false,
            now: now,
          ),
          isA<ToursInconnus>(),
        );
      }
    });

    test('compte du mois : compteurs absents à 0, total des postes', () {
      final c = CompteMoisIa.fromFirestore('2026-11_uid', {
        'month': '2026-11',
        'uid': 'uid',
        'member_email': 'Bruno@Exemple.fr',
        'features': {
          kPosteAssistantRecette: {'calls': 3, 'cost_usd': 0.12},
          'autre': {'calls': 2, 'unpriced_calls': 2},
        },
      });
      expect(c.email, 'bruno@exemple.fr');
      expect(c.total.appels, 5);
      expect(c.total.sansMontant, 2);
      expect(c.total.montantUsd, closeTo(0.12, 1e-9));
    });

    test('mois : clé, identifiant, mois précédents', () {
      expect(cleMois(DateTime(2026, 1, 3)), '2026-01');
      expect(idCompteMois('2026-11', 'u1'), '2026-11_u1');
      expect(moisAvant(DateTime(2026, 1, 3), 1), (annee: 2025, mois: 12));
      expect(moisAvant(DateTime(2026, 11, 3), 12), (annee: 2025, mois: 11));
    });
  });

  group('ligne « IA ce mois »', () {
    test('montants : stockés, jamais recalculés', () {
      expect(formatMontantUsd(0.42), '≈\u00a00,42\u00a0\$');
      expect(formatMontantUsd(0.004), '<\u00a00,01\u00a0\$');
      expect(
        texteComptesDuMois(desComptes(appels: 12, montant: 0.42)),
        'IA ce mois : 12 tours, ≈\u00a00,42\u00a0\$',
      );
      expect(
        texteComptesDuMois(
          desComptes(appels: 12, sansMontant: 2, montant: 0.4),
        ),
        'IA ce mois : 12 tours, ≈\u00a00,40\u00a0\$ (2 sans montant)',
      );
      expect(
        texteComptesDuMois(desComptes(appels: 12, sansMontant: 12)),
        'IA ce mois : 12 tours, montant inconnu',
      );
    });

    const fermee = AsyncData(
      LectureIa<PolitiqueIa>(DocumentAbsent(), fromCache: false),
    );
    final ouverte = AsyncData(
      politiqueLue(
        const ReglagePosteIa(
          modele: 'claude-sonnet-5-5',
          effort: 'medium',
          ouvertAuxMembres: true,
          toursParJour: 20,
          toursFondateurParJour: 60,
          toursParConversation: 20,
        ),
      ),
    );
    const sansCompte = AsyncData<LectureIa<CompteMoisIa>?>(
      LectureIa(DocumentAbsent(), fromCache: false),
    );
    final avecCompte = AsyncData<LectureIa<CompteMoisIa>?>(
      LectureIa(
        DocumentTrouve(
          CompteMoisIa(
            id: '2026-11_u',
            mois: '2026-11',
            uid: 'u',
            email: null,
            postes: {
              kPosteAssistantRecette: desComptes(appels: 2, montant: 0.08),
            },
          ),
        ),
        fromCache: false,
      ),
    );

    test('admin : toujours ; brasseur : poste ouvert ou tours ce mois', () {
      expect(
        texteIaCeMois(admin: true, politique: fermee, compte: sansCompte),
        'IA ce mois : aucun tour',
      );
      expect(
        texteIaCeMois(admin: false, politique: fermee, compte: sansCompte),
        isNull,
      );
      expect(
        texteIaCeMois(admin: false, politique: ouverte, compte: sansCompte),
        'IA ce mois : aucun tour',
      );
      expect(
        texteIaCeMois(admin: false, politique: fermee, compte: avecCompte),
        'IA ce mois : 2 tours, ≈\u00a00,08\u00a0\$',
      );
    });

    test('lecture en cours : rien pour un brasseur au droit inconnu', () {
      const enCours = AsyncLoading<LectureIa<CompteMoisIa>?>();
      expect(
        texteIaCeMois(admin: true, politique: fermee, compte: enCours),
        'IA ce mois : lecture en cours',
      );
      expect(
        texteIaCeMois(
          admin: false,
          politique: const AsyncLoading(),
          compte: enCours,
        ),
        isNull,
      );
      expect(
        texteIaCeMois(
          admin: true,
          politique: fermee,
          compte: const AsyncData(
            LectureIa(DocumentAbsentDuCache(), fromCache: true),
          ),
        ),
        'IA ce mois : indisponible hors ligne',
      );
      expect(
        texteIaCeMois(
          admin: true,
          politique: fermee,
          compte: AsyncError(StateError('panne'), StackTrace.empty),
        ),
        'IA ce mois : lecture impossible',
      );
    });
  });

  group('assistant : données envoyées (ADR-015, section 5)', () {
    const content = RecipeContent(
      name: 'Blonde',
      author: 'Jean Auteur',
      style: 'Blonde Ale',
      notes: 'Note du brasseur',
      batchVolumeL: 20,
      boilTimeMin: 60,
      equipmentId: 'eq-1',
      importedFrom: 'BeerJSON · sha256:abc',
      fermentables: [
        FermentableLine(
          name: 'Pils',
          type: 'grain',
          weightG: 4500,
          ebc: 3,
          yieldPct: 80,
        ),
      ],
      hops: [
        HopLine(
          name: 'Citra',
          amount: Quantite.grammes(20),
          use: HopUse.boil,
          form: 'pellet',
          timeMin: 60,
        ),
        HopLine(
          name: 'Citra',
          amount: Quantite.grammes(30),
          use: HopUse.boil,
          form: 'pellet',
          timeMin: 5,
        ),
      ],
    );

    test('recette : sous-arbre recipe, sans auteur ni enveloppe', () {
      final r = recettePourAssistant(content);
      expect(r['name'], 'Blonde');
      expect(r['notes'], 'Note du brasseur');
      expect(r.containsKey('author'), isFalse);
      final texte = jsonEncode(r);
      for (final interdit in [
        'owner',
        'equipment_id',
        'imported_from',
        'Jean Auteur',
      ]) {
        expect(texte.contains(interdit), isFalse, reason: interdit);
      }
    });

    test('calculs : valeurs de computeRecipe, indisponibles absentes', () {
      final calcul = computeRecipe(
        recipe: content.toInput(),
        mashEfficiencyPercent: null,
      );
      final c = calculsPourAssistant(calcul);
      expect(c.containsKey('original_gravity'), isFalse);
      expect(c['missing_inputs'], contains('mashEfficiency'));
      final avec = calculsPourAssistant(
        computeRecipe(recipe: content.toInput(), mashEfficiencyPercent: 72),
        rendementEmpatage: 72,
      );
      expect(avec['original_gravity'], {
        'value': (calculOg(content, 72)),
        'unit': 'sg',
      });
      expect(avec['mash_efficiency_pct'], 72);
      expect(calculsPourAssistant(null, champRefuse: 'x'), {
        'refused_field': 'x',
      });
    });

    test('équipement : contenu sans propriétaire', () {
      const e = EquipmentContent(
        name: 'Grainfather',
        kind: EquipmentKind.allInOne,
        mashEfficiencyPct: 72,
      );
      expect(equipementPourAssistant(e), {
        'name': 'Grainfather',
        'kind': EquipmentKind.allInOne.storedValue,
        'mash_efficiency_pct': 72.0,
      });
    });

    test('houblons distincts, dans l\'ordre, 20 au plus', () {
      expect(houblonsDistincts(content), ['Citra']);
      final beaucoup = RecipeContent(
        name: 'x',
        hops: [
          for (var i = 0; i < 25; i++)
            HopLine(
              name: 'H$i',
              amount: const Quantite.grammes(1),
              use: HopUse.boil,
              form: 'pellet',
              timeMin: 10,
            ),
        ],
      );
      expect(houblonsDistincts(beaucoup), hasLength(kAssistantAromesMax));
    });

    test('argument en liste blanche : tour, puis résumé', () {
      const ctx = ContexteAssistant(recette: {'name': 'B'}, calculs: {});
      final tour = argumentsAssistant(
        idConversation: 'abcdefgh',
        historique: const [],
        mode: ModeAssistant.tour,
        message: 'Bonjour',
        contexte: ctx,
      );
      expect(tour.keys.toSet(), {
        'conversationId',
        'history',
        'message',
        'recipe',
        'calculs',
      });
      final resume = argumentsAssistant(
        idConversation: 'abcdefgh',
        historique: const [
          MessageConversation(AuteurMessage.personne, 'Q'),
          MessageConversation(AuteurMessage.assistant, 'R'),
        ],
        mode: ModeAssistant.resume,
        resume: 'Ancien résumé',
        contexte: ctx,
      );
      expect(resume['mode'], 'summary');
      expect(resume.containsKey('message'), isFalse);
      expect(resume['summary'], 'Ancien résumé');
      expect(resume['history'], [
        {'role': 'user', 'text': 'Q'},
        {'role': 'assistant', 'text': 'R'},
      ]);
    });

    test('identifiant de conversation conforme au motif du serveur', () {
      final ids = {for (var i = 0; i < 20; i++) nouvelIdConversation()};
      expect(ids, hasLength(20));
      for (final id in ids) {
        expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id), isTrue);
      }
    });

    test('réponse lue : texte, tour, quota', () {
      final r = ReponseAssistant.lire({
        'reponse': '## Avis',
        'proposition': null,
        'turn': 2,
        'quota': {
          'limit': 20,
          'remaining': 17,
          'resets_at': '2026-11-15T23:00:00.000Z',
        },
      });
      expect(r.tour, 2);
      expect(r.quota?.restants, 17);
      expect(r.quota?.repriseLe, DateTime.utc(2026, 11, 15, 23).toLocal());
      expect(
        () => ReponseAssistant.lire({'reponse': ' '}),
        throwsFormatException,
      );
    });

    test('raisons du serveur', () {
      EchecAssistant e(String code, [Map<String, Object?>? details]) =>
          EchecAssistant.depuis(code: code, details: details);
      expect(
        e('failed-precondition', {'reason': 'ai_policy_unavailable'}).cause,
        CauseEchecAssistant.reglagesAbsents,
      );
      expect(
        e('permission-denied', {'reason': 'ai_feature_closed'}).cause,
        CauseEchecAssistant.posteFerme,
      );
      final plafond = e('resource-exhausted', {
        'reason': 'quota_exhausted',
        'quota': {
          'limit': 20,
          'remaining': 0,
          'resets_at': '2026-11-15T23:00:00Z',
        },
      });
      expect(plafond.cause, CauseEchecAssistant.plafondJour);
      expect(plafond.quota?.limite, 20);
      expect(
        e('failed-precondition', {'reason': 'conversation_full'}).cause,
        CauseEchecAssistant.conversationPleine,
      );
      final long = e('invalid-argument', {
        'reason': 'too_long',
        'field': 'aromas.3',
      });
      expect(
        (long.cause, long.champ),
        (CauseEchecAssistant.tropLong, 'aromas.3'),
      );
      expect(
        e('deadline-exceeded', {'reason': 'ai_timeout'}).cause,
        CauseEchecAssistant.delaiDepasse,
      );
      expect(
        e('aborted', {'reason': 'ai_no_answer'}).cause,
        CauseEchecAssistant.reponseIllisible,
      );
      expect(
        e('unavailable', {'reason': 'ai_unreachable'}).cause,
        CauseEchecAssistant.envoiImpossible,
      );
      // Sans raison : la coupure du réseau laisse le résultat inconnu.
      expect(e('unavailable').cause, CauseEchecAssistant.resultatInconnu);
      expect(e('deadline-exceeded').cause, CauseEchecAssistant.resultatInconnu);
      expect(e('invalid-argument').cause, CauseEchecAssistant.refus);
      expect(
        e('invalid-argument', {
          'reason': 'invalid_argument',
          'field': 'x',
        }).cause,
        CauseEchecAssistant.refus,
      );
      expect(
        e('failed-precondition', {'reason': 'ai_cost_center_unknown'}).cause,
        CauseEchecAssistant.envoiImpossible,
      );
      for (final r in ['ai_key_invalid', 'ai_model_unavailable']) {
        expect(
          e('failed-precondition', {'reason': r}).cause,
          CauseEchecAssistant.reglageACorriger,
        );
      }
      expect(
        e('resource-exhausted', {'reason': 'ai_credit_exhausted'}).cause,
        CauseEchecAssistant.creditEpuise,
      );
      expect(
        e('resource-exhausted', {'reason': 'ai_rate_limited'}).cause,
        CauseEchecAssistant.tropDemande,
      );
      expect(
        e('unavailable', {'reason': 'ai_failed'}).cause,
        CauseEchecAssistant.delaiDepasse,
      );
    });
  });

  group('P60 : aucun tarif, aucune liste de modèles ni d\'efforts en Dart', () {
    final fichiers = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f,
    ];

    test('aucune liste d\'efforts', () {
      for (final f in fichiers) {
        expect(
          f.readAsStringSync().contains("'xhigh'"),
          isFalse,
          reason: f.path,
        );
      }
    });

    test('identifiants de modèle : la proposition initiale seule', () {
      final avec = [
        for (final f in fichiers)
          if (RegExp(r"'claude-[a-z0-9-]+'").hasMatch(f.readAsStringSync()))
            f.path.replaceAll('\\', '/'),
      ];
      expect(avec, ['lib/features/admin/presentation/moteur_ia_screen.dart']);
    });

    test('tarifs lus dans un seul fichier', () {
      final avec = [
        for (final f in fichiers)
          if (f.readAsStringSync().contains('_usd_per_mtok'))
            f.path.replaceAll('\\', '/'),
      ];
      expect(avec, ['lib/features/ai/domain/reglages_ia.dart']);
    });
  });

  group(
    'P2 et P60 : l\'écran du jour n\'importe aucun fichier de l\'assistant',
    () {
      test('imports transitifs depuis brew_day/', () {
        final racines = [
          for (final f in Directory(
            'lib/features/brew_day',
          ).listSync(recursive: true))
            if (f is File && f.path.endsWith('.dart')) f.absolute.path,
        ];
        final vus = <String>{};
        final aVoir = [...racines];
        final motif = RegExp(r'''^import\s+'([^']+)';''', multiLine: true);
        final lib = Directory('lib').absolute.path;
        while (aVoir.isNotEmpty) {
          final chemin = File(aVoir.removeLast()).absolute.uri.normalizePath();
          if (!vus.add(chemin.toFilePath())) continue;
          final texte = File.fromUri(chemin).readAsStringSync();
          for (final m in motif.allMatches(texte)) {
            final cible = m.group(1)!;
            if (cible.startsWith('dart:')) continue;
            if (cible.startsWith('package:kass_beer/')) {
              aVoir.add('$lib/${cible.substring('package:kass_beer/'.length)}');
            } else if (!cible.startsWith('package:')) {
              aVoir.add(chemin.resolve(cible).toFilePath());
            }
          }
        }
        final assistant = [
          for (final v in vus)
            if (RegExp(
              r'(assistant_controleur|panneau_assistant|assistant_repository|'
              r'assistant_recette)\.dart$',
            ).hasMatch(v))
              v,
        ];
        expect(assistant, isEmpty);
      });
    },
  );
}

/// Densité initiale calculée par `brewing/` pour comparaison.
double calculOg(RecipeContent content, double rendement) =>
    (computeRecipe(
              recipe: content.toInput(),
              mashEfficiencyPercent: rendement,
            ).originalGravity
            as CalculationComputed)
        .value;
