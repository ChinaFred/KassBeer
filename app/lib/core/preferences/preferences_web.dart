import 'package:web/web.dart' as web;

/// `window.localStorage` du navigateur (ADR-009). Un navigateur qui refuse le
/// stockage (mode privé strict, stockage bloqué) lève : l'appelant rapporte.
class PreferencesWeb {
  String? lire(String cle) => web.window.localStorage.getItem(cle);

  void ecrire(String cle, String valeur) =>
      web.window.localStorage.setItem(cle, valeur);
}
