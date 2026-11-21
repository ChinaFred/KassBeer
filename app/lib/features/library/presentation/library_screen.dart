import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/ligne_liste.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../data/library_repository.dart';
import '../domain/aromes_houblon.dart';
import '../domain/recette_publique.dart';
import '../domain/referentiel.dart';
import 'couleur_ebc.dart';
import 'libelles_bibliotheque.dart';
import 'library_providers.dart';
import 'reference_entry_screen.dart' show fermerFicheBibliotheque;
import 'section_aromes.dart' show TextesAromes;

/// Liste et fiche côte à côte dans la Bibliothèque : fenêtre d'au moins
/// [kBibliothequeCoteACoteMinWidth] (rail étendu et [kExpandedMinWidth] de
/// contenu), texte sous [kGrandTexteMinScale]. Sinon, une colonne.
bool bibliothequeCoteACote(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kBibliothequeCoteACoteMinWidth &&
    MediaQuery.textScalerOf(context).scale(1) < kGrandTexteMinScale;

/// Bibliothèque : styles, ingrédients et recettes publiques, en lecture seule
/// (ADR-005, L4). Un segment par chemin (`/bibliotheque/houblons`) ; la
/// recherche et le filtre vivent dans [rechercheBibliothequeProvider], jamais
/// écrits en base.
///
/// En une colonne : l'en-tête, la recherche épinglée et la liste ; la fiche
/// s'ouvre par-dessus. Côte à côte, voir [BibliothequeCoteACote].
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.segment});

  final SegmentBibliotheque segment;

  static const loadError =
      'Impossible de lire la bibliothèque. L\'erreur est signalée à '
      'l\'administrateur.';
  static const offlineMessage =
      'Bibliothèque indisponible hors ligne. Elle s\'ouvre au retour du réseau.';
  static const unreadableMessage =
      'Cette liste ne peut pas s\'afficher. L\'erreur est signalée à '
      'l\'administrateur.';
  static const searchHelp = 'Le début du nom. Validez pour chercher.';
  static const sourcesLabel = 'Sources des données';
  static const offlinePartial =
      'Hors ligne : liste lue sur l\'appareil. Elle peut être incomplète.';
  static const offlineIndex = 'Hors ligne : liste lue sur l\'appareil.';
  static const clearSearch = 'Effacer la recherche';
  static String noMatch(String text) => 'Aucun résultat pour « $text ».';
  static String noRecipeMatch(String text) =>
      'Aucune recette ne commence par « $text ».';
  static String unreadableEntries(int count) => count == 1
      ? '1 entrée illisible n\'est pas affichée. L\'erreur est signalée à '
            'l\'administrateur.'
      : '$count entrées illisibles ne sont pas affichées. L\'erreur est '
            'signalée à l\'administrateur.';

  @override
  Widget build(BuildContext context) =>
      _liste(segment, enTete: _EnTete(segment: segment));
}

/// Liste du segment ; [enTete] en tête de la liste (une colonne), ou `null`
/// quand l'en-tête est au-dessus des deux colonnes ([selectedId] : ligne de
/// la fiche ouverte).
Widget _liste(
  SegmentBibliotheque segment, {
  Widget? enTete,
  String? selectedId,
}) {
  final nature = segment.nature;
  return nature == null
      ? _RecettesPubliques(enTete: enTete, selectedId: selectedId)
      : _ListeReferentiel(
          segment: segment,
          nature: nature,
          enTete: enTete,
          selectedId: selectedId,
        );
}

/// Bibliothèque en deux colonnes ([bibliothequeCoteACote]) : l'en-tête sur
/// toute la largeur, puis la liste ([kListeBibliothequeWidth]) à gauche, sa
/// recherche épinglée en tête, et [child] à droite (la fiche ouverte, ou
/// l'invite [InviteFicheBibliotheque]), bornée à [kContentMaxWidth] et
/// alignée en haut à gauche. La liste et la fiche défilent chacune de leur
/// côté ; un groupe de parcours au clavier par colonne. Tant qu'une fiche est
/// ouverte, la touche Échap la ferme ([fermerFicheBibliotheque]), le focus
/// étant dans la liste ou dans la fiche ; un champ ou un menu qui traite Échap
/// lui-même (menu du filtre ouvert) le garde.
class BibliothequeCoteACote extends StatelessWidget {
  const BibliothequeCoteACote({
    super.key,
    required this.segment,
    required this.selectedId,
    required this.child,
  });

  final SegmentBibliotheque segment;
  final String? selectedId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colonnes = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EnTete(segment: segment),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: kListeBibliothequeWidth,
                child: FocusTraversalGroup(
                  // Material propre : le fond de la ligne choisie et l'encre de
                  // l'appui se peignent sur lui.
                  child: Material(
                    type: MaterialType.transparency,
                    child: _liste(segment, selectedId: selectedId),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: FocusTraversalGroup(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: kContentMaxWidth,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    // Toujours présent, sans raccourci quand aucune fiche n'est ouverte :
    // l'arbre ne change pas, et la liste garde son état.
    return CallbackShortcuts(
      bindings: {
        if (selectedId != null)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              fermerFicheBibliotheque(context, segment),
      },
      child: colonnes,
    );
  }
}

/// Colonne de droite sans fiche ouverte : « Choisissez un houblon pour voir sa
/// fiche. »
class InviteFicheBibliotheque extends StatelessWidget {
  const InviteFicheBibliotheque({super.key, required this.segment});

  final SegmentBibliotheque segment;

  @override
  Widget build(BuildContext context) =>
      EtatVide(icon: segment.icone, message: inviteFiche(segment));
}

/// Segments, accès à « Échelle des couleurs » et à « Sources des données ».
/// Chaque puce porte l'icône et le nom de son segment ; la puce ouverte montre
/// la coche à la place de son icône. Les puces passent à la ligne à toutes les
/// largeurs : aucune n'est cachée hors de l'écran. Sur téléphone, ou avec un
/// texte agrandi à partir de [kGrandTexteMinScale], les deux accès sont des
/// icônes sur une ligne au-dessus des puces, qui affichent leur nom court.
/// Sinon, « Échelle des couleurs » en texte et l'icône des sources sont à
/// droite des puces, qui affichent leur nom complet.
class _EnTete extends StatelessWidget {
  const _EnTete({required this.segment});

  final SegmentBibliotheque segment;

  @override
  Widget build(BuildContext context) {
    final compact =
        WindowSize.of(MediaQuery.sizeOf(context).width) == WindowSize.compact;
    // Texte agrandi : les deux accès à droite et les noms complets ne tiennent
    // plus à côté du rail. Les accès passent au-dessus des puces, en icônes, et
    // les puces prennent leur nom court.
    final enColonne =
        compact ||
        MediaQuery.textScalerOf(context).scale(1) >= kGrandTexteMinScale;
    final segments = Padding(
      padding: EdgeInsets.fromLTRB(16, 0, enColonne ? 16 : 0, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in SegmentBibliotheque.values)
            ChoiceChip(
              // Puce ouverte : la coche remplace l'icône, qui serait
              // sinon peinte sous elle.
              avatar: s == segment ? null : Icon(s.icone),
              // Le nom complet reste lu par le lecteur d'écran.
              label: Text(
                enColonne ? s.labelCourt : s.label,
                semanticsLabel: s.label,
              ),
              selected: s == segment,
              onSelected: (_) {
                if (s != segment) context.go(AppRoutes.librarySegment(s.slug));
              },
            ),
        ],
      ),
    );
    final acces = [
      if (enColonne)
        IconButton(
          tooltip: TextesCouleurEbc.echelle,
          onPressed: () => unawaited(context.push(AppRoutes.libraryColors)),
          icon: const Icon(Icons.palette_outlined),
        )
      else
        TextButton.icon(
          onPressed: () => unawaited(context.push(AppRoutes.libraryColors)),
          icon: const Icon(Icons.palette_outlined),
          label: const Text(TextesCouleurEbc.echelle),
        ),
      IconButton(
        tooltip: LibraryScreen.sourcesLabel,
        onPressed: () => unawaited(context.push(AppRoutes.dataSources)),
        icon: const Icon(Icons.info_outline),
      ),
      const SizedBox(width: 4),
    ];
    if (enColonne) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.end, children: acces),
          segments,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(child: segments),
          ...acces,
        ],
      ),
    );
  }
}

/// Champ de recherche, sur [kFormMaxWidth] au plus.
class _ChampRecherche extends StatelessWidget {
  const _ChampRecherche({
    required this.controller,
    required this.label,
    this.helper,
    this.onChanged,
    this.onSubmitted,
    this.onEffacer,
    this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? helper;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  /// Recherche locale (référentiels) : « × » qui vide le champ, affiché
  /// quand il n'est pas vide. Sans effet quand [onSubmitted] est donné.
  final VoidCallback? onEffacer;

  @override
  Widget build(BuildContext context) {
    final submit = onSubmitted;
    final effacer = onEffacer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: submit == null
                ? TextInputAction.done
                : TextInputAction.search,
            decoration: InputDecoration(
              labelText: label,
              helperText: helper,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: submit == null
                  ? (effacer == null || controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: LibraryScreen.clearSearch,
                            onPressed: effacer,
                            icon: const Icon(Icons.clear),
                          ))
                  : IconButton(
                      tooltip: 'Rechercher',
                      onPressed: submit,
                      icon: const Icon(Icons.arrow_forward),
                    ),
            ),
            onChanged: onChanged,
            onSubmitted: submit == null ? null : (_) => submit(),
          ),
        ),
      ),
    );
  }
}

/// Ligne d'aide sous la recherche (illisibles, hors ligne).
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Compte de la liste (« 37 sur 442 houblons »), affiché à chaque frappe et
/// annoncé aux lecteurs d'écran quand la frappe s'arrête depuis
/// [_Compte.delai] : une annonce par recherche, et non par lettre.
class _Compte extends StatefulWidget {
  const _Compte(this.text);

  final String text;

  static const delai = Duration(milliseconds: 500);

  @override
  State<_Compte> createState() => _CompteState();
}

class _CompteState extends State<_Compte> {
  late String _annonce = widget.text;
  Timer? _attente;

  @override
  void didUpdateWidget(_Compte oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == oldWidget.text) return;
    _attente?.cancel();
    _attente = Timer(_Compte.delai, () {
      if (mounted) setState(() => _annonce = widget.text);
    });
  }

  @override
  void dispose() {
    _attente?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        liveRegion: true,
        label: _annonce,
        child: ExcludeSemantics(
          child: Text(
            widget.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Textes du filtre de confiance.
abstract final class TextesFiltreConfiance {
  static const titre = 'Confiance des arômes';
  static const aide = 'Confiance indiquée par l\'IA qui a rédigé les arômes.';
  static const toutes = 'Afficher toutes les confiances';
  static const sansDescription = 'Sans description';

  static String aucun(String recherche, FiltreConfiance filtre) =>
      recherche.isEmpty
      ? 'Aucun houblon ${filtre.suite}.'
      : 'Aucun houblon pour « $recherche » ${filtre.suite}.';
}

/// Filtre de confiance sur une ligne, sous la recherche épinglée : un bouton
/// « Confiance des arômes : Faible (37) », lu « Confiance des arômes : Faible,
/// 37 houblons », qui ouvre un menu à choix unique. Le menu commence par la
/// ligne d'aide, non cliquable, puis les cinq choix comptés, le choix en cours
/// coché. Zone d'appui de 48 px ; le libellé passe à la ligne en grand texte.
class _FiltreConfiance extends StatelessWidget {
  const _FiltreConfiance({
    required this.filtre,
    required this.comptes,
    required this.segment,
    required this.onSelected,
  });

  final FiltreConfiance filtre;
  final Map<FiltreConfiance, int> comptes;
  final SegmentBibliotheque segment;
  final ValueChanged<FiltreConfiance> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String court(FiltreConfiance f) => '${f.libelle} (${comptes[f] ?? 0})';
    String lu(FiltreConfiance f) =>
        '${f.libelle}, ${segment.compte(comptes[f] ?? 0)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        // ticket: /bibliotheque/houblons/menu/confiance
        child: MenuAnchor(
          menuChildren: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  TextesFiltreConfiance.aide,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            // Un seul nœud lu par entrée : nombre et état coché ensemble.
            for (final f in FiltreConfiance.values)
              MergeSemantics(
                child: Semantics(
                  checked: f == filtre,
                  inMutuallyExclusiveGroup: true,
                  child: RadioMenuButton<FiltreConfiance>(
                    value: f,
                    groupValue: filtre,
                    onChanged: (v) {
                      if (v != null) onSelected(v);
                    },
                    child: Text(court(f), semanticsLabel: lu(f)),
                  ),
                ),
              ),
          ],
          builder: (context, controller, _) => OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.filter_list),
            label: Text(
              '${TextesFiltreConfiance.titre} : ${court(filtre)}',
              semanticsLabel: '${TextesFiltreConfiance.titre} : ${lu(filtre)}',
              softWrap: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton « Réessayer » d'un état sans réseau.
Widget _boutonReessayer(VoidCallback onRetry) =>
    FilledButton(onPressed: onRetry, child: const Text('Réessayer'));

// ------------------------------------------------------------ référentiels

/// Rend le focus à la liste quand la fiche ouverte à côté se ferme (« Fermer
/// la fiche », Échap) : sur la ligne de la fiche fermée si elle est affichée,
/// sinon sur le champ de recherche. [noeudLigne] suit la ligne de la dernière
/// fiche ouverte.
mixin _FocusApresFermeture<W extends ConsumerStatefulWidget>
    on ConsumerState<W> {
  /// Fiche ouverte à côté de la liste selon [widget].
  String? selectionDe(W widget);

  final noeudRecherche = FocusNode(debugLabel: 'recherche de la bibliothèque');
  final noeudLigne = FocusNode(debugLabel: 'ligne de la fiche ouverte');

  /// Dernière fiche ouverte : sa ligne porte [noeudLigne].
  String? derniereFiche;

  /// Nœud de la ligne [id].
  FocusNode? noeudDe(String id) => id == derniereFiche ? noeudLigne : null;

  @override
  void initState() {
    super.initState();
    derniereFiche = selectionDe(widget);
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    final avant = selectionDe(oldWidget);
    final apres = selectionDe(widget);
    if (apres == avant) return;
    if (apres != null) {
      derniereFiche = apres;
      // Fiche ouverte au clavier (Entrée sur une ligne) : le focus reste sur
      // la ligne, au lieu de passer à la page de la fiche.
      final focus = FocusManager.instance.primaryFocus?.context;
      if (focus == null || focus.findAncestorStateOfType<State<W>>() != this) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ligneDansLArbre()) noeudLigne.requestFocus();
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_ligneDansLArbre() ? noeudLigne : noeudRecherche).requestFocus();
    });
  }

  /// La ligne de la dernière fiche est construite : affichée par le filtre et
  /// la recherche, et dans la partie défilée de la liste.
  bool _ligneDansLArbre() =>
      noeudLigne.parent != null && (noeudLigne.context?.mounted ?? false);

  @override
  void dispose() {
    noeudRecherche.dispose();
    noeudLigne.dispose();
    super.dispose();
  }
}

class _ListeReferentiel extends ConsumerStatefulWidget {
  const _ListeReferentiel({
    required this.segment,
    required this.nature,
    required this.enTete,
    required this.selectedId,
  });

  final SegmentBibliotheque segment;
  final NatureReferentiel nature;

  /// En-tête en tête de la liste (une colonne) ; `null` côte à côte : la
  /// recherche, le compte, le filtre et les notes restent alors épinglés en
  /// tête de la colonne.
  final Widget? enTete;
  final String? selectedId;

  @override
  ConsumerState<_ListeReferentiel> createState() => _ListeReferentielState();
}

class _ListeReferentielState extends ConsumerState<_ListeReferentiel>
    with _FocusApresFermeture<_ListeReferentiel> {
  @override
  String? selectionDe(_ListeReferentiel widget) => widget.selectedId;

  /// Texte repris de [rechercheBibliothequeProvider] : il survit au passage
  /// d'une à deux colonnes, qui reconstruit la liste.
  final _search = TextEditingController();

  RechercheBibliothequeNotifier get _recherche =>
      ref.read(rechercheBibliothequeProvider(widget.segment).notifier);

  @override
  void initState() {
    super.initState();
    _search.text = ref
        .read(rechercheBibliothequeProvider(widget.segment))
        .texte;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _retry() => ref.invalidate(indexReferentielProvider(widget.nature));

  void _effacer() {
    _search.clear();
    _recherche.saisir('');
  }

  /// Index des arômes lisible, ou `null` : absent, illisible (rapporté par le
  /// dépôt de données), en panne ou en cours de lecture. Lu pour le seul
  /// segment Houblons.
  IndexAromes? _indexAromes() {
    if (widget.nature != NatureReferentiel.hops) return null;
    return switch (ref.watch(indexAromesProvider).value) {
      DocumentTrouve(value: final index) => index,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(indexReferentielProvider(widget.nature));
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    // Filtre de confiance des houblons : gardé au retour d'une fiche et au
    // choix d'une autre, perdu au changement de segment.
    final choix = ref.watch(rechercheBibliothequeProvider(widget.segment));
    final aromes = _indexAromes();
    final value = async.value;

    Widget? etat;
    IndexReferentiel? index;
    var fromCache = false;
    if (value == null) {
      if (!async.hasError) {
        etat = const EtatChargement(label: 'Chargement de la bibliothèque');
      } else if (offline) {
        etat = EtatVide(
          icon: Icons.cloud_off,
          message: LibraryScreen.offlineMessage,
          action: _boutonReessayer(_retry),
        );
      } else {
        etat = EtatErreur(
          message: LibraryScreen.loadError,
          retrying: async.isLoading,
          retryingLabel: 'Lecture en cours',
          onRetry: _retry,
        );
      }
    } else {
      switch (value) {
        case DocumentTrouve(value: final found, fromCache: final cache):
          index = found;
          fromCache = cache;
        case DocumentAbsent():
          etat = EtatVide(
            icon: Icons.local_library_outlined,
            message: widget.segment.vide,
          );
        case DocumentAbsentDuCache():
          etat = EtatVide(
            icon: Icons.cloud_off,
            message: LibraryScreen.offlineMessage,
            action: _boutonReessayer(_retry),
          );
        case DocumentIllisibleTrouve():
          etat = const EtatVide(
            icon: Icons.error_outline,
            message: LibraryScreen.unreadableMessage,
          );
      }
    }
    if (index != null && index.entrees.isEmpty && index.illisibles == 0) {
      etat = EtatVide(
        icon: Icons.local_library_outlined,
        message: widget.segment.vide,
      );
    }
    if (etat != null || index == null) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [?widget.enTete, ?etat],
      );
    }

    final texte = choix.texte.trim();
    final query = normaliserRecherche(texte);
    final trouves = [
      for (final e in index.entrees)
        if (e.correspond(query)) e,
    ];
    // Sans index des arômes, ni filtre ni étiquette : la liste reste entière.
    final filtre = aromes == null ? FiltreConfiance.toutes : choix.filtre;
    final comptes = <FiltreConfiance, int>{
      for (final f in FiltreConfiance.values) f: 0,
    };
    final shown = <EntreeIndex>[];
    for (final e in trouves) {
      final c = aromes?.confianceDe(e.id);
      for (final f in FiltreConfiance.values) {
        if (c == null ? f == FiltreConfiance.toutes : f.retient(c)) {
          comptes[f] = comptes[f]! + 1;
        }
      }
      if (c == null || filtre.retient(c)) shown.add(e);
    }
    final total = index.entrees.length;
    final compte = widget.segment.compte(total);

    // Partie épinglée : recherche et compte seuls, sur le fond de la page, et
    // un trait qui la sépare de la liste qui glisse dessous. Les segments, le
    // filtre et son aide défilent avec la liste. Côte à côte, le filtre et les
    // notes sont épinglés avec eux.
    final scheme = Theme.of(context).colorScheme;
    final champ = _ChampRecherche(
      controller: _search,
      focusNode: noeudRecherche,
      label: widget.nature == NatureReferentiel.styles
          ? 'Rechercher par nom ou code'
          : 'Rechercher par nom',
      onChanged: _recherche.saisir,
      onEffacer: _effacer,
    );
    final compteListe = _Compte(
      shown.length == total ? compte : '${shown.length} sur $compte',
    );
    final trait = Divider(
      height: 1,
      thickness: 1,
      color: scheme.outlineVariant,
    );
    final filtreConfiance = aromes == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _FiltreConfiance(
              filtre: filtre,
              comptes: comptes,
              segment: widget.segment,
              onSelected: _recherche.filtrer,
            ),
          );
    final notes = [
      if (fromCache) const _Note(LibraryScreen.offlineIndex),
      if (index.illisibles > 0)
        _Note(LibraryScreen.unreadableEntries(index.illisibles)),
    ];
    final Widget? vide = shown.isNotEmpty
        ? null
        : filtre == FiltreConfiance.toutes
        ? EtatVide(
            icon: Icons.search_off,
            message: LibraryScreen.noMatch(texte),
            action: TextButton(
              onPressed: _effacer,
              child: const Text(LibraryScreen.clearSearch),
            ),
          )
        : EtatVide(
            icon: Icons.search_off,
            message: TextesFiltreConfiance.aucun(texte, filtre),
            action: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (texte.isNotEmpty)
                  TextButton(
                    onPressed: _effacer,
                    child: const Text(LibraryScreen.clearSearch),
                  ),
                TextButton(
                  onPressed: () => _recherche.filtrer(FiltreConfiance.toutes),
                  child: const Text(TextesFiltreConfiance.toutes),
                ),
              ],
            ),
          );
    final lignes = SliverPadding(
      padding: const EdgeInsets.only(bottom: 24),
      sliver: SliverList.builder(
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final e = shown[i];
          final c = aromes?.confianceDe(e.id);
          return _Ligne(
            titre: titreEntree(e),
            details: detailsEntree(e),
            selected: e.id == widget.selectedId,
            focusNode: noeudDe(e.id),
            etiquettes: [
              // Sans icône : `info_outline` est celle de « Sources des
              // données » dans l'en-tête.
              if (c == ConfianceIndex.faible)
                const Etiquette(
                  label: TextesAromes.confianceFaible,
                  ton: TonEtiquette.neutre,
                ),
              if (c == ConfianceIndex.sansDescription)
                const Etiquette(
                  label: TextesFiltreConfiance.sansDescription,
                  ton: TonEtiquette.neutre,
                ),
            ],
            onTap: () =>
                context.go(AppRoutes.libraryEntry(widget.segment.slug, e.id)),
          );
        },
      ),
    );
    final enTete = widget.enTete;
    if (enTete == null) {
      // Côte à côte : tout l'en-tête de la colonne reste en place, la liste
      // défile dessous.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          champ,
          compteListe,
          ?filtreConfiance,
          ...notes,
          trait,
          Expanded(
            child: CustomScrollView(
              slivers: [
                if (vide != null) SliverToBoxAdapter(child: vide),
                lignes,
              ],
            ),
          ),
        ],
      );
    }
    final recherche = ColoredBox(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [champ, compteListe, trait],
      ),
    );
    // Recherche et compte épinglés pendant le défilement ; à partir de
    // kGrandTexteMinScale, ils défilent avec la liste pour lui laisser la place.
    final grandTexte =
        MediaQuery.textScalerOf(context).scale(1) >= kGrandTexteMinScale;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: enTete),
        if (grandTexte)
          SliverToBoxAdapter(child: recherche)
        else
          PinnedHeaderSliver(child: recherche),
        if (filtreConfiance != null) SliverToBoxAdapter(child: filtreConfiance),
        for (final note in notes) SliverToBoxAdapter(child: note),
        if (vide != null) SliverToBoxAdapter(child: vide),
        lignes,
      ],
    );
  }
}

// ------------------------------------------------------------ recettes publiques

class _RecettesPubliques extends ConsumerStatefulWidget {
  const _RecettesPubliques({required this.enTete, required this.selectedId});

  /// En-tête en tête de la liste (une colonne) ; `null` côte à côte.
  final Widget? enTete;
  final String? selectedId;

  @override
  ConsumerState<_RecettesPubliques> createState() => _RecettesPubliquesState();
}

class _RecettesPubliquesState extends ConsumerState<_RecettesPubliques>
    with _FocusApresFermeture<_RecettesPubliques> {
  @override
  String? selectionDe(_RecettesPubliques widget) => widget.selectedId;

  final _search = TextEditingController();
  final _documents = <DocumentLu<RecettePublique>>[];
  CurseurPage? _suite;
  bool _fromCache = false;

  /// Au moins une page lue pour la recherche en cours.
  bool _lue = false;
  bool _chargement = true;
  Object? _erreur;

  /// Numéro de la lecture en cours : une réponse d'une lecture remplacée est
  /// ignorée.
  int _lecture = 0;

  /// Recherche du segment : texte du champ et préfixe validé, gardés au
  /// passage d'une à deux colonnes, qui reconstruit la liste.
  RechercheBibliothequeNotifier get _recherche => ref.read(
    rechercheBibliothequeProvider(SegmentBibliotheque.recettes).notifier,
  );

  /// Préfixe de la recherche en cours (texte validé, pas la frappe).
  String get _prefixe => ref
      .read(rechercheBibliothequeProvider(SegmentBibliotheque.recettes))
      .prefixe;

  @override
  void initState() {
    super.initState();
    _search.text = ref
        .read(rechercheBibliothequeProvider(SegmentBibliotheque.recettes))
        .texte;
    unawaited(_lire(apres: null));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Relit la première page avec le texte du champ. La recherche part sur
  /// « Entrée » ou sur le bouton, jamais à la frappe : chaque recherche lit
  /// jusqu'à [kTaillePageRecettes] documents.
  void _rechercher() {
    _recherche
      ..saisir(_search.text)
      ..valider();
    setState(() {
      _documents.clear();
      _suite = null;
      _lue = false;
      _chargement = true;
      _erreur = null;
    });
    unawaited(_lire(apres: null));
  }

  void _pageSuivante() {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    unawaited(_lire(apres: _suite));
  }

  void _effacer() {
    _search.clear();
    _rechercher();
  }

  Future<void> _lire({required CurseurPage? apres}) async {
    final lecture = ++_lecture;
    final PageRecettesPubliques page;
    try {
      page = await ref
          .read(libraryRepositoryProvider)
          .pageRecettesPubliques(prefixe: _prefixe, apres: apres);
    } catch (error) {
      // Déjà rapportée par le dépôt de données : l'écran affiche la panne.
      if (!mounted || lecture != _lecture) return;
      setState(() {
        _erreur = error;
        _chargement = false;
      });
      return;
    }
    if (!mounted || lecture != _lecture) return;
    setState(() {
      _documents.addAll(page.documents);
      _suite = page.suite;
      _fromCache = page.fromCache;
      _lue = true;
      _chargement = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    // Garde la recherche du segment tant que la liste est ouverte.
    ref.watch(rechercheBibliothequeProvider(SegmentBibliotheque.recettes));
    final head = <Widget>[
      ?widget.enTete,
      _ChampRecherche(
        controller: _search,
        focusNode: noeudRecherche,
        label: 'Rechercher par début de nom',
        helper: LibraryScreen.searchHelp,
        onChanged: _recherche.saisir,
        onSubmitted: _rechercher,
      ),
    ];

    Widget? etat;
    if (!_lue) {
      if (_erreur == null) {
        etat = const EtatChargement(label: 'Chargement des recettes publiques');
      } else if (offline) {
        etat = EtatVide(
          icon: Icons.cloud_off,
          message: LibraryScreen.offlineMessage,
          action: _boutonReessayer(_rechercher),
        );
      } else {
        etat = EtatErreur(
          message: LibraryScreen.loadError,
          retrying: _chargement,
          retryingLabel: 'Lecture en cours',
          onRetry: _rechercher,
        );
      }
    } else if (_documents.isEmpty) {
      if (_prefixe.isNotEmpty) {
        etat = EtatVide(
          icon: Icons.search_off,
          message: LibraryScreen.noRecipeMatch(_prefixe),
          action: TextButton(
            onPressed: _effacer,
            child: const Text(LibraryScreen.clearSearch),
          ),
        );
      } else if (_fromCache) {
        etat = EtatVide(
          icon: Icons.cloud_off,
          message: LibraryScreen.offlineMessage,
          action: _boutonReessayer(_rechercher),
        );
      } else {
        etat = EtatVide(
          icon: Icons.local_library_outlined,
          message: SegmentBibliotheque.recettes.vide,
        );
      }
    }
    if (etat != null) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [...head, etat],
      );
    }

    if (_fromCache) head.add(const _Note(LibraryScreen.offlinePartial));
    final foot = <Widget>[
      if (_erreur != null)
        BandeauListePerimee(
          message: 'Impossible de lire la page suivante.',
          retrying: _chargement,
          onRetry: _pageSuivante,
        )
      else if (_suite != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _chargement
                ? const OutlinedButton(
                    onPressed: null,
                    child: IndicateurBouton(label: 'Lecture en cours'),
                  )
                : OutlinedButton(
                    onPressed: _pageSuivante,
                    child: const Text('Afficher les recettes suivantes'),
                  ),
          ),
        ),
    ];
    // Une colonne : l'en-tête et la recherche défilent avec la liste. Côte à
    // côte, la recherche et la note restent en tête de la colonne.
    final epingles = widget.enTete == null ? head : const <Widget>[];
    final defilants = widget.enTete == null ? const <Widget>[] : head;
    final liste = ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: defilants.length + _documents.length + foot.length,
      itemBuilder: (context, i) {
        if (i < defilants.length) return defilants[i];
        final j = i - defilants.length;
        if (j >= _documents.length) return foot[j - _documents.length];
        return switch (_documents[j]) {
          DocumentValide(:final value) => _LigneRecette(
            recette: value,
            selected: value.id == widget.selectedId,
            focusNode: noeudDe(value.id),
          ),
          DocumentInvalide() => const _Ligne(
            titre: 'Recette illisible',
            details: ['L\'erreur est signalée à l\'administrateur.'],
            erreur: true,
          ),
        };
      },
    );
    if (epingles.isEmpty) return liste;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...epingles,
        Divider(
          height: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        Expanded(child: liste),
      ],
    );
  }
}

class _LigneRecette extends StatelessWidget {
  const _LigneRecette({
    required this.recette,
    required this.selected,
    required this.focusNode,
  });

  final RecettePublique recette;
  final bool selected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final c = recette.content;
    final volume = c.batchVolumeL;
    final abv = recette.annonce.alcoholByVolume;
    final details = [
      ?c.style,
      if (volume != null) formatLitres(volume),
      if (abv != null) '${formatDegre(abv)} annoncés',
    ];
    return _Ligne(
      icone: Icons.menu_book_outlined,
      titre: c.name,
      details: details,
      selected: selected,
      focusNode: focusNode,
      onTap: () => context.go(
        AppRoutes.libraryEntry(SegmentBibliotheque.recettes.slug, recette.id),
      ),
    );
  }
}

/// Ligne d'une liste : titre et détails sur une ligne. [icone] : repère d'une
/// recette publique, le même que la liste des recettes ; les ingrédients et les
/// styles n'en ont pas. [erreur] : document illisible, sans action.
class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.titre,
    required this.details,
    this.etiquettes = const [],
    this.icone,
    this.onTap,
    this.erreur = false,
    this.selected = false,
    this.focusNode,
  });

  final String titre;
  final List<String> details;

  /// Exceptions seules (« Confiance faible », « Sans description »).
  final List<Widget> etiquettes;
  final IconData? icone;
  final VoidCallback? onTap;
  final bool erreur;

  /// Ligne de la fiche ouverte à côté de la liste.
  final bool selected;

  /// Nœud qui reçoit le focus quand cette fiche se ferme.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => LigneListe(
    icone: erreur ? Icons.error_outline : icone,
    erreur: erreur,
    titre: titre,
    details: [if (details.isNotEmpty) Text(details.join(' · '))],
    etiquettes: etiquettes,
    onTap: onTap,
    selected: selected,
    focusNode: focusNode,
  );
}
