import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:exchange/exchange.dart' show NomNonResolu;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/library/data/library_repository.dart';
import 'package:kass_beer/features/library/domain/recette_publique.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/recipes/data/recipes_repository.dart';

import 'support/fakes.dart';
import 'support/library_fixtures.dart';

/// Champs de premier niveau acceptés par `recipeFields()` et clés de `recipe`
/// acceptées par `isBeerJsonRecipe` (`firestore.rules`).
const _recipeFields = {
  'format_version',
  'owner_uid',
  'owner_name',
  'equipment_id',
  'imported_from',
  'brew_steps',
  'recipe',
  'created_at',
  'updated_at',
};
const _beerJsonRecipeKeys = {
  'name',
  'type',
  'author',
  'notes',
  'style',
  'batch_size',
  'boil',
  'mash',
  'ingredients',
};

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingErrorReportService errors;
  late FirestoreLibraryRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    errors = RecordingErrorReportService();
    repository = FirestoreLibraryRepository(
      errorReportService: errors,
      firestore: firestore,
    );
  });

  group('beer_index', () {
    test('lu par get(), puis gardé pour la session', () async {
      await firestore.doc('beer_index/hops').set(hopsIndex);
      final first = await repository.lireIndex(NatureReferentiel.hops);
      expect(first, isA<DocumentTrouve<IndexReferentiel>>());
      final index = (first as DocumentTrouve<IndexReferentiel>).value;
      expect(index.entrees.map((e) => e.id), [
        'hop-cascade',
        'hop-houblon-dore',
      ]);
      // Le document change sur le serveur : la session garde sa lecture.
      await firestore.doc('beer_index/hops').set(indexDoc([]));
      final second = await repository.lireIndex(NatureReferentiel.hops);
      expect(identical(second, first), isTrue);
      // Une autre nature a sa propre lecture.
      expect(
        await repository.lireIndex(NatureReferentiel.styles),
        isA<DocumentAbsent<IndexReferentiel>>(),
      );
    });

    test('entrées illisibles : un seul rapport pour l\'index', () async {
      await firestore.doc('beer_index/hops').set(hopsIndex);
      await repository.lireIndex(NatureReferentiel.hops);
      expect(errors.reports, hasLength(1));
      expect(errors.reports.single.feature, 'library.index_entries');
      expect(
        errors.reports.single.context,
        'beer_index/hops : 1 entrées illisibles sur 3',
      );
    });

    test('absent : DocumentAbsent, non gardé', () async {
      expect(
        await repository.lireIndex(NatureReferentiel.miscs),
        isA<DocumentAbsent<IndexReferentiel>>(),
      );
      await firestore.doc('beer_index/miscs').set(indexDoc([]));
      expect(
        await repository.lireIndex(NatureReferentiel.miscs),
        isA<DocumentTrouve<IndexReferentiel>>(),
      );
      expect(errors.reports, isEmpty);
    });

    test('illisible : rapporté, rendu comme tel', () async {
      await firestore.doc('beer_index/styles').set({'entries': 'texte'});
      final read = await repository.lireIndex(NatureReferentiel.styles);
      expect(read, isA<DocumentIllisibleTrouve<IndexReferentiel>>());
      expect(errors.reports.single.feature, 'library.index');
      expect(errors.reports.single.context, 'beer_index/styles illisible');
    });
  });

  group('fiches', () {
    test('get() de beer_*/{id}', () async {
      await firestore.doc('beer_hops/hop-cascade').set(hopDoc());
      final read = await repository.lireFiche(
        NatureReferentiel.hops,
        'hop-cascade',
      );
      final fiche = (read as DocumentTrouve<FicheReferentiel>).value;
      expect(fiche, isA<FicheHoublon>());
      expect(fiche.name, 'Cascade');
      expect(
        await repository.lireFiche(NatureReferentiel.hops, 'absent'),
        isA<DocumentAbsent<FicheReferentiel>>(),
      );
    });

    test('fiche illisible : rapportée avec son chemin', () async {
      await firestore.doc('beer_styles/s').set({...styleDoc(), 'name': 3});
      final read = await repository.lireFiche(NatureReferentiel.styles, 's');
      expect(read, isA<DocumentIllisibleTrouve<FicheReferentiel>>());
      expect(errors.reports.single.feature, 'library.entry');
      expect(errors.reports.single.context, 'beer_styles/s illisible');
    });
  });

  group('public_recipes', () {
    Future<void> seed(int count) async {
      for (var i = 1; i <= count; i++) {
        final name = 'Recette ${i.toString().padLeft(3, '0')}';
        await firestore
            .doc('public_recipes/diydog-$i')
            .set(publicRecipeDoc(id: '$i', name: name));
      }
    }

    test('pages de 50 par recipe.name, suite par startAfterDocument', () async {
      await seed(120);
      final first = await repository.pageRecettesPubliques();
      expect(first.documents, hasLength(kTaillePageRecettes));
      expect(first.documents.first.id, 'diydog-1');
      expect(first.suite, isNotNull);
      final second = await repository.pageRecettesPubliques(apres: first.suite);
      expect(second.documents.first.id, 'diydog-51');
      final third = await repository.pageRecettesPubliques(apres: second.suite);
      expect(third.documents, hasLength(20));
      expect(third.documents.last.id, 'diydog-120');
      expect(third.suite, isNull);
    });

    test('recherche par préfixe sur search_name, saisie normalisée', () async {
      await seed(3);
      await firestore
          .doc('public_recipes/diydog-9')
          .set(publicRecipeDoc(id: '9', name: 'Punk IPA 2007 - 2010'));
      for (final saisie in ['Punk', 'punk', ' PUNK  ipa 2007 -', 'Pùnk']) {
        final page = await repository.pageRecettesPubliques(prefixe: saisie);
        expect(page.documents.map((d) => d.id), ['diydog-9'], reason: saisie);
        expect(page.suite, isNull);
      }
      final none = await repository.pageRecettesPubliques(prefixe: 'ipa');
      expect(none.documents, isEmpty);
      // Sans lettre ni chiffre : aucun filtre.
      final all = await repository.pageRecettesPubliques(prefixe: '—');
      expect(all.documents, hasLength(4));
    });

    test(
      'document illisible dans une page : rapporté, rendu comme tel',
      () async {
        await seed(1);
        await firestore.doc('public_recipes/diydog-2').set({
          ...publicRecipeDoc(id: '2', name: 'Recette 002'),
          'format_version': 2,
        });
        final page = await repository.pageRecettesPubliques();
        expect(page.documents.first, isA<DocumentValide<RecettePublique>>());
        expect(page.documents.last, isA<DocumentInvalide<RecettePublique>>());
        expect(errors.reports.single.feature, 'library.public_recipe_read');
        expect(
          errors.reports.single.context,
          'public_recipes/diydog-2 illisible',
        );
      },
    );

    test('une recette par get()', () async {
      await seed(1);
      final read = await repository.lireRecettePublique('diydog-1');
      expect(
        (read as DocumentTrouve<RecettePublique>).value.name,
        'Recette 001',
      );
      expect(
        await repository.lireRecettePublique('diydog-404'),
        isA<DocumentAbsent<RecettePublique>>(),
      );
    });
  });

  group('Dupliquer', () {
    test('clés écrites dans recipes/ : celles des règles, sans les champs '
        'propres aux recettes publiques', () async {
      final recipes = FirestoreRecipesRepository(
        errorReportService: errors,
        firestore: firestore,
      );
      final created = recipes.create(
        content: publicRecipe().copie,
        ownerUid: 'uid-brasseur',
        ownerName: 'Bruno Brasseur',
      );
      await created.written;
      final data = (await firestore.doc('recipes/${created.id}').get()).data()!;
      expect(_recipeFields.containsAll(data.keys), isTrue);
      expect(data.keys.toSet(), {
        'format_version',
        'owner_uid',
        'owner_name',
        'imported_from',
        'recipe',
        'created_at',
        'updated_at',
      });
      for (final key in [
        'style_id',
        'ingredient_refs',
        'source_hop_timing',
        'announced',
        'provenance',
        'search_name',
        'content_sha256',
      ]) {
        expect(data.containsKey(key), isFalse, reason: key);
      }
      expect(data['owner_uid'], 'uid-brasseur');
      expect(data['imported_from'], 'DIY Dog · diydog-1');
      expect(data['created_at'], isA<Timestamp>());
      final recipe = data['recipe'] as Map<String, dynamic>;
      expect(_beerJsonRecipeKeys.containsAll(recipe.keys), isTrue);
      expect(recipe['name'], 'Blonde du Verger');
      expect(recipe['author'], 'BrewDog');
      final ingredients = recipe['ingredients'] as Map<String, dynamic>;
      expect(ingredients.keys.toSet(), {
        'fermentable_additions',
        'hop_additions',
        'miscellaneous_additions',
        'culture_additions',
      });
      expect(ingredients['hop_additions'], hasLength(2));
      expect(errors.reports, isEmpty);
    });
  });

  group('import_unresolved (ADR-005, E6)', () {
    const houblon = NomNonResolu('hop', 'Houblon Inconnu');
    const malt = NomNonResolu('fermentable', 'Malt Inconnu');

    test('création : liste blanche, count 1, sans e-mail ni uid', () async {
      await repository.signalerNonResolus([houblon, malt]);
      final doc = await firestore
          .doc('import_unresolved/${houblon.empreinte}')
          .get();
      final data = doc.data()!;
      expect(data.keys.toSet(), {
        'nature',
        'key',
        'name',
        'source',
        'count',
        'updated_at',
      });
      expect(data['nature'], 'hop');
      expect(data['key'], 'houblon-inconnu');
      expect(data['name'], 'Houblon Inconnu');
      expect(data['source'], 'import');
      expect(data['count'], 1);
      expect(data['updated_at'], isA<Timestamp>());
      expect(houblon.empreinte, matches(RegExp(r'^[0-9a-f]{64}$')));
      final malts = await firestore
          .doc('import_unresolved/${malt.empreinte}')
          .get();
      expect(malts.data()!['nature'], 'fermentable');
      expect(errors.reports, isEmpty);
    });

    test('autre graphie du même nom : même document, compte + 1', () async {
      await repository.signalerNonResolus([houblon]);
      const autre = NomNonResolu('hop', 'HOUBLON inconnu');
      expect(autre.empreinte, houblon.empreinte);
      await repository.signalerNonResolus([autre]);
      final doc = await firestore
          .doc('import_unresolved/${houblon.empreinte}')
          .get();
      expect(doc.data()!['count'], 2);
      expect(doc.data()!['source'], 'import');
      expect(doc.data()!['name'], 'HOUBLON inconnu');
      expect(errors.reports, isEmpty);
    });

    test('120 noms : lots de 10, tous écrits', () async {
      final noms = [
        for (var i = 0; i < 120; i++) NomNonResolu('misc', 'Ajout Inconnu $i'),
      ];
      final lots = _FirestoreLots();
      final depot = FirestoreLibraryRepository(
        errorReportService: errors,
        firestore: lots,
      );
      await depot.signalerNonResolus(noms);
      expect(lots.lots, 12);
      final docs = await lots.collection(kNonResolus).get();
      expect(docs.docs, hasLength(120));
      expect(errors.reports, isEmpty);
    });

    test(
      'lot refusé : les autres écrits, un rapport sans nom, rien ne lève',
      () async {
        final noms = [
          for (var i = 0; i < 30; i++)
            NomNonResolu('hop', 'Houblon Inconnu $i'),
        ];
        final lots = _FirestoreLots(enPanne: 2);
        final depot = FirestoreLibraryRepository(
          errorReportService: errors,
          firestore: lots,
        );
        await depot.signalerNonResolus(noms);
        final ids = {
          for (final d in (await lots.collection(kNonResolus).get()).docs) d.id,
        };
        expect(ids, {
          for (final n in [...noms.sublist(0, 10), ...noms.sublist(20)])
            n.empreinte,
        });
        final rapport = errors.reports.single;
        expect(rapport.feature, 'library.unresolved');
        expect(rapport.context, contains('lot de 10 noms (hop)'));
        expect(rapport.context, isNot(contains('Houblon')));
      },
    );
  });
}

/// Firestore de test dont le lot n° [enPanne] (à partir de 1) échoue au commit.
class _FirestoreLots extends FakeFirebaseFirestore {
  _FirestoreLots({this.enPanne});

  final int? enPanne;
  int lots = 0;

  @override
  WriteBatch batch() {
    lots++;
    return _Lot(super.batch(), panne: lots == enPanne);
  }
}

class _Lot implements WriteBatch {
  _Lot(this._lot, {required this.panne});

  final WriteBatch _lot;
  final bool panne;

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) =>
      _lot.set(document, data, options);

  @override
  Future<void> commit() async {
    if (panne) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    await _lot.commit();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
