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

  /// Écran « Nouveautés », ouvert depuis le menu du compte.
  static const news = '/nouveautes';

  static const newRecipe = '/recettes/nouvelle';
  static String recipe(String id) => '$recipes/$id';
  static String editRecipe(String id) => '$recipes/$id/modifier';

  static const newEquipment = '/equipements/nouveau';
  static String equipmentItem(String id) => '$equipment/$id';
  static String editEquipment(String id) => '$equipment/$id/modifier';

  static String editBrewSteps(String id) => '$recipes/$id/chronologie';

  static String brew(String id) => '$brews/$id';
  static String prepareBrew(String id) => '$brews/$id/preparer';
  static String brewDay(String id) => '$brews/$id/jour';

  /// Écrans d'accès : un membre qui y arrive repart vers l'accueil.
  static const accessScreens = {loading, login, notInvited, accessError};

  /// Écran d'arrivée d'un membre.
  static const home = recipes;
}
