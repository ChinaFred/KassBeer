import '../bornes.dart';
import '../texte.dart';
import '../unites.dart';

/// Lecture des valeurs des sources vers les unités canoniques (`g`, `l`, `C`,
/// `min`, `EBC`, `sg`, `%`), en couples `{value, unit}` et en plages
/// `{minimum, maximum}` comme BeerJSON. Couleurs par `brewing/` (P3, via
/// `versEbc`), °F et masses impériales par `exchange/`. Une valeur d'unité
/// inconnue, non finie ou hors bornes est écartée et notée dans le [Journal] :
/// aucune valeur n'est remplacée par une autre.

/// Valeur écartée d'une source, comptée au rapport.
class ValeurEcartee {
  /// Crée la valeur écartée.
  const ValeurEcartee(this.source, this.nom, this.champ, this.raison);

  /// Source (`brewtarget-005`, `diydog`…).
  final String source;

  /// Nom de l'entrée ou identifiant de la recette.
  final String nom;

  /// Champ de la source.
  final String champ;

  /// Raison : unité inconnue, valeur illisible, hors bornes.
  final String raison;

  /// Ligne du rapport.
  Map<String, Object> toJson() => {
    'source': source,
    'nom': nom,
    'champ': champ,
    'raison': raison,
  };
}

/// Valeurs écartées d'une lecture.
class Journal {
  /// Valeurs écartées, dans l'ordre de lecture.
  final List<ValeurEcartee> ecartees = [];

  /// Note une valeur écartée.
  void ecarter(String source, String nom, String champ, String raison) =>
      ecartees.add(ValeurEcartee(source, nom, champ, raison));
}

/// Couple `{value, unit}`.
Map<String, Object> couple(num valeur, String unite) => {
  'value': valeur,
  'unit': unite,
};

/// Plage `{minimum: {value, unit}, maximum: {value, unit}}`.
Map<String, Object> plage(num minimum, num maximum, String unite) => {
  'minimum': couple(minimum, unite),
  'maximum': couple(maximum, unite),
};

/// [valeur] arrondie à [decimales] décimales : une conversion (°F, Lovibond,
/// SRM) ne garde pas sa queue binaire.
double arrondi(double valeur, int decimales) {
  var facteur = 1.0;
  for (var i = 0; i < decimales; i++) {
    facteur *= 10;
  }
  return (valeur * facteur).roundToDouble() / facteur;
}

/// Nombre fini lu dans [brut] : un nombre JSON, ou un texte qui en est un.
double? nombre(Object? brut) {
  final double? n = switch (brut) {
    num() => brut.toDouble(),
    String() => double.tryParse(brut.trim()),
    _ => null,
  };
  return n != null && n.isFinite ? n : null;
}

/// Nom d'une ligne : nettoyé (P9), coupé à [kMaxNom], ou `null` s'il est vide.
String? nomPropre(Object? brut) {
  if (brut is! String) return null;
  final texte = nettoyerLigne(brut).texte;
  return texte.isEmpty ? null : couper(texte, kMaxNom);
}

/// Grandeurs lues, avec leur unité canonique et leurs bornes.
enum Grandeur {
  /// Pourcentage : rendement, acides, atténuation, degré.
  pourcent('%', 0, 100, 2),

  /// Couleur en EBC.
  couleur('EBC', 0, kMaxEbc, 1),

  /// Température en °C.
  temperature('C', -20, 100, 1),

  /// Densité en SG.
  densite('sg', 0.9, 1.3, 4),

  /// Amertume en IBU.
  amertume('IBUs', 0, 1000, 1);

  const Grandeur(this.unite, this.min, this.max, this.decimales);

  /// Unité canonique.
  final String unite;

  /// Borne basse, comprise.
  final double min;

  /// Borne haute, comprise.
  final double max;

  /// Décimales gardées après une conversion.
  final int decimales;
}

/// Lecteur des valeurs d'une entrée : chaque valeur écartée est notée sous
/// [source] et [nom].
class LecteurValeurs {
  /// Crée le lecteur.
  LecteurValeurs(this.journal, this.source, this.nom);

  /// Journal des valeurs écartées.
  final Journal journal;

  /// Source de l'entrée.
  final String source;

  /// Nom de l'entrée.
  final String nom;

  /// Note la valeur écartée du champ [champ].
  void ecarter(String champ, String raison) =>
      journal.ecarter(source, nom, champ, raison);

  /// Valeur [brut] (nombre nu) dans l'unité [unite] de la source, convertie
  /// dans l'unité canonique de [grandeur] ; `null` si elle manque ou est
  /// écartée.
  double? valeur(String champ, Object? brut, String unite, Grandeur grandeur) {
    if (brut == null) return null;
    final n = nombre(brut);
    if (n == null) {
      ecarter(champ, 'valeur illisible');
      return null;
    }
    final double converti;
    switch (grandeur) {
      case Grandeur.couleur:
        if (!kUnitesCouleur.contains(unite)) {
          ecarter(champ, 'unité inconnue');
          return null;
        }
        if (n < 0) {
          ecarter(champ, 'hors bornes');
          return null;
        }
        converti = unite == 'EBC'
            ? n
            : arrondi(versEbc(n, unite), grandeur.decimales);
      case Grandeur.temperature:
        if (!kUnitesTemperature.contains(unite)) {
          ecarter(champ, 'unité inconnue');
          return null;
        }
        converti = unite == 'C'
            ? n
            : arrondi(versCelsius(n, unite), grandeur.decimales);
      case Grandeur.pourcent || Grandeur.densite || Grandeur.amertume:
        if (unite != grandeur.unite) {
          ecarter(champ, 'unité inconnue');
          return null;
        }
        converti = n;
    }
    if (converti < grandeur.min || converti > grandeur.max) {
      ecarter(champ, 'hors bornes');
      return null;
    }
    return converti;
  }

  /// Couple BeerJSON `{value, unit}` [brut] converti en couple canonique de
  /// [grandeur], ou `null`.
  Map<String, Object>? mesure(String champ, Object? brut, Grandeur grandeur) {
    if (brut == null) return null;
    if (brut is! Map || brut['unit'] is! String) {
      ecarter(champ, 'valeur illisible');
      return null;
    }
    final v = valeur(champ, brut['value'], brut['unit'] as String, grandeur);
    return v == null ? null : couple(v, grandeur.unite);
  }

  /// Plage BeerJSON `{minimum, maximum}` [brut] convertie, ou `null` si une
  /// borne manque ou est écartée, ou si le minimum dépasse le maximum.
  Map<String, Object>? plageMesuree(
    String champ,
    Object? brut,
    Grandeur grandeur,
  ) {
    if (brut == null) return null;
    if (brut is! Map) {
      ecarter(champ, 'valeur illisible');
      return null;
    }
    final min = mesure('$champ.minimum', brut['minimum'], grandeur);
    final max = mesure('$champ.maximum', brut['maximum'], grandeur);
    if (min == null || max == null) {
      if (min != null || max != null) ecarter(champ, 'plage incomplète');
      return null;
    }
    return plageDe(
      champ,
      min['value']! as double,
      max['value']! as double,
      grandeur,
    );
  }

  /// Plage de [min] à [max] dans l'unité canonique de [grandeur], ou `null`
  /// si [min] dépasse [max].
  Map<String, Object>? plageDe(
    String champ,
    double min,
    double max,
    Grandeur grandeur,
  ) {
    if (min > max) {
      ecarter(champ, 'minimum au-dessus du maximum');
      return null;
    }
    return plage(min, max, grandeur.unite);
  }

  /// Texte court [brut] (origine, producteur) nettoyé, ou `null`.
  String? texte(String champ, Object? brut) {
    if (brut == null) return null;
    if (brut is! String) {
      ecarter(champ, 'valeur illisible');
      return null;
    }
    return nomPropre(brut);
  }

  /// Valeur énumérée [brut], en minuscules, de [permises] (après [table]), ou
  /// `null`.
  String? enumeree(
    String champ,
    Object? brut,
    Set<String> permises, [
    Map<String, String> table = const {},
  ]) {
    if (brut == null) return null;
    if (brut is! String) {
      ecarter(champ, 'valeur illisible');
      return null;
    }
    final minuscule = brut.trim().toLowerCase();
    if (minuscule.isEmpty) return null;
    final v = table[minuscule] ?? minuscule;
    if (permises.contains(v)) return v;
    ecarter(champ, 'valeur hors du schéma');
    return null;
  }
}
