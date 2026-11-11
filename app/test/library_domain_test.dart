import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/library/domain/recette_publique.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/library/presentation/libelles_bibliotheque.dart';

import 'support/library_fixtures.dart';

void main() {
  group('beer_index', () {
    test('entrées lues, champ inconnu ignoré, entrée mal typée écartée', () {
      final index = IndexReferentiel.fromFirestore(
        NatureReferentiel.hops,
        hopsIndex,
      );
      expect(index.entrees, hasLength(2));
      final cascade = index.entrees.first as EntreeHoublon;
      expect(cascade.id, 'hop-cascade');
      expect(cascade.aliases, ['Cascade US']);
      expect(cascade.form, 'pellet');
      expect(cascade.alphaPct, 6.5);
      expect(index.illisibles, 1);
      expect(index.premiereErreur?.field, 'entries[2].alpha');
    });

    test('style : code, catégorie, degré et amertume [min, max]', () {
      final index = IndexReferentiel.fromFirestore(
        NatureReferentiel.styles,
        stylesIndex,
      );
      final ipa = index.entrees.first as EntreeStyle;
      expect(ipa.code, '21A');
      expect(ipa.abv, const Plage(minimum: 5.5, maximum: 7.5));
      expect(ipa.ibu, const Plage(minimum: 40, maximum: 70));
      final lager = index.entrees.last as EntreeStyle;
      expect(lager.abv, isNull);
      expect(index.illisibles, 0);
    });

    test('plage d\'index qui n\'est pas une paire : entrée écartée', () {
      final index = IndexReferentiel.fromFirestore(
        NatureReferentiel.styles,
        indexDoc([
          {
            'id': 'x',
            'name': 'X',
            'code': '1A',
            'abv': [4.5],
            // Non lus : la liste ne les affiche pas.
            'og': 'ignoré',
          },
        ]),
      );
      expect(index.entrees, isEmpty);
      expect(index.illisibles, 1);
      expect(index.premiereErreur?.field, 'entries[0].abv');
    });

    test('élément qui n\'est pas une map, alias non texte : écartés', () {
      final index = IndexReferentiel.fromFirestore(
        NatureReferentiel.miscs,
        indexDoc([
          'texte',
          {
            'id': 'misc-a',
            'name': 'A',
            'aliases': [1],
          },
          {'id': 'misc-b', 'name': 'Coriandre', 'label_fr': 'Coriandre'},
        ]),
      );
      expect(index.entrees.single.id, 'misc-b');
      expect(index.illisibles, 2);
    });

    test('sans entries : document illisible', () {
      expect(
        () => IndexReferentiel.fromFirestore(NatureReferentiel.hops, {
          'count': 0,
        }),
        throwsA(
          isA<DocumentIllisible>().having((e) => e.field, 'field', 'entries'),
        ),
      );
    });

    test('recherche : nom, alias, code, sans accents ni majuscules', () {
      final hops = IndexReferentiel.fromFirestore(
        NatureReferentiel.hops,
        hopsIndex,
      ).entrees;
      List<String> ids(String q) => [
        for (final e in hops)
          if (e.correspond(normaliserRecherche(q))) e.id,
      ];
      expect(ids(''), ['hop-cascade', 'hop-houblon-dore']);
      expect(ids('us'), ['hop-cascade']);
      expect(ids('DORE'), ['hop-houblon-dore']);
      final styles = IndexReferentiel.fromFirestore(
        NatureReferentiel.styles,
        stylesIndex,
      ).entrees;
      expect(
        styles.where((e) => e.correspond(normaliserRecherche('21a'))),
        hasLength(1),
      );
    });
  });

  group('fiches', () {
    test('style : plages en sg, IBUs, EBC et %, provenance', () {
      final fiche =
          FicheReferentiel.fromFirestore(
                NatureReferentiel.styles,
                'bjcp2021-21a',
                styleDoc(),
              )
              as FicheStyle;
      expect(fiche.styleId, '21A');
      expect(fiche.categoryId, '21');
      expect(fiche.og, const Plage(minimum: 1.056, maximum: 1.070));
      expect(fiche.ibu, const Plage(minimum: 40, maximum: 70));
      expect(fiche.color, const Plage(minimum: 12, maximum: 28));
      expect(fiche.provenance.single.licence, 'BJCP (noms et plages)');
      expect(fiche.provenance.single.retrieved, '2026-11-08');
    });

    test('code de catégorie écrit en entier : lu en texte', () {
      final fiche =
          FicheReferentiel.fromFirestore(NatureReferentiel.styles, 's', {
                ...styleDoc(),
                'category_id': 21,
              })
              as FicheStyle;
      expect(fiche.categoryId, '21');
    });

    test('houblon : valeurs, usage, licence CC BY-SA 4.0', () {
      final fiche =
          FicheReferentiel.fromFirestore(
                NatureReferentiel.hops,
                'hop-cascade',
                hopDoc(),
              )
              as FicheHoublon;
      expect(fiche.alphaPct, 6.5);
      expect(fiche.betaPct, 5.5);
      expect(fiche.purpose, 'aroma');
      expect(fiche.provenance.single.licence, 'CC BY-SA 4.0');
    });

    test('autre unité que l\'unité canonique : fiche illisible', () {
      expect(
        () => FicheReferentiel.fromFirestore(NatureReferentiel.hops, 'h', {
          ...hopDoc(),
          'alpha_acid': mesure(0.065, 'ratio'),
        }),
        throwsA(isA<DocumentIllisible>()),
      );
      expect(
        () => FicheReferentiel.fromFirestore(NatureReferentiel.styles, 's', {
          ...styleDoc(),
          'color': plage(6, 14, 'SRM'),
        }),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('levure : plages d\'atténuation et de température', () {
      final fiche =
          FicheReferentiel.fromFirestore(NatureReferentiel.cultures, 'c', {
                'name': 'American Ale',
                'producer': 'Wyeast',
                'product_id': 1056,
                'type': 'ale',
                'form': 'liquid',
                'attenuation': plage(73, 77, '%'),
                'temperature_range': {'minimum': mesure(16, 'C')},
                'flocculation': 'medium',
                'provenance': [provenance()],
              })
              as FicheLevure;
      expect(fiche.productId, '1056');
      expect(fiche.attenuation, const Plage(minimum: 73, maximum: 77));
      expect(fiche.temperature, const Plage(minimum: 16));
      expect(producteurLevure(fiche.producer, fiche.productId), 'Wyeast 1056');
    });

    test('provenance sans licence : fiche illisible', () {
      expect(
        () => FicheReferentiel.fromFirestore(NatureReferentiel.hops, 'h', {
          ...hopDoc(),
          'provenance': [
            {'source': 'brewtarget-003', 'version': 'v5.2.3 ea10908'},
          ],
        }),
        throwsA(isA<DocumentIllisible>()),
      );
    });
  });

  group('recette publique', () {
    test('recipe lu par RecipeContent, champs propres lus à part', () {
      final r = publicRecipe(styleId: 'bjcp2021-21a');
      expect(r.id, 'diydog-1');
      expect(r.ownerName, 'DIY Dog');
      expect(r.styleId, 'bjcp2021-21a');
      expect(r.searchName, 'blonde du verger');
      expect(r.content.name, 'Blonde du Verger');
      expect(r.content.author, 'BrewDog');
      expect(r.content.type, isNull);
      expect(r.content.boilTimeMin, isNull);
      expect(r.content.importedFrom, 'DIY Dog · diydog-1');
      expect(r.content.hops, hasLength(2));
      expect(r.content.hops[1].timeMin, isNull);
      expect(r.momentsOrigine, {1: 'middle'});
      expect(r.annonce.originalGravity, 1.052);
      expect(r.annonce.alcoholByVolume, 5.6);
      expect(r.annonce.ibu, 28);
      expect(r.annonce.colorEbc, 9);
      expect(r.provenance.single.source, 'diydog');
    });

    test('houblons sans forme, sans style_id : lisible, rien d\'inventé', () {
      final r = publicRecipe(avecForme: false);
      expect(r.styleId, isNull);
      expect(r.content.hops.map((h) => h.form), [null, null]);
      final hops =
          (r.copie.toFirestore(creation: true)['recipe']
                  as Map<String, Object?>)['ingredients']
              as Map<String, Object?>;
      for (final h in hops['hop_additions']! as List) {
        expect((h as Map).containsKey('form'), isFalse);
      }
    });

    test('nom de recherche : même forme que l\'ingestion', () {
      expect(
        normaliserNomRecherche('Punk IPA 2007 - 2010'),
        'punk ipa 2007 2010',
      );
      expect(normaliserNomRecherche('  Bière   Été '), 'biere ete');
      expect(normaliserNomRecherche('—'), '');
    });

    test('sans announced ni source_hop_timing : vides', () {
      final doc = publicRecipeDoc()
        ..remove('announced')
        ..remove('source_hop_timing');
      final r = RecettePublique.fromFirestore('diydog-1', doc);
      expect(r.annonce.vide, isTrue);
      expect(r.momentsOrigine, isEmpty);
    });

    test('rang de houblon hors de la liste : illisible', () {
      final doc = publicRecipeDoc()
        ..['source_hop_timing'] = [
          {'hop_index': 5, 'label': 'start'},
        ];
      expect(
        () => RecettePublique.fromFirestore('diydog-1', doc),
        throwsA(
          isA<DocumentIllisible>().having(
            (e) => e.field,
            'field',
            'source_hop_timing[0].hop_index',
          ),
        ),
      );
    });

    test('valeur annoncée dans une autre unité : illisible', () {
      final doc = publicRecipeDoc()
        ..['announced'] = {'original_gravity': mesure(11.2, 'plato')};
      expect(
        () => RecettePublique.fromFirestore('diydog-1', doc),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test(
      'copie : clés de recipes/ seulement, sans équipement ni chronologie',
      () {
        final doc = publicRecipeDoc()
          ..['equipment_id'] = 'eq-1'
          ..['brew_steps'] = [
            {'key': 'k1', 'name': 'Chauffe', 'duration_min': 30},
          ];
        final r = RecettePublique.fromFirestore('diydog-1', doc);
        expect(r.content.equipmentId, 'eq-1');
        expect(r.content.brewSteps, hasLength(1));
        final data = r.copie.toFirestore(creation: true);
        expect(data.keys.toSet(), {
          'format_version',
          'imported_from',
          'recipe',
        });
        expect(data['imported_from'], 'DIY Dog · diydog-1');
        final recipe = data['recipe'] as Map<String, Object?>;
        expect(
          {
            'name',
            'type',
            'author',
            'notes',
            'style',
            'batch_size',
            'boil',
            'mash',
            'ingredients',
          }.containsAll(recipe.keys),
          isTrue,
        );
        expect(recipe['name'], 'Blonde du Verger');
      },
    );
  });

  group('libellés', () {
    test('plage, source, date du relevé', () {
      String f(double v) => '$v';
      expect(formatPlage(const Plage(minimum: 1, maximum: 2), f), '1.0 à 2.0');
      expect(formatPlage(const Plage(minimum: 1), f), 'à partir de 1.0');
      expect(formatPlage(const Plage(maximum: 2), f), 'jusqu\'à 2.0');
      expect(formatPlage(null, f), isNull);
      expect(libelleSource('brewtarget-005'), 'Brewtarget');
      expect(libelleSource('diydog'), 'DIY Dog');
      expect(libelleSource('autre'), 'autre');
      expect(libelleReleve('2026-11-08'), '8 novembre 2026');
      expect(libelleReleve('inconnue'), 'inconnue');
      expect(versionCourte('v5.2.3 ea10908'), '5.2.3');
      expect(versionCourte('e6c12ab'), isNull);
      expect(
        lignesProvenance([
          Provenance.fromFirestore(LecteurChamps(provenance())),
          Provenance.fromFirestore(
            LecteurChamps(provenance(source: 'brewtarget-001')),
          ),
          Provenance.fromFirestore(
            LecteurChamps(
              provenance(
                source: 'diydog',
                licence: 'DIY Dog (usage privé)',
                version: 'e6c12ab',
              ),
            ),
          ),
        ]),
        [
          'Brewtarget 5.2.3 · licence GPL-3.0 · relevé le 8 novembre 2026',
          'DIY Dog · licence DIY Dog (usage privé) · relevé le 8 novembre 2026',
        ],
      );
    });

    test('moments d\'origine, type de style, usage d\'un houblon', () {
      expect(libelleMomentOrigine('start'), 'début d\'ébullition (start)');
      expect(libelleMomentOrigine('Middle'), 'milieu d\'ébullition (Middle)');
      expect(libelleMomentOrigine('end'), 'fin d\'ébullition (end)');
      expect(libelleMomentOrigine('dry hop'), 'houblonnage à cru (dry hop)');
      expect(libelleMomentOrigine('Whirlpool'), 'whirlpool (Whirlpool)');
      expect(libelleMomentOrigine('HD1'), 'HD1');
      expect(libelleTypeStyle('beer'), 'Bière');
      expect(libelleTypeStyle('mead'), 'Hydromel');
      expect(libelleTypeStyle('inconnu'), 'inconnu');
      expect(libelleUsageHoublon('aroma/bittering'), 'Aromatique et amérisant');
    });
  });
}
