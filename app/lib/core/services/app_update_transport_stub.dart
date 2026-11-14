import 'app_update_transport.dart';

/// Web : aucune mise à jour de l'APK (ADR-012, arbitrage 4). `AppUpdateService`
/// rend `null` avant tout appel ; cette classe n'est jamais appelée.
class TransportMiseAJourPlateforme implements TransportMiseAJour {
  @override
  Future<ReponseManifeste?> lireManifeste(
    Uri url, {
    required Duration delai,
    required int maxOctets,
  }) => throw UnsupportedError('mise à jour de l\'APK hors d\'Android');

  @override
  Future<Transfert> telecharger(
    Uri url,
    String chemin, {
    required int maxOctets,
    required bool Function() annule,
    required void Function(int recus) progression,
  }) => throw UnsupportedError('mise à jour de l\'APK hors d\'Android');

  @override
  Future<void> supprimer(String chemin) =>
      throw UnsupportedError('mise à jour de l\'APK hors d\'Android');
}
