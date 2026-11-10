/// Chemins de l'application (go_router).
abstract final class AppRoutes {
  static const loading = '/chargement';
  static const login = '/connexion';
  static const notInvited = '/non-invite';
  static const accessError = '/erreur-acces';

  static const recipes = '/recettes';
  static const brews = '/brassins';
  static const equipment = '/equipements';
  static const admin = '/admin';
  static const adminMembers = '/admin/membres';

  /// « Mes prix » : page pleine hors de la coquille, ouverte par `push`.
  static const prices = '/prix';

  /// Écran « Nouveautés », ouvert depuis le menu du compte.
  static const news = '/nouveautes';

  static const newRecipe = '/recettes/nouvelle';
  static String recipe(String id) => '$recipes/$id';
  static String editRecipe(String id) => '$recipes/$id/modifier';

  /// « Importer des recettes » : page pleine hors de la coquille, ouverte par
  /// `push` depuis la liste des recettes.
  static const importRecipes = '/recettes/importer';

  static const newEquipment = '/equipements/nouveau';
  static String equipmentItem(String id) => '$equipment/$id';
  static String editEquipment(String id) => '$equipment/$id/modifier';

  static String editBrewSteps(String id) => '$recipes/$id/chronologie';

  static String brew(String id) => '$brews/$id';
  static String prepareBrew(String id) => '$brews/$id/preparer';
  static String brewDay(String id) => '$brews/$id/jour';

  /// Tickets du membre (ADR-006) : pages pleines hors de la coquille, ouvertes
  /// par `push` depuis le menu du compte.
  static const tickets = '/tickets';
  static const newTicket = '/tickets/nouveau';
  static String ticket(String id) => '$tickets/$id';

  /// Écrans d'accès : un membre qui y arrive repart vers l'accueil.
  static const accessScreens = {loading, login, notInvited, accessError};

  /// Écran d'arrivée d'un membre.
  static const home = recipes;
}
