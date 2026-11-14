import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/ligne_liste.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../data/library_repository.dart';
import '../domain/recette_publique.dart';
import '../domain/referentiel.dart';
import 'libelles_bibliotheque.dart';
import 'library_providers.dart';

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

/// Segments et accès à « Sources des données ». Sur téléphone, les puces
/// tiennent sur une ligne qui défile à l'horizontale, et « Sources des
/// données » est une icône à sa droite ; au-delà, les puces passent à la ligne
/// et le lien est écrit en toutes lettres.
class _EnTete extends StatelessWidget {
  const _EnTete({required this.segment});

  final SegmentBibliotheque segment;

  @override
  Widget build(BuildContext context) {
    final compact =
        WindowSize.of(MediaQuery.sizeOf(context).width) == WindowSize.compact;
    final puces = [
      for (final s in SegmentBibliotheque.values)
        ChoiceChip(
          label: Text(s.label),
          selected: s == segment,
          onSelected: (_) {
            if (s != segment) context.go(AppRoutes.librarySegment(s.slug));
          },
        ),
    ];
    void sources() => unawaited(context.push(AppRoutes.dataSources));
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    for (final p in puces) ...[p, const SizedBox(width: 8)],
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: LibraryScreen.sourcesLabel,
              onPressed: sources,
              icon: const Icon(Icons.info_outline),
            ),
            const SizedBox(width: 4),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: puces),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: sources,
            icon: const Icon(Icons.info_outline),
            label: const Text(LibraryScreen.sourcesLabel),
          ),
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
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final submit = onSubmitted;
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
                  ? null
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

/// Ligne d'aide sous la recherche (compte, illisibles, hors ligne).
class _Note extends StatelessWidget {
  const _Note(this.text, {this.annoncee = false});

  final String text;

  /// Annoncée aux lecteurs d'écran à chaque changement (compte d'une recherche).
  final bool annoncee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        liveRegion: annoncee,
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _retry() => ref.invalidate(indexReferentielProvider(widget.nature));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(indexReferentielProvider(widget.nature));
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final value = async.value;

    Widget? etat;
    IndexReferentiel? index;
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
        case DocumentTrouve(value: final found):
          index = found;
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

    final query = normaliserRecherche(_search.text.trim());
    final shown = [
      for (final e in index.entrees)
        if (e.correspond(query)) e,
    ];
    final total = index.entrees.length;
    final head = <Widget>[
      widget.enTete,
      _ChampRecherche(
        controller: _search,
        label: widget.nature == NatureReferentiel.styles
            ? 'Rechercher par nom ou code'
            : 'Rechercher par nom',
        onChanged: (_) => setState(() {}),
      ),
      _Note(
        query.isEmpty
            ? (total == 1 ? '1 entrée' : '$total entrées')
            : '${shown.length} sur $total',
        annoncee: true,
      ),
      if (index.illisibles > 0)
        _Note(LibraryScreen.unreadableEntries(index.illisibles)),
      if (shown.isEmpty)
        EtatVide(
          icon: Icons.search_off,
          message: LibraryScreen.noMatch(_search.text.trim()),
          action: TextButton(
            onPressed: () => setState(_search.clear),
            child: const Text('Effacer la recherche'),
          ),
        ),
    ];
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: head.length + shown.length,
      itemBuilder: (context, i) {
        if (i < head.length) return head[i];
        final e = shown[i - head.length];
        final details = detailsEntree(e);
        return _Ligne(
          titre: titreEntree(e),
          details: details,
          onTap: () =>
              context.go(AppRoutes.libraryEntry(widget.segment.slug, e.id)),
        );
      },
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
            child: const Text('Effacer la recherche'),
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
      titre: c.name,
      details: details,
      onTap: () => context.go(
        AppRoutes.libraryEntry(SegmentBibliotheque.recettes.slug, recette.id),
      ),
    );
  }
}

/// Ligne d'une liste : titre et détails sur une ligne. [erreur] : document
/// illisible, sans action.
class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.titre,
    required this.details,
    this.onTap,
    this.erreur = false,
  });

  final String titre;
  final List<String> details;
  final VoidCallback? onTap;
  final bool erreur;

  @override
  Widget build(BuildContext context) => LigneListe(
    icone: erreur ? Icons.error_outline : null,
    erreur: erreur,
    titre: titre,
    details: [if (details.isNotEmpty) Text(details.join(' · '))],
    onTap: onTap,
  );
}
