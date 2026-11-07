/// Seuils de largeur de l'interface, en pixels logiques.
///
/// Moins de [kCompactMaxWidth] : téléphone (barre de navigation en bas, feuilles du
/// bas). De [kCompactMaxWidth] à [kExpandedMinWidth] : rail de navigation. À partir
/// de [kExpandedMinWidth] : rail étendu, contenu centré sur [kContentMaxWidth].
const double kCompactMaxWidth = 600;
const double kExpandedMinWidth = 840;
const double kContentMaxWidth = 840;

/// Largeur d'un dialogue de formulaire sur grand écran.
const double kDialogMaxWidth = 480;

/// Largeur d'une colonne de formulaire ou de message centrée (connexion, compte non
/// invité, panne).
const double kFormMaxWidth = 400;

/// Largeur d'un message de démarrage (configuration absente, démarrage impossible).
const double kMessageMaxWidth = 480;

/// Largeur du bloc nom, e-mail et version du menu du compte.
const double kAccountMenuMaxWidth = 280;

/// Taille d'écran déduite de la largeur disponible.
enum WindowSize {
  compact,
  medium,
  expanded;

  static WindowSize of(double width) {
    if (width < kCompactMaxWidth) return WindowSize.compact;
    if (width < kExpandedMinWidth) return WindowSize.medium;
    return WindowSize.expanded;
  }
}
