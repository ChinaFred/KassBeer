import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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
  // Installe la plateforme FieldValue de fake_cloud_firestore avant le premier
  // FieldValue.serverTimestamp() du fichier.
  setUpAll(FakeFirebaseFirestore.new);

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

  test('aucune URL dans le rapport (photo Google, jeton)', () {
    final fields = ErrorReportFields.build(
      uid: 'uid-1',
      feature: 'shell.avatar',
      error: Exception(
        'HTTP 403 pour https://lh3.googleusercontent.com/a/ACg8oc?sz=96&token=abc',
      ),
      stackTrace: StackTrace.fromString(
        'https://kassbeer.web.app/main.dart.js 1234:56  f',
      ),
      context: 'image http://exemple.fr/x.png illisible',
      platform: 'web',
    ).data;
    for (final key in ['error', 'stack_trace', 'context']) {
      final value = fields[key] as String;
      expect(value, isNot(contains('://')), reason: key);
      expect(value, contains(ErrorReportFields.urlPlaceholder), reason: key);
    }
    expect(fields['error'] as String, contains('HTTP 403'));
    expect(fields['stack_trace'] as String, contains('1234:56'));
  });

  group('plafonds d\'écriture', () {
    late FakeFirebaseFirestore firestore;
    late DateTime now;
    late ErrorReportService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      now = DateTime(2026, 11, 7, 12);
      service = ErrorReportService(
        firestore: firestore,
        currentUid: () => 'uid-1',
        clock: () => now,
      );
    });

    /// Documents écrits, une fois les écritures en mémoire terminées : attend au
    /// plus 2 s que [expected] soit atteint, puis 100 ms de plus pour voir un excès.
    Future<int> written(int expected) async {
      Future<int> count() async =>
          (await firestore.collection('error_reports').get()).size;
      for (var i = 0; i < 100 && await count() < expected; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return count();
    }

    test('500 rapports identiques en 1 s : une écriture', () async {
      final stack = StackTrace.fromString('#0 main (file:///a.dart:1:1)');
      for (var i = 0; i < 500; i++) {
        now = now.add(const Duration(milliseconds: 2));
        service.reportError(
          feature: 'boucle',
          error: StateError('même $i'),
          stackTrace: stack,
        );
      }
      expect(await written(1), 1);
      expect(service.skippedCount, 499);
    });

    test('500 rapports distincts en 1 s : au plus 20', () async {
      for (var i = 0; i < 500; i++) {
        now = now.add(const Duration(milliseconds: 2));
        service.reportError(feature: 'distinct.$i', error: StateError('e'));
      }
      expect(
        await written(ErrorReportService.maxPerMinute),
        ErrorReportService.maxPerMinute,
      );
    });

    test('au plus 200 par session, même étalés dans le temps', () async {
      for (var i = 0; i < 500; i++) {
        now = now.add(const Duration(seconds: 10));
        service.reportError(feature: 'distinct.$i', error: StateError('e'));
      }
      expect(
        await written(ErrorReportService.maxPerSession),
        ErrorReportService.maxPerSession,
      );
    });

    test('la fenêtre d\'une minute se libère', () async {
      for (var i = 0; i < 25; i++) {
        service.reportError(feature: 'a.$i', error: StateError('e'));
      }
      now = now.add(const Duration(minutes: 1));
      for (var i = 0; i < 25; i++) {
        service.reportError(feature: 'b.$i', error: StateError('e'));
      }
      expect(await written(40), 40);
    });
  });
}
