import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'app_update_transport.dart';

/// Android : `HttpClient` de `dart:io` et fichier de `cacheDir/updates/`
/// (ADR-012). Aucun paquet `http` : `dart:io` est déjà chargé sur l'appareil.
///
/// Les erreurs de réseau (`SocketException`, `TimeoutException`,
/// `HttpException`, `TlsException` dont `HandshakeException`) rendent `null` ou
/// [TransfertInterrompu] sans rapport : c'est l'exception écrite à « Aucun
/// `catch` silencieux » (ADR-012, arbitrages 2 et 6). Toute autre erreur
/// remonte à `AppUpdateService`, qui la rapporte.
class TransportMiseAJourPlateforme implements TransportMiseAJour {
  TransportMiseAJourPlateforme({HttpClient Function()? client})
    : _nouveauClient = client ?? HttpClient.new;

  final HttpClient Function() _nouveauClient;

  /// Délai sans octet reçu au-delà duquel un téléchargement est interrompu.
  static const delaiSilence = Duration(seconds: 30);

  @override
  Future<ReponseManifeste?> lireManifeste(
    Uri url, {
    required Duration delai,
    required int maxOctets,
  }) async {
    final client = _nouveauClient()..connectionTimeout = delai;
    try {
      return await _lire(client, url, maxOctets).timeout(delai);
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on HttpException {
      return null;
    } on TlsException {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<ReponseManifeste> _lire(
    HttpClient client,
    Uri url,
    int maxOctets,
  ) async {
    final requete = await client.getUrl(url);
    requete.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final reponse = await requete.close();
    final octets = <int>[];
    await for (final bloc in reponse) {
      final reste = maxOctets + 1 - octets.length;
      octets.addAll(bloc.length > reste ? bloc.sublist(0, reste) : bloc);
      if (octets.length > maxOctets) break;
    }
    return ReponseManifeste(reponse.statusCode, octets);
  }

  @override
  Future<Transfert> telecharger(
    Uri url,
    String chemin, {
    required int maxOctets,
    required bool Function() annule,
    required void Function(int recus) progression,
  }) async {
    final client = _nouveauClient()..connectionTimeout = delaiSilence;
    final ecriture = _Ecriture();
    Transfert issue;
    try {
      issue = await _recevoir(
        client,
        url,
        chemin,
        ecriture,
        maxOctets: maxOctets,
        annule: annule,
        progression: progression,
      );
    } on SocketException {
      issue = const TransfertInterrompu();
    } on TimeoutException {
      issue = const TransfertInterrompu();
    } on HttpException {
      issue = const TransfertInterrompu();
    } on TlsException {
      issue = const TransfertInterrompu();
    } on FileSystemException catch (erreur, pile) {
      issue = TransfertEcritureImpossible(erreur, pile);
    } finally {
      client.close(force: true);
    }
    // Le fichier est refermé avant que l'appelant ne le lise ou ne l'efface.
    // Une écriture refusée par le système ressort ici : elle devient l'issue
    // du transfert, rapportée par l'appelant.
    final sortie = ecriture.sortie;
    if (sortie != null) {
      try {
        await sortie.close();
      } on FileSystemException catch (erreur, pile) {
        if (issue is! TransfertEcritureImpossible) {
          issue = TransfertEcritureImpossible(erreur, pile);
        }
      }
    }
    return issue;
  }

  Future<Transfert> _recevoir(
    HttpClient client,
    Uri url,
    String chemin,
    _Ecriture ecriture, {
    required int maxOctets,
    required bool Function() annule,
    required void Function(int recus) progression,
  }) async {
    final requete = await client.getUrl(url);
    final reponse = await requete.close();
    if (reponse.statusCode != HttpStatus.ok) {
      return const TransfertInterrompu();
    }
    final empreinte = _Empreinte();
    final calcul = sha256.startChunkedConversion(empreinte);
    final sortie = File(chemin).openWrite();
    ecriture.sortie = sortie;
    var recus = 0;
    await for (final bloc in reponse.timeout(delaiSilence)) {
      if (annule()) return const TransfertInterrompu();
      final reste = maxOctets + 1 - recus;
      final part = bloc.length > reste ? bloc.sublist(0, reste) : bloc;
      recus += part.length;
      if (recus > maxOctets) return const TransfertTropLong();
      calcul.add(part);
      sortie.add(part);
      progression(recus);
    }
    if (annule()) return const TransfertInterrompu();
    await sortie.flush();
    calcul.close();
    return TransfertFini(recus, empreinte.valeur.toString());
  }

  @override
  Future<void> supprimer(String chemin) async {
    final fichier = File(chemin);
    if (await fichier.exists()) await fichier.delete();
  }
}

/// Fichier ouvert par un téléchargement, refermé par l'appelant.
class _Ecriture {
  IOSink? sortie;
}

/// Reçoit le SHA-256 calculé au fil de l'écriture.
class _Empreinte implements Sink<Digest> {
  Digest? _valeur;

  Digest get valeur => _valeur ?? (throw StateError('SHA-256 non calculé'));

  @override
  void add(Digest data) => _valeur = data;

  @override
  void close() {}
}
