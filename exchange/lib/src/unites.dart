import 'package:brewing/brewing.dart';

/// Conversions des unités sans formule de brassage vers les unités canoniques
/// d'ADR-005 (`g`, `l`, `C`, `min`). Les couleurs et la densité potentielle
/// passent par `brewing/` (P3). Les unités sont celles de
/// `measureable_units.json` au commit figé.

/// Grammes par unité de masse.
const Map<String, double> kGrammesPar = {
  'mg': 0.001,
  'g': 1,
  'kg': 1000,
  'lb': 453.59237,
  'oz': 28.349523125,
};

/// Litres par unité de volume (mesures américaines, puis impériales).
const Map<String, double> kLitresPar = {
  'ml': 0.001,
  'l': 1,
  'tsp': 0.00492892159375,
  'tbsp': 0.01478676478125,
  'floz': 0.0295735295625,
  'cup': 0.2365882365,
  'pt': 0.473176473,
  'qt': 0.946352946,
  'gal': 3.785411784,
  'bbl': 117.347765304,
  'ifloz': 0.0284130625,
  'ipt': 0.56826125,
  'iqt': 1.1365225,
  'igal': 4.54609,
  'ibbl': 163.65924,
};

/// Minutes par unité de durée.
const Map<String, double> kMinutesPar = {
  'sec': 1 / 60,
  'min': 1,
  'hr': 60,
  'day': 1440,
  'week': 10080,
};

/// Unités de température du schéma.
const Set<String> kUnitesTemperature = {'C', 'F'};

/// Unités de couleur du schéma.
const Set<String> kUnitesCouleur = {'EBC', 'Lovi', 'SRM'};

/// Unités de densité du schéma.
const Set<String> kUnitesDensite = {'sg', 'plato', 'brix'};

/// Unités sans dimension du schéma (`UnitType` : un sachet, une pastille).
const Set<String> kUnitesSansDimension = {
  '1',
  'unit',
  'each',
  'dimensionless',
  'pkg',
};

/// Température en °C d'une température exprimée en [unite] (`C` ou `F`).
double versCelsius(double valeur, String unite) =>
    unite == 'F' ? (valeur - 32) * 5 / 9 : valeur;

/// Couleur en EBC d'une couleur exprimée en [unite] (`EBC`, `Lovi`, `SRM`).
/// [valeur] est positive ou nulle : l'appelant l'a vérifié.
double versEbc(double valeur, String unite) => switch (unite) {
  'Lovi' => lovibondToEbc(valeur),
  'SRM' => srmToEbc(valeur),
  _ => valeur,
};
