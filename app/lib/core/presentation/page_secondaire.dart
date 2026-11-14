import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/routes.dart';
import 'bandeau_hors_ligne.dart';
import 'breakpoints.dart';
import 'menu_compte.dart';
import 'zone_capture.dart';

/// Cadre d'une page pleine hors de la coquille, ouverte depuis le menu du
/// compte ou une autre page : barre avec retour, titre et menu du compte ;
/// bandeau hors ligne ; contenu centré sur [largeurMax].
///
/// Le retour ferme la page ouverte par `push`, sinon ouvre [repli] (adresse
/// ouverte directement).
class PageSecondaire extends StatelessWidget {
  const PageSecondaire({
    super.key,
    required this.titre,
    required this.body,
    this.repli = AppRoutes.home,
    this.horsLigne = false,
    this.largeurMax = kContentMaxWidth,
    this.floatingActionButton,
  });

  final String titre;
  final Widget body;
  final String repli;

  /// Vrai : bandeau « hors ligne » au-dessus du contenu.
  final bool horsLigne;

  /// `null` : contenu sur toute la largeur (liste et fiche côte à côte).
  final double? largeurMax;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final largeur = largeurMax;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(repli),
        ),
        title: Text(titre),
        actions: const [MenuCompte(), SizedBox(width: 8)],
      ),
      body: ZoneCapture(
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (horsLigne) const BandeauHorsLigne(),
              Expanded(
                child: largeur == null
                    ? body
                    : Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: largeur),
                          child: body,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
