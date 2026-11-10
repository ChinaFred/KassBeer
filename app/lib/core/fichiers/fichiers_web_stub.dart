import 'dart:typed_data';

import 'echange_fichiers.dart';

/// Hors du web : le choix et l'envoi passent par le canal Android, cette classe
/// n'est pas appelée (garde `kIsWeb` de `echange_fichiers.dart`).
class FichiersWeb {
  Future<ResultatChoix> choisir(int maxOctets) =>
      throw UnsupportedError('choix de fichier web hors du web');

  void telecharger(String nom, String typeMime, Uint8List octets) =>
      throw UnsupportedError('téléchargement web hors du web');
}
