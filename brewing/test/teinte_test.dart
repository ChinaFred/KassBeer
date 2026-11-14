import 'package:brewing/brewing.dart';
import 'package:brewing/src/teintes_srm.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// `#RRGGBB` d'une fixture en entier `0xRRGGBB`.
int hex(Object? value) {
  final text = value as String;
  expect(text, matches(RegExp(r'^#[0-9A-F]{6}$')));
  return int.parse(text.substring(1), radix: 16);
}

void main() {
  final fixture = loadFixture('teinte');

  test('table : 400 teintes de 0 à 255', () {
    expect(teintesSrm, hasLength(400));
    for (final (r, g, b) in teintesSrm) {
      for (final v in [r, g, b]) {
        expect(v, inInclusiveRange(0, 255));
      }
    }
  });

  test('limite haute : 78,8 EBC', () {
    expect(teinteEbcLimite, closeTo(number(fixture['limite_ebc']), 1e-9));
  });

  test('teinteEbc', () {
    final cases = objects(fixture['teinte']);
    expect(cases, isNotEmpty);
    for (final c in cases) {
      final expected = hex(c['expected']);
      expect(teinteEbc(number(c['ebc'])), expected, reason: label(c));
      // La valeur attendue est celle de l'indice noté dans la fixture.
      final (r, g, b) = teintesSrm[c['table_index'] as int];
      expect(r << 16 | g << 8 | b, expected, reason: '${label(c)} : indice');
    }
  });

  test('degradeEbc', () {
    for (final c in objects(fixture['degrade'])) {
      expect(
        degradeEbc(
          number(c['debut']),
          number(c['fin']),
          points: c['points'] as int,
        ),
        [for (final e in c['expected'] as List<Object?>) hex(e)],
        reason: label(c),
      );
    }
    expect(degradeEbc(8, 16), hasLength(24));
  });

  test('entrées invalides', () {
    for (final c in objects(fixture['invalid'])) {
      switch (c['fonction']) {
        case 'teinte':
          expectInvalid(() => teinteEbc(number(c['ebc'])), label(c));
        case 'degrade':
          expectInvalid(
            () => degradeEbc(
              number(c['debut']),
              number(c['fin']),
              points: c['points'] as int,
            ),
            label(c),
          );
        default:
          fail('fonction inconnue : ${c['fonction']}');
      }
    }
    expectInvalid(() => teinteEbc(double.nan), 'NaN');
    expectInvalid(() => teinteEbc(double.infinity), 'infini');
    expectInvalid(() => degradeEbc(double.nan, 10), 'NaN');
  });
}
