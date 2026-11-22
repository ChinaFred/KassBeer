import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:exchange/exchange.dart';
import 'package:exchange/ingestion.dart' as ingestion;
import 'package:test/test.dart';

/// Résolution d'un import contre la Bibliothèque (ADR-005, E5) : noms exacts
/// après normalisation, alias, souche d'une levure ; valeurs absentes reprises,
/// valeurs du fichier gardées ; noms non résolus, avec la même empreinte que
/// l'ingestion.

Map<String, Object> _m(num value, String unit) => {
  'value': value,
  'unit': unit,
};

final _malts = IndexBibliotheque(ListeRecette.malts, const [
  EntreeBibliotheque(
    id: 'fermentable-pilsner',
    nom: 'Pilsner',
    alias: ['Malt Pils'],
    type: 'grain',
    rendement: 81,
    couleur: 3.5,
  ),
  EntreeBibliotheque(
    id: 'fermentable-miel-fictif',
    nom: 'Miel Fictif',
    type: 'honey',
    rendement: 75,
    couleur: 2,
  ),
  // Deux entrées portent l'alias « Caramel » : il ne résout rien.
  EntreeBibliotheque(
    id: 'fermentable-cara-a',
    nom: 'Cara A',
    alias: ['Caramel'],
  ),
  EntreeBibliotheque(
    id: 'fermentable-cara-b',
    nom: 'Cara B',
    alias: ['Caramel'],
  ),
]);

final _houblons = IndexBibliotheque(ListeRecette.houblons, const [
  EntreeBibliotheque(id: 'hop-saaz', nom: 'Saaz', alpha: 3.5, forme: 'pellet'),
  EntreeBibliotheque(id: 'hop-fictif', nom: 'Houblon Fictif', alpha: 0),
]);

final _levures = IndexBibliotheque(ListeRecette.levures, const [
  EntreeBibliotheque(
    id: 'culture-wyeast-1056-american-ale',
    nom: 'American Ale',
    producteur: 'Wyeast Labs',
    reference: '1056',
    type: 'ale',
    forme: 'liquid',
    attenuation: 75,
  ),
  EntreeBibliotheque(
    id: 'culture-fermentis-us05-safale-american',
    nom: 'Safale American',
    producteur: 'Fermentis',
    reference: 'US-05',
    type: 'ale',
    forme: 'dry',
    attenuation: 78,
  ),
]);

final _ajouts = IndexBibliotheque(ListeRecette.ajouts, const [
  EntreeBibliotheque(id: 'misc-coriandre', nom: 'Coriandre', type: 'spice'),
]);

const _vide = IndexImport();

IndexImport get _tous => IndexImport(
  malts: _malts,
  houblons: _houblons,
  ajouts: _ajouts,
  levures: _levures,
);

Map<String, Object?> _recette() => {
  'name': 'Recette Fictive',
  'ingredients': {
    'fermentable_additions': [
      {'name': 'malt pils', 'type': 'grain', 'amount': _m(4000, 'g')},
      {
        'name': 'Pilsner',
        'type': 'grain',
        'amount': _m(500, 'g'),
        'color': _m(4, 'EBC'),
        'yield': {'fine_grind': _m(79, '%')},
      },
      {'name': 'Caramel', 'type': 'grain', 'amount': _m(200, 'g')},
    ],
    'hop_additions': [
      {
        'name': 'SAAZ',
        'amount': _m(20, 'g'),
        'timing': {'use': 'add_to_boil', 'time': _m(60, 'min')},
      },
      {
        'name': 'Houblon Fictif',
        'amount': _m(10, 'g'),
        'timing': {'use': 'add_to_boil', 'time': _m(10, 'min')},
      },
    ],
    'miscellaneous_additions': [
      {'name': 'Coriandre', 'amount': _m(10, 'g')},
      {'name': 'Épice Inconnue', 'amount': _m(5, 'g')},
    ],
    'culture_additions': [
      {'name': 'Wyeast 1056 American Ale', 'amount': _m(1, 'l')},
    ],
  },
};

String _reprise(ValeurReprise r) =>
    '${r.grandeur.champ.name}(${r.grandeur.ligne})';

List<Map<String, Object?>> _lignes(Map<String, Object?> recipe, String cle) => [
  for (final l in (recipe['ingredients']! as Map)[cle] as List)
    l as Map<String, Object?>,
];

void main() {
  group('IndexBibliotheque.resoudre', () {
    test('nom et alias, après normalisation (casse, accents, ponctuation)', () {
      expect(_malts.resoudre('PILSNER')?.id, 'fermentable-pilsner');
      expect(_malts.resoudre('malt-pils')?.id, 'fermentable-pilsner');
      expect(_malts.resoudre('Miel  fictif !')?.id, 'fermentable-miel-fictif');
    });

    test('aucune correspondance floue ; deux entrées pour un nom : aucune', () {
      expect(_malts.resoudre('Pilsne'), isNull);
      expect(_malts.resoudre('Pils'), isNull);
      expect(_malts.resoudre('Caramel'), isNull);
      expect(_malts.resoudre('—'), isNull);
    });

    test('levure : souche dans le nom, référence, producteur et référence', () {
      const wyeast = 'culture-wyeast-1056-american-ale';
      const us05 = 'culture-fermentis-us05-safale-american';
      expect(_levures.resoudre('Wyeast 1056 - American Ale™')?.id, wyeast);
      expect(_levures.resoudre('1056')?.id, wyeast);
      expect(_levures.resoudre('US-05')?.id, us05);
      expect(_levures.resoudre('us05')?.id, us05);
      expect(_levures.resoudre('Fermentis US-05')?.id, us05);
      expect(_levures.resoudre('Safale American')?.id, us05);
      expect(_levures.resoudre('Fermentis S-04'), isNull);
    });

    test(
      'levure : référence lue dans un nom écrit à la main (formes du groupe)',
      () {
        // Fixtures inventées (P20) : un producteur fictif à références « LF »,
        // une référence partagée par deux producteurs, deux souches sans
        // référence au même nom de gamme.
        final index = IndexBibliotheque(ListeRecette.levures, const [
          EntreeBibliotheque(
            id: 'culture-labo-fictif-lf84-lager-fictive',
            nom: 'LF84 Lager Fictive',
            producteur: 'Labo Fictif',
            reference: 'LF84',
          ),
          EntreeBibliotheque(
            id: 'culture-labo-fictif-lf31-triple-fictive',
            nom: 'LF31 Triple Fictive',
            producteur: 'Labo Fictif',
            reference: 'LF31',
          ),
          EntreeBibliotheque(
            id: 'culture-seche-fictive-ab256-abbaye-fictive',
            nom: 'AbbAle AB-256',
            producteur: 'Sèche Fictive',
            reference: 'AB-256',
          ),
          EntreeBibliotheque(
            id: 'culture-seche-fictive-z23-lager-fictive',
            nom: 'ZetaLager Z-23',
            producteur: 'Sèche Fictive',
            reference: 'Z-23',
          ),
          EntreeBibliotheque(
            id: 'culture-seche-fictive-q-34-70-lager',
            nom: 'ZetaLager Q-34/70',
            producteur: 'Sèche Fictive',
            reference: 'Q-34/70',
          ),
          // Même référence chez deux producteurs : jamais choisie.
          EntreeBibliotheque(
            id: 'culture-labo-fictif-k9-un',
            nom: 'K9 Un',
            producteur: 'Labo Fictif',
            reference: 'K9',
          ),
          EntreeBibliotheque(
            id: 'culture-autre-fictif-k9-deux',
            nom: 'K9 Deux',
            producteur: 'Autre Fictif',
            reference: 'K9',
          ),
          EntreeBibliotheque(
            id: 'culture-labo-fictif-belle-gamme-fictive',
            nom: 'Belle Gamme Fictive',
            producteur: 'Labo Fictif',
          ),
          EntreeBibliotheque(
            id: 'culture-labo-fictif-flacon-belle-gamme',
            nom: 'Flacon Belle Gamme',
            producteur: 'Labo Fictif',
          ),
        ]);
        const lf84 = 'culture-labo-fictif-lf84-lager-fictive';
        const lf31 = 'culture-labo-fictif-lf31-triple-fictive';
        const ab256 = 'culture-seche-fictive-ab256-abbaye-fictive';
        // Producteur en suffixe, majuscules.
        expect(index.resoudre('LAGER FICTIVE LF84 LABO FICTIF')?.id, lf84);
        // Référence en fin de nom.
        expect(index.resoudre('Lager rustique LF84')?.id, lf84);
        // Mots français et poids, avec ou sans espace.
        expect(index.resoudre('Levure de bière sèche Triple LF31')?.id, lf31);
        expect(index.resoudre('Triple Fictive LF31 10g')?.id, lf31);
        expect(
          index
              .resoudre(
                'Sèche Fictive levure de bière sèche AbbAle AB-256 (Abbaye) 11.5 g',
              )
              ?.id,
          ab256,
        );
        // Référence sans tiret, et coquille dans le nom de gamme.
        expect(
          index.resoudre('ZetaLagerr Z23')?.id,
          'culture-seche-fictive-z23-lager-fictive',
        );
        // Référence en trois segments (`Q-34/70`).
        expect(
          index.resoudre('Lager Q 34/70')?.id,
          'culture-seche-fictive-q-34-70-lager',
        );
        // Un poids n'est jamais une référence, ni des chiffres seuls.
        expect(index.resoudre('Ma levure 84'), isNull);
        expect(index.resoudre('Ma levure 23g'), isNull);
        // Référence partagée par deux producteurs : aucune, deux candidats.
        expect(index.resoudre('Ma levure K9'), isNull);
        expect(index.candidats('Ma levure K9'), [
          'culture-autre-fictif-k9-deux',
          'culture-labo-fictif-k9-un',
        ]);
        // Correspondance partielle : candidats seulement, jamais choisis.
        expect(index.resoudre('Belle Gamme'), isNull);
        expect(index.candidats('Belle Gamme'), [
          'culture-labo-fictif-belle-gamme-fictive',
          'culture-labo-fictif-flacon-belle-gamme',
        ]);
        expect(index.candidats('belle gamme labo fictif'), hasLength(2));
        expect(index.candidats('Ma levure'), isEmpty);
        expect(index.candidatsAvecOrigine('Belle Gamme').partiels, isTrue);
        expect(index.candidatsAvecOrigine('Ma levure K9').partiels, isFalse);
        // Référence d'un producteur, nom qui en nomme un autre : aucune, la
        // souche reste candidate.
        expect(index.resoudre('Labo Fictif Z23'), isNull);
        expect(index.candidats('Labo Fictif Z23'), [
          'culture-seche-fictive-z23-lager-fictive',
        ]);
        expect(
          index.resoudre('Sèche Fictive Z23')?.id,
          'culture-seche-fictive-z23-lager-fictive',
        );
        // Le nom entier reste la règle d'abord.
        expect(
          index.resoudre('Flacon Belle Gamme')?.id,
          'culture-labo-fictif-flacon-belle-gamme',
        );
      },
    );

    test('houblons : aucune lecture de référence ni candidat partiel', () {
      expect(_houblons.resoudre('Saaz LF84'), isNull);
      expect(_houblons.candidats('Saaz Tchèque'), isEmpty);
    });

    test('une liste sans nature (paliers) est refusée', () {
      expect(
        () => IndexBibliotheque(ListeRecette.paliers, const []),
        throwsArgumentError,
      );
    });
  });

  group('completerRecette', () {
    test('valeurs absentes reprises, valeurs du fichier gardées', () {
      final source = _recette();
      final r = completerRecette(source, _tous);
      final malts = _lignes(r.recipe, 'fermentable_additions');
      expect(malts[0]['yield'], {'fine_grind': _m(81, '%')});
      expect(malts[0]['color'], _m(3.5, 'EBC'));
      expect(malts[0]['type'], 'grain');
      // Valeurs du fichier : jamais remplacées.
      expect(malts[1]['yield'], {'fine_grind': _m(79, '%')});
      expect(malts[1]['color'], _m(4, 'EBC'));
      final houblons = _lignes(r.recipe, 'hop_additions');
      expect(houblons[0]['alpha_acid'], _m(3.5, '%'));
      expect(houblons[0]['form'], 'pellet');
      // Acide alpha nul dans l'index : rien n'est repris.
      expect(houblons[1].containsKey('alpha_acid'), isFalse);
      final levure = _lignes(r.recipe, 'culture_additions').single;
      expect(levure['type'], 'ale');
      expect(levure['form'], 'liquid');
      expect(levure['attenuation'], _m(75, '%'));
      expect(
        [for (final x in r.reprises) _reprise(x)],
        [
          'rendement(malt pils)',
          'couleur(malt pils)',
          'acidesAlpha(SAAZ)',
          'forme(SAAZ)',
          'type(Coriandre)',
          'type(Wyeast 1056 American Ale)',
          'forme(Wyeast 1056 American Ale)',
          'attenuation(Wyeast 1056 American Ale)',
        ],
      );
      // La recette lue n'est pas modifiée.
      expect(
        _lignes(source, 'fermentable_additions')[0].containsKey('color'),
        isFalse,
      );
    });

    test(
      'noms non résolus : une fois chacun, empreinte propre à l\'import',
      () {
        final r = completerRecette(_recette(), _tous);
        expect(
          [for (final n in r.nonResolus) '${n.nature}|${n.nom}'],
          ['fermentable|Caramel', 'misc|Épice Inconnue'],
        );
        final epice = r.nonResolus.last;
        // sha256('import|misc|epice-inconnue') : jamais celle de l'ingestion.
        expect(
          epice.empreinte,
          sha256.convert(utf8.encode('import|misc|epice-inconnue')).toString(),
        );
        expect(
          epice.empreinte,
          isNot(
            ingestion.idNonResolu(
              ingestion.NatureReferentiel.misc,
              'Épice Inconnue',
            ),
          ),
        );
        expect(epice.empreinte, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(
          epice.empreinte,
          empreinteNonResoluImport('misc', 'epice inconnue'),
        );
      },
    );

    test('sans index : recette inchangée, aucun nom non résolu', () {
      final source = _recette();
      final r = completerRecette(source, _vide);
      expect(r.recipe, source);
      expect(r.reprises, isEmpty);
      expect(r.nonResolus, isEmpty);
      expect(_vide.complet, isFalse);
      expect(_tous.complet, isTrue);
    });

    test('une valeur hors du schéma n\'est pas reprise', () {
      final index = IndexImport(
        houblons: IndexBibliotheque(ListeRecette.houblons, const [
          EntreeBibliotheque(id: 'hop-x', nom: 'X', alpha: 120, forme: 'cube'),
        ]),
      );
      final r = completerRecette({
        'name': 'R',
        'ingredients': {
          'hop_additions': [
            {'name': 'X', 'amount': _m(1, 'g')},
          ],
        },
      }, index);
      final h = _lignes(r.recipe, 'hop_additions').single;
      expect(h.containsKey('alpha_acid'), isFalse);
      expect(h.containsKey('form'), isFalse);
      expect(r.reprises, isEmpty);
    });
  });
}
