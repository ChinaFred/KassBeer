import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/services/error_report_service.dart';

/// Champs admis par `firestore.rules`, `error_reports/`.
const _allowed = {
  'uid',
  'feature',
  'error',
  'stack_trace',
  'context',
  'app_version',
  'platform',
  'created_at',
};

void main() {
  test(
    'seuls les champs admis par les règles, created_at posé par le serveur',
    () {
      final fields = ErrorReportFields.build(
        uid: 'uid-1',
        feature: 'members.invite',
        error: Exception('refus'),
        stackTrace: StackTrace.current,
        context: 'étape 2',
        appVersion: '0.1.0',
        platform: 'web',
      ).data;
      expect(_allowed.containsAll(fields.keys), isTrue);
      expect(
        fields.keys,
        containsAll(['uid', 'feature', 'error', 'created_at']),
      );
      expect(fields['created_at'], isA<FieldValue>());
      expect(fields['context'], isA<String>());
      expect(fields['platform'], 'web');
    },
  );

  test('bornes de taille des règles', () {
    final long = 'x' * 20000;
    final fields = ErrorReportFields.build(
      uid: 'uid-1',
      feature: long,
      error: long,
      stackTrace: StackTrace.fromString(long),
      context: long,
      appVersion: long,
      platform: 'android',
    ).data;
    expect((fields['feature'] as String).length, lessThanOrEqualTo(100));
    expect((fields['error'] as String).length, lessThanOrEqualTo(2000));
    expect((fields['stack_trace'] as String).length, lessThanOrEqualTo(8000));
    expect((fields['context'] as String).length, lessThanOrEqualTo(2000));
    expect((fields['app_version'] as String).length, lessThanOrEqualTo(40));
  });

  test('aucune adresse e-mail dans le rapport', () {
    final fields = ErrorReportFields.build(
      uid: 'uid-1',
      feature: 'auth.sign_in',
      error: Exception('compte Jean.Dupont@exemple.fr refusé'),
      stackTrace: StackTrace.fromString('at jean@exemple.fr'),
      context: 'pour alice@exemple.fr',
      platform: 'web',
    ).data;
    for (final key in ['error', 'stack_trace', 'context']) {
      expect(
        fields[key] as String,
        isNot(contains('@exemple.fr')),
        reason: key,
      );
      expect(
        fields[key] as String,
        contains(ErrorReportFields.emailPlaceholder),
        reason: key,
      );
    }
  });

  test('champs facultatifs vides omis, feature vide nommée', () {
    final fields = ErrorReportFields.build(
      uid: 'uid-1',
      feature: '  ',
      error: 'e',
      platform: 'android',
    ).data;
    expect(fields.containsKey('stack_trace'), isFalse);
    expect(fields.containsKey('context'), isFalse);
    expect(fields.containsKey('app_version'), isFalse);
    expect((fields['feature'] as String).isNotEmpty, isTrue);
  });

  test('coupe sans séparer une paire de substitution', () {
    final value = '${'a' * 8}😀😀';
    final cut = ErrorReportFields.truncate(value, 10);
    expect(cut.length, lessThanOrEqualTo(10));
    expect(cut.endsWith('…'), isTrue);
    final beforeEllipsis = cut.codeUnitAt(cut.length - 2);
    expect(beforeEllipsis >= 0xD800 && beforeEllipsis <= 0xDBFF, isFalse);
  });
}
