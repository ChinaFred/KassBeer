import 'dart:convert';
import 'dart:typed_data';

import 'package:exchange/exchange.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fichiers/echange_fichiers.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/providers.dart';
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
  // ticket: /recettes/:id/fenetre/exporter
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

  ResultatExport? _exporter() {
    final recipe = widget.recipe;
    try {
      final calculs = widget.calculs;
      return exporterBeerJson(
        recipe:
            recipe.content.toFirestore(creation: true)['recipe']!
                as Map<String, Object?>,
        // Décision du 2026-11-10 : sans `recipe.author`, seul le propriétaire
        // exporte à son nom ; un autre membre duplique la recette.
        ownerName: widget.proprietaire ? recipe.ownerName : null,
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

  Future<void> _envoyer(ModeEnvoi mode, ExportPret pret) async {
    if (_enCours != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final nom = nomFichierExport(widget.recipe.name, 'json');
    setState(() {
      _enCours = mode;
      _echec = false;
    });
    final resultat = await ref
        .read(echangeFichiersProvider)
        .envoyer(
          mode,
          nom: nom,
          typeMime: 'application/json',
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
    final resultat = _format == FormatExport.beerXml ? null : _beerJson;
    final modes = ref.read(echangeFichiersProvider).modes;
    final fermer = FilledButton(
      onPressed: navigator.pop,
      child: const Text(TextesExport.fermer),
    );

    final List<Widget> etat;
    final List<Widget> boutons;
    if (_format == FormatExport.beerXml) {
      etat = [const Text(TextesExport.beerXmlBloque)];
      boutons = [fermer];
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
      final completer = widget.onCompleter;
      etat = [
        if (manques.isNotEmpty) ...[
          Text(
            TextesExport.bloque(manques.length),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          _liste(manques),
          const SizedBox(height: 8),
        ],
        if (sansAuteur)
          const Text(TextesExport.dupliquerPourExporter)
        else if (completer == null)
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
        boutons = [fermer];
      } else {
        boutons = [
          TextButton(
            onPressed: navigator.pop,
            child: const Text(TextesExport.annuler),
          ),
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
            if (f != null && _enCours == null) setState(() => _format = f);
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
