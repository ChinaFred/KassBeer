import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final fixture = loadFixture('density');

  test('SG → points', () {
    for (final c in objects(fixture['sg_to_points'])) {
      expect(sgToPoints(number(c['sg'])), closeTo(number(c['expected']), 1e-9));
    }
  });

  test('points → SG', () {
    for (final c in objects(fixture['points_to_sg'])) {
      expect(
        pointsToSg(number(c['points'])),
        closeTo(number(c['expected']), 1e-12),
      );
    }
  });

  test('lecture de la notation des fiches', () {
    for (final c in objects(fixture['parse'])) {
      expect(
        parseGravity(c['text'] as String),
        closeTo(number(c['expected']), 1e-12),
        reason: label(c),
      );
    }
  });

  test('notation illisible ou hors intervalle refusée', () {
    for (final c in objects(fixture['parse_invalid'])) {
      expectInvalid(() => parseGravity(c['text'] as String), label(c));
    }
  });

  test('SG hors intervalle refusée', () {
    expectInvalid(() => sgToPoints(1.61), '1.61');
    expectInvalid(() => pointsToSg(500), '500 points');
  });
}
