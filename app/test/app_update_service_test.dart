import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/services/app_installer.dart';
import 'package:kass_beer/core/services/app_update_service.dart';
import 'package:kass_beer/core/services/app_update_transport.dart';

import 'support/fakes.dart';

/// Service de mise à jour de l'APK (ADR-012) : manifeste, comparaison par
/// build, rapports (arbitrages 2 et 6).
void main() {
  const sha =
      'a3b1c2d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9a';

  Map<String, Object?> manifeste({
    Object? version = '0.1.46',
    Object? build = 47,
    Object? taille = 52428800,
    Object? empreinte = sha,
  }) => {
    'version': version,
    'build_number': build,
    'file': 'app-release.apk',
    'size_bytes': taille,
    'sha256': empreinte,
    'built_at': '2026-11-14T10:00:00Z',
  };

  List<int> corps(Object? json) => utf8.encode(jsonEncode(json));

  late RecordingErrorReportService errors;
  late FakeTransportMiseAJour transport;
  late FakeInstallateurApk installateur;

  AppUpdateService service({
    int? build = 46,
    bool android = true,
    String? version = '0.1.45',
  }) => AppUpdateService(
    errorReportService: errors,
    installateur: installateur,
    buildInstalle: build,
    versionInstallee: version,
    transport: transport,
    estAndroid: () => android,
    horloge: () => DateTime.utc(2026, 11, 14, 10),
  );

  setUp(() {
    errors = RecordingErrorReportService();
    transport = FakeTransportMiseAJour();
    installateur = FakeInstallateurApk();
  });

  group('ManifesteApk.lire', () {
    test('manifeste valide : les quatre champs lus', () {
      final m = ManifesteApk.lire(corps(manifeste()));
      expect(m.version, '0.1.46');
      expect(m.build, 47);
      expect(m.tailleOctets, 52428800);
      expect(m.sha256, sha);
    });

    final refus = <String, Map<String, Object?>>{
      'version absente': manifeste(version: null),
      'version 0.1': manifeste(version: '0.1'),
      'version v0.1.46': manifeste(version: 'v0.1.46'),
      'version nombre': manifeste(version: 46),
      'build_number absent': manifeste(build: null),
      'build_number texte': manifeste(build: '47'),
      'build_number décimal': manifeste(build: 47.5),
      'build_number 0': manifeste(build: 0),
      'build_number au-delà de 2 100 000 000': manifeste(build: 2100000001),
      'size_bytes absent': manifeste(taille: null),
      'size_bytes 0': manifeste(taille: 0),
      'size_bytes au-delà de 200 000 000': manifeste(taille: 200000001),
      'sha256 absent': manifeste(empreinte: null),
      'sha256 en majuscules': manifeste(empreinte: sha.toUpperCase()),
      'sha256 de 63 caractères': manifeste(empreinte: sha.substring(1)),
      'sha256 non hexadécimal': manifeste(empreinte: 'z${sha.substring(1)}'),
    };
    for (final cas in refus.entries) {
      test('refusé : ${cas.key}', () {
        expect(
          () => ManifesteApk.lire(corps(cas.value)),
          throwsA(isA<ManifesteIllisible>()),
        );
      });
    }

    test('bornes acceptées : build 2 100 000 000, taille 200 000 000', () {
      final m = ManifesteApk.lire(
        corps(manifeste(build: 2100000000, taille: 200000000)),
      );
      expect(m.build, 2100000000);
    });

    test('corps HTML, tableau, corps de plus de 4 096 octets : refusés', () {
      for (final octets in [
        utf8.encode('<!doctype html><html></html>'),
        corps([1, 2]),
        List<int>.filled(4097, 0x20),
        [0xff, 0xfe],
      ]) {
        expect(
          () => ManifesteApk.lire(octets),
          throwsA(isA<ManifesteIllisible>()),
        );
      }
    });
  });

  group('verifier', () {
    test('build publié supérieur : proposé, URL horodatée', () async {
      transport.manifeste = ReponseManifeste(200, corps(manifeste()));
      final dispo = await service().verifier();
      expect(dispo!.manifeste.build, 47);
      expect(dispo.versionInstallee, '0.1.45');
      final url = transport.lectures.single;
      expect(url.origin, 'https://kassbeer.web.app');
      expect(url.path, '/apk_release.json');
      expect(url.queryParameters['t'], isNotEmpty);
      expect(errors.reports, isEmpty);
    });

    test(
      'build égal ou inférieur : rien, quelle que soit la version',
      () async {
        transport.manifeste = ReponseManifeste(
          200,
          corps(manifeste(version: '9.9.9', build: 46)),
        );
        expect(await service().verifier(), isNull);
        transport.manifeste = ReponseManifeste(
          200,
          corps(manifeste(build: 12)),
        );
        expect(await service().verifier(), isNull);
        expect(errors.reports, isEmpty);
      },
    );

    test('web ou autre plateforme : rien, aucun appel réseau', () async {
      transport.manifeste = ReponseManifeste(200, corps(manifeste()));
      expect(await service(android: false).verifier(), isNull);
      expect(transport.lectures, isEmpty);
    });

    test('build installé illisible : rien, aucun appel réseau', () async {
      expect(await service(build: null).verifier(), isNull);
      expect(transport.lectures, isEmpty);
    });

    test('échec de réseau : rien, aucun rapport', () async {
      transport.manifeste = null;
      expect(await service().verifier(), isNull);
      expect(errors.reports, isEmpty);
    });

    test('code différent de 200 : rien, aucun rapport', () async {
      for (final code in [404, 500, 304]) {
        transport.manifeste = ReponseManifeste(code, corps(manifeste()));
        expect(await service().verifier(), isNull);
      }
      expect(errors.reports, isEmpty);
    });

    test('200 illisible : rapport app_update_check avec le champ', () async {
      transport.manifeste = ReponseManifeste(
        200,
        corps(manifeste(empreinte: 'abc')),
      );
      expect(await service().verifier(), isNull);
      final r = errors.reports.single;
      expect(r.feature, 'app_update_check');
      expect(r.context, 'raison: sha256');
    });

    test(
      'index.html servi en 200 pour un manifeste absent : rapporté',
      () async {
        transport.manifeste = ReponseManifeste(
          200,
          utf8.encode('<!DOCTYPE html>'),
        );
        expect(await service().verifier(), isNull);
        expect(errors.reports.single.context, 'raison: corps non JSON');
      },
    );
  });

  group('telecharger', () {
    final m = ManifesteApk.lire(corps(manifeste(taille: 300)));

    test('fichier conforme : prêt, borne = size_bytes, progression', () async {
      transport.progressions = [100, 300];
      transport.transfert = const TransfertFini(300, sha);
      final progres = <int>[];
      final issue = await service().telecharger(
        m,
        suivi: ApkDownload(),
        progression: (recus, total) {
          expect(total, 300);
          progres.add(recus);
        },
      );
      expect(issue, Telechargement.pret);
      expect(progres, [100, 300]);
      final t = transport.telechargements.single;
      expect(t.url.toString(), 'https://kassbeer.web.app/app-release.apk');
      expect(t.chemin, '/cache/updates/kass-beer-update.apk');
      expect(t.max, 300);
      expect(transport.suppressions, isEmpty);
      expect(errors.reports, isEmpty);
    });

    test(
      'coupure de réseau : interrompu, fichier effacé, aucun rapport',
      () async {
        transport.transfert = const TransfertInterrompu();
        final issue = await service().telecharger(m, suivi: ApkDownload());
        expect(issue, Telechargement.interrompu);
        expect(transport.suppressions, hasLength(1));
        expect(errors.reports, isEmpty);
      },
    );

    test('annulation : annulé, fichier effacé, aucun rapport', () async {
      final suivi = ApkDownload();
      transport.progressions = [100, 200];
      transport.pendantTransfert = suivi.annuler;
      final issue = await service().telecharger(m, suivi: suivi);
      expect(issue, Telechargement.annule);
      expect(transport.suppressions, hasLength(1));
      expect(errors.reports, isEmpty);
    });

    test('taille différente : refusé, effacé, rapport sans chemin', () async {
      transport.transfert = const TransfertFini(299, sha);
      final issue = await service().telecharger(m, suivi: ApkDownload());
      expect(issue, Telechargement.refuse);
      expect(transport.suppressions, hasLength(1));
      final r = errors.reports.single;
      expect(r.feature, 'app_update_download');
      expect(r.context, contains('taille'));
      expect('${r.error} ${r.context}', isNot(contains('/cache')));
    });

    test('plus d\'octets que size_bytes : refusé et rapporté', () async {
      transport.transfert = const TransfertTropLong();
      final issue = await service().telecharger(m, suivi: ApkDownload());
      expect(issue, Telechargement.refuse);
      expect(errors.reports.single.feature, 'app_update_download');
    });

    test('SHA-256 différent : refusé, effacé, rapporté', () async {
      transport.transfert = TransfertFini(300, 'b${sha.substring(1)}');
      final issue = await service().telecharger(m, suivi: ApkDownload());
      expect(issue, Telechargement.refuse);
      expect(transport.suppressions, hasLength(1));
      expect(errors.reports.single.context, 'raison: sha256');
    });

    test(
      'écriture impossible : rapport sans le message qui porte le chemin',
      () async {
        transport.transfert = TransfertEcritureImpossible(
          Exception('disque plein : /data/user/0/fr.kassbeer/cache/updates'),
          StackTrace.current,
        );
        final issue = await service().telecharger(m, suivi: ApkDownload());
        expect(issue, Telechargement.impossible);
        final r = errors.reports.single;
        expect('${r.error} ${r.context}', isNot(contains('/data')));
      },
    );

    test('effacement en échec : rapporté', () async {
      transport.transfert = const TransfertInterrompu();
      transport.erreurSuppression = Exception('/cache/updates refusé');
      await service().telecharger(m, suivi: ApkDownload());
      final r = errors.reports.single;
      expect(r.context, 'raison: effacement');
      expect('${r.error}', isNot(contains('/cache')));
    });

    test('dossier indisponible : impossible, aucun téléchargement', () async {
      installateur.dossier = null;
      final issue = await service().telecharger(m, suivi: ApkDownload());
      expect(issue, Telechargement.impossible);
      expect(transport.telechargements, isEmpty);
    });
  });

  group('installer', () {
    final m = ManifesteApk.lire(corps(manifeste()));

    test('le build du manifeste part vers le canal', () async {
      expect(await service().installer(m), Installation.ouverte);
      expect(installateur.builds, [47]);
      expect(errors.reports, isEmpty);
    });

    test(
      'paquet ou versionCode refusés : rapport app_update_download',
      () async {
        installateur.installation = Installation.refusee;
        expect(await service().installer(m), Installation.refusee);
        final r = errors.reports.single;
        expect(r.feature, 'app_update_download');
        expect(r.context, contains('apk_invalid'));
      },
    );
  });
}
