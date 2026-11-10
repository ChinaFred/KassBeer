/// Descriptions stables du compte rendu, sans `dart:io` : les suites qui ne
/// lisent aucun fichier tournent aussi dans un navigateur.
library;

import 'package:exchange/exchange.dart';

/// Description stable d'un [Refus] ou d'une [Modification], pour les fixtures
/// attendues : le type, puis ses valeurs.
String decrire(Object value) => switch (value) {
  NomAbsent() => 'NomAbsent',
  TropDeLignes(:final liste, :final nombre, :final maximum) =>
    'TropDeLignes(${liste.name}, $nombre, $maximum)',
  UniteInconnue(:final grandeur, :final unite) =>
    'UniteInconnue(${_g(grandeur)}, $unite)',
  ValeurHorsLimites(:final grandeur) => 'ValeurHorsLimites(${_g(grandeur)})',
  ValeurIllisible(:final grandeur) => 'ValeurIllisible(${_g(grandeur)})',
  ValeurAbsente(:final grandeur) => 'ValeurAbsente(${_g(grandeur)})',
  ValeurInconnue(:final grandeur, :final valeur) =>
    'ValeurInconnue(${_g(grandeur)}, $valeur)',
  NomDeLigneIllisible(:final liste) => 'NomDeLigneIllisible(${liste.name})',
  RecetteIllisible() => 'RecetteIllisible',
  StyleReduitAuNom(:final style) => 'StyleReduitAuNom($style)',
  PartiesNonImportees(:final parties) =>
    'PartiesNonImportees(${parties.map((p) => p.name).join(', ')})',
  TexteCoupe(:final grandeur, :final maximum) =>
    'TexteCoupe(${_g(grandeur)}, $maximum)',
  UnitesConverties(:final unites) => 'UnitesConverties(${unites.join(', ')})',
  ValeurRejetee(:final grandeur, :final raison, :final unite) =>
    'ValeurRejetee(${_g(grandeur)}, ${raison.name}${unite == null ? '' : ', $unite'})',
  DureeArrondie(:final grandeur) => 'DureeArrondie(${_g(grandeur)})',
  MomentSimplifie(:final ligne, :final usage) =>
    'MomentSimplifie($ligne, $usage)',
  FirstWortEnEbullition(:final ligne, :final minutes) =>
    'FirstWortEnEbullition($ligne, $minutes)',
  ArretDuFeuSansDuree(:final ligne, :final usage) =>
    'ArretDuFeuSansDuree($ligne, $usage)',
  AromaEnEbullition(:final ligne, :final minutes) =>
    'AromaEnEbullition($ligne, $minutes)',
  CaracteresRetires() => 'CaracteresRetires',
  ChampsInconnus(:final nombre) => 'ChampsInconnus($nombre)',
  _ => throw ArgumentError('type inattendu : ${value.runtimeType}'),
};

String _g(Grandeur g) =>
    g.ligne == null ? g.champ.name : '${g.champ.name}, ${g.ligne}';

/// Description d'une analyse, comparée à une fixture `*.attendu.json`. Une
/// recette lue porte `format_version` et `recipe`, comme un document
/// `recipes/{id}` : `rules-tests/` la valide contre le schéma partiel.
Map<String, Object?> decrireAnalyse(AnalyseFichier analyse) =>
    switch (analyse) {
      FichierRefuse(:final raison, :final taille, :final version) => {
        'refus': raison.name,
        'taille': ?taille,
        'version': ?version,
      },
      FichierLu(:final format, :final recettes, :final total) => {
        'format': format.nom,
        'total': total,
        'recettes': [
          for (final r in recettes)
            {
              'numero': r.numero,
              'nom': r.nom,
              'empreinte': r.empreinte,
              'en_double': r.enDouble,
              ...switch (r.resultat) {
                RecetteRefusee(:final refus) => {'refus': decrire(refus)},
                RecetteLue(:final recipe, :final modifications) => {
                  'modifications': [for (final m in modifications) decrire(m)],
                  'document': {'format_version': 1, 'recipe': recipe},
                },
              },
            },
        ],
      },
    };
