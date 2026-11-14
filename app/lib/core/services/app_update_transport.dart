/// Échanges réseau et fichier de la mise à jour de l'APK (ADR-012), sans
/// `dart:io` : le web ne charge que le stub (`app_update_transport_stub.dart`),
/// Android la mise en œuvre de `app_update_transport_io.dart`.
library;

/// Réponse reçue à la lecture du manifeste : code HTTP et corps lu, borné.
class ReponseManifeste {
  const ReponseManifeste(this.statut, this.octets);

  final int statut;

  /// Corps lu jusqu'à la borne + 1 octet : un corps plus long se voit.
  final List<int> octets;
}

/// Issue d'un téléchargement de l'APK.
sealed class Transfert {
  const Transfert();
}

/// Fichier reçu en entier : [octets] écrits, SHA-256 [sha256] en hexadécimal
/// minuscule.
class TransfertFini extends Transfert {
  const TransfertFini(this.octets, this.sha256);

  final int octets;
  final String sha256;
}

/// Plus d'octets reçus que la borne : lecture arrêtée à la borne + 1.
class TransfertTropLong extends Transfert {
  const TransfertTropLong();
}

/// Coupure de réseau, délai, erreur TLS, code HTTP différent de 200 ou
/// annulation : aucun rapport (ADR-012, arbitrage 6).
class TransfertInterrompu extends Transfert {
  const TransfertInterrompu();
}

/// Écriture du fichier impossible sur l'appareil. [erreur] peut contenir le
/// chemin : elle ne part jamais telle quelle dans un rapport.
class TransfertEcritureImpossible extends Transfert {
  const TransfertEcritureImpossible(this.erreur, this.pile);

  final Object erreur;
  final StackTrace pile;
}

/// Accès au réseau et au fichier de la mise à jour.
abstract class TransportMiseAJour {
  /// Lit [url] en `GET`, en [delai] au plus, corps borné à [maxOctets] + 1.
  /// `null` sur une absence de réseau, un délai dépassé, une erreur de
  /// connexion ou de TLS : aucun rapport (ADR-012, arbitrage 2).
  Future<ReponseManifeste?> lireManifeste(
    Uri url, {
    required Duration delai,
    required int maxOctets,
  });

  /// Télécharge [url] dans [chemin] (dossier rendu par le canal), en calculant
  /// le SHA-256 au fil de l'écriture. Lecture arrêtée à [maxOctets] + 1 octets.
  /// [annule] est lu à chaque bloc reçu.
  Future<Transfert> telecharger(
    Uri url,
    String chemin, {
    required int maxOctets,
    required bool Function() annule,
    required void Function(int recus) progression,
  });

  /// Efface [chemin] s'il existe. Lève en cas d'échec.
  Future<void> supprimer(String chemin);
}
