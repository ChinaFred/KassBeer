import 'package:flutter/material.dart';

import '../../../core/presentation/breakpoints.dart';
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

/// Largeur maximale de la boîte de dialogue sur grand écran.
const double kChoixStyleMaxWidth = 560;

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

/// Index lu pour la feuille : [entrees] quand il est lu, sinon `null` et
/// [aide], le message affiché à la place de la liste.
typedef IndexStyles = ({List<EntreeIndex>? entrees, String? aide});

/// Ouvre « Choisir un style » : feuille du bas presque plein écran sous
/// [kCompactMaxWidth], boîte de dialogue de [kChoixStyleMaxWidth] au plus
/// au-delà. [index] : l'index lu, ou sa lecture en cours (indicateur de
/// chargement). Rend le style choisi, ou `null` (« Fermer »).
Future<EntreeStyle?> choisirStyle(
  BuildContext context, {
  required Future<IndexStyles> index,
}) {
  final taille = MediaQuery.sizeOf(context);
  Widget contenu(BuildContext context) => _ChoixStyle(index: index);
  if (taille.width < kCompactMaxWidth) {
    // ticket: /recettes/nouvelle/fenetre/style, /recettes/:id/modifier/fenetre/style
    return showModalBottomSheet<EntreeStyle>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
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
          maxWidth: kChoixStyleMaxWidth,
          maxHeight: taille.height * 0.8,
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
  const _ChoixStyle({required this.index});

  final Future<IndexStyles> index;

  @override
  State<_ChoixStyle> createState() => _ChoixStyleState();
}

class _ChoixStyleState extends State<_ChoixStyle> {
  final _recherche = TextEditingController();

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
              future: widget.index,
              builder: (context, lu) {
                final data = lu.data;
                if (data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entrees = data.entrees;
                if (entrees == null) {
                  return _Message(data.aide ?? '');
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

class _Message extends StatelessWidget {
  const _Message(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(texte, textAlign: TextAlign.center),
  );
}

class _Liste extends StatelessWidget {
  const _Liste({required this.groupes, required this.recherche});

  final List<({String categorie, List<EntreeStyle> styles})> groupes;
  final String recherche;

  @override
  Widget build(BuildContext context) {
    if (groupes.isEmpty) return _Message(aucunStyle(recherche));
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
