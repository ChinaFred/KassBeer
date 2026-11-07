import 'package:go_router/go_router.dart';

/// Page affichée dans la coquille : elle donne à la barre du haut son titre et,
/// pour une page de second niveau, le chemin du bouton retour.
class PageDeCoquille extends GoRoute {
  PageDeCoquille({
    required super.path,
    required this.titre,
    this.retour,
    required super.builder,
    super.routes,
  });

  /// Titre de la barre du haut.
  final String titre;

  /// Chemin ouvert par le bouton retour ; `null` pour une destination principale.
  final String? retour;
}
