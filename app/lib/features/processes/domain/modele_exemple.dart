import 'modele_processus.dart';

/// Modèle d'exemple accepté le 2026-11-11 (ADR-010) : trois journées, durées en
/// minutes. Il ne s'applique jamais seul : il ne s'écrit que sur l'action du
/// brasseur « Partir du modèle d'exemple », et devient alors une donnée du
/// brasseur, modifiable. Un brassin sans processus garde sa journée tirée de la
/// recette (P37). Ses durées ne sont pas des formules de brassage (P3). Cas
/// `exemple` de `brewing/test/fixtures/process.json`.

/// Nom de la copie, modifiable avant « Enregistrer ».
const kNomModeleExemple = 'Brassage, houblonnage à cru, embouteillage';

/// Note portée par chaque copie du modèle d'exemple.
const kNoteModeleExemple = 'Durées typiques, à ajuster à votre matériel.';

typedef _Element = (NatureElement nature, String? name, double? minutes);

const _journees =
    <
      ({
        String name,
        int offsetDays,
        bool requiresRecipeBlock,
        List<_Element> elements,
      })
    >[
      (
        name: 'Brassage',
        offsetDays: 0,
        requiresRecipeBlock: false,
        elements: [
          (NatureElement.etape, 'Mise en place du matériel', 30),
          (NatureElement.etape, 'Désinfection du fermenteur', 20),
          (NatureElement.etape, 'Chauffe de l\'eau d\'empâtage', 40),
          (NatureElement.etape, 'Mouture du grain', 20),
          (NatureElement.chronologieRecette, null, null),
          (NatureElement.etape, 'Refroidissement', 30),
          (NatureElement.etape, 'Mise en cuve et mesure de densité', 15),
          (NatureElement.etape, 'Oxygénation et ensemencement', 10),
          (NatureElement.etape, 'Nettoyage du matériel', 60),
          (NatureElement.etape, 'Rangement', 30),
        ],
      ),
      (
        name: 'Houblonnage à cru',
        offsetDays: 4,
        requiresRecipeBlock: true,
        elements: [
          (NatureElement.etape, 'Désinfection du matériel', 10),
          (NatureElement.etape, 'Mesure de densité', 5),
          (NatureElement.houblonsACru, null, null),
          (NatureElement.etape, 'Nettoyage', 10),
        ],
      ),
      (
        name: 'Embouteillage',
        offsetDays: 14,
        requiresRecipeBlock: false,
        elements: [
          (NatureElement.etape, 'Lavage des bouteilles', 60),
          (
            NatureElement.etape,
            'Désinfection des bouteilles et du matériel',
            30,
          ),
          (NatureElement.etape, 'Préparation du sucre de resucrage', 15),
          (NatureElement.etape, 'Transfert en cuve d\'embouteillage', 15),
          (NatureElement.ajoutsEmbouteillage, null, null),
          (NatureElement.etape, 'Mise en bouteilles et capsulage', 60),
          (NatureElement.etape, 'Nettoyage et rangement', 30),
        ],
      ),
    ];

/// Copie du modèle d'exemple, avec des clés neuves ([nouvelleCle] : `doc().id`),
/// à écrire sous le nom du brasseur qui la demande.
ContenuModele modeleExemple(String Function() nouvelleCle) => ContenuModele(
  name: kNomModeleExemple,
  notes: kNoteModeleExemple,
  journees: [
    for (final j in _journees)
      JourneeModele(
        key: nouvelleCle(),
        name: j.name,
        offsetDays: j.offsetDays,
        requiresRecipeBlock: j.requiresRecipeBlock,
        elements: [
          for (final (nature, name, minutes) in j.elements)
            nature == NatureElement.etape
                ? ElementModele.etape(
                    key: nouvelleCle(),
                    name: name!,
                    durationMin: minutes!,
                  )
                : ElementModele.bloc(key: nouvelleCle(), nature: nature),
        ],
      ),
  ],
);
