/// Hors du web : la préférence passe par le canal Android, cette classe n'est
/// pas appelée (garde `kIsWeb` de `preferences_appareil.dart`).
class PreferencesWeb {
  String? lire(String cle) =>
      throw UnsupportedError('localStorage absent hors du web');

  void ecrire(String cle, String valeur) =>
      throw UnsupportedError('localStorage absent hors du web');
}
