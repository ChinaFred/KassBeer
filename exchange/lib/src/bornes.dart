/// Bornes d'un import (P9 réécrit par ADR-005, amendements de L2) et bornes des
/// champs (`firestore.rules`, éditeur de recette).
library;

/// Taille maximale d'un fichier lu : 10 Mo.
const int kMaxOctetsParFichier = 10 * 1024 * 1024;

/// Nombre maximal de recettes lues dans un fichier ; au-delà, les premières.
const int kMaxRecettesParFichier = 500;

/// Plafonds des listes d'une recette (`firestore.rules`).
const Map<String, int> kPlafondsListes = {
  'fermentable_additions': 50,
  'hop_additions': 50,
  'miscellaneous_additions': 50,
  'culture_additions': 10,
};

/// Plafond des paliers d'empâtage (`firestore.rules`).
const int kMaxPaliers = 20;

/// Longueur maximale du nom, de l'auteur et du style d'une recette, et du nom
/// d'une ligne.
const int kMaxNom = 120;

/// Longueur maximale des notes d'une recette.
const int kMaxNotes = 10000;

/// Durée d'ébullition maximale, en minutes (éditeur).
const int kMaxDureeEbullition = 600;

/// Durée maximale d'un palier, en minutes (éditeur).
const int kMaxDureePalier = 600;

/// Température d'un palier, en °C (éditeur).
const double kMinTemperaturePalier = 0;

/// Température d'un palier, en °C (éditeur).
const double kMaxTemperaturePalier = 100;

/// Température du grain, en °C (éditeur).
const double kMinTemperatureGrain = -20;

/// Température du grain, en °C (éditeur).
const double kMaxTemperatureGrain = 60;

/// Plafonds hauts d'une valeur convertie, sans borne dans l'éditeur : au-delà,
/// une valeur obligatoire refuse la recette, une valeur facultative est écartée.
/// Ce sont des garde-fous contre un fichier faux, pas des valeurs métier : ils
/// laissent passer toute recette amateur ou de brasserie.

/// Quantité d'une ligne en masse : 1 000 kg.
const double kMaxGrammesParLigne = 1000000;

/// Quantité d'une ligne en volume : 1 000 L.
const double kMaxLitresParLigne = 1000;

/// Volume en fermenteur : 10 000 L.
const double kMaxVolumeBrassin = 10000;

/// Couleur d'un fermentescible : 2 000 EBC. Les malts torréfiés les plus foncés
/// approchent 1 500 EBC.
const double kMaxEbc = 2000;

/// Durée d'un ajout hors ébullition (à cru, empâtage, conditionnement) : 365
/// jours, en minutes. L'ébullition et les paliers gardent les 600 minutes de
/// l'éditeur.
const int kMaxDuree = 365 * 1440;
