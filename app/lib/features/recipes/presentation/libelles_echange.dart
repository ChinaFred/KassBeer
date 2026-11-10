import 'package:exchange/exchange.dart';

import '../../../core/presentation/formats.dart';
import '../domain/beerjson.dart';

/// Libellés de Recettes › Importer et de l'export d'une recette. Un nom tiré
/// d'un fichier (recette, ingrédient, unité) s'affiche en texte simple (P9).
abstract final class TextesImport {
  static const titre = 'Importer des recettes';
  static const aide =
      'Choisissez un fichier BeerXML (.xml) ou BeerJSON (.json) exporté de '
      'votre logiciel de brassage. 500 recettes et 10 Mo au plus. Les prix et '
      'le stock du fichier ne sont pas importés.';
  static const choisir = 'Choisir un fichier';
  static const choisirAutre = 'Choisir un autre fichier';
  static const lecture = 'Lecture du fichier';
  static const sansPrix =
      'Les prix et le stock du fichier ne sont pas importés.';
  static const equipement = 'Équipement des recettes';
  static const equipementAide = 'Vous pourrez le changer dans chaque recette.';
  static const ouvertureImpossible =
      'Impossible d\'ouvrir le fichier. Réessayez ou choisissez un autre '
      'fichier.';
  static const tronque =
      'Ce fichier contient plus de 500 recettes : seules les 500 premières '
      'sont lues.';
  static const aucuneAImporter = 'Aucune recette à importer.';
  static const aucuneCochee = 'Cochez au moins une recette.';
  static const aucunePourFiltre = 'Aucune recette pour ce filtre.';
  static const termine = 'Import terminé';
  static const revenir = 'Revenir aux recettes';
  static const autreFichier = 'Importer un autre fichier';
  static const enAttente = 'En attente du réseau';

  static String importer(int n) =>
      n == 1 ? 'Importer 1 recette' : 'Importer $n recettes';
  static String toutes(int n) => 'Toutes les recettes ($n)';
  static String toutesAffichees(int n) => 'Toutes les recettes affichées ($n)';

  /// Résumé de l'aperçu, accordé en nombre, sans les compteurs à zéro.
  static String resume({
    required int pretes,
    required int incompletes,
    required int refusees,
    required int deja,
    required int enDouble,
  }) => [
    if (pretes > 0) _n(pretes, 'prête', 'prêtes'),
    if (incompletes > 0) _n(incompletes, 'incomplète', 'incomplètes'),
    if (refusees > 0) _n(refusees, 'refusée', 'refusées'),
    if (deja > 0) _n(deja, 'déjà importée', 'déjà importées'),
    if (enDouble > 0) '$enDouble en double',
  ].join(' · ');

  /// Ligne d'une recette ignorée : son nom et sa raison.
  static String ignoree(String nom, String raison) => '$nom — $raison';
  static const nonCochee = 'Non cochée';
  static String refusee(String raison) => 'Refusée : $raison';
  static String enCours(int faites, int total) =>
      'Import en cours : $faites sur $total';
  static String bilan(int creees, int ignorees, int erreurs) =>
      '${_n(creees, 'créée', 'créées')} · '
      '${_n(ignorees, 'ignorée', 'ignorées')} · '
      '$erreurs en erreur';
  static String horsLigne(int n) => n == 1
      ? '1 recette créée sur l\'appareil. Elle partira au retour du réseau.'
      : '$n recettes créées sur l\'appareil. Elles partiront au retour du '
            'réseau.';
  static String refusServeur(String nom) =>
      'L\'enregistrement de « $nom » a échoué.';
  static String refusGroupe(List<String> noms) =>
      'Import : ${noms.length == 1 ? '1 recette refusée' : '${noms.length} recettes refusées'} '
      'par le serveur : ${noms.join(', ')}.';
  static String details(int n) => 'Détails ($n)';
  static String detailsDe(String nom, int n) => 'Détails de $nom ($n)';
  static const aCompleter = 'À compléter';
  static const modifie = 'Modifié à l\'import';
}

String _n(int n, String singulier, String pluriel) =>
    '$n ${n > 1 ? pluriel : singulier}';

/// Message d'un fichier refusé ; [nomFichier] : nom donné par le système.
String libelleFichierRefuse(
  FichierRefuse refus,
  String nomFichier,
) => switch (refus.raison) {
  RaisonFichier.tropGros => _tropGros(refus.taille),
  RaisonFichier.illisible =>
    'Fichier illisible : « $nomFichier » n\'est ni un fichier BeerXML ni un '
        'fichier BeerJSON.',
  RaisonFichier.jsonNonBeerJson =>
    'Ce fichier JSON n\'est pas au format BeerJSON. Dans votre logiciel, '
        'exportez la recette en BeerXML ou en BeerJSON.',
  RaisonFichier.bsmx =>
    'Fichier BeerSmith (.bsmx) non lu. Dans BeerSmith, exportez la recette '
        'en BeerXML.',
  RaisonFichier.versionInconnue =>
    'Version de BeerJSON non prise en charge (${refus.version ?? 'absente'}). '
        'Kass\'Beer lit les versions 1, 2 et 3.',
  RaisonFichier.aucuneRecette => 'Aucune recette dans « $nomFichier ».',
};

/// Message d'un fichier illisible (JSON ou XML mal formé, encodage invalide).
String fichierIllisible(String nomFichier) => libelleFichierRefuse(
  const FichierRefuse(RaisonFichier.illisible),
  nomFichier,
);

/// « Fichier trop gros : 12,4 Mo. Kass'Beer lit les fichiers de 10 Mo au plus. »
String _tropGros(int? taille) {
  const fin = 'Kass\'Beer lit les fichiers de 10 Mo au plus.';
  if (taille == null) return 'Fichier trop gros. $fin';
  final mo = taille / (1024 * 1024);
  return 'Fichier trop gros : ${formatNombre(mo, decimales: 1)}${nbsp}Mo. $fin';
}

/// Nom d'un champ sans article, et son article.
(String, String) _champ(Champ champ) => switch (champ) {
  Champ.nom => ('nom', 'le '),
  Champ.auteur => ('auteur', 'l\''),
  Champ.notes => ('notes', 'les '),
  Champ.style => ('style', 'le '),
  Champ.type => ('type', 'le '),
  Champ.volume => ('volume', 'le '),
  Champ.dureeEbullition => ('durée d\'ébullition', 'la '),
  Champ.temperatureGrain => ('température du grain', 'la '),
  Champ.quantite => ('quantité', 'la '),
  Champ.couleur => ('couleur', 'la '),
  Champ.rendement => ('rendement d\'extrait', 'le '),
  Champ.acidesAlpha => ('acides alpha', 'les '),
  Champ.forme => ('forme', 'la '),
  Champ.moment => ('moment d\'ajout', 'le '),
  Champ.duree => ('durée', 'la '),
  Champ.attenuation => ('atténuation', 'l\''),
  Champ.temperaturePalier => ('température', 'la '),
  Champ.dureePalier => ('durée', 'la '),
};

/// « quantité de Pils », « volume ».
String _designation(Grandeur g) {
  final (nom, _) = _champ(g.champ);
  return g.ligne == null ? nom : '$nom de ${g.ligne}';
}

/// « la quantité de Pils », « le volume ».
String _avecArticle(Grandeur g) => '${_champ(g.champ).$2}${_designation(g)}';

String _liste(ListeRecette liste) => switch (liste) {
  ListeRecette.malts => 'malts',
  ListeRecette.houblons => 'houblons',
  ListeRecette.ajouts => 'ajouts',
  ListeRecette.levures => 'levures',
  ListeRecette.paliers => 'paliers',
};

String _uneLigne(ListeRecette liste) => switch (liste) {
  ListeRecette.malts => 'd\'un malt',
  ListeRecette.houblons => 'd\'un houblon',
  ListeRecette.ajouts => 'd\'un ajout',
  ListeRecette.levures => 'd\'une levure',
  ListeRecette.paliers => 'd\'un palier',
};

/// Raison du refus d'une recette.
String libelleRefus(Refus refus) => switch (refus) {
  NomAbsent() => 'Nom absent.',
  TropDeLignes(:final liste, :final nombre, :final maximum) =>
    'Plus de $maximum ${_liste(liste)} ($nombre).',
  UniteInconnue(:final grandeur, :final unite) =>
    'Unité inconnue pour ${_avecArticle(grandeur)} : « $unite ».',
  ValeurHorsLimites(:final grandeur) =>
    'Valeur hors limites : ${_designation(grandeur)}.',
  ValeurIllisible(:final grandeur) =>
    'Valeur illisible : ${_designation(grandeur)}.',
  ValeurAbsente(:final grandeur) =>
    'Valeur absente : ${_designation(grandeur)}.',
  ValeurInconnue(:final grandeur, :final valeur) =>
    'Valeur inconnue pour ${_avecArticle(grandeur)} : « $valeur ».',
  NomDeLigneIllisible(:final liste) =>
    'Nom ${_uneLigne(liste)} absent ou sans lettre ni chiffre.',
  RecetteIllisible() => 'Recette illisible.',
};

String _partie(PartieNonImportee partie) => switch (partie) {
  PartieNonImportee.eau => 'profil d\'eau',
  PartieNonImportee.fermentation => 'étapes de fermentation',
  PartieNonImportee.conditionnement => 'conditionnement',
  PartieNonImportee.degustation => 'notes de dégustation',
  PartieNonImportee.rendement => 'rendement du fichier',
  PartieNonImportee.valeursAnnoncees =>
    'densités, degré, amertume et couleur annoncés',
  PartieNonImportee.ebullition => 'détails de l\'ébullition',
  PartieNonImportee.detailsPaliers => 'détails des paliers',
  PartieNonImportee.detailsIngredients =>
    'détails des ingrédients (producteur, origine…)',
  PartieNonImportee.coAuteurEtDate => 'co-auteur et date de création',
  PartieNonImportee.equipement => 'équipement du fichier',
  PartieNonImportee.nomEmpatage => 'nom de l\'empâtage',
};

String _unite(String unite) => switch (unite) {
  'lb' => 'livres',
  'oz' => 'onces',
  'kg' => 'kilogrammes',
  'mg' => 'milligrammes',
  'ml' => 'millilitres',
  'gal' => 'gallons',
  'igal' => 'gallons impériaux',
  'qt' => 'quarts',
  'iqt' => 'quarts impériaux',
  'pt' => 'pintes',
  'ipt' => 'pintes impériales',
  'cup' => 'tasses',
  'tsp' => 'cuillères à café',
  'tbsp' => 'cuillères à soupe',
  'floz' => 'onces liquides',
  'ifloz' => 'onces liquides impériales',
  'bbl' => 'barils',
  'ibbl' => 'barils impériaux',
  'F' => '°F',
  'Lovi' => 'Lovibond',
  'SRM' => 'SRM',
  'potential' => 'densité potentielle',
  'sec' => 'secondes',
  'hr' => 'heures',
  'day' => 'jours',
  'week' => 'semaines',
  _ => unite,
};

String _texteCoupe(Grandeur g, int maximum) {
  final max = formatNombre(maximum.toDouble(), decimales: 0);
  return switch (g.champ) {
    Champ.notes => 'Notes coupées à $max caractères.',
    Champ.auteur => 'Auteur coupé à $max caractères.',
    Champ.style => 'Style coupé à $max caractères.',
    _ => 'Nom coupé à $max caractères.',
  };
}

String _majuscule(String texte) =>
    texte.isEmpty ? texte : '${texte[0].toUpperCase()}${texte.substring(1)}';

/// Moment retenu pour un ajout dont le moment a été simplifié.
String _moment(String? usage) => switch (usage) {
  'add_to_boil' => 'compté à l\'ébullition',
  'add_to_fermentation' => 'compté à cru',
  'add_to_mash' => 'compté à l\'empâtage',
  'add_to_package' => 'compté au conditionnement',
  _ => 'gardé sans moment',
};

/// Changement fait à la lecture d'une recette.
String libelleModification(Modification m) => switch (m) {
  StyleReduitAuNom(:final style) => 'Style : seul le nom « $style » est gardé.',
  PartiesNonImportees(:final parties) =>
    'Non importés : ${parties.map(_partie).join(', ')}.',
  TexteCoupe(:final grandeur, :final maximum) => _texteCoupe(grandeur, maximum),
  UnitesConverties(:final unites) =>
    'Unités converties (${unites.map(_unite).toSet().join(', ')}).',
  ValeurRejetee(:final grandeur, :final raison, :final unite) =>
    switch (raison) {
      RaisonRejet.nulle =>
        'Valeur 0 lue comme absente : ${_designation(grandeur)}.',
      RaisonRejet.uniteNonPriseEnCharge =>
        'Non importé : ${_designation(grandeur)} en « $unite ».',
      RaisonRejet.horsLimites =>
        'Non importé : ${_designation(grandeur)}, hors limites.',
      RaisonRejet.inconnue =>
        'Non importé : ${_designation(grandeur)}, valeur inconnue.',
      RaisonRejet.moutureGrossiere =>
        'Non importé : ${_designation(grandeur)}, donné pour une mouture '
            'grossière seule.',
    },
  DureeArrondie(:final grandeur) =>
    grandeur.ligne == null
        ? '${_majuscule(_designation(grandeur))} arrondie à la minute.'
        : 'Durée de ${grandeur.ligne} arrondie à la minute.',
  MomentSimplifie(:final ligne, :final usage) =>
    'Moment d\'ajout simplifié : $ligne, ${_moment(usage)}.',
  FirstWortEnEbullition(:final ligne, :final minutes) =>
    minutes == null
        ? 'First Wort : $ligne compté à l\'ébullition, durée à compléter.'
        : 'First Wort : $ligne compté à l\'ébullition, $minutes${nbsp}min.',
  ArretDuFeuSansDuree(:final ligne, :final usage) =>
    '$usage sans durée : $ligne compté à l\'arrêt du feu.',
  AromaEnEbullition(:final ligne, :final minutes) =>
    'Aroma : $ligne compté à l\'ébullition, $minutes${nbsp}min. Si c\'est un '
        'whirlpool, choisissez Whirlpool dans la recette.',
  CaracteresRetires() => 'Caractères de contrôle retirés des textes.',
  ChampsInconnus(:final nombre) =>
    nombre == 1
        ? '1 champ inconnu ignoré.'
        : '$nombre champs inconnus ignorés.',
};

/// Textes de la feuille « Exporter ».
abstract final class TextesExport {
  static String titre(String nom) => 'Exporter « $nom »';
  static const sansPrix = 'Le fichier ne contient aucun prix.';
  static const beerJson = 'BeerJSON';
  static const beerJsonAide = 'Format le plus complet.';
  static const beerXml = 'BeerXML';
  static const beerXmlAide = 'Lu par la plupart des logiciels de brassage.';
  static const pret = 'Prêt à exporter.';
  static String auteur(String nom) => 'Auteur dans le fichier : $nom.';
  static const beerXmlBloque =
      'BeerXML demande un style de la liste BJCP. Le choix du style arrive '
      'dans une prochaine version.';
  static String bloque(int n) => n == 1
      ? 'Export impossible : 1 valeur à compléter.'
      : 'Export impossible : $n valeurs à compléter.';
  static const completer = 'Compléter la recette';
  static const dupliquer = 'Dupliquer';
  static const dupliquerPourExporter =
      'Dupliquez la recette pour l\'exporter à votre nom.';
  static const autreMembre =
      'Seul l\'auteur complète cette recette. Dupliquez-la pour la compléter '
      'à votre nom.';
  static const annuler = 'Annuler';
  static const fermer = 'Fermer';
  static const echec = 'Le fichier n\'a pas pu être créé.';
  static String telecharge(String nom) => 'Téléchargement lancé : $nom.';
  static const enregistre = 'Fichier enregistré.';
}

/// « le moment Conditionnement », « la forme Poudre », « le type Miel » : la valeur
/// de la recette avec les mots de l'éditeur.
String _valeurEditeur(ListeRecette liste, Champ champ, String source) {
  final EnumerationBeerJson? valeurs = switch ((liste, champ)) {
    (ListeRecette.malts, _) => typesFermentable,
    (ListeRecette.houblons, Champ.forme) => formesHoublon,
    (ListeRecette.levures, Champ.forme) => formesLevure,
    (ListeRecette.levures, _) => typesLevure,
    (ListeRecette.ajouts, _) => typesAjout,
    (ListeRecette.paliers, _) => typesPalier,
    _ => null,
  };
  final valeur = switch (source) {
    'whirlpool' => 'Whirlpool',
    'add_to_package' => 'Conditionnement',
    _ => valeurs?.libelle(source) ?? source,
  };
  return switch (champ) {
    Champ.moment => 'le moment $valeur',
    Champ.forme => 'la forme $valeur',
    _ => 'le type $valeur',
  };
}

/// Information non exportée.
String libellePerte(PerteExport perte) => switch (perte) {
  StyleNonExporte(:final nom) =>
    'Non exporté : le style « $nom » (BeerJSON demande sa catégorie).',
  ChronologieNonExportee() => 'Non exporté : la chronologie du jour.',
  EmpatageNonExporte() => 'Non exporté : empâtage (aucun palier).',
  EbullitionNonExportee() => 'Non exporté : ébullition (durée non renseignée).',
  // Pertes du BeerXML : l'export BeerXML reste bloqué tant que le choix du
  // style n'existe pas (ADR-005, décision 2) ; ces libellés le suivront.
  ValeurEcriteAutrement(
    :final ligne,
    :final liste,
    :final champ,
    :final source,
    :final ecrite,
  ) =>
    '$ligne : ${_valeurEditeur(liste, champ, source)} '
        'est ${champ == Champ.forme ? 'écrite' : 'écrit'} $ecrite en BeerXML.',
  VolumeInfusionNonExporte(:final paliers) =>
    'Non exporté : volume d\'eau des paliers (${paliers.join(', ')}).',
  JourAjoutNonExporte(:final lignes) =>
    'Non exporté : jour d\'ajout à cru (${lignes.join(', ')}).',
  DureeApresArretNonExportee(:final lignes) =>
    'Non exporté : durée après l\'arrêt du feu (${lignes.join(', ')}).',
};
