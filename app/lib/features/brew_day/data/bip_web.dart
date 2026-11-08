import 'package:web/web.dart' as web;

/// Bip synthétisé par Web Audio : aucun fichier ni URL chargé (P2 étendu).
class BipWeb {
  web.AudioContext? _contexte;

  /// Crée l'`AudioContext` sur un appui de l'utilisateur : un navigateur bloque un
  /// son sans geste préalable.
  void preparer() {
    _contexte ??= web.AudioContext();
  }

  /// Joue un oscillateur pendant 300 ms.
  void jouer() {
    final contexte = _contexte ??= web.AudioContext();
    final oscillateur = contexte.createOscillator();
    oscillateur.connect(contexte.destination);
    oscillateur.frequency.value = 880;
    oscillateur.start();
    oscillateur.stop(contexte.currentTime + 0.3);
  }
}
