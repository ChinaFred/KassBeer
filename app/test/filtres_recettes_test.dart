import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/recipes/domain/filtres_recettes.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/boite_filtres_recettes.dart';

void main() {
  group('origine', () {
    test('Toutes, Les miennes, Autres', () {
      expect(OrigineRecettes.toutes.contient('a', 'moi'), isTrue);
      expect(OrigineRecettes.miennes.contient('moi', 'moi'), isTrue);
      expect(OrigineRecettes.miennes.contient('a', 'moi'), isFalse);
      expect(OrigineRecettes.autres.contient('a', 'moi'), isTrue);
      expect(OrigineRecettes.autres.contient('moi', 'moi'), isFalse);
      expect(OrigineRecettes.miennes.montreIllisibles, isFalse);
      expect(OrigineRecettes.autres.montreIllisibles, isTrue);
      expect(OrigineRecettes.toutes.montreIllisibles, isTrue);
    });
  });

  group('outils', () {
    test('bornesDe : min et max des valeurs, null sans valeur', () {
      expect(bornesDe([null, 5.2, 9, null, 6]), const Intervalle(5.2, 9));
      expect(bornesDe([null, null]), isNull);
      expect(bornesDe(const []), isNull);
    });

    test('cleStyle et motsAromes : sans casse ni accents', () {
      expect(cleStyle('  Bière de Garde '), 'biere de garde');
      expect(cleStyle(null), kSansStyle);
      expect(cleStyle('  '), kSansStyle);
      expect(motsAromes(' Agrumes, , PÊCHE ,'), ['agrumes', 'peche']);
      expect(motsAromes(''), isEmpty);
    });

    test('stylesComptes : du plus fréquent, première graphie, sans style '
        'en dernier', () {
      final s = stylesComptes(['IPA', 'Tripel', 'ipa', null, 'Stout', '']);
      expect(
        [for (final x in s) (x.cle, x.libelle, x.nombre)],
        [
          ('ipa', 'IPA', 2),
          ('stout', 'Stout', 1),
          ('tripel', 'Tripel', 1),
          (kSansStyle, null, 2),
        ],
      );
    });

    test('curseurDe : bornes élargies au pas, null pour une valeur unique', () {
      final c = curseurDe(const Intervalle(5.24, 8.96), 0.1)!;
      expect(c.bornes.min, closeTo(5.2, 1e-9));
      expect(c.bornes.max, closeTo(9.0, 1e-9));
      expect(c.divisions, 38);
      expect(curseurDe(const Intervalle(12, 12), 1), isNull);
      expect(curseurDe(null, 1), isNull);
      expect(curseurDe(const Intervalle(7.4, 38.2), 1)!.divisions, 32);
    });
  });

  group('filtres', () {
    bool accepte(
      FiltresRecettes f, {
      String? style,
      double? degre,
      double? ebc,
      String? description,
    }) => f.accepte(
      style: style,
      degre: degre,
      ebc: ebc,
      description: description,
    );

    test('vide : tout passe, aucun groupe actif', () {
      expect(FiltresRecettes.vide.groupesActifs, 0);
      expect(FiltresRecettes.vide.actifs, isFalse);
      expect(accepte(FiltresRecettes.vide), isTrue);
    });

    test('styles en « ou », sans casse ni accents, « Sans style »', () {
      final f = FiltresRecettes.vide.avecStyles({'ipa', kSansStyle});
      expect(accepte(f, style: 'IPA'), isTrue);
      expect(accepte(f, style: null), isTrue);
      expect(accepte(f, style: 'Tripel'), isFalse);
      expect(
        accepte(
          FiltresRecettes.vide.avecStyles({'biere de garde'}),
          style: 'Bière de garde',
        ),
        isTrue,
      );
    });

    test('degré et couleur : bornes comprises, valeur absente exclue', () {
      final f = FiltresRecettes.vide
          .avecDegre(const Intervalle(5, 9))
          .avecEbc(const Intervalle(8, 40));
      expect(accepte(f, degre: 5, ebc: 40), isTrue);
      expect(accepte(f, degre: 9.1, ebc: 20), isFalse);
      expect(accepte(f, degre: 6, ebc: 7), isFalse);
      expect(accepte(f, degre: null, ebc: 20), isFalse);
      expect(accepte(f, degre: 6, ebc: null), isFalse);
      expect(f.groupesActifs, 2);
    });

    test('arômes : tous les mots, sans casse ni accents', () {
      final f = FiltresRecettes.vide.avecAromes('agrumes, peche');
      expect(accepte(f, description: 'Agrumes, PÊCHE blanche'), isTrue);
      expect(accepte(f, description: 'Agrumes seuls'), isFalse);
      expect(accepte(f, description: null), isFalse);
      expect(FiltresRecettes.vide.avecAromes(' , ').groupesActifs, 0);
    });

    test('critères combinés en « et » ; quatre groupes au plus', () {
      final f = FiltresRecettes.vide
          .avecStyles({'tripel'})
          .avecDegre(const Intervalle(7, 10))
          .avecEbc(const Intervalle(5, 20))
          .avecAromes('epices');
      expect(f.groupesActifs, 4);
      expect(
        accepte(
          f,
          style: 'Tripel',
          degre: 8.5,
          ebc: 12,
          description: 'Épices et poire',
        ),
        isTrue,
      );
      expect(
        accepte(
          f,
          style: 'IPA',
          degre: 8.5,
          ebc: 12,
          description: 'Épices et poire',
        ),
        isFalse,
      );
    });

    test('recherche : nom ou style, en minuscules', () {
      expect(correspondRecherche('', 'Blonde', null), isTrue);
      expect(correspondRecherche('ipa', 'West Coast', 'IPA'), isTrue);
      expect(correspondRecherche('blo', 'Blonde', null), isTrue);
      expect(correspondRecherche('stout', 'Blonde', 'IPA'), isFalse);
    });
  });

  group('relecture', () {
    test('ramener : bornée, nulle quand elle couvre les bornes', () {
      const b = Intervalle(4, 10);
      expect(ramener(const Intervalle(2, 8), b), const Intervalle(4, 8));
      expect(ramener(const Intervalle(1, 20), b), isNull);
      expect(ramener(const Intervalle(12, 20), b), const Intervalle(10, 10));
      // Valeurs toutes égales : une plage hors des bornes reste active.
      const egales = Intervalle(6, 6);
      expect(ramener(const Intervalle(7, 9), egales), const Intervalle(6, 6));
      expect(ramener(const Intervalle(5, 9), egales), isNull);
      // Seule la plage d'avant la réduction décide du retrait.
      expect(ramener(const Intervalle(2, 9), b), const Intervalle(4, 9));
      expect(ramener(const Intervalle(2, 8), null), const Intervalle(2, 8));
      expect(ramener(null, b), isNull);
    });

    test('motsSaisis et sansMot', () {
      final f = FiltresRecettes.vide.avecAromes(' Poire , ,pin');
      expect(f.motsSaisis, ['Poire', 'pin']);
      expect(f.sansMot('Poire').aromes, 'pin');
      expect(f.sansMot('pin').sansMot('Poire').groupesActifs, 0);
    });
  });

  group('description aromatique (aroma_description)', () {
    const content = RecipeContent(
      name: 'Blonde',
      aromaDescription: 'Agrumes et miel.',
    );

    test('écrite dans l\'enveloppe, jamais dans recipe ; relue', () {
      final data = content.toFirestore(creation: true);
      expect(data['aroma_description'], 'Agrumes et miel.');
      expect(
        (data['recipe']! as Map).containsKey('aroma_description'),
        isFalse,
      );
      final relue = RecipeContent.fromFirestore({
        ...data,
        'recipe': {...(data['recipe']! as Map)},
      });
      expect(relue.aromaDescription, 'Agrumes et miel.');
    });

    test('vide : absente à la création, supprimée à la modification', () {
      const vide = RecipeContent(name: 'Blonde', aromaDescription: '  ');
      expect(
        vide.toFirestore(creation: true).containsKey('aroma_description'),
        isFalse,
      );
      expect(
        vide.toFirestore(creation: false)['aroma_description'],
        FieldValue.delete(),
      );
    });

    test('« Dupliquer » la garde ; la copie figée d\'un brassin ne la garde '
        'pas', () {
      expect(content.duplicate().aromaDescription, 'Agrumes et miel.');
      expect(
        content.avecFormeHoublons('pellet').aromaDescription,
        'Agrumes et miel.',
      );
      final snapshot = recipeSnapshot(
        const Recipe(id: 'r', ownerUid: 'u', content: content),
      );
      expect(snapshot.containsKey('aroma_description'), isFalse);
      expect(snapshot['recipe'], isNotNull);
    });
  });
}
