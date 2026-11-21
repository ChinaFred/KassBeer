import 'dart:async';

import 'package:flutter/material.dart';
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
import 'texte_redige.dart' show TextesRediges;

/// Bibliothèque : styles, ingrédients et recettes publiques, en lecture seule
/// (ADR-005, L4). Un segment par chemin (`/bibliotheque/houblons`) ; la recherche
/// est un état de l'écran, jamais écrit en base.
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
  Widget build(BuildContext context) {
    final enTete = _EnTete(segment: segment);
    final nature = segment.nature;
    return nature == null
        ? _RecettesPubliques(enTete: enTete)
        : _ListeReferentiel(segment: segment, nature: nature, enTete: enTete);
  }
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
  });

  final TextEditingController controller;
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

/// Filtre de confiance des arômes (segment Houblons) : choix unique, jamais
/// écrit en base ; « Sans description » regroupe les entrées `unknown` et les
/// houblons absents de l'index.
enum FiltreConfiance {
  toutes('Toutes', null, ''),
  elevee('Élevée', ConfianceIndex.elevee, 'avec une confiance élevée'),
  moyenne('Moyenne', ConfianceIndex.moyenne, 'avec une confiance moyenne'),
  faible('Faible', ConfianceIndex.faible, 'avec une confiance faible'),
  sansDescription(
    'Sans description',
    ConfianceIndex.sansDescription,
    'sans description',
  );

  const FiltreConfiance(this.libelle, this.confiance, this.suite);

  final String libelle;

  /// Confiance retenue ; `null` : toutes.
  final ConfianceIndex? confiance;

  /// Fin du message d'une liste vide (« avec une confiance faible »).
  final String suite;

  bool retient(ConfianceIndex c) => confiance == null || confiance == c;
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

class _ListeReferentiel extends ConsumerStatefulWidget {
  const _ListeReferentiel({
    required this.segment,
    required this.nature,
    required this.enTete,
  });

  final SegmentBibliotheque segment;
  final NatureReferentiel nature;
  final Widget enTete;

  @override
  ConsumerState<_ListeReferentiel> createState() => _ListeReferentielState();
}

class _ListeReferentielState extends ConsumerState<_ListeReferentiel> {
  final _search = TextEditingController();

  /// Filtre de confiance des houblons : état de l'écran, gardé au retour d'une
  /// fiche, perdu au changement de segment.
  var _filtre = FiltreConfiance.toutes;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _retry() => ref.invalidate(indexReferentielProvider(widget.nature));

  void _effacer() => setState(_search.clear);

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
        children: [widget.enTete, ?etat],
      );
    }

    final texte = _search.text.trim();
    final query = normaliserRecherche(texte);
    final trouves = [
      for (final e in index.entrees)
        if (e.correspond(query)) e,
    ];
    // Sans index des arômes, ni filtre ni étiquette : la liste reste entière.
    final filtre = aromes == null ? FiltreConfiance.toutes : _filtre;
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
    // filtre et son aide défilent avec la liste.
    final scheme = Theme.of(context).colorScheme;
    final recherche = ColoredBox(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ChampRecherche(
            controller: _search,
            label: widget.nature == NatureReferentiel.styles
                ? 'Rechercher par nom ou code'
                : 'Rechercher par nom',
            onChanged: (_) => setState(() {}),
            onEffacer: _effacer,
          ),
          _Compte(
            shown.length == total ? compte : '${shown.length} sur $compte',
          ),
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ],
      ),
    );
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
                  onPressed: () =>
                      setState(() => _filtre = FiltreConfiance.toutes),
                  child: const Text(TextesFiltreConfiance.toutes),
                ),
              ],
            ),
          );
    // Recherche et compte épinglés pendant le défilement ; à partir de
    // kGrandTexteMinScale, ils défilent avec la liste pour lui laisser la place.
    final grandTexte =
        MediaQuery.textScalerOf(context).scale(1) >= kGrandTexteMinScale;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: widget.enTete),
        if (grandTexte)
          SliverToBoxAdapter(child: recherche)
        else
          PinnedHeaderSliver(child: recherche),
        if (aromes != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _FiltreConfiance(
                filtre: filtre,
                comptes: comptes,
                segment: widget.segment,
                onSelected: (f) => setState(() => _filtre = f),
              ),
            ),
          ),
        if (fromCache)
          const SliverToBoxAdapter(child: _Note(LibraryScreen.offlineIndex)),
        if (index.illisibles > 0)
          SliverToBoxAdapter(
            child: _Note(LibraryScreen.unreadableEntries(index.illisibles)),
          ),
        if (vide != null) SliverToBoxAdapter(child: vide),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final e = shown[i];
              final c = aromes?.confianceDe(e.id);
              return _Ligne(
                titre: titreEntree(e),
                details: detailsEntree(e),
                etiquettes: [
                  // Sans icône : `info_outline` est celle de « Sources des
                  // données » dans l'en-tête.
                  if (c == ConfianceIndex.faible)
                    const Etiquette(
                      label: TextesRediges.confianceFaible,
                      ton: TonEtiquette.neutre,
                    ),
                  if (c == ConfianceIndex.sansDescription)
                    const Etiquette(
                      label: TextesFiltreConfiance.sansDescription,
                      ton: TonEtiquette.neutre,
                    ),
                ],
                onTap: () => context.go(
                  AppRoutes.libraryEntry(widget.segment.slug, e.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ recettes publiques

class _RecettesPubliques extends ConsumerStatefulWidget {
  const _RecettesPubliques({required this.enTete});

  final Widget enTete;

  @override
  ConsumerState<_RecettesPubliques> createState() => _RecettesPubliquesState();
}

class _RecettesPubliquesState extends ConsumerState<_RecettesPubliques> {
  final _search = TextEditingController();
  final _documents = <DocumentLu<RecettePublique>>[];
  CurseurPage? _suite;
  bool _fromCache = false;

  /// Au moins une page lue pour la recherche en cours.
  bool _lue = false;
  bool _chargement = true;
  Object? _erreur;

  /// Préfixe de la recherche en cours (texte validé, pas la frappe).
  String _prefixe = '';

  /// Numéro de la lecture en cours : une réponse d'une lecture remplacée est
  /// ignorée.
  int _lecture = 0;

  @override
  void initState() {
    super.initState();
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
    setState(() {
      _prefixe = _search.text.trim();
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
    final head = <Widget>[
      widget.enTete,
      _ChampRecherche(
        controller: _search,
        label: 'Rechercher par début de nom',
        helper: LibraryScreen.searchHelp,
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
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: head.length + _documents.length + foot.length,
      itemBuilder: (context, i) {
        if (i < head.length) return head[i];
        final j = i - head.length;
        if (j >= _documents.length) return foot[j - _documents.length];
        return switch (_documents[j]) {
          DocumentValide(:final value) => _LigneRecette(recette: value),
          DocumentInvalide() => const _Ligne(
            titre: 'Recette illisible',
            details: ['L\'erreur est signalée à l\'administrateur.'],
            erreur: true,
          ),
        };
      },
    );
  }
}

class _LigneRecette extends StatelessWidget {
  const _LigneRecette({required this.recette});

  final RecettePublique recette;

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
  });

  final String titre;
  final List<String> details;

  /// Exceptions seules (« Confiance faible », « Sans description »).
  final List<Widget> etiquettes;
  final IconData? icone;
  final VoidCallback? onTap;
  final bool erreur;

  @override
  Widget build(BuildContext context) => LigneListe(
    icone: erreur ? Icons.error_outline : icone,
    erreur: erreur,
    titre: titre,
    details: [if (details.isNotEmpty) Text(details.join(' · '))],
    etiquettes: etiquettes,
    onTap: onTap,
  );
}
