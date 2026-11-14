import 'modele_exemple.dart';
import 'modele_processus.dart';

/// Plan de brassage des fiches Excel, accepté le 2026-11-14 : la journée de
/// brassage des fiches (étapes, durées en minutes, températures visées en °C),
/// puis les journées J+4 et J+14 du modèle d'exemple. Comme lui, il ne
/// s'écrit que sur l'action du brasseur et devient une donnée du brasseur. Ses
/// durées et températures ne sont pas des formules de brassage (P3). Cas
/// `fiches` de `brewing/test/fixtures/process.json`.

/// Nom de la copie, modifiable avant « Enregistrer ».
const kNomModeleFiches = 'Plan de brassage des fiches';

/// Note portée par chaque copie du plan de brassage des fiches.
const kNoteModeleFiches =
    'Tiré du plan de brassage des fiches Excel. Durées et températures à '
    'ajuster.';

final _journees = <JourneePredefinie>[
  (
    name: 'Brassage',
    offsetDays: 0,
    requiresRecipeBlock: false,
    elements: [
      (
        NatureElement.etape,
        'Mise en place et nettoyage du matériel et de l\'espace de travail',
        30,
        null,
      ),
      (NatureElement.etape, 'Remplissage de la cuve', 10, 16),
      (NatureElement.etape, 'Correction de l\'eau (sel et acide)', 5, null),
      (
        NatureElement.etape,
        'Chauffe de l\'eau et concassage des malts',
        15,
        68,
      ),
      (NatureElement.chronologieRecette, null, null, null),
      (NatureElement.etape, 'Début du refroidissement', 40, 100),
      (NatureElement.etape, 'Fin du refroidissement', 0, 25),
      (NatureElement.etape, 'Whirlpool', 5, null),
      (NatureElement.etape, 'Mesure de la densité initiale', 5, null),
      (
        NatureElement.etape,
        'Transvasement dans la cuve de fermentation',
        5,
        null,
      ),
      (NatureElement.etape, 'Ajout des levures', 2, null),
      (NatureElement.etape, 'Stockage en cave', 5, null),
      (NatureElement.etape, 'Nettoyage', 20, null),
      (NatureElement.etape, 'Rangement', 10, null),
    ],
  ),
  ...kJourneesSuiteExemple,
];

/// Copie du plan de brassage des fiches, avec des clés neuves ([nouvelleCle] :
/// `doc().id`).
ContenuModele modeleFiches(String Function() nouvelleCle) => contenuPredefini(
  name: kNomModeleFiches,
  notes: kNoteModeleFiches,
  journees: _journees,
  nouvelleCle: nouvelleCle,
);
