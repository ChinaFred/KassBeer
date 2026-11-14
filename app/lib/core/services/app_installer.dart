import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'error_report_service.dart';

/// Canal Android des mises à jour (ADR-012). Noms identiques dans
/// `MisesAJour.kt` (P17).
const kCanalMisesAJour = 'fr.kassbeer/updates';
const kMethodeDossier = 'updatesDir';
const kMethodePeutInstaller = 'canRequestInstall';
const kMethodeReglages = 'openInstallSettings';
const kMethodeInstaller = 'installApk';

/// Code de `MisesAJour.kt` : l'APK téléchargé n'est pas celui de Kass'Beer, ou
/// son `versionCode` n'est pas celui du manifeste. Le fichier est effacé par
/// le Kotlin.
const kCodeApkInvalide = 'apk_invalid';

/// Issue d'une demande d'installation.
enum Installation {
  /// L'installateur du système est ouvert.
  ouverte,

  /// Paquet ou `versionCode` refusés par le Kotlin ; fichier effacé.
  refusee,

  /// Le canal a échoué (déjà rapporté).
  impossible,
}

/// Les quatre gestes qu'Android réserve au code natif : dossier des mises à
/// jour, autorisation « installer des applications inconnues », réglage de
/// cette autorisation, installateur du système. Le Dart ne passe jamais de
/// chemin au Kotlin.
abstract class InstallateurApk {
  /// `cacheDir/updates/`, créé si besoin ; `null` en cas d'échec (rapporté).
  Future<String?> dossierMisesAJour();

  /// Vrai si Kass'Beer peut demander une installation.
  Future<bool> peutInstaller();

  /// Ouvre le réglage de l'autorisation ; faux s'il n'a pas pu s'ouvrir.
  Future<bool> ouvrirReglages();

  /// Contrôle `cacheDir/updates/kass-beer-update.apk` (paquet, `versionCode`
  /// égal à [buildAttendu]) puis ouvre l'installateur du système.
  Future<Installation> installer(int buildAttendu);
}

/// [InstallateurApk] du canal `fr.kassbeer/updates`. Chaque échec est rapporté
/// sous `app_update_install` avec le nom de la méthode et le code seuls : ni
/// chemin, ni message du système (P13, P28).
class InstallateurApkPlateforme implements InstallateurApk {
  InstallateurApkPlateforme({required ErrorReportService errorReportService})
    : _errors = errorReportService;

  static const _canal = MethodChannel(kCanalMisesAJour);

  final ErrorReportService _errors;

  @override
  Future<String?> dossierMisesAJour() async {
    if (kIsWeb) return null;
    try {
      final dossier = await _canal.invokeMethod<String>(kMethodeDossier);
      if (dossier == null || dossier.isEmpty) {
        throw StateError('canal $kMethodeDossier : réponse vide');
      }
      return dossier;
    } on PlatformException catch (error, stackTrace) {
      _rapporter(kMethodeDossier, error.code, stackTrace);
      return null;
    } catch (error, stackTrace) {
      _rapporter(kMethodeDossier, error.runtimeType.toString(), stackTrace);
      return null;
    }
  }

  @override
  Future<bool> peutInstaller() =>
      _booleen(kMethodePeutInstaller, const <String, Object?>{});

  @override
  Future<bool> ouvrirReglages() =>
      _booleen(kMethodeReglages, const <String, Object?>{});

  @override
  Future<Installation> installer(int buildAttendu) async {
    if (kIsWeb) return Installation.impossible;
    try {
      final ouverte = await _canal.invokeMethod<bool>(kMethodeInstaller, {
        'expectedBuild': buildAttendu,
      });
      if (ouverte != true) {
        throw StateError('canal $kMethodeInstaller : réponse inattendue');
      }
      return Installation.ouverte;
    } on PlatformException catch (error, stackTrace) {
      // Fichier refusé : rapporté par `AppUpdateService` comme un fichier faux.
      if (error.code == kCodeApkInvalide) return Installation.refusee;
      _rapporter(kMethodeInstaller, error.code, stackTrace);
      return Installation.impossible;
    } catch (error, stackTrace) {
      _rapporter(kMethodeInstaller, error.runtimeType.toString(), stackTrace);
      return Installation.impossible;
    }
  }

  Future<bool> _booleen(String methode, Map<String, Object?> args) async {
    if (kIsWeb) return false;
    try {
      final reponse = await _canal.invokeMethod<bool>(methode, args);
      if (reponse == null) throw StateError('canal $methode : réponse vide');
      return reponse;
    } on PlatformException catch (error, stackTrace) {
      _rapporter(methode, error.code, stackTrace);
      return false;
    } catch (error, stackTrace) {
      _rapporter(methode, error.runtimeType.toString(), stackTrace);
      return false;
    }
  }

  /// Erreur neutre : le message d'une `PlatformException` n'est jamais recopié.
  void _rapporter(String methode, String code, StackTrace stackTrace) =>
      _errors.reportError(
        feature: 'app_update_install',
        error: StateError('canal $methode : $code'),
        stackTrace: stackTrace,
        context: 'méthode $methode, code $code',
      );
}
