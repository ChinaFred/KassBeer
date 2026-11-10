import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/formats.dart';

void main() {
  group('lireNombre (U1)', () {
    test('virgule ou point décimal', () {
      expect(lireNombre('22.4').valeur, 22.4);
      expect(lireNombre('22,4').valeur, 22.4);
      expect(lireNombre('1.500').valeur, 1.5);
    });

    test('espaces ignorés, y compris insécables', () {
      expect(lireNombre(' 22 400 ').valeur, 22400);
      expect(lireNombre('22 400').valeur, 22400);
    });

    test('plus d\'un séparateur : illisible', () {
      expect(lireNombre('1.234,5').illisible, isTrue);
      expect(lireNombre('1,2,3').illisible, isTrue);
      expect(lireNombre('1..5').illisible, isTrue);
    });

    test('texte non numérique : illisible ; vide : sans valeur', () {
      expect(lireNombre('abc').illisible, isTrue);
      expect(lireNombre('12a').illisible, isTrue);
      expect(lireNombre('').valeur, isNull);
      expect(lireNombre('').illisible, isFalse);
    });
  });

  group('erreurNombre', () {
    test('messages', () {
      expect(erreurNombre('', obligatoire: true), 'Champ obligatoire.');
      expect(erreurNombre(''), isNull);
      expect(erreurNombre('1.234,5'), 'Nombre illisible.');
      expect(erreurNombre('-1'), 'Nombre positif attendu.');
      expect(erreurNombre('0', minExclu: true), 'Nombre positif attendu.');
      expect(erreurNombre('101', max: 100), 'Entre 0 et 100.');
      expect(erreurNombre('100', max: 100), isNull);
      expect(erreurNombre('22,4'), isNull);
    });
  });

  group('affichage à la française', () {
    test('densité, degré, IBU, EBC (C11)', () {
      expect(formatDensite(1.0579), '1057,9');
      expect(formatDensite(1.01), '1010,0');
      expect(formatDegre(6.62), '6,6 % vol');
      expect(formatIbu(32.4), '32 IBU');
      expect(formatEbc(17.6), '18 EBC');
    });

    test('masses, volumes, milliers', () {
      expect(formatGrammes(22.4), '22,4 g');
      expect(formatGrammes(22400), '22 400 g');
      expect(formatKilogrammes(4500), '4,5 kg');
      expect(formatKilogrammes(850), '0,85 kg');
      expect(formatLitres(20), '20 L');
    });

    test('durée à cru en jours', () {
      expect(formatJours(3 * minutesParJour.toDouble()), '3 jours');
      expect(formatJours(minutesParJour.toDouble()), '1 jour');
    });

    test('date longue, « 1er » le premier du mois', () {
      expect(formatDateLongue(DateTime(2026, 11, 8)), '8 novembre 2026');
      expect(formatDateLongue(DateTime(2026, 2, 1)), '1er février 2026');
      expect(formatDateLongue(DateTime(2026, 12, 31)), '31 décembre 2026');
    });

    test('date en chiffres « jj/mm/aa »', () {
      expect(formatDateChiffres(DateTime(2026, 11, 8)), '08/11/26');
      expect(formatDateChiffres(DateTime(2030, 1, 31)), '31/01/30');
    });

    test('texte d\'un champ : virgule, sans espace', () {
      expect(texteSaisi(4.5), '4,5');
      expect(texteSaisi(22400), '22400');
      expect(texteSaisi(null), '');
    });
  });

  group('nombres non finis et bornes des règles', () {
    test('plus de 309 chiffres : illisible, jamais l\x27infini', () {
      final lu = lireNombre('1' * 400);
      expect(lu.illisible, isTrue);
      expect(lu.valeur, isNull);
      expect(erreurNombre('1' * 400), 'Nombre illisible.');
    });

    test('à partir de 1e9 : refusé comme par les règles', () {
      expect(erreurNombre('999999999'), isNull);
      expect(erreurNombre('1000000000'), 'Nombre trop grand.');
    });

    test('« 1,5 jour » au singulier sous 2', () {
      expect(formatJours(1.5 * minutesParJour), '1,5 jour');
      expect(formatJours(2.0 * minutesParJour), '2 jours');
    });
  });
}
