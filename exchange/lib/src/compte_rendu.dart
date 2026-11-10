/// Types du compte rendu d'un import : ce que le fichier contient, ce qui est
/// refusé, ce qui est modifié. Aucun texte affiché ici : l'application écrit les
/// libellés. Un nom tiré du fichier (recette, ingrédient, unité) est une donnée,
/// affichée en texte simple, jamais interprétée (P9).
library;

/// Format d'un fichier reconnu.
enum FormatFichier {
  /// BeerJSON, versions 1, 2 et 3.
  beerJson('BeerJSON'),

  /// BeerXML 1.0.
  beerXml('BeerXML');

  const FormatFichier(this.nom);

  /// Nom du format, écrit dans `imported_from`.
  final String nom;
}

/// Liste d'une recette qui a un plafond (`firestore.rules`).
enum ListeRecette {
  /// Malts et sucres (`fermentable_additions`).
  malts,

  /// Houblons (`hop_additions`).
  houblons,

  /// Autres ajouts (`miscellaneous_additions`).
  ajouts,

  /// Levures (`culture_additions`).
  levures,

  /// Paliers d'empâtage (`mash.mash_steps`).
  paliers,
}

/// Champ d'une recette nommé par le compte rendu.
enum Champ {
  /// Nom de la recette ou d'une ligne.
  nom,

  /// Auteur de la recette.
  auteur,

  /// Notes de la recette.
  notes,

  /// Style de la recette.
  style,

  /// Type de la recette, d'un malt, d'un ajout, d'une levure ou d'un palier.
  type,

  /// Volume en fermenteur.
  volume,

  /// Durée d'ébullition.
  dureeEbullition,

  /// Température du grain.
  temperatureGrain,

  /// Quantité d'une ligne.
  quantite,

  /// Couleur d'un malt.
  couleur,

  /// Rendement d'extrait d'un malt.
  rendement,

  /// Acides alpha d'un houblon.
  acidesAlpha,

  /// Forme d'un houblon ou d'une levure.
  forme,

  /// Moment d'ajout d'un houblon ou d'un ajout.
  moment,

  /// Durée ou heure d'ajout d'un houblon ou d'un ajout.
  duree,

  /// Atténuation d'une levure.
  attenuation,

  /// Température d'un palier.
  temperaturePalier,

  /// Durée d'un palier.
  dureePalier,
}

/// Valeur désignée par le compte rendu : un champ, et le nom de la ligne qui le
/// porte (ingrédient, palier), ou `null` pour un champ de la recette.
class Grandeur {
  /// Crée la désignation.
  const Grandeur(this.champ, [this.ligne]);

  /// Champ concerné.
  final Champ champ;

  /// Nom de la ligne, tel que le fichier le donne après nettoyage.
  final String? ligne;

  @override
  bool operator ==(Object other) =>
      other is Grandeur && other.champ == champ && other.ligne == ligne;

  @override
  int get hashCode => Object.hash(champ, ligne);

  @override
  String toString() => 'Grandeur(${champ.name}, $ligne)';
}

/// Raison du refus d'une recette entière : rien n'est écrit pour elle.
sealed class Refus {
  const Refus();
}

/// La recette n'a pas de nom.
class NomAbsent extends Refus {
  /// Crée la raison.
  const NomAbsent();
}

/// Une liste dépasse son plafond : aucune troncature.
class TropDeLignes extends Refus {
  /// Crée la raison.
  const TropDeLignes(this.liste, this.nombre, this.maximum);

  /// Liste concernée.
  final ListeRecette liste;

  /// Nombre de lignes du fichier.
  final int nombre;

  /// Plafond.
  final int maximum;
}

/// Unité inconnue du schéma, ou sans conversion pour une valeur que la recette
/// ne peut pas perdre (quantité d'un ingrédient).
class UniteInconnue extends Refus {
  /// Crée la raison.
  const UniteInconnue(this.grandeur, this.unite);

  /// Valeur concernée.
  final Grandeur grandeur;

  /// Unité lue dans le fichier.
  final String unite;
}

/// Valeur obligatoire hors des bornes de l'éditeur (quantité négative…).
class ValeurHorsLimites extends Refus {
  /// Crée la raison.
  const ValeurHorsLimites(this.grandeur);

  /// Valeur concernée.
  final Grandeur grandeur;
}

/// Valeur d'un type inattendu (texte à la place d'un nombre…).
class ValeurIllisible extends Refus {
  /// Crée la raison.
  const ValeurIllisible(this.grandeur);

  /// Valeur concernée.
  final Grandeur grandeur;
}

/// Valeur obligatoire absente (quantité, forme d'un houblon, moment d'ajout).
class ValeurAbsente extends Refus {
  /// Crée la raison.
  const ValeurAbsente(this.grandeur);

  /// Valeur concernée.
  final Grandeur grandeur;
}

/// Valeur obligatoire hors des valeurs du schéma (type de malt inconnu…).
class ValeurInconnue extends Refus {
  /// Crée la raison.
  const ValeurInconnue(this.grandeur, this.valeur);

  /// Valeur concernée.
  final Grandeur grandeur;

  /// Valeur lue dans le fichier.
  final String valeur;
}

/// Nom d'une ligne absent, ou sans lettre ni chiffre pour un ingrédient
/// (règle K3 de `brewing/`).
class NomDeLigneIllisible extends Refus {
  /// Crée la raison.
  const NomDeLigneIllisible(this.liste);

  /// Liste de la ligne.
  final ListeRecette liste;
}

/// Structure de la recette illisible (objet attendu, liste attendue…).
class RecetteIllisible extends Refus {
  /// Crée la raison.
  const RecetteIllisible();
}

/// Partie d'un fichier que Kass'Beer n'importe pas.
enum PartieNonImportee {
  /// Profil et ajouts d'eau (`water_additions`).
  eau,

  /// Étapes de fermentation.
  fermentation,

  /// Conditionnement.
  conditionnement,

  /// Dégustation.
  degustation,

  /// Rendement indiqué par le fichier : l'export écrit celui de l'équipement.
  rendement,

  /// Densités, degré, amertume et couleur annoncés : Kass'Beer les recalcule.
  valeursAnnoncees,

  /// Volume avant ébullition et étapes d'ébullition.
  ebullition,

  /// Détails des paliers (rampe, rapport eau-grain, pH…).
  detailsPaliers,

  /// Détails des ingrédients (producteur, origine, moment d'un malt…).
  detailsIngredients,

  /// Co-auteur et date de création.
  coAuteurEtDate,

  /// Équipement décrit dans le fichier (`EQUIPMENT` d'un BeerXML) :
  /// `equipment/` reste plat (ADR-005).
  equipement,

  /// Nom de l'empâtage d'un BeerXML : remplacé par « Empâtage »
  /// (`kNomEmpatage`).
  nomEmpatage,
}

/// Raison d'une valeur facultative écartée : le champ reste absent.
enum RaisonRejet {
  /// Valeur nulle lue comme absente (rendement ou acides alpha à 0).
  nulle,

  /// Unité du schéma sans conversion (`each`, `pkg`, `brix`).
  uniteNonPriseEnCharge,

  /// Valeur hors des bornes de l'éditeur.
  horsLimites,

  /// Valeur hors des valeurs du schéma.
  inconnue,

  /// Rendement donné pour une mouture grossière seule.
  moutureGrossiere,
}

/// Changement fait à la lecture, listé au compte rendu.
sealed class Modification {
  const Modification();
}

/// Le style garde son nom seul : le reste demande le référentiel des styles.
class StyleReduitAuNom extends Modification {
  /// Crée la modification.
  const StyleReduitAuNom(this.style);

  /// Nom du style.
  final String style;
}

/// Parties du fichier non importées.
class PartiesNonImportees extends Modification {
  /// Crée la modification.
  const PartiesNonImportees(this.parties);

  /// Parties, dans l'ordre de leur rencontre.
  final Set<PartieNonImportee> parties;
}

/// Texte coupé à sa borne.
class TexteCoupe extends Modification {
  /// Crée la modification.
  const TexteCoupe(this.grandeur, this.maximum);

  /// Texte concerné.
  final Grandeur grandeur;

  /// Longueur gardée.
  final int maximum;
}

/// Unités converties vers les unités canoniques (`lb`, `F`, `Lovi`…), et
/// rendement donné en densité potentielle (`potential`).
class UnitesConverties extends Modification {
  /// Crée la modification.
  const UnitesConverties(this.unites);

  /// Unités du fichier, dans l'ordre de leur rencontre.
  final Set<String> unites;
}

/// Valeur facultative écartée : le champ reste absent.
class ValeurRejetee extends Modification {
  /// Crée la modification.
  const ValeurRejetee(this.grandeur, this.raison, [this.unite]);

  /// Valeur concernée.
  final Grandeur grandeur;

  /// Raison.
  final RaisonRejet raison;

  /// Unité lue, pour [RaisonRejet.uniteNonPriseEnCharge].
  final String? unite;
}

/// Durée arrondie à la minute (`TimeType` est entier).
class DureeArrondie extends Modification {
  /// Crée la modification.
  const DureeArrondie(this.grandeur);

  /// Durée concernée.
  final Grandeur grandeur;
}

/// Moment d'ajout simplifié : une heure, une durée ou un repère que le modèle
/// ne garde pas pour ce moment.
class MomentSimplifie extends Modification {
  /// Crée la modification.
  const MomentSimplifie(this.ligne, this.usage);

  /// Nom de la ligne.
  final String ligne;

  /// Moment retenu (`TimingType.use`), ou `null` pour un ajout gardé sans
  /// moment.
  final String? usage;
}

/// Houblon `First Wort` d'un BeerXML : compté à l'ébullition, pendant toute la
/// durée d'ébullition de la recette (ADR-005). BeerJSON n'a pas ce moment.
class FirstWortEnEbullition extends Modification {
  /// Crée la modification.
  const FirstWortEnEbullition(this.ligne, this.minutes);

  /// Nom du houblon.
  final String ligne;

  /// Durée d'ébullition retenue, ou `null` si la recette n'en donne pas : la
  /// durée du houblon reste à compléter.
  final int? minutes;
}

/// Houblon `Whirlpool` ou `Aroma` d'un BeerXML sans durée : compté à l'arrêt
/// du feu (`add_to_boil` à 0 minute, sans `duration` ; ADR-005, amendements
/// de L2).
class ArretDuFeuSansDuree extends Modification {
  /// Crée la modification.
  const ArretDuFeuSansDuree(this.ligne, this.usage);

  /// Nom du houblon.
  final String ligne;

  /// Moment d'ajout du fichier : `Whirlpool` ou `Aroma`.
  final String usage;
}

/// Houblon `Aroma` d'un BeerXML avec une durée : compté à l'ébullition pendant
/// cette durée, comme le dit la norme. Un logiciel peut y avoir écrit une
/// durée de whirlpool : la ligne le signale.
class AromaEnEbullition extends Modification {
  /// Crée la modification.
  const AromaEnEbullition(this.ligne, this.minutes);

  /// Nom du houblon.
  final String ligne;

  /// Durée lue, arrondie à la minute.
  final int minutes;
}

/// Caractères de contrôle retirés des textes (direction du texte, sauts de
/// ligne dans un nom).
class CaracteresRetires extends Modification {
  /// Crée la modification.
  const CaracteresRetires();
}

/// Champs inconnus du schéma, ignorés.
class ChampsInconnus extends Modification {
  /// Crée la modification.
  const ChampsInconnus(this.nombre);

  /// Nombre de champs.
  final int nombre;
}

/// Résultat de la lecture d'une recette.
sealed class ResultatRecette {
  const ResultatRecette();
}

/// Recette refusée.
class RecetteRefusee extends ResultatRecette {
  /// Crée le résultat.
  const RecetteRefusee(this.refus);

  /// Raison du refus.
  final Refus refus;
}

/// Recette lue : sous-arbre `recipe` en BeerJSON partiel (ADR-005), dans la
/// forme qu'écrit l'application, et ce qui a changé à la lecture.
class RecetteLue extends ResultatRecette {
  /// Crée le résultat.
  const RecetteLue(this.recipe, this.modifications);

  /// Sous-arbre `recipe`, unités canoniques.
  final Map<String, Object?> recipe;

  /// Changements, dans l'ordre de la recette.
  final List<Modification> modifications;
}

/// Une recette du fichier.
class RecetteDuFichier {
  /// Crée la recette.
  const RecetteDuFichier({
    required this.numero,
    required this.nom,
    required this.empreinte,
    required this.resultat,
    required this.enDouble,
  });

  /// Rang dans le fichier, à partir de 1.
  final int numero;

  /// Nom nettoyé et coupé, ou `null` s'il manque.
  final String? nom;

  /// Empreinte du contenu de la recette dans le fichier (`sha256:…`).
  final String empreinte;

  /// Recette lue ou refusée.
  final ResultatRecette resultat;

  /// Vrai si une recette précédente du fichier a la même empreinte.
  final bool enDouble;
}

/// Résultat de l'analyse d'un fichier.
sealed class AnalyseFichier {
  const AnalyseFichier();
}

/// Raison du refus d'un fichier entier.
enum RaisonFichier {
  /// Plus d'octets que la borne.
  tropGros,

  /// Ni BeerJSON, ni BeerXML, ni BeerSmith ; JSON ou XML mal formé, encodage
  /// illisible ou non pris en charge, `DOCTYPE` ou entité XML inconnue.
  illisible,

  /// JSON qui n'est pas du BeerJSON.
  jsonNonBeerJson,

  /// Fichier BeerSmith (`.bsmx`).
  bsmx,

  /// Version de BeerJSON hors de 1, 2 et 3.
  versionInconnue,

  /// Aucune recette.
  aucuneRecette,
}

/// Fichier refusé.
class FichierRefuse extends AnalyseFichier {
  /// Crée le résultat.
  const FichierRefuse(this.raison, {this.taille, this.version});

  /// Raison.
  final RaisonFichier raison;

  /// Taille en octets, pour [RaisonFichier.tropGros].
  final int? taille;

  /// Version lue, pour [RaisonFichier.versionInconnue].
  final String? version;
}

/// Fichier lu.
class FichierLu extends AnalyseFichier {
  /// Crée le résultat.
  const FichierLu({
    required this.format,
    required this.recettes,
    required this.total,
  });

  /// Format reconnu.
  final FormatFichier format;

  /// Recettes lues, [kMaxRecettesParFichier] au plus.
  final List<RecetteDuFichier> recettes;

  /// Nombre de recettes du fichier.
  final int total;

  /// Vrai si le fichier contient plus de recettes que celles lues.
  bool get tronque => total > recettes.length;
}
