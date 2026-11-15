import 'package:flutter/material.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../domain/referentiel.dart';

/// Titre de la feuille de choix d'un style.
const kChoisirStyle = 'Choisir un style';

/// Libellé du champ de recherche de la feuille.
const kRechercherStyle = 'Rechercher un code ou un nom';

/// Libellé de l'icône qui ouvre la feuille, lu par le lecteur d'écran.
const kListeStylesLibelle = 'Choisir un style dans la Bibliothèque';

/// Aide du champ « Style » quand le texte n'est le nom exact d'aucun style.
const kStyleHorsBibliotheque =
    'Style hors Bibliothèque : l\'export BeerXML le refusera.';

/// Groupe des styles sans catégorie.
const kSansCategorie = 'Sans catégorie';

/// Libellé du chargement de la feuille, lu par le lecteur d'écran.
const kLectureStyles = 'Lecture des styles';

/// Feuille ouverte sans index lisible (panne, absent du cache hors ligne).
const kStylesIndisponibles =
    'La liste des styles est indisponible. Vous pouvez fermer et saisir le nom.';

/// Feuille ouverte quand l'index est absent du serveur.
const kAucunStyleBibliotheque =
    'La Bibliothèque ne contient encore aucun style.';

/// Annonce du lecteur d'écran après un choix dans la feuille.
String styleChoisi(String nom) => 'Style choisi : $nom';

/// « Style de la Bibliothèque : 21A · IPA ».
String aideStyleBibliotheque(EntreeStyle style) =>
    'Style de la Bibliothèque : ${[style.code, ?style.category].join(' · ')}';

/// « Aucun style ne correspond à « {texte} ». Vous pouvez garder votre saisie. »
String aucunStyle(String texte) =>
    'Aucun style ne correspond à « $texte ». Vous pouvez garder votre saisie.';

/// Aide du champ « Style » pour [texte], l'index [entrees] lu : `null` pour un
/// texte vide ; [aideStyleBibliotheque] quand le texte, espaces de bord
/// retirées, est le nom exact d'un style ; [kStyleHorsBibliotheque] sinon. La
/// comparaison tient compte de la casse et des accents, comme l'export
/// BeerXML, qui cherche le style sous ce nom exact.
String? aideStyleSaisi(List<EntreeIndex> entrees, String texte) {
  final nom = texte.trim();
  if (nom.isEmpty) return null;
  for (final e in stylesParCode(entrees)) {
    if (e.name == nom) return aideStyleBibliotheque(e);
  }
  return kStyleHorsBibliotheque;
}

/// Styles de [entrees] qui correspondent à [texte] (code, nom, autre nom,
/// catégorie), groupés par catégorie. Les groupes et les styles d'un groupe
/// suivent l'ordre des codes BJCP ([stylesParCode]).
List<({String categorie, List<EntreeStyle> styles})> stylesGroupes(
  List<EntreeIndex> entrees,
  String texte,
) {
  final requete = normaliserRecherche(texte.trim());
  final groupes = <String, List<EntreeStyle>>{};
  for (final e in stylesParCode(entrees)) {
    final categorie = e.category ?? kSansCategorie;
    if (!e.correspond(requete) &&
        !normaliserRecherche(categorie).contains(requete)) {
      continue;
    }
    groupes.putIfAbsent(categorie, () => []).add(e);
  }
  return [
    for (final MapEntry(:key, :value) in groupes.entries)
      (categorie: key, styles: value),
  ];
}

/// Index lu pour la feuille : [entrees] quand il est lu ; sinon `null`, et
/// [vide] vrai quand l'index est absent du serveur (Bibliothèque pas encore
/// remplie), faux pour une panne qu'une nouvelle lecture peut corriger.
typedef IndexStyles = ({List<EntreeIndex>? entrees, bool vide});

/// Ouvre « Choisir un style » : feuille du bas presque plein écran sous
/// [kCompactMaxWidth], boîte de dialogue de [kDialogueListeMaxWidth] au plus
/// au-delà. [lire] rend l'index lu, ou sa lecture en cours (indicateur de
/// chargement) ; « Réessayer » le rappelle après une panne. Rend le style
/// choisi, ou `null` (« Fermer »).
///
/// `showFeuilleOuDialogue` n'est pas repris : il place le contenu dans un
/// `SingleChildScrollView`, où la liste en `Expanded` n'a pas de hauteur.
Future<EntreeStyle?> choisirStyle(
  BuildContext context, {
  required Future<IndexStyles> Function() lire,
}) {
  final taille = MediaQuery.sizeOf(context);
  final grandEcran = taille.width >= kCompactMaxWidth;
  Widget contenu(BuildContext context) =>
      _ChoixStyle(lire: lire, autofocus: grandEcran);
  if (!grandEcran) {
    // ticket: /recettes/nouvelle/fenetre/style, /recettes/:id/modifier/fenetre/style
    return showModalBottomSheet<EntreeStyle>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * kFeuilleListeHauteur,
        child: contenu(context),
      ),
    );
  }
  // ticket: /recettes/nouvelle/fenetre/style, /recettes/:id/modifier/fenetre/style
  return showDialog<EntreeStyle>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: kDialogueListeMaxWidth,
          maxHeight: taille.height * kDialogueListeHauteur,
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: contenu(context),
        ),
      ),
    ),
  );
}

class _ChoixStyle extends StatefulWidget {
  const _ChoixStyle({required this.lire, required this.autofocus});

  final Future<IndexStyles> Function() lire;

  /// Curseur dans la recherche à l'ouverture : grand écran seulement ; au
  /// téléphone, le clavier cacherait la moitié de la liste.
  final bool autofocus;

  @override
  State<_ChoixStyle> createState() => _ChoixStyleState();
}

class _ChoixStyleState extends State<_ChoixStyle> {
  final _recherche = TextEditingController();
  late Future<IndexStyles> _index = widget.lire();

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Semantics(
              header: true,
              child: Text(kChoisirStyle, style: theme.textTheme.titleLarge),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: TextField(
              controller: _recherche,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: kRechercherStyle,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: FutureBuilder<IndexStyles>(
              future: _index,
              builder: (context, lu) {
                final data = lu.data;
                if (data == null) {
                  return const EtatChargement(label: kLectureStyles);
                }
                final entrees = data.entrees;
                if (entrees == null) {
                  if (data.vide) {
                    return const EtatVide(
                      icon: Icons.menu_book_outlined,
                      message: kAucunStyleBibliotheque,
                    );
                  }
                  // Pendant une nouvelle lecture, `FutureBuilder` garde la
                  // réponse précédente : le bouton attend.
                  return EtatErreur(
                    message: kStylesIndisponibles,
                    retrying: lu.connectionState != ConnectionState.done,
                    retryingLabel: kLectureStyles,
                    onRetry: () => setState(() {
                      _index = widget.lire();
                    }),
                  );
                }
                return _Liste(
                  groupes: stylesGroupes(entrees, _recherche.text),
                  recherche: _recherche.text.trim(),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Liste extends StatelessWidget {
  const _Liste({required this.groupes, required this.recherche});

  final List<({String categorie, List<EntreeStyle> styles})> groupes;
  final String recherche;

  @override
  Widget build(BuildContext context) {
    if (groupes.isEmpty) {
      return EtatVide(icon: Icons.search_off, message: aucunStyle(recherche));
    }
    final theme = Theme.of(context);
    final lignes = <Widget>[];
    for (final g in groupes) {
      lignes.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          child: Semantics(
            header: true,
            child: Text(
              g.categorie,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      );
      for (final s in g.styles) {
        lignes.add(
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            title: Text('${s.code} · ${s.name}'),
            subtitle: Text(g.categorie),
            onTap: () => Navigator.of(context).pop(s),
          ),
        );
      }
    }
    return ListView(children: lignes);
  }
}
