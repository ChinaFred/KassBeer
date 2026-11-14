import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/services/app_update_transport.dart';
import 'package:kass_beer/core/services/app_update_transport_io.dart';

/// Transport `dart:io` de la mise à jour de l'APK (ADR-012), contre un serveur
/// HTTP local : réponses lues, erreurs de réseau rendues sans exception.
void main() {
  late HttpServer serveur;
  late Directory dossier;
  late Future<void> Function(HttpRequest) repondre;
  final transport = TransportMiseAJourPlateforme();

  setUp(() async {
    serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serveur.listen((requete) => repondre(requete));
    dossier = await Directory.systemTemp.createTemp('kass-beer-maj');
  });

  tearDown(() async {
    await serveur.close(force: true);
    await dossier.delete(recursive: true);
  });

  Uri url(String chemin) =>
      Uri.parse('http://127.0.0.1:${serveur.port}$chemin');

  group('lireManifeste', () {
    test('200 : code et corps', () async {
      repondre = (r) async {
        r.response.write('{"version":"0.1.46"}');
        await r.response.close();
      };
      final rep = await transport.lireManifeste(
        url('/apk_release.json'),
        delai: const Duration(seconds: 2),
        maxOctets: 4096,
      );
      expect(rep!.statut, 200);
      expect(String.fromCharCodes(rep.octets), '{"version":"0.1.46"}');
    });

    test('404 : code rendu, sans exception', () async {
      repondre = (r) async {
        r.response.statusCode = 404;
        await r.response.close();
      };
      final rep = await transport.lireManifeste(
        url('/x'),
        delai: const Duration(seconds: 2),
        maxOctets: 4096,
      );
      expect(rep!.statut, 404);
    });

    test('corps lu jusqu\'à la borne + 1 octet', () async {
      repondre = (r) async {
        r.response.add(List<int>.filled(10000, 0x20));
        await r.response.close();
      };
      final rep = await transport.lireManifeste(
        url('/x'),
        delai: const Duration(seconds: 2),
        maxOctets: 4096,
      );
      expect(rep!.octets, hasLength(4097));
    });

    test('délai dépassé : null', () async {
      final fin = Completer<void>();
      repondre = (r) async {
        await fin.future;
        await r.response.close();
      };
      final rep = await transport.lireManifeste(
        url('/x'),
        delai: const Duration(milliseconds: 200),
        maxOctets: 4096,
      );
      expect(rep, isNull);
      fin.complete();
    });

    test('connexion refusée : null', () async {
      final port = serveur.port;
      await serveur.close(force: true);
      serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final rep = await transport.lireManifeste(
        Uri.parse('http://127.0.0.1:$port/x'),
        delai: const Duration(seconds: 2),
        maxOctets: 4096,
      );
      expect(rep, isNull);
    });
  });

  group('telecharger', () {
    final contenu = List<int>.generate(5000, (i) => i % 251);

    Future<Transfert> lancer({
      required int max,
      bool Function()? annule,
      List<int>? progres,
    }) => transport.telecharger(
      url('/app-release.apk'),
      '${dossier.path}/kass-beer-update.apk',
      maxOctets: max,
      annule: annule ?? () => false,
      progression: (n) => progres?.add(n),
    );

    test('fichier complet : taille et SHA-256 calculé à l\'écriture', () async {
      repondre = (r) async {
        r.response.add(contenu);
        await r.response.close();
      };
      final progres = <int>[];
      final issue = await lancer(max: 5000, progres: progres) as TransfertFini;
      expect(issue.octets, 5000);
      expect(issue.sha256, sha256.convert(contenu).toString());
      expect(progres.last, 5000);
      final ecrit = File('${dossier.path}/kass-beer-update.apk');
      expect(await ecrit.readAsBytes(), contenu);
    });

    test('plus long que la borne : arrêté', () async {
      repondre = (r) async {
        r.response.add(contenu);
        await r.response.close();
      };
      expect(await lancer(max: 4999), isA<TransfertTropLong>());
    });

    test('code différent de 200 : interrompu', () async {
      repondre = (r) async {
        r.response.statusCode = 503;
        await r.response.close();
      };
      expect(await lancer(max: 5000), isA<TransfertInterrompu>());
    });

    test('annulé : interrompu', () async {
      repondre = (r) async {
        r.response.add(contenu);
        await r.response.close();
      };
      expect(
        await lancer(max: 5000, annule: () => true),
        isA<TransfertInterrompu>(),
      );
    });

    test('connexion coupée en cours de corps : interrompu', () async {
      repondre = (r) async {
        r.response.contentLength = 5000;
        final socket = await r.response.detachSocket();
        socket.add(contenu.sublist(0, 1000));
        await socket.flush();
        socket.destroy();
      };
      expect(await lancer(max: 5000), isA<TransfertInterrompu>());
    });

    test('dossier absent : écriture impossible', () async {
      repondre = (r) async {
        r.response.add(contenu);
        await r.response.close();
      };
      final issue = await transport.telecharger(
        url('/app-release.apk'),
        '${dossier.path}/absent/kass-beer-update.apk',
        maxOctets: 5000,
        annule: () => false,
        progression: (_) {},
      );
      expect(issue, isA<TransfertEcritureImpossible>());
    });

    test('supprimer : fichier effacé, absent sans erreur', () async {
      final f = File('${dossier.path}/kass-beer-update.apk');
      await f.writeAsBytes([1]);
      await transport.supprimer(f.path);
      expect(await f.exists(), isFalse);
      await transport.supprimer(f.path);
    });
  });
}
