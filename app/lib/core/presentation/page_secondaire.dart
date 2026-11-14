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
/// Le corps occupe toute la largeur : la molette fait défiler la page
/// au-dessus des marges latérales. Une liste centre ses lignes par
/// [PageSecondaire.marges] ; un état (`EtatVide`, `EtatErreur`) se borne
/// lui-même.
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

  /// Marges d'une liste de la page : [base], plus de chaque côté la marge qui
  /// centre le contenu sur [largeurMax]. [context] doit être sous la page
  /// (widget du corps, ou `Builder`).
  static EdgeInsets marges(BuildContext context, EdgeInsets base) {
    final page = context.dependOnInheritedWidgetOfExactType<_MargePage>();
    assert(
      page != null,
      'PageSecondaire.marges appelé avec un contexte hors de la page.',
    );
    return base + EdgeInsets.symmetric(horizontal: page?.marge ?? 0);
  }

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
                child: LayoutBuilder(
                  builder: (context, constraints) => _MargePage(
                    marge: largeur == null || constraints.maxWidth <= largeur
                        ? 0
                        : (constraints.maxWidth - largeur) / 2,
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

/// Marge latérale qui centre le contenu d'une [PageSecondaire].
class _MargePage extends InheritedWidget {
  const _MargePage({required this.marge, required super.child});

  final double marge;

  @override
  bool updateShouldNotify(_MargePage oldWidget) => marge != oldWidget.marge;
}
