/// Écran concerné par un ticket : un modèle de route, jamais une adresse.
///
/// L'écran part sur une Issue publique (ADR-006). Une adresse réelle
/// (`/recettes/aB3…`) y publierait l'identifiant d'une recette ; seul le modèle
/// (`/recettes/:id`) part. [ticketScreenValue] ne rend qu'une valeur d'un
/// ensemble fermé : une clé de [kTicketScreenNames] ou de [kTicketElements],
/// [kTicketScreenOther] ou [kTicketScreenUnknown].
///
/// Un élément (menu ou fenêtre) s'écrit dans la même valeur :
/// `<modèle de route>/menu/<clé>` ou `<modèle de route>/fenetre/<clé>`. Aucune
/// route ne contient de segment `menu` ou `fenetre` : la valeur se lit sans
/// ambiguïté.
library;

/// Valeur de « Autre écran ».
const kTicketScreenOther = 'autre';

/// Valeur de « Je ne sais pas ».
const kTicketScreenUnknown = 'inconnu';

/// Modèle de route → nom de l'écran, dans l'ordre de la liste déroulante.
///
/// `test/ticket_screens_test.dart` vérifie que chaque route de `app_router.dart`
/// y figure : une route ajoutée sans son nom fait échouer la suite.
const Map<String, String> kTicketScreenNames = {
  '/recettes': 'Recettes',
  '/recettes/:id': 'Recette',
  '/recettes/nouvelle': 'Nouvelle recette',
  '/recettes/importer': 'Importer des recettes',
  '/recettes/:id/modifier': 'Modifier la recette',
  '/recettes/:id/chronologie': 'Chronologie du jour',
  '/bibliotheque': 'Bibliothèque',
  '/bibliotheque/styles': 'Bibliothèque › Styles',
  '/bibliotheque/styles/:id': 'Bibliothèque › Style',
  '/bibliotheque/malts': 'Bibliothèque › Malts et sucres',
  '/bibliotheque/malts/:id': 'Bibliothèque › Malt ou sucre',
  '/bibliotheque/houblons': 'Bibliothèque › Houblons',
  '/bibliotheque/houblons/:id': 'Bibliothèque › Houblon',
  '/bibliotheque/levures': 'Bibliothèque › Levures',
  '/bibliotheque/levures/:id': 'Bibliothèque › Levure',
  '/bibliotheque/divers': 'Bibliothèque › Divers',
  '/bibliotheque/divers/:id': 'Bibliothèque › Ajout divers',
  '/bibliotheque/recettes': 'Bibliothèque › Recettes publiques',
  '/bibliotheque/recettes/:id': 'Bibliothèque › Recette publique',
  '/sources-des-donnees': 'Sources des données',
  '/brassins': 'Brassins',
  '/brassins/:id': 'Brassin',
  '/brassins/:id/preparer': 'Préparer le brassage',
  '/brassins/:id/jour': 'Jour de brassage',
  '/equipements': 'Équipements',
  '/equipements/:id': 'Équipement',
  '/equipements/nouveau': 'Nouvel équipement',
  '/equipements/:id/modifier': 'Modifier l\'équipement',
  '/prix': 'Mes prix',
  '/processus': 'Mes processus',
  '/processus/nouveau': 'Nouveau processus',
  '/processus/:id': 'Processus',
  '/processus/:id/modifier': 'Modifier le processus',
  '/nouveautes': 'Nouveautés',
  '/tickets': 'Mes tickets',
  '/tickets/nouveau': 'Signaler ou proposer',
  '/tickets/:id': 'Suivi d\'un ticket',
  '/admin': 'Admin',
  '/admin/membres': 'Admin › Membres',
  '/admin/tickets': 'Admin › Tickets des membres',
  '/admin/tickets/:id': 'Admin › Ticket d\'un membre',
};

/// Écrans affichés dans la coquille : barre du haut avec le menu du compte,
/// barre ou rail de navigation.
///
/// `test/ticket_screens_test.dart` vérifie que cette liste est celle des routes
/// de la `ShellRoute` de `app_router.dart`.
const kTicketShellScreens = [
  '/recettes',
  '/recettes/:id',
  '/bibliotheque/styles',
  '/bibliotheque/styles/:id',
  '/bibliotheque/malts',
  '/bibliotheque/malts/:id',
  '/bibliotheque/houblons',
  '/bibliotheque/houblons/:id',
  '/bibliotheque/levures',
  '/bibliotheque/levures/:id',
  '/bibliotheque/divers',
  '/bibliotheque/divers/:id',
  '/bibliotheque/recettes',
  '/bibliotheque/recettes/:id',
  '/brassins',
  '/brassins/:id',
  '/brassins/:id/preparer',
  '/equipements',
  '/equipements/:id',
  '/admin',
  '/admin/membres',
  '/admin/tickets',
  '/admin/tickets/:id',
];

/// Éléments de la coquille, ajoutés à chaque écran de [kTicketShellScreens].
/// Les commentaires `// ticket:` de `app_shell.dart` citent, pour chaque écran
/// de la coquille, sa clé `menu/compte` ou `menu/navigation`.
const kTicketShellElements = {
  'menu/compte': 'Menu du compte',
  'menu/navigation': 'Barre de navigation',
};

/// Éléments propres à un écran, dans l'ordre de la liste « Élément précis ».
const _kTicketScreenElements = {
  '/recettes/:id/fenetre/exporter': 'Exporter la recette',
  '/recettes/:id/fenetre/nouveau-brassin': 'Nouveau brassin',
  '/recettes/:id/fenetre/prix': 'Prix d\'un ingrédient',
  '/recettes/:id/fenetre/reprendre': 'Reprendre un prix',
  '/recettes/nouvelle/fenetre/malt': 'Malt ou sucre',
  '/recettes/nouvelle/fenetre/houblon': 'Houblon',
  '/recettes/nouvelle/fenetre/ajout': 'Autre ajout',
  '/recettes/nouvelle/fenetre/levure': 'Levure',
  '/recettes/nouvelle/fenetre/palier': 'Palier',
  '/recettes/nouvelle/fenetre/calculs': 'Détail des calculs',
  '/recettes/nouvelle/menu/ligne': 'Actions d\'une ligne',
  '/recettes/:id/modifier/fenetre/malt': 'Malt ou sucre',
  '/recettes/:id/modifier/fenetre/houblon': 'Houblon',
  '/recettes/:id/modifier/fenetre/ajout': 'Autre ajout',
  '/recettes/:id/modifier/fenetre/levure': 'Levure',
  '/recettes/:id/modifier/fenetre/palier': 'Palier',
  '/recettes/:id/modifier/fenetre/calculs': 'Détail des calculs',
  '/recettes/:id/modifier/menu/ligne': 'Actions d\'une ligne',
  '/recettes/:id/chronologie/fenetre/etape': 'Étape',
  '/recettes/:id/chronologie/menu/actions': 'Plus d\'actions',
  '/recettes/:id/chronologie/menu/ligne': 'Actions d\'une ligne',
  '/brassins/:id/menu/actions': 'Plus d\'actions',
  '/brassins/:id/fenetre/modifier': 'Modifier le brassin',
  '/brassins/:id/fenetre/embouteillage': 'Embouteillage',
  '/brassins/:id/fenetre/releve': 'Relevé de fermentation',
  '/brassins/:id/fenetre/densite-volume': 'Densité ou volume saisi',
  '/brassins/:id/fenetre/mesure-retenue': 'Mesure retenue',
  '/brassins/:id/fenetre/correction': 'Correction d\'une saisie',
  '/brassins/:id/fenetre/cout': 'Coût du brassin',
  '/brassins/:id/fenetre/prix': 'Prix d\'un ingrédient',
  '/brassins/:id/fenetre/reprendre': 'Reprendre un prix',
  '/brassins/:id/jour/menu/actions': 'Plus d\'actions',
  '/brassins/:id/jour/fenetre/mesure': 'Mesure ou note',
  '/brassins/:id/jour/fenetre/correction': 'Correction d\'une saisie',
  '/brassins/:id/jour/fenetre/etape': 'Actions d\'une étape',
  '/brassins/:id/jour/fenetre/recette': 'Voir la recette',
  '/brassins/:id/jour/fenetre/envoi': 'Envoi des saisies',
  '/prix/fenetre/prix': 'Prix d\'un ingrédient',
  '/prix/fenetre/reprendre': 'Reprendre un prix',
  '/prix/fenetre/frais': 'Frais',
  '/admin/membres/fenetre/inviter': 'Inviter un membre',
  '/admin/tickets/:id/fenetre/decision': 'Refuser ou clore',
};

/// Élément (menu ou fenêtre) → nom affiché : table fermée.
///
/// `test/ticket_screens_test.dart` vérifie que chaque appel de menu ou de
/// fenêtre de `lib/` porte, sur la ligne précédente, `// ticket: <clé>` ou
/// `// ticket: aucun (<raison>)`, et que chaque clé y est citée. Un appel
/// partagé par plusieurs écrans cite ses clés séparées par des virgules.
final Map<String, String> kTicketElements = Map.unmodifiable({
  ..._kTicketScreenElements,
  for (final screen in kTicketShellScreens)
    for (final e in kTicketShellElements.entries) '$screen/${e.key}': e.value,
});

/// Libellé de « L'écran entier », valeur par défaut de « Élément précis ».
const kTicketWholeScreen = 'L\'écran entier';

final _elementPattern = RegExp(r'^(.+)/(?:menu|fenetre)/[a-z][a-z-]*$');

/// Écran d'un élément de [kTicketElements], ou `null` si [value] n'en est pas
/// un.
String? ticketElementScreen(String value) {
  if (!kTicketElements.containsKey(value)) return null;
  return _elementPattern.firstMatch(value)?.group(1);
}

/// Valeur stockée pour [routePattern] : toujours une clé de
/// [kTicketScreenNames] ou de [kTicketElements], [kTicketScreenOther] ou
/// [kTicketScreenUnknown].
String ticketScreenValue(String? routePattern) {
  if (routePattern == kTicketScreenOther) return kTicketScreenOther;
  if (routePattern != null &&
      (kTicketScreenNames.containsKey(routePattern) ||
          kTicketElements.containsKey(routePattern))) {
    return routePattern;
  }
  return kTicketScreenUnknown;
}

/// Écran réservé à l'administrateur : absent des choix d'un brasseur.
bool isAdminTicketScreen(String value) =>
    value == '/admin' || value.startsWith('/admin/');

/// Choix de « Écran concerné », dans l'ordre. Un brasseur ne voit pas les
/// écrans d'Admin, qu'il ne peut pas ouvrir.
List<({String value, String label})> ticketScreenOptions({
  required bool isAdmin,
}) => [
  for (final e in kTicketScreenNames.entries)
    if (isAdmin || !isAdminTicketScreen(e.key)) (value: e.key, label: e.value),
  (value: kTicketScreenOther, label: 'Autre écran'),
  (value: kTicketScreenUnknown, label: 'Je ne sais pas'),
];

/// Choix de « Élément précis » pour l'écran [screen] : « L'écran entier »
/// (valeur [screen]) puis ses éléments. Vide quand l'écran n'en a pas
/// (« Autre écran », « Je ne sais pas ») ou, pour un brasseur, quand c'est un
/// écran d'Admin.
List<({String value, String label})> ticketElementOptions(
  String screen, {
  required bool isAdmin,
}) {
  if (!isAdmin && isAdminTicketScreen(screen)) return const [];
  final elements = [
    for (final e in kTicketElements.entries)
      if (ticketElementScreen(e.key) == screen) (value: e.key, label: e.value),
  ];
  if (elements.isEmpty) return const [];
  return [(value: screen, label: kTicketWholeScreen), ...elements];
}

/// Nom affiché d'une valeur stockée (« Brassin › Embouteillage » pour un
/// élément). Une valeur que cette version ne connaît pas (route retirée
/// depuis) s'affiche telle quelle.
String ticketScreenLabel(String value) {
  if (value == kTicketScreenOther) return 'Autre écran';
  if (value == kTicketScreenUnknown) return 'Je ne sais pas';
  final screen = ticketElementScreen(value);
  if (screen != null) {
    return '${kTicketScreenNames[screen] ?? screen} › ${kTicketElements[value]}';
  }
  return kTicketScreenNames[value] ?? value;
}
