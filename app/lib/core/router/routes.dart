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

  /// Bibliothèque (ADR-005, L4) : un segment par référentiel et les recettes
  /// publiques ; `/bibliotheque` redirige vers les styles.
  static const library = '/bibliotheque';
  static String librarySegment(String slug) => '$library/$slug';
  static String libraryEntry(String slug, String id) =>
      '$library/$slug/${Uri.encodeComponent(id)}';

  /// « Sources des données » : page pleine hors de la coquille, ouverte par
  /// `push` depuis la Bibliothèque et depuis le menu du compte.
  static const dataSources = '/sources-des-donnees';
  static const adminMembers = '/admin/membres';

  /// Admin › Import des fiches Excel (v0.6) : page pleine hors de la
  /// coquille, réservée à l'admin par le routeur (`/admin/**`).
  static const adminImport = '/admin/import';

  /// Admin › Rapports d'erreur (ADR-011, J1), dans la coquille.
  static const adminErrorReports = '/admin/rapports-erreur';

  /// Admin › Journaux (ADR-011, J2), dans la coquille.
  static const adminLogs = '/admin/journaux';

  /// Admin › Tickets des membres (ADR-006, T2), dans la coquille.
  static const adminTickets = '/admin/tickets';
  static String adminTicket(String id) => '$adminTickets/$id';

  /// « Mes prix » : page pleine hors de la coquille, ouverte par `push`.
  static const prices = '/prix';

  /// « Mes processus » (ADR-010) : pages pleines hors de la coquille, la liste
  /// ouverte par `push` depuis le menu du compte. `?modele=exemple` ouvre
  /// « Nouveau processus » prérempli du modèle d'exemple.
  static const processes = '/processus';
  static const newProcess = '/processus/nouveau';
  static const exampleQueryParam = 'modele';
  static const newProcessFromExample = '$newProcess?$exampleQueryParam=exemple';
  static String process(String id) => '$processes/$id';
  static String editProcess(String id) => '$processes/$id/modifier';

  /// « Préférences » (thème de l'appareil, ADR-009) : page pleine hors de la
  /// coquille, ouverte par `push` depuis le menu du compte.
  static const preferences = '/preferences';

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

  /// Journée 2 et suivantes d'un déroulé (ADR-010) : préparation dans la
  /// coquille, écran de la journée plein écran. `/brassins/:id/jour` reste la
  /// journée de brassage.
  static String prepareJournee(String id, String journee) =>
      '${brewDay(id)}/${Uri.encodeComponent(journee)}/preparer';
  static String journee(String id, String journee) =>
      '${brewDay(id)}/${Uri.encodeComponent(journee)}';

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
