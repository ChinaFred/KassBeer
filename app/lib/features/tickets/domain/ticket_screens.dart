/// Écran concerné par un ticket : un modèle de route, jamais une adresse.
///
/// L'écran part sur une Issue publique (ADR-006). Une adresse réelle
/// (`/recettes/aB3…`) y publierait l'identifiant d'une recette ; seul le modèle
/// (`/recettes/:id`) part. [ticketScreenValue] ne rend qu'une valeur d'un
/// ensemble fermé : une clé de [kTicketScreenNames], [kTicketScreenOther] ou
/// [kTicketScreenUnknown].
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
  '/nouveautes': 'Nouveautés',
  '/tickets': 'Mes tickets',
  '/tickets/nouveau': 'Signaler ou proposer',
  '/tickets/:id': 'Suivi d\'un ticket',
  '/admin': 'Admin',
  '/admin/membres': 'Admin › Membres',
  '/admin/tickets': 'Admin › Tickets des membres',
  '/admin/tickets/:id': 'Admin › Ticket d\'un membre',
};

/// Valeur stockée pour le modèle de route [routePattern] : toujours une clé de
/// [kTicketScreenNames], [kTicketScreenOther] ou [kTicketScreenUnknown].
String ticketScreenValue(String? routePattern) {
  if (routePattern == kTicketScreenOther) return kTicketScreenOther;
  if (routePattern != null && kTicketScreenNames.containsKey(routePattern)) {
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

/// Nom affiché d'une valeur stockée. Une valeur que cette version ne connaît
/// pas (route retirée depuis) s'affiche telle quelle.
String ticketScreenLabel(String value) {
  if (value == kTicketScreenOther) return 'Autre écran';
  if (value == kTicketScreenUnknown) return 'Je ne sais pas';
  return kTicketScreenNames[value] ?? value;
}
