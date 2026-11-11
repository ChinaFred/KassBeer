import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:exchange/exchange.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/fichiers/echange_fichiers.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../library/domain/referentiel.dart';
import '../domain/recipe.dart';
import 'libelles_echange.dart';
import 'recipe_calculations_view.dart';

/// Format choisi dans la feuille ; BeerJSON par défaut, jamais mémorisé.
enum FormatExport { beerJson, beerXml }

/// Ouvre « Exporter » pour [recipe] : tout membre, toute recette lisible du
/// groupe. [proprietaire] : le lecteur a créé la recette ; [onCompleter] :
/// « Compléter la recette », pour lui seul ; [onDupliquer] : « Dupliquer »,
/// l'action de la fiche.
Future<void> ouvrirExport(
  BuildContext context, {
  required Recipe recipe,
  required bool proprietaire,
  required EquipementRecette equipement,
  required CalculsRecette calculs,
  required VoidCallback? onCompleter,
  required VoidCallback onDupliquer,
}) => showFeuilleOuDialogue<void>(
  context: context,
  builder: (_) => ExportRecipeSheet(
    recipe: recipe,
    proprietaire: proprietaire,
    equipement: equipement,
    calculs: calculs,
    onCompleter: onCompleter,
    onDupliquer: onDupliquer,
  ),
);

/// Contenu de la feuille « Exporter » : format, état (prêt, pertes, échec, ou
/// ce qui manque), boutons de la plateforme. Tout est local : l'export marche
/// hors ligne si la recette et son équipement sont dans le cache.
class ExportRecipeSheet extends ConsumerStatefulWidget {
  const ExportRecipeSheet({
    super.key,
    required this.recipe,
    required this.proprietaire,
    required this.equipement,
    required this.calculs,
    required this.onCompleter,
    required this.onDupliquer,
  });

  final Recipe recipe;
  final bool proprietaire;
  final EquipementRecette equipement;
  final CalculsRecette calculs;
  final VoidCallback? onCompleter;
  final VoidCallback onDupliquer;

  @override
  ConsumerState<ExportRecipeSheet> createState() => _ExportRecipeSheetState();
}

class _ExportRecipeSheetState extends ConsumerState<ExportRecipeSheet> {
  FormatExport _format = FormatExport.beerJson;
  ModeEnvoi? _enCours;

  /// Dernier envoi impossible : affiché dans le bloc d'état, boutons actifs.
  bool _echec = false;

  /// Export BeerJSON calculé une fois : la recette ne change pas sous la feuille.
  late final ResultatExport? _beerJson = _exporter();

  /// Export BeerXML : lancé au premier choix du format, relancé par
  /// « Réessayer » quand la fiche du style n'a pas pu être lue.
  _EtatBeerXml? _beerXml;

  /// Sous-arbre `recipe` tel qu'il est stocké.
  Map<String, Object?> get _recipeMap =>
      widget.recipe.content.toFirestore(creation: true)['recipe']!
          as Map<String, Object?>;

  /// Décision du 2026-11-10 : sans `recipe.author`, seul le propriétaire
  /// exporte à son nom ; un autre membre duplique la recette.
  String? get _ownerName =>
      widget.proprietaire ? widget.recipe.ownerName : null;

  ResultatExport? _exporter() {
    final recipe = widget.recipe;
    try {
      final calculs = widget.calculs;
      return exporterBeerJson(
        recipe: _recipeMap,
        ownerName: _ownerName,
        rendementEmpatage: widget.equipement.efficiency,
        calcul: calculs is CalculsObtenus ? calculs.calculation : null,
        chronologie: recipe.content.brewSteps.isNotEmpty,
      );
    } catch (error, stackTrace) {
      ref
          .read(errorReportServiceProvider)
          .reportError(
            feature: 'exchange.export',
            error: error,
            stackTrace: stackTrace,
            context: 'recipes/${recipe.id} : export BeerJSON impossible',
          );
      return null;
    }
  }

  /// Lit le style puis exporte en BeerXML ; l'état s'affiche dans la feuille.
  Future<void> _preparerBeerXml() async {
    setState(() => _beerXml = const _BeerXmlEnLecture());
    final etat = await _exporterBeerXml();
    if (!mounted) return;
    setState(() => _beerXml = etat);
  }

  /// Style de la recette retrouvé par son nom exact dans `beer_index/styles`,
  /// puis sa fiche `beer_styles/{id}` (ADR-005, E4), et l'export BeerXML.
  Future<_EtatBeerXml> _exporterBeerXml() async {
    final recipe = widget.recipe;
    final map = _recipeMap;
    StyleBeerXml? style;
    var manquesStyle = const <ManqueDeFormat>[];
    final nom = recipe.content.style;
    if (nom != null) {
      final lu = await _lireStyle(nom);
      if (lu == null) return const _BeerXmlStyleNonLu();
      if (lu case FicheStyle()) {
        final s = styleBeerXmlDe(_styleBibliotheque(lu), map);
        style = s.style;
        manquesStyle = s.manques;
      }
    }
    final equipement = widget.equipement;
    final materiel = equipement is EquipementConnu
        ? equipement.equipment.content
        : null;
    final calculs = widget.calculs;
    try {
      return _BeerXmlPret(
        exporterBeerXml(
          recipe: map,
          ownerName: _ownerName,
          rendementEmpatage: equipement.efficiency,
          evaporationLParH: materiel?.boilOffLPerH,
          pertesAuTrubL: materiel?.trubLossL,
          volumeMortL: materiel?.kettleDeadSpaceL,
          style: style,
          manquesStyle: manquesStyle,
          calcul: calculs is CalculsObtenus ? calculs.calculation : null,
          chronologie: recipe.content.brewSteps.isNotEmpty,
        ),
      );
    } catch (error, stackTrace) {
      // Valeur d'équipement négative (`BrewingInputException`), ou panne.
      ref
          .read(errorReportServiceProvider)
          .reportError(
            feature: 'exchange.export',
            error: error,
            stackTrace: stackTrace,
            context: 'recipes/${recipe.id} : export BeerXML impossible',
          );
      return const _BeerXmlPret(null);
    }
  }

  /// Fiche du style [nom] : [FicheStyle] trouvée ; [_StyleIntrouvable] si la
  /// Bibliothèque n'a aucun style de ce nom exact ; `null` si l'index ou la
  /// fiche n'ont pas pu être lus (hors ligne sans cache, illisible, panne).
  Future<Object?> _lireStyle(String nom) async {
    final repository = ref.read(libraryRepositoryProvider);
    try {
      final index = await repository.lireIndex(NatureReferentiel.styles);
      final IndexReferentiel styles;
      switch (index) {
        case DocumentTrouve(:final value):
          styles = value;
        case DocumentAbsent():
          return const _StyleIntrouvable();
        case DocumentAbsentDuCache() || DocumentIllisibleTrouve():
          return null;
      }
      String? id;
      for (final e in styles.entrees) {
        if (e.name == nom) {
          id = e.id;
          break;
        }
      }
      if (id == null) return const _StyleIntrouvable();
      return switch (await repository.lireFiche(NatureReferentiel.styles, id)) {
        DocumentTrouve(value: final FicheStyle fiche) => fiche,
        DocumentTrouve() || DocumentAbsent() => const _StyleIntrouvable(),
        DocumentAbsentDuCache() || DocumentIllisibleTrouve() => null,
      };
    } catch (_) {
      // Déjà rapportée par le dépôt de données : `lireIndex` et `lireFiche`
      // rapportent la panne avant de la relancer (`lireIndex`, la première de
      // chaque index de la session). La feuille
      // affiche la panne et « Réessayer ».
      return null;
    }
  }

  Future<void> _envoyer(ModeEnvoi mode, ExportPret pret) async {
    if (_enCours != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final xml = _format == FormatExport.beerXml;
    final nom = nomFichierExport(widget.recipe.name, xml ? 'xml' : 'json');
    setState(() {
      _enCours = mode;
      _echec = false;
    });
    final resultat = await ref
        .read(echangeFichiersProvider)
        .envoyer(
          mode,
          nom: nom,
          typeMime: xml ? 'application/xml' : 'application/json',
          octets: Uint8List.fromList(utf8.encode(pret.contenu)),
        );
    if (!mounted) return;
    setState(() => _enCours = null);
    switch (resultat) {
      case EnvoiAnnule():
        return;
      case EnvoiImpossible():
        // Déjà rapporté ; affiché dans la feuille, l'envoi peut se refaire.
        setState(() => _echec = true);
      case EnvoiFait():
        navigator.pop();
        final message = switch (mode) {
          ModeEnvoi.telecharger => TextesExport.telecharge(nom),
          ModeEnvoi.enregistrer => TextesExport.enregistre,
          ModeEnvoi.partager => null,
        };
        if (message != null) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
    }
  }

  Widget _liste(List<String> lignes) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final m in lignes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(child: Text('•  ')),
              Expanded(child: Text(m)),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navigator = Navigator.of(context);
    final xml = _beerXml;
    final resultat = switch (_format) {
      FormatExport.beerJson => _beerJson,
      FormatExport.beerXml => xml is _BeerXmlPret ? xml.resultat : null,
    };
    final modes = ref.read(echangeFichiersProvider).modes;
    final fermer = FilledButton(
      onPressed: navigator.pop,
      child: const Text(TextesExport.fermer),
    );

    final List<Widget> etat;
    final List<Widget> boutons;
    if (_format == FormatExport.beerXml && xml is! _BeerXmlPret) {
      if (xml is _BeerXmlStyleNonLu) {
        etat = [const Text(TextesExport.styleIllisible)];
        boutons = [
          TextButton(
            onPressed: navigator.pop,
            child: const Text(TextesExport.fermer),
          ),
          FilledButton(
            onPressed: _preparerBeerXml,
            child: const Text(TextesExport.reessayer),
          ),
        ];
      } else {
        etat = [const IndicateurBouton(label: TextesExport.styleEnLecture)];
        boutons = [fermer];
      }
    } else if (resultat == null) {
      etat = [const Text(TextesExport.echec)];
      boutons = [fermer];
    } else if (resultat is ExportBloque) {
      bool estAuteur(ManqueExport m) =>
          m is ManqueDeFormat && m.champ == ChampExport.auteur;
      // Recette d'un autre membre sans auteur : « Dupliquer » le règle.
      final sansAuteur =
          !widget.proprietaire && resultat.manques.any(estAuteur);
      final manques = [
        for (final m in resultat.manques)
          if (!(sansAuteur && estAuteur(m)))
            libelleManqueExport(
              m,
              widget.equipement,
              content: widget.recipe.content,
            ),
      ];
      // Style sans plages, seul manque : la recette n'a rien à compléter, le
      // libellé propose un autre style ou le BeerJSON.
      final seulStyle = resultat.manques.every(
        (m) => m is ManqueDeFormat && m.champ == ChampExport.ficheStyle,
      );
      // Champs de l'équipement seuls en cause : la recette n'a rien à compléter.
      bool estEquipement(ManqueExport m) =>
          m is ManqueDeFormat &&
          const {
            ChampExport.evaporation,
            ChampExport.pertesAuTrub,
            ChampExport.volumeMort,
          }.contains(m.champ);
      final seulEquipement = resultat.manques.every(estEquipement);
      final completer = seulStyle || seulEquipement ? null : widget.onCompleter;
      // Équipement du lecteur à compléter (BeerXML) : bouton vers son éditeur,
      // plein quand l'équipement est seul en cause.
      final equipement = widget.equipement;
      final uid = ref.read(grantedAccessProvider)?.user.uid;
      final equipementACompleter =
          equipement is EquipementConnu &&
              uid != null &&
              equipement.equipment.ownerUid == uid &&
              resultat.manques.any(estEquipement)
          ? equipement.equipment.id
          : null;
      final router = GoRouter.of(context);
      void ouvrirEquipement() {
        navigator.pop();
        unawaited(router.push(AppRoutes.editEquipment(equipementACompleter!)));
      }

      final boutonEquipement = equipementACompleter == null
          ? null
          : seulEquipement
          ? FilledButton(
              onPressed: ouvrirEquipement,
              child: const Text(TextesExport.completerEquipement),
            )
          : OutlinedButton(
              onPressed: ouvrirEquipement,
              child: const Text(TextesExport.completerEquipement),
            );
      etat = [
        if (manques.isNotEmpty) ...[
          Text(
            seulStyle
                ? TextesExport.styleImpossible
                : TextesExport.bloque(manques.length),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          _liste(manques),
          const SizedBox(height: 8),
        ],
        if (sansAuteur)
          const Text(TextesExport.dupliquerPourExporter)
        else if (completer == null && !seulStyle && !seulEquipement)
          const Text(TextesExport.autreMembre),
      ];
      if (sansAuteur) {
        boutons = [
          TextButton(
            onPressed: navigator.pop,
            child: const Text(TextesExport.fermer),
          ),
          FilledButton(
            onPressed: () {
              navigator.pop();
              widget.onDupliquer();
            },
            child: const Text(TextesExport.dupliquer),
          ),
        ];
      } else if (completer == null) {
        boutons = boutonEquipement != null && seulEquipement
            ? [
                TextButton(
                  onPressed: navigator.pop,
                  child: const Text(TextesExport.fermer),
                ),
                boutonEquipement,
              ]
            : [?boutonEquipement, fermer];
      } else {
        boutons = [
          TextButton(
            onPressed: navigator.pop,
            child: const Text(TextesExport.annuler),
          ),
          ?boutonEquipement,
          FilledButton(
            onPressed: () {
              navigator.pop();
              completer();
            },
            child: const Text(TextesExport.completer),
          ),
        ];
      }
    } else {
      final pret = resultat as ExportPret;
      etat = [
        const Text(TextesExport.pret),
        Text(TextesExport.auteur(pret.auteur)),
        for (final p in pret.pertes) Text(libellePerte(p)),
        if (_echec) ...[
          const SizedBox(height: 8),
          Text(
            TextesExport.echec,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      ];
      Widget bouton(ModeEnvoi mode) {
        final onPressed = _enCours == null ? () => _envoyer(mode, pret) : null;
        final child = _enCours == mode
            ? IndicateurBouton(label: mode.libelle)
            : Text(mode.libelle);
        // Un seul bouton plein : partager (Android) ou télécharger (web).
        return mode == ModeEnvoi.enregistrer
            ? OutlinedButton(onPressed: onPressed, child: child)
            : FilledButton(onPressed: onPressed, child: child);
      }

      boutons = [
        TextButton(
          onPressed: _enCours == null ? navigator.pop : null,
          child: const Text(TextesExport.annuler),
        ),
        for (final mode in modes) bouton(mode),
      ];
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            TextesExport.titre(widget.recipe.name),
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        const Text(TextesExport.sansPrix),
        const SizedBox(height: 8),
        RadioGroup<FormatExport>(
          groupValue: _format,
          onChanged: (f) {
            if (f == null || _enCours != null) return;
            setState(() {
              _format = f;
              _echec = false;
            });
            // Le style se lit au premier choix de BeerXML, pas à l'ouverture.
            if (f == FormatExport.beerXml && _beerXml == null) {
              unawaited(_preparerBeerXml());
            }
          },
          // Inactifs pendant un envoi.
          child: Column(
            children: [
              RadioListTile<FormatExport>(
                value: FormatExport.beerJson,
                enabled: _enCours == null,
                contentPadding: EdgeInsets.zero,
                title: const Text(TextesExport.beerJson),
                subtitle: const Text(TextesExport.beerJsonAide),
              ),
              RadioListTile<FormatExport>(
                value: FormatExport.beerXml,
                enabled: _enCours == null,
                contentPadding: EdgeInsets.zero,
                title: const Text(TextesExport.beerXml),
                subtitle: const Text(TextesExport.beerXmlAide),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: etat,
          ),
        ),
        const SizedBox(height: 16),
        // Les boutons s'empilent quand la largeur manque (texte à 200 %).
        OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: 8,
          overflowSpacing: 8,
          children: boutons,
        ),
      ],
    );
  }
}

/// État de l'export BeerXML dans la feuille.
sealed class _EtatBeerXml {
  const _EtatBeerXml();
}

/// Lecture du style dans la Bibliothèque en cours.
class _BeerXmlEnLecture extends _EtatBeerXml {
  const _BeerXmlEnLecture();
}

/// Index ou fiche du style illisibles (hors ligne sans cache, panne).
class _BeerXmlStyleNonLu extends _EtatBeerXml {
  const _BeerXmlStyleNonLu();
}

/// Export calculé ; `null` si l'export a échoué (rapporté).
class _BeerXmlPret extends _EtatBeerXml {
  const _BeerXmlPret(this.resultat);

  final ResultatExport? resultat;
}

/// Aucun style de ce nom exact dans la Bibliothèque.
class _StyleIntrouvable {
  const _StyleIntrouvable();
}

/// [fiche] telle que l'export BeerXML la lit.
StyleBibliotheque _styleBibliotheque(FicheStyle fiche) => StyleBibliotheque(
  nom: fiche.name,
  categorie: fiche.category,
  numeroCategorie: fiche.categoryId,
  code: fiche.styleId,
  guide: fiche.styleGuide,
  type: fiche.type,
  ogMin: fiche.og?.minimum,
  ogMax: fiche.og?.maximum,
  fgMin: fiche.fg?.minimum,
  fgMax: fiche.fg?.maximum,
  ibuMin: fiche.ibu?.minimum,
  ibuMax: fiche.ibu?.maximum,
  ebcMin: fiche.color?.minimum,
  ebcMax: fiche.color?.maximum,
  abvMin: fiche.abv?.minimum,
  abvMax: fiche.abv?.maximum,
);
