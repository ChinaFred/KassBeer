import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/providers.dart';
import 'package:kass_beer/features/brews/presentation/plage_levure.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';

import 'support/fakes.dart';

/// Plage de la levure de la courbe de fermentation : résolution par le nom dans
/// `beer_index/cultures`, puis fiche lue par `get()` (P22).

const _us05 = EntreeLevure(
  id: 'culture-safale-us-05',
  name: 'SafAle US-05',
  producer: 'Fermentis',
  productId: 'US-05',
);

FakeLibraryRepository _bibliotheque({Plage? plage, bool avecFiche = true}) {
  final repo = FakeLibraryRepository();
  repo.index[NatureReferentiel.cultures] = DocumentTrouve(
    const IndexReferentiel(
      nature: NatureReferentiel.cultures,
      entrees: [_us05],
    ),
  );
  if (avecFiche) {
    repo.fiches[_us05.id] = DocumentTrouve(
      FicheLevure(id: _us05.id, name: _us05.name, temperature: plage),
    );
  }
  return repo;
}

Future<EtatPlageLevure?> _lire(
  FakeLibraryRepository repo,
  String nom, {
  bool cacheSeul = false,
}) async {
  final container = ProviderContainer(
    overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container.read(
    plageLevureProvider((nom: nom, cacheSeul: cacheSeul)).future,
  );
}

void main() {
  test('nom résolu : plage lue sur la fiche', () async {
    final repo = _bibliotheque(plage: const Plage(minimum: 18, maximum: 22));
    final etat = await _lire(repo, 'SafAle US-05');
    expect(etat, isA<PlageLevureConnue>());
    final plage = etat! as PlageLevureConnue;
    expect((plage.minimum, plage.maximum), (18, 22));
    expect(repo.indexReads, [NatureReferentiel.cultures]);
    expect(repo.ficheReads, [_us05.id]);
  });

  test('souche lue dans le nom (Fermentis US-05) : même entrée', () async {
    final repo = _bibliotheque(plage: const Plage(minimum: 15, maximum: 24));
    expect(await _lire(repo, 'Fermentis US-05'), isA<PlageLevureConnue>());
  });

  test('aucune correspondance : levure absente, aucune fiche lue', () async {
    final repo = _bibliotheque();
    final etat = await _lire(repo, 'Levure de la maison');
    expect(etat, isA<LevureAbsenteDeLaBibliotheque>());
    expect((etat! as LevureAbsenteDeLaBibliotheque).nom, 'Levure de la maison');
    expect(repo.ficheReads, isEmpty);
  });

  test('fiche sans plage, ou plage d\'une seule borne : sans plage', () async {
    expect(
      await _lire(_bibliotheque(), 'SafAle US-05'),
      isA<LevureSansPlage>(),
    );
    expect(
      await _lire(
        _bibliotheque(plage: const Plage(minimum: 18)),
        'SafAle US-05',
      ),
      isA<LevureSansPlage>(),
    );
  });

  test('hors ligne : cache seul, rien sans copie sur l\'appareil', () async {
    final repo = _bibliotheque(avecFiche: false);
    repo.fiches[_us05.id] = DocumentAbsentDuCache<FicheReferentiel>();
    expect(await _lire(repo, 'SafAle US-05', cacheSeul: true), isNull);
    expect(repo.indexCacheReads, [NatureReferentiel.cultures]);
    expect(repo.ficheCacheReads, [_us05.id]);

    final sansIndex = FakeLibraryRepository()
      ..index[NatureReferentiel.cultures] =
          DocumentAbsentDuCache<IndexReferentiel>();
    expect(await _lire(sansIndex, 'SafAle US-05', cacheSeul: true), isNull);
    expect(sansIndex.ficheReads, isEmpty);
  });
}
