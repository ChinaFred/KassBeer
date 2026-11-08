import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/services/error_report_service.dart';
import 'bip_web_stub.dart' if (dart.library.js_interop) 'bip_web.dart';

/// Alerte de fin de minuteur : son et vibration, écran ouvert seulement.
abstract class AlerteMinuteur {
  /// Prépare le son sur un appui de l'utilisateur (`AudioContext` sur le web).
  void preparer();

  /// Déclenche le son et la vibration.
  Future<void> declencher();
}

/// Canal Android de l'alerte. Nom et méthodes identiques dans `MainActivity.kt` (P17).
const kCanalAlerte = 'fr.kassbeer/alert';
const kMethodeBip = 'beep';
const kMethodeVibration = 'vibrate';

/// [AlerteMinuteur] de la plateforme : canal Android, Web Audio sur le web. Aucune
/// ressource n'est chargée (P2 étendu). Chaque échec est rapporté une fois par session.
class AlerteMinuteurPlateforme implements AlerteMinuteur {
  AlerteMinuteurPlateforme({required ErrorReportService errorReportService})
    : _errors = errorReportService;

  static const _canal = MethodChannel(kCanalAlerte);

  final ErrorReportService _errors;
  final BipWeb _bipWeb = BipWeb();
  final _reported = <String>{};

  @override
  void preparer() {
    if (!kIsWeb) return;
    try {
      _bipWeb.preparer();
    } catch (error, stackTrace) {
      _report('brew_day.alert_prepare', error, stackTrace);
    }
  }

  @override
  Future<void> declencher() async {
    if (kIsWeb) {
      try {
        _bipWeb.jouer();
      } catch (error, stackTrace) {
        _report('brew_day.alert_beep', error, stackTrace);
      }
      return;
    }
    // Séparés : un son indisponible n'empêche pas la vibration.
    await _appeler(kMethodeBip, 'brew_day.alert_beep');
    await _appeler(kMethodeVibration, 'brew_day.alert_vibrate');
  }

  Future<void> _appeler(String methode, String feature) async {
    try {
      await _canal.invokeMethod<void>(methode);
    } catch (error, stackTrace) {
      _report(feature, error, stackTrace);
    }
  }

  void _report(String feature, Object error, StackTrace stackTrace) {
    if (!_reported.add(feature)) return;
    _errors.reportError(feature: feature, error: error, stackTrace: stackTrace);
  }
}
