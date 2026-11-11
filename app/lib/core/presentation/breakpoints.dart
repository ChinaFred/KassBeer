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

/// Largeur maximale du libellé d'une destination du rail (600 à 839 px) : un
/// libellé plus large est réduit au lieu d'élargir le rail. Sans elle,
/// « Bibliothèque » en texte × 2 élargit le rail et le bandeau hors ligne
/// déborde du contenu.
const double kRailLabelMaxWidth = 160;

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

/// Largeur d'un éditeur plein écran (recette, équipement) : formulaire et, au-delà de
/// [kExpandedMinWidth], panneau des calculs à droite.
const double kEditorMaxWidth = 920;

/// Largeur du panneau des calculs à droite de l'éditeur de recette, au-delà de
/// [kExpandedMinWidth].
const double kCalculationPanelWidth = 340;

/// Largeur minimale d'une tuile de calcul pour un texte à 100 % ; multipliée par
/// l'échelle du texte pour que « 1057,9 » ne se coupe pas.
const double kCalculationTileMinWidth = 120;

/// Largeur minimale d'un champ du relevé (densité, température) pour un texte à 100 %
/// ; multipliée par l'échelle du texte. Sous cette largeur, ils s'empilent.
const double kReleveChampMinWidth = 140;

/// Largeur minimale d'une colonne du tableau « Prévu et mesuré », multipliée par
/// l'échelle du texte. Sous cette largeur, le tableau passe en lignes.
const double kComparaisonValeurMinWidth = 96;

/// Hauteur sous laquelle l'écran du jour de brassage passe en deux colonnes
/// (téléphone en paysage).
const double kCompactMaxHeight = 480;

/// Largeur des boutons et de la chronologie de l'écran du jour.
const double kBrewDayActionsMaxWidth = 480;
const double kBrewDayChronologyMaxWidth = 480;

/// Largeur de l'écran du jour, centré au-delà.
const double kBrewDayMaxWidth = 1200;
