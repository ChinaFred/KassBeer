import 'modele_processus.dart';

/// Modèle d'exemple accepté le 2026-11-11 (ADR-010) : trois journées, durées en
/// minutes. Il ne s'applique jamais seul : il ne s'écrit que sur l'action du
/// brasseur (section « Modèles à copier » de « Mes processus », puis
/// « Enregistrer »), et devient alors une donnée du brasseur, modifiable. Un brassin sans processus garde sa journée tirée de la
/// recette (P37). Ses durées ne sont pas des formules de brassage (P3). Cas
/// `exemple` de `brewing/test/fixtures/process.json`.

/// Nom de la copie, modifiable avant « Enregistrer ».
const kNomModeleExemple = 'Brassage, houblonnage à cru, embouteillage';

/// Note portée par chaque copie du modèle d'exemple.
const kNoteModeleExemple = 'Durées typiques, à ajuster à votre matériel.';

/// Étape ou bloc d'une journée de modèle prédéfini : nature, nom, durée en
/// minutes et température en °C (étape seulement).
typedef ElementPredefini = (
  NatureElement nature,
  String? name,
  double? minutes,
  double? tempC,
);

/// Journée d'un modèle prédéfini.
typedef JourneePredefinie = ({
  String name,
  int offsetDays,
  bool requiresRecipeBlock,
  List<ElementPredefini> elements,
});

/// Bloc tiré de la recette, sans nom ni durée.
ElementPredefini _bloc(NatureElement nature) => (nature, null, null, null);

/// Journées « Houblonnage à cru » (J+4) et « Embouteillage » (J+14) du modèle
/// d'exemple, reprises telles quelles par le plan de brassage des fiches.
final kJourneesSuiteExemple = <JourneePredefinie>[
  (
    name: 'Houblonnage à cru',
    offsetDays: 4,
    requiresRecipeBlock: true,
    elements: [
      (NatureElement.etape, 'Désinfection du matériel', 10, null),
      (NatureElement.etape, 'Mesure de densité', 5, null),
      _bloc(NatureElement.houblonsACru),
      (NatureElement.etape, 'Nettoyage', 10, null),
    ],
  ),
  (
    name: 'Embouteillage',
    offsetDays: 14,
    requiresRecipeBlock: false,
    elements: [
      (NatureElement.etape, 'Lavage des bouteilles', 60, null),
      (
        NatureElement.etape,
        'Désinfection des bouteilles et du matériel',
        30,
        null,
      ),
      (NatureElement.etape, 'Préparation du sucre de resucrage', 15, null),
      (NatureElement.etape, 'Transfert en cuve d\'embouteillage', 15, null),
      _bloc(NatureElement.ajoutsEmbouteillage),
      (NatureElement.etape, 'Mise en bouteilles et capsulage', 60, null),
      (NatureElement.etape, 'Nettoyage et rangement', 30, null),
    ],
  ),
];

final _journees = <JourneePredefinie>[
  (
    name: 'Brassage',
    offsetDays: 0,
    requiresRecipeBlock: false,
    elements: [
      (NatureElement.etape, 'Mise en place du matériel', 30, null),
      (NatureElement.etape, 'Désinfection du fermenteur', 20, null),
      (NatureElement.etape, 'Chauffe de l\'eau d\'empâtage', 40, null),
      (NatureElement.etape, 'Mouture du grain', 20, null),
      _bloc(NatureElement.chronologieRecette),
      (NatureElement.etape, 'Refroidissement', 30, null),
      (NatureElement.etape, 'Mise en cuve et mesure de densité', 15, null),
      (NatureElement.etape, 'Oxygénation et ensemencement', 10, null),
      (NatureElement.etape, 'Nettoyage du matériel', 60, null),
      (NatureElement.etape, 'Rangement', 30, null),
    ],
  ),
  ...kJourneesSuiteExemple,
];

/// Copie d'un modèle prédéfini, avec des clés neuves ([nouvelleCle] :
/// `doc().id`), à écrire sous le nom du brasseur qui la demande.
ContenuModele contenuPredefini({
  required String name,
  required String notes,
  required List<JourneePredefinie> journees,
  required String Function() nouvelleCle,
}) => ContenuModele(
  name: name,
  notes: notes,
  journees: [
    for (final j in journees)
      JourneeModele(
        key: nouvelleCle(),
        name: j.name,
        offsetDays: j.offsetDays,
        requiresRecipeBlock: j.requiresRecipeBlock,
        elements: [
          for (final (nature, name, minutes, tempC) in j.elements)
            nature == NatureElement.etape
                ? ElementModele.etape(
                    key: nouvelleCle(),
                    name: name!,
                    durationMin: minutes!,
                    tempC: tempC,
                  )
                : ElementModele.bloc(key: nouvelleCle(), nature: nature),
        ],
      ),
  ],
);

/// Copie du modèle d'exemple, avec des clés neuves ([nouvelleCle] : `doc().id`),
/// à écrire sous le nom du brasseur qui la demande.
ContenuModele modeleExemple(String Function() nouvelleCle) => contenuPredefini(
  name: kNomModeleExemple,
  notes: kNoteModeleExemple,
  journees: _journees,
  nouvelleCle: nouvelleCle,
);
