import 'package:exchange/exchange.dart';
import 'package:test/test.dart';

import 'support/description.dart';

/// Fichiers BeerJSON écrits à la main (noms fictifs) et leur lecture
/// attendue. `rules-tests/test/exchange_schema.test.mjs` valide chaque document
/// lu contre le schéma partiel (ADR-005, P21).
void main() {
  for (final nom in ['brewtarget-201', 'v1-metrique']) {
    test('$nom : lecture attendue', () {
      final analyse = analyserFichier(octetsFixture('lecture/$nom.json'));
      expectFixture('lecture/$nom.attendu.json', decrireAnalyse(analyse));
    });
  }
}
