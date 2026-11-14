import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/fichiers/echange_fichiers.dart';

import 'support/fakes.dart';

/// Canal `fr.kassbeer/files` (ADR-007, P17) simulé par
/// `TestDefaultBinaryMessenger` : le Kotlin n'est couvert que par la
/// compilation de l'APK et un essai sur téléphone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(kCanalFichiers);

  late RecordingErrorReportService errors;
  late EchangeFichiersPlateforme fichiers;
  final calls = <MethodCall>[];

  setUp(() {
    errors = RecordingErrorReportService();
    fichiers = EchangeFichiersPlateforme(errorReportService: errors);
    calls.clear();
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void repondre(Future<Object?> Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });

  final octets = Uint8List.fromList([0x7B, 0x7D]);

  test(
    'noms du canal, des méthodes et des codes : ceux de EchangeFichiers.kt',
    () {
      expect(kCanalFichiers, 'fr.kassbeer/files');
      expect(kMethodeChoisir, 'pickDocument');
      expect(kMethodePartager, 'shareFile');
      expect(kMethodeEnregistrer, 'saveDocument');
      expect(kCodeTropGros, 'TOO_LARGE');
    },
  );

  test('Android : Enregistrer puis Partager le fichier', () {
    expect(fichiers.modes, [ModeEnvoi.enregistrer, ModeEnvoi.partager]);
    expect(ModeEnvoi.enregistrer.libelle, 'Enregistrer');
    expect(ModeEnvoi.partager.libelle, 'Partager le fichier');
    expect(ModeEnvoi.telecharger.libelle, 'Télécharger');
  });

  group('pickDocument', () {
    test('la borne vient du Dart ; choix annulé : rien de rapporté', () async {
      repondre((_) async => null);
      final r = await fichiers.choisir(maxOctets: 10 * 1024 * 1024);
      expect(r, isA<ChoixAnnule>());
      expect(calls.single.method, 'pickDocument');
      expect(calls.single.arguments, {'maxBytes': 10 * 1024 * 1024});
      expect(errors.reports, isEmpty);
    });

    test('fichier rendu : nom et octets', () async {
      repondre((_) async => {'name': 'ipa.json', 'bytes': octets});
      final r = await fichiers.choisir(maxOctets: 100) as FichierChoisi;
      expect(r.nom, 'ipa.json');
      expect(r.octets, octets);
    });

    test(
      'TOO_LARGE avec la taille du fournisseur : rapporté sans nom de fichier',
      () async {
        repondre(
          (_) async =>
              throw PlatformException(code: 'TOO_LARGE', details: 13000000),
        );
        final r = await fichiers.choisir(maxOctets: 100) as FichierTropGros;
        expect(r.taille, 13000000);
        final report = errors.reports.single;
        expect(report.feature, 'exchange.pick');
        expect(report.context, 'code TOO_LARGE, taille 13000000 octets');
      },
    );

    test(
      'TOO_LARGE sans taille (lecture arrêtée à la borne + 1 octet)',
      () async {
        repondre((_) async => throw PlatformException(code: 'TOO_LARGE'));
        final r = await fichiers.choisir(maxOctets: 100) as FichierTropGros;
        expect(r.taille, isNull);
      },
    );

    for (final code in ['ALREADY_ACTIVE', 'NO_PICKER', 'READ_FAILED']) {
      test('$code : ouverture impossible, rapportée avec son code', () async {
        repondre((_) async => throw PlatformException(code: code));
        expect(await fichiers.choisir(maxOctets: 100), isA<ChoixImpossible>());
        expect(errors.reports.single.context, 'code $code');
      });
    }

    test('réponse plus grosse que la borne : refusée', () async {
      repondre((_) async => {'name': 'a.json', 'bytes': Uint8List(101)});
      expect(await fichiers.choisir(maxOctets: 100), isA<FichierTropGros>());
    });

    test('filtre de types : passé au canal avec la borne', () async {
      repondre((_) async => {'name': 'photo.jpg', 'bytes': octets});
      final r = await fichiers.choisir(maxOctets: 100, types: kTypesImages);
      expect(r, isA<FichierChoisi>());
      expect(calls.single.arguments, {
        'maxBytes': 100,
        'mimeTypes': ['image/png', 'image/jpeg', 'image/webp'],
      });
    });

    test('filtre de types hors motif : refusé sans appel, rapporté', () async {
      repondre((_) async => null);
      for (final types in [
        <String>[],
        ['image/png;x=1'],
        ['IMAGE/PNG'],
        ['image'],
        List.filled(kTypesMax + 1, 'image/png'),
      ]) {
        expect(
          await fichiers.choisir(maxOctets: 100, types: types),
          isA<ChoixImpossible>(),
          reason: '$types',
        );
      }
      expect(calls, isEmpty);
      expect(errors.reports, hasLength(5));
      expect(errors.reports.first.context, 'filtre de types refusé');
    });

    test('motif des types : celui de EchangeFichiers.kt', () {
      expect(kMotifTypeMime.pattern, r'^[a-z]{1,20}/[a-z0-9.+*-]{1,60}$');
      expect(kTypesMax, 10);
      expect(kTypesImages.every(kMotifTypeMime.hasMatch), isTrue);
    });

    test('réponse inattendue : rapportée, ouverture impossible', () async {
      repondre((_) async => {'name': 3});
      expect(await fichiers.choisir(maxOctets: 100), isA<ChoixImpossible>());
      expect(errors.reports.single.feature, 'exchange.pick');
    });
  });

  group('shareFile et saveDocument', () {
    test('partager : nom, type et octets passés au canal', () async {
      repondre((_) async => null);
      final r = await fichiers.envoyer(
        ModeEnvoi.partager,
        nom: 'ipa.json',
        typeMime: 'application/json',
        octets: octets,
      );
      expect(r, isA<EnvoiFait>());
      expect(calls.single.method, 'shareFile');
      expect(calls.single.arguments, {
        'name': 'ipa.json',
        'mimeType': 'application/json',
        'bytes': octets,
      });
    });

    test('INVALID_NAME : envoi impossible, rapporté sans le nom', () async {
      repondre((_) async => throw PlatformException(code: 'INVALID_NAME'));
      final r = await fichiers.envoyer(
        ModeEnvoi.partager,
        nom: '../secret.json',
        typeMime: 'application/json',
        octets: octets,
      );
      expect(r, isA<EnvoiImpossible>());
      final report = errors.reports.single;
      expect(report.feature, 'exchange.share');
      expect(report.context, 'code INVALID_NAME, taille 2 octets');
      expect('${report.error}${report.context}', isNot(contains('secret')));
    });

    test('partage pendant un autre : ALREADY_ACTIVE, rapporté', () async {
      repondre((_) async => throw PlatformException(code: 'ALREADY_ACTIVE'));
      final r = await fichiers.envoyer(
        ModeEnvoi.partager,
        nom: 'ipa.json',
        typeMime: 'application/json',
        octets: octets,
      );
      expect(r, isA<EnvoiImpossible>());
      expect(
        errors.reports.single.context,
        'code ALREADY_ACTIVE, taille 2 octets',
      );
    });

    test('enregistrer : vrai si écrit, faux si annulé', () async {
      repondre((_) async => true);
      expect(
        await fichiers.envoyer(
          ModeEnvoi.enregistrer,
          nom: 'ipa.json',
          typeMime: 'application/json',
          octets: octets,
        ),
        isA<EnvoiFait>(),
      );
      expect(calls.single.method, 'saveDocument');
      repondre((_) async => false);
      expect(
        await fichiers.envoyer(
          ModeEnvoi.enregistrer,
          nom: 'ipa.json',
          typeMime: 'application/json',
          octets: octets,
        ),
        isA<EnvoiAnnule>(),
      );
    });

    test(
      'WRITE_FAILED à l\'enregistrement : rapporté sous exchange.save',
      () async {
        repondre((_) async => throw PlatformException(code: 'WRITE_FAILED'));
        final r = await fichiers.envoyer(
          ModeEnvoi.enregistrer,
          nom: 'ipa.json',
          typeMime: 'application/json',
          octets: octets,
        );
        expect(r, isA<EnvoiImpossible>());
        expect(errors.reports.single.feature, 'exchange.save');
      },
    );

    test('téléchargement hors du web : refusé et rapporté', () async {
      final r = await fichiers.envoyer(
        ModeEnvoi.telecharger,
        nom: 'ipa.json',
        typeMime: 'application/json',
        octets: octets,
      );
      expect(r, isA<EnvoiImpossible>());
      expect(errors.reports.single.feature, 'exchange.share');
    });
  });
}
