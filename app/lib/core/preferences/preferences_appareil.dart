import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/error_report_service.dart';
import 'preferences_web_stub.dart'
    if (dart.library.js_interop) 'preferences_web.dart';

/// Préférences gardées sur l'appareil, hors Firestore (ADR-009) : canal Kotlin
/// `fr.kassbeer/prefs` sur Android, `window.localStorage` sur le web. Aucun
/// greffon. Seule préférence : le thème.
abstract class PreferencesAppareil {
  /// Valeur enregistrée du thème, telle quelle ; `null` si rien n'est
  /// enregistré. Lève si le stockage est illisible.
  Future<String?> lireValeurTheme();

  /// Enregistre [mode]. Lève si l'écriture échoue.
  Future<void> ecrireTheme(ThemeMode mode);
}

/// Canal Android des préférences. Noms identiques dans `PreferencesAppareil.kt`
/// (P17).
const kCanalPreferences = 'fr.kassbeer/prefs';
const kMethodeLireTheme = 'getTheme';
const kMethodeEcrireTheme = 'setTheme';
const kArgumentValeur = 'value';

/// Clé du thème dans `localStorage` (web).
const kCleThemeWeb = 'kassbeer.theme';

/// Valeurs enregistrées, et rien d'autre.
const kValeursTheme = <ThemeMode, String>{
  ThemeMode.light: 'light',
  ThemeMode.dark: 'dark',
  ThemeMode.system: 'system',
};

/// [PreferencesAppareil] de la plateforme : canal Android, `localStorage` sur le
/// web.
///
/// Sur Android, le canal refuse un appel reçu pendant un autre (`BUSY`, P17).
/// [ecrireTheme] n'envoie donc jamais un second appel avant la fin du premier :
/// les choix arrivés entre-temps sont réduits au dernier, envoyé à la fin de
/// l'appel en cours. La lecture au démarrage reste un seul appel, avant
/// `runApp`.
class PreferencesAppareilPlateforme implements PreferencesAppareil {
  PreferencesAppareilPlateforme();

  static const _canal = MethodChannel(kCanalPreferences);

  final PreferencesWeb _web = PreferencesWeb();

  /// Une écriture est partie sur le canal et n'a pas encore répondu.
  bool _ecritureEnCours = false;

  /// Dernier choix arrivé pendant l'écriture en cours, et l'attente de son
  /// appelant.
  String? _valeurEnAttente;
  Completer<void>? _attente;

  @override
  Future<String?> lireValeurTheme() async {
    if (kIsWeb) return _web.lire(kCleThemeWeb);
    return _canal.invokeMethod<String>(kMethodeLireTheme);
  }

  @override
  Future<void> ecrireTheme(ThemeMode mode) async {
    final valeur = kValeursTheme[mode]!;
    if (kIsWeb) {
      _web.ecrire(kCleThemeWeb, valeur);
      return;
    }
    if (!_ecritureEnCours) return _envoyer(valeur);
    // Un choix plus récent remplace celui qui attendait : la valeur remplacée
    // n'est plus le choix de l'utilisateur, son appelant n'a rien à rapporter.
    _attente?.complete();
    final attente = Completer<void>();
    _valeurEnAttente = valeur;
    _attente = attente;
    return attente.future;
  }

  /// Envoie [valeur] ; à la réponse, succès ou échec, envoie le choix en
  /// attente s'il y en a un. L'erreur de cet appel part à son appelant.
  Future<void> _envoyer(String valeur) async {
    _ecritureEnCours = true;
    try {
      await _canal.invokeMethod<void>(kMethodeEcrireTheme, {
        kArgumentValeur: valeur,
      });
    } finally {
      _ecritureEnCours = false;
      _envoyerEnAttente();
    }
  }

  void _envoyerEnAttente() {
    final valeur = _valeurEnAttente;
    final attente = _attente;
    if (valeur == null || attente == null) return;
    _valeurEnAttente = null;
    _attente = null;
    // L'erreur de cet envoi part à l'appelant en attente, qui la rapporte.
    attente.complete(_envoyer(valeur));
  }
}

/// Thème lu au démarrage, avec l'erreur à rapporter une fois le service
/// d'erreurs construit (`main.dart`).
@immutable
class LectureTheme {
  const LectureTheme(this.mode, {this.erreur, this.pile, this.contexte});

  final ThemeMode mode;
  final Object? erreur;
  final StackTrace? pile;

  /// Code d'erreur du canal ou longueur d'une valeur inconnue, rien d'autre (P13).
  final String? contexte;

  /// Rapporte l'erreur de lecture, s'il y en a une.
  void rapporter(ErrorReportService errors) {
    final error = erreur;
    if (error == null) return;
    errors.reportError(
      feature: 'theme_mode.load',
      error: error,
      stackTrace: pile,
      context: contexte,
    );
  }
}

/// Lit le thème enregistré. Ne lève pas : une valeur absente vaut
/// [ThemeMode.system] ; une valeur inconnue ou une lecture en échec aussi, avec
/// l'erreur gardée dans le résultat.
Future<LectureTheme> lireTheme(PreferencesAppareil preferences) async {
  final String? valeur;
  try {
    valeur = await preferences.lireValeurTheme();
  } catch (error, stackTrace) {
    // Rapporté par `LectureTheme.rapporter`, une fois le service construit.
    return LectureTheme(
      ThemeMode.system,
      erreur: error,
      pile: stackTrace,
      contexte: contextePreference(error),
    );
  }
  if (valeur == null) return const LectureTheme(ThemeMode.system);
  for (final entry in kValeursTheme.entries) {
    if (entry.value == valeur) return LectureTheme(entry.key);
  }
  return LectureTheme(
    ThemeMode.system,
    erreur: const FormatException('valeur de thème inconnue'),
    pile: StackTrace.current,
    // La valeur vient d'un stockage modifiable (entrée non fiable) : seule sa
    // longueur part dans le rapport, jamais son contenu (P13).
    contexte: 'valeur inconnue (longueur ${valeur.length})',
  );
}

/// Contexte d'un rapport de préférence : le code d'erreur du canal seul.
String? contextePreference(Object error) =>
    error is PlatformException ? 'code : ${error.code}' : null;
