import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Page affichée dans la coquille : elle donne à la barre du haut son titre et,
/// pour une page de second niveau, le chemin du bouton retour.
class PageDeCoquille extends GoRoute {
  PageDeCoquille({
    required super.path,
    required this.titre,
    this.retour,
    this.pleineLargeur = false,
    this.titreSelon,
    this.retourSelon,
    super.builder,
    super.pageBuilder,
    super.routes,
  });

  /// Titre de la barre du haut.
  final String titre;

  /// Chemin ouvert par le bouton retour ; `null` pour une destination principale.
  final String? retour;

  /// La page occupe toute la largeur, sans la borne de `kContentMaxWidth`
  /// (liste et fiche côte à côte d'Admin › Tickets).
  final bool pleineLargeur;

  /// Titre qui dépend de la largeur ou du chemin ; `null` : [titre].
  final String Function(BuildContext context, GoRouterState state)? titreSelon;

  /// Retour qui dépend de la largeur ou du chemin ; `null` : [retour].
  final String? Function(BuildContext context, GoRouterState state)?
  retourSelon;
}

/// Page de second niveau dont le retour dépend du chemin (préparation d'un brassin).
class PageDeCoquilleDynamique extends PageDeCoquille {
  PageDeCoquilleDynamique({
    required super.path,
    required super.titre,
    required this.retourDepuis,
    required super.builder,
  });

  final String Function(GoRouterState state) retourDepuis;
}
