import 'modele_exemple.dart';
import 'modele_fiches.dart';
import 'modele_processus.dart';

/// Modèles proposés par la section « Modèles à copier » de « Mes processus ».
/// Rien ne s'écrit avant « Enregistrer » : l'appui ouvre « Nouveau processus »
/// prérempli (`?modele=<valeur>`).
enum ModeleACopier {
  exemple('exemple', kNomModeleExemple, kNoteModeleExemple, modeleExemple),
  fiches('fiches', kNomModeleFiches, kNoteModeleFiches, modeleFiches);

  const ModeleACopier(this.parametre, this.nom, this.note, this._copie);

  /// Valeur du paramètre `modele` de la route « Nouveau processus ».
  final String parametre;
  final String nom;
  final String note;
  final ContenuModele Function(String Function() nouvelleCle) _copie;

  /// Copie du modèle, avec des clés neuves.
  ContenuModele copie(String Function() nouvelleCle) => _copie(nouvelleCle);

  /// Modèle du paramètre [valeur], ou `null` pour une valeur inconnue ou
  /// absente.
  static ModeleACopier? deParametre(String? valeur) {
    for (final m in values) {
      if (m.parametre == valeur) return m;
    }
    return null;
  }
}
