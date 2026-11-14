import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_installer.dart';
import 'app_update_transport.dart';
import 'app_update_transport_stub.dart'
    if (dart.library.io) 'app_update_transport_io.dart';
import 'error_report_service.dart';

export 'app_update_transport.dart' show TransportMiseAJour;

/// Manifeste de l'APK publié sur Firebase Hosting, écrit par le job `build` de
/// `deploy.yml` au moment où l'APK est construit (ADR-012). Lu avec un
/// horodatage pour passer les caches intermédiaires.
const kUrlManifesteApk = 'https://kassbeer.web.app/apk_release.json';

/// APK publié à côté du manifeste. Le champ `file` du manifeste n'est pas lu
/// pour construire une adresse.
const kUrlApk = 'https://kassbeer.web.app/app-release.apk';

/// Nom du fichier téléchargé dans `cacheDir/updates/` ; `MisesAJour.kt` lit
/// ce même nom (P51).
const kNomFichierMiseAJour = 'kass-beer-update.apk';

/// Bornes de la lecture du manifeste (ADR-012, « Détail retenu »).
const kDelaiManifeste = Duration(seconds: 8);
const kMaxOctetsManifeste = 4096;
const kBuildMax = 2100000000;
const kTailleApkMax = 200000000;

/// Manifeste lu et contrôlé champ par champ.
@immutable
class ManifesteApk {
  const ManifesteApk({
    required this.version,
    required this.build,
    required this.tailleOctets,
    required this.sha256,
  });

  /// Lit [octets] (UTF-8, JSON). Lève [ManifesteIllisible] si un champ manque
  /// ou n'a pas sa forme : `version` `X.Y.Z`, `build_number` entier de 1 à
  /// 2 100 000 000, `size_bytes` entier de 1 à 200 000 000, `sha256` de 64
  /// caractères `[0-9a-f]`.
  factory ManifesteApk.lire(List<int> octets) {
    if (octets.length > kMaxOctetsManifeste) {
      throw const ManifesteIllisible('corps de plus de 4 096 octets');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(octets));
    } on FormatException {
      // Corps HTML (Hosting sert index.html pour un fichier absent) ou JSON
      // tronqué : rapporté par l'appelant comme une réponse illisible.
      throw const ManifesteIllisible('corps non JSON');
    }
    if (json is! Map<String, Object?>) {
      throw const ManifesteIllisible('corps qui n\'est pas un objet');
    }
    final version = json['version'];
    if (version is! String || !_version.hasMatch(version)) {
      throw const ManifesteIllisible('version');
    }
    final build = json['build_number'];
    if (build is! int || build < 1 || build > kBuildMax) {
      throw const ManifesteIllisible('build_number');
    }
    final taille = json['size_bytes'];
    if (taille is! int || taille < 1 || taille > kTailleApkMax) {
      throw const ManifesteIllisible('size_bytes');
    }
    final empreinte = json['sha256'];
    if (empreinte is! String || !_sha256.hasMatch(empreinte)) {
      throw const ManifesteIllisible('sha256');
    }
    return ManifesteApk(
      version: version,
      build: build,
      tailleOctets: taille,
      sha256: empreinte,
    );
  }

  static final _version = RegExp(r'^\d+\.\d+\.\d+$');
  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  final String version;
  final int build;
  final int tailleOctets;
  final String sha256;
}

/// Manifeste refusé ; [raison] nomme le champ, jamais sa valeur.
class ManifesteIllisible implements Exception {
  const ManifesteIllisible(this.raison);

  final String raison;

  @override
  String toString() => 'ManifesteIllisible: $raison';
}

/// Nouvelle version proposée au brasseur.
@immutable
class MiseAJourDisponible {
  const MiseAJourDisponible({
    required this.manifeste,
    required this.versionInstallee,
  });

  final ManifesteApk manifeste;

  /// Version installée, lue par `package_info_plus` ; `null` si illisible.
  final String? versionInstallee;
}

/// Suivi d'un téléchargement : le seul moyen de l'interrompre.
class ApkDownload {
  bool _annule = false;
  bool get estAnnule => _annule;
  void annuler() => _annule = true;
}

/// Issue d'un téléchargement.
enum Telechargement {
  /// Fichier complet, taille et SHA-256 égaux au manifeste.
  pret,

  /// Coupure de réseau, délai, code HTTP différent de 200 : aucun rapport.
  interrompu,

  /// Annulé par le brasseur : aucun rapport.
  annule,

  /// Fichier faux (taille ou SHA-256) : effacé et rapporté.
  refuse,

  /// Dossier ou écriture impossible sur l'appareil : rapporté.
  impossible,
}

/// Vérifie, télécharge et fait installer la nouvelle version de l'APK
/// (ADR-012). Android seul : sur le web, [verifier] rend `null` avant tout
/// appel (arbitrage 4).
class AppUpdateService {
  AppUpdateService({
    required ErrorReportService errorReportService,
    required InstallateurApk installateur,
    required int? buildInstalle,
    required String? versionInstallee,
    TransportMiseAJour? transport,
    bool Function()? estAndroid,
    DateTime Function()? horloge,
  }) : _errors = errorReportService,
       _installateur = installateur,
       _buildInstalle = buildInstalle,
       _versionInstallee = versionInstallee,
       _transportInjecte = transport,
       _estAndroid = estAndroid ?? _androidNatif,
       _horloge = horloge ?? DateTime.now;

  final ErrorReportService _errors;
  final InstallateurApk _installateur;
  final int? _buildInstalle;
  final String? _versionInstallee;
  final TransportMiseAJour? _transportInjecte;
  final bool Function() _estAndroid;
  final DateTime Function() _horloge;

  /// Construit au premier appel : rien n'est créé au démarrage.
  late final TransportMiseAJour _transport =
      _transportInjecte ?? TransportMiseAJourPlateforme();

  static bool _androidNatif() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Nouvelle version si le `build_number` du manifeste dépasse le build
  /// installé, sinon `null`. Échec de réseau ou code différent de 200 : `null`
  /// sans rapport (arbitrage 2). Réponse 200 illisible : rapport
  /// `app_update_check`, puis `null`. Aucun repli sur `version.json`.
  Future<MiseAJourDisponible?> verifier() async {
    if (!_estAndroid()) return null;
    final installe = _buildInstalle;
    if (installe == null) return null;
    final url = Uri.parse(
      '$kUrlManifesteApk?t=${_horloge().millisecondsSinceEpoch}',
    );
    final reponse = await _transport.lireManifeste(
      url,
      delai: kDelaiManifeste,
      maxOctets: kMaxOctetsManifeste,
    );
    if (reponse == null || reponse.statut != 200) return null;
    final ManifesteApk manifeste;
    try {
      manifeste = ManifesteApk.lire(reponse.octets);
    } on ManifesteIllisible catch (error, stackTrace) {
      _errors.reportError(
        feature: 'app_update_check',
        error: error,
        stackTrace: stackTrace,
        context: 'raison: ${error.raison}',
      );
      return null;
    }
    if (manifeste.build <= installe) return null;
    return MiseAJourDisponible(
      manifeste: manifeste,
      versionInstallee: _versionInstallee,
    );
  }

  /// Vrai si Kass'Beer peut demander une installation.
  Future<bool> peutInstaller() => _installateur.peutInstaller();

  /// Ouvre le réglage « installer des applications inconnues ».
  Future<bool> ouvrirReglages() => _installateur.ouvrirReglages();

  /// Télécharge l'APK dans `cacheDir/updates/kass-beer-update.apk`, lecture
  /// arrêtée à `size_bytes` + 1 octets. Le fichier est gardé seulement si sa
  /// taille et son SHA-256 sont ceux du manifeste.
  Future<Telechargement> telecharger(
    ManifesteApk manifeste, {
    required ApkDownload suivi,
    void Function(int recus, int total)? progression,
  }) async {
    if (!_estAndroid()) return Telechargement.impossible;
    final dossier = await _installateur.dossierMisesAJour();
    if (dossier == null) return Telechargement.impossible;
    final chemin = '$dossier/$kNomFichierMiseAJour';
    final Transfert issue;
    try {
      issue = await _transport.telecharger(
        Uri.parse(kUrlApk),
        chemin,
        maxOctets: manifeste.tailleOctets,
        annule: () => suivi.estAnnule,
        progression: (recus) =>
            progression?.call(recus, manifeste.tailleOctets),
      );
    } catch (error, stackTrace) {
      // Erreur hors des cas de réseau du transport : son message peut porter
      // le chemin, il n'est pas recopié.
      await _effacer(chemin);
      _rapporterTelechargement(
        StateError('téléchargement : ${error.runtimeType}'),
        stackTrace,
        'raison: erreur inattendue',
      );
      return Telechargement.impossible;
    }
    switch (issue) {
      case TransfertInterrompu():
        await _effacer(chemin);
        return suivi.estAnnule
            ? Telechargement.annule
            : Telechargement.interrompu;
      case TransfertTropLong():
        await _effacer(chemin);
        _rapporterTelechargement(
          StateError('APK refusé : taille'),
          StackTrace.current,
          'raison: taille; plus de ${manifeste.tailleOctets} octets reçus',
        );
        return Telechargement.refuse;
      case TransfertEcritureImpossible(:final erreur, :final pile):
        await _effacer(chemin);
        _rapporterTelechargement(
          StateError('écriture impossible : ${erreur.runtimeType}'),
          pile,
          'raison: écriture',
        );
        return Telechargement.impossible;
      case TransfertFini(:final octets, :final sha256):
        if (octets != manifeste.tailleOctets) {
          await _effacer(chemin);
          _rapporterTelechargement(
            StateError('APK refusé : taille'),
            StackTrace.current,
            'raison: taille; $octets octets reçus sur '
            '${manifeste.tailleOctets} attendus',
          );
          return Telechargement.refuse;
        }
        if (sha256 != manifeste.sha256) {
          await _effacer(chemin);
          _rapporterTelechargement(
            StateError('APK refusé : sha256'),
            StackTrace.current,
            'raison: sha256',
          );
          return Telechargement.refuse;
        }
        return Telechargement.pret;
    }
  }

  /// Fait contrôler par le Kotlin le paquet et le `versionCode` du fichier
  /// téléchargé, puis ouvre l'installateur. Un refus est rapporté comme un
  /// fichier faux (arbitrage 6) ; le Kotlin a effacé le fichier.
  Future<Installation> installer(ManifesteApk manifeste) async {
    final issue = await _installateur.installer(manifeste.build);
    if (issue == Installation.refusee) {
      _rapporterTelechargement(
        StateError('APK refusé : paquet ou versionCode'),
        StackTrace.current,
        'raison: $kCodeApkInvalide; build attendu ${manifeste.build}',
      );
    }
    return issue;
  }

  Future<void> _effacer(String chemin) async {
    try {
      await _transport.supprimer(chemin);
    } catch (error, stackTrace) {
      _rapporterTelechargement(
        StateError('effacement impossible : ${error.runtimeType}'),
        stackTrace,
        'raison: effacement',
      );
    }
  }

  /// Rapport sans chemin ni contenu (P13).
  void _rapporterTelechargement(
    Object error,
    StackTrace stackTrace,
    String context,
  ) => _errors.reportError(
    feature: 'app_update_download',
    error: error,
    stackTrace: stackTrace,
    context: context,
  );
}

/// Service de la mise à jour de l'APK. `main.dart` le fournit ; les tests y
/// mettent un double. Importé par la coquille seule : l'écran du jour et les
/// journées du déroulé ne l'importent pas (P51).
final appUpdateServiceProvider = Provider<AppUpdateService>(
  (ref) => throw UnimplementedError('appUpdateServiceProvider non fourni'),
);
