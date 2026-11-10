import 'package:exchange/exchange.dart';
import 'package:test/test.dart';

import 'support/description.dart';

/// Fichiers BeerJSON et BeerXML écrits à la main (noms fictifs ; aucun fichier
/// tiré de Brewtarget, de DIY Dog ni de diydog-beerxml, ADR-005) et leur lecture
/// attendue. `rules-tests/test/exchange_schema.test.mjs` valide chaque document
/// lu contre le schéma partiel (ADR-005, P21).
void main() {
  for (final nom in [
    'brewtarget-201.json',
    'v1-metrique.json',
    'beerxml-beersmith.xml',
    'beerxml-brewfather.xml',
    'beerxml-brewers-friend.xml',
    'beerxml-brewtarget.xml',
  ]) {
    final base = nom.substring(0, nom.lastIndexOf('.'));
    test('$nom : lecture attendue', () {
      final analyse = analyserFichier(octetsFixture('lecture/$nom'));
      expectFixture('lecture/$base.attendu.json', decrireAnalyse(analyse));
    });
  }
}
